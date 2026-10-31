-- Recipe encoding through test crafts.
--
-- The player lays one craft into the 27-slot barrel grid (slots 4,5,6 / 13,14,15 / 22,23,24),
-- fluids into the recipe tanks, presses ADD and picks turtle / machine / multiblock.
-- We run the craft once, measure what was consumed and what appeared, and return everything
-- to the barrel: results go to slot 14 first (the grid is empty by then), fluids to the tanks.
-- Turtle tests also record the results' stack size (unstackable ones are crafted one by one)
-- and tools: grid items that stay after the craft, maybe with less durability.
-- A multiblock with several inputs (multiblock.json "inputs": depot, deployer...) takes each
-- row of the barrel grid into one of them: row 1 -> inputs[1], row 2 -> inputs[2], row 3 ->
-- inputs[3]. The recipe remembers it (input.into).
local net      = require("system.core.net")
local indexer  = require("system.core.indexer")
local executor = require("system.craft.executor")
local console  = require("system.utils.console")

local M = {}

M.GRID = { 4, 5, 6, 13, 14, 15, 22, 23, 24 }
M.RESULT_SLOT = 14

local function itemKey(it) return indexer.itemKey(it.name, it.nbt) end

function M.init(cfg)
  M.cfg = cfg
end

local function enc()
  local name = M.cfg.encoder
  if not name or not peripheral.isPresent(name) then error("encoder barrel not found: " .. tostring(name), 0) end
  return name
end

-- grid[1..9] = { key, name, count, maxCount } or {}; plus number of filled slots
function M.readGrid()
  local e = enc()
  local grid, n = {}, 0
  for i, slot in ipairs(M.GRID) do
    local d = peripheral.call(e, "getItemDetail", slot)
    if d then
      grid[i] = { key = itemKey(d), name = d.name, count = d.count, maxCount = d.maxCount or 64 }
      indexer.names[d.name] = indexer.names[d.name] or d.displayName
      n = n + 1
    else
      grid[i] = {}
    end
  end
  return grid, n
end

-- Fluids currently in the recipe tanks: { { tank, key, name, amount } }
function M.readTanks()
  local out = {}
  for _, tank in ipairs(M.cfg.recipe_tanks or {}) do
    local ok, list = pcall(peripheral.call, tank, "tanks")
    if ok and list then
      for _, f in pairs(list) do
        if f.amount and f.amount > 0 then
          out[#out + 1] = { tank = tank, key = indexer.fluidKey(f.name), name = f.name, amount = f.amount }
        end
      end
    end
  end
  return out
end

-- Pours `amount` mB of a fluid from storage into the recipe tanks: tanks already holding it
-- first, then empty ones; tanks with another fluid are skipped. Returns mB poured.
function M.deliverFluid(key, amount)
  local name = key:sub(2)
  local same, empty = {}, {}
  for _, tank in ipairs(M.cfg.recipe_tanks or {}) do
    local ok, list = pcall(peripheral.call, tank, "tanks")
    if ok and list then
      local has, other = false, false
      for _, f in pairs(list) do
        if f.amount and f.amount > 0 then
          if f.name == name then has = true else other = true end
        end
      end
      if has then same[#same + 1] = tank elseif not other then empty[#empty + 1] = tank end
    end
  end
  local poured = 0
  for _, tanks in ipairs({ same, empty }) do
    for _, tank in ipairs(tanks) do
      if poured >= amount then break end
      poured = poured + indexer.extractFluid(key, amount - poured, tank)
    end
  end
  return poured
end

-- Everything in one recipe tank back into storage. Returns mB moved.
function M.drainTank(tank)
  local moved = 0
  local ok, list = pcall(peripheral.call, tank, "tanks")
  for _, f in pairs(ok and list or {}) do
    if f.amount and f.amount > 0 then
      moved = moved + indexer.insertFluid(tank, indexer.fluidKey(f.name), f.amount)
    end
  end
  return moved
end

-- Puts items from `from` slot into the barrel, slot 14 first for the first result.
local function toBarrel(from, slot, count, preferResult)
  local e = enc()
  local moved = 0
  if preferResult then
    local ok, n = pcall(peripheral.call, e, "pullItems", from, slot, count, M.RESULT_SLOT)
    moved = ok and n or 0
  end
  if moved < count then
    local ok, n = pcall(peripheral.call, e, "pullItems", from, slot, count - moved)
    moved = moved + (ok and n or 0)
  end
  return moved
end

local function sorted(map)
  local list = {}
  for k, n in pairs(map) do list[#list + 1] = { key = k, count = n } end
  table.sort(list, function(a, b) return a.count > b.count end)
  return list
end

-- Recipe inputs from per-inventory counts: { [index] = { key = n } } -> { { key, count, into } }.
-- into is left out for the first (only) input, like recipes saved before it existed.
local function routed(byInput, fluids)
  local list = {}
  for into, map in pairs(byInput) do
    for _, e in ipairs(sorted(map)) do
      if into > 1 then e.into = into end
      list[#list + 1] = e
    end
  end
  for _, e in ipairs(sorted(fluids)) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    if (a.into or 1) ~= (b.into or 1) then return (a.into or 1) < (b.into or 1) end
    return a.count > b.count
  end)
  return list
end

-- ---------------------------------------------------------------- turtle

-- Turtle slots as console rows: "slot 1 > minecraft:oak_planks x1".
function M.testTurtle(t)
  local e = enc()
  local grid, n = M.readGrid()
  if n == 0 then error("barrel grid is empty", 0) end
  if not peripheral.isPresent(t.name) then
    error(("turtle '%s' is not on the wired network: right-click its modem (red ring), check the cable"):format(t.name), 0)
  end
  executor.clearTurtle(t)
  for i, g in ipairs(grid) do
    if g.key then
      local moved = peripheral.call(e, "pushItems", t.name, M.GRID[i], g.count, executor.TSLOT[i])
      if moved < g.count then error("could not move items into the turtle (wired modem?)", 0) end
    end
  end

  local t0 = os.clock()
  local reply, err = executor.ask(t, "craft", { count = 1, detail = true }, 15)
  if not reply then error("turtle: " .. tostring(err), 0) end

  local after = reply.after or {}
  local consumed, gained, kept = {}, {}, {}
  if reply.ok then consumed, gained, kept = executor.diff(reply.before, after) end

  -- everything back to the barrel: results first into slot 14
  local first = true
  for slot, it in pairs(after) do
    local isResult = gained[itemKey(it)] ~= nil
    toBarrel(t.name, slot, it.count, isResult and first)
    if isResult then first = false end
  end
  if not reply.ok then
    -- show what the turtle actually had: wrong slots, missing items, a recipe a turtle can't do
    console.block("Turtle craft failed: " .. tostring(reply.error), colors.red, executor.slotRows(reply.before or {}))
    error("not a valid recipe: " .. tostring(reply.error) .. " (see the terminal)", 0)
  end

  local recipeGrid, inputs, tools, seen = {}, {}, {}, {}
  for i, g in ipairs(grid) do
    local used = consumed[executor.TSLOT[i]]
    local ts = executor.TSLOT[i]
    if g.key and kept[ts] then
      -- durability spent by one craft; 0 seen (unbreaking luck) counts as 1
      local b, a = reply.before[ts], after[ts]
      local maxDamage = a.maxDamage or b.maxDamage
      local cost = maxDamage and math.max(1, (a.damage or 0) - (b.damage or 0)) or nil
      local key = indexer.anyKey(g.name)
      recipeGrid[i] = { key = key, count = 1, maxCount = g.maxCount, tool = true, cost = cost, maxDamage = maxDamage }
      if not seen[key] then seen[key] = true; tools[#tools + 1] = { key = key, cost = cost, maxDamage = maxDamage } end
    elseif g.key and used then
      recipeGrid[i] = { key = g.key, count = used, maxCount = g.maxCount }
      inputs[g.key] = (inputs[g.key] or 0) + used
    else
      recipeGrid[i] = {}
    end
  end
  local outputs, maxCounts = sorted(gained), executor.maxCounts(after)
  for _, o in ipairs(outputs) do o.maxCount = maxCounts[o.key] end
  return {
    type = "turtle", grid = recipeGrid, inputs = sorted(inputs), tools = #tools > 0 and tools or nil,
    outputs = outputs, time = os.clock() - t0,
  }
end

-- ---------------------------------------------------------------- machine / multiblock

-- fluidAmounts: { [fluidKey] = mB } chosen by the player for this test.
function M.testMachine(r, fluidAmounts, onProgress)
  local e = enc()
  local io = executor.machineIO(r)
  local grid = M.readGrid()
  local base = executor.snapshotIO(io)
  local inputs, byInput, maxOf = {}, {}, {}
  local several = #io.inputs > 1

  for i, g in ipairs(grid) do
    if g.key then
      local into = several and math.ceil(i / 3) or 1
      local to = io.inputs[into]
      if not to then
        error(("grid row %d has no input in %s (it has %d)"):format(into, tostring(r.machine), #io.inputs), 0)
      end
      local ok, moved = pcall(peripheral.call, e, "pushItems", to, M.GRID[i], g.count)
      moved = ok and moved or 0
      if moved > 0 then
        inputs[g.key] = (inputs[g.key] or 0) + moved
        byInput[into] = byInput[into] or {}
        byInput[into][g.key] = (byInput[into][g.key] or 0) + moved
        maxOf[g.key] = g.maxCount
      end
    end
  end
  for _, f in ipairs(M.readTanks()) do
    local want = (fluidAmounts or {})[f.key] or 0
    if want > 0 then
      local ok, moved = pcall(peripheral.call, f.tank, "pushFluid", io.inFluid, want - (inputs[f.key] or 0), f.name)
      moved = ok and moved or 0
      if moved > 0 then inputs[f.key] = (inputs[f.key] or 0) + moved end
    end
  end
  if next(inputs) == nil then error("nothing was accepted by " .. io.inItem, 0) end

  -- inputs lie in the machine's inventories (the snapshot covers them all): not results
  local expectBase = {}
  for k, v in pairs(base) do expectBase[k] = v end
  for k, v in pairs(inputs) do
    if not indexer.isFluid(k) then expectBase[k] = (expectBase[k] or 0) + v end
  end
  if io.inFluid == io.outFluid then
    for k, v in pairs(inputs) do
      if indexer.isFluid(k) then expectBase[k] = (expectBase[k] or 0) + v end
    end
  end

  local t0 = os.clock()
  local timeout = M.cfg.craft_timeout or 60
  local gains, stable, prevSig = {}, 0, ""
  while true do
    sleep(0.5)
    local cur = executor.snapshotIO(io)
    gains = {}
    for k, v in pairs(cur) do
      local d = v - (expectBase[k] or 0)
      if d > 0 and not inputs[k] then gains[k] = d end
    end
    local parts = {}
    for k, v in pairs(gains) do parts[#parts + 1] = k .. "=" .. v end
    table.sort(parts)
    local sig = table.concat(parts, ",")
    if sig ~= "" and sig == prevSig then stable = stable + 1 else stable = 0 end
    prevSig = sig
    if onProgress then onProgress(os.clock() - t0, gains) end
    if stable >= 3 then break end
    if os.clock() - t0 > timeout then
      error(("no result after %ds"):format(timeout), 0)
    end
  end
  local elapsed = os.clock() - t0
  local outputs = sorted(gains)

  -- results back to the barrel (slot 14 first) and the recipe tanks
  local left = {}
  for k, v in pairs(gains) do left[k] = v end
  local first = true
  for _, inv in ipairs(io.items) do
    local ok, list = pcall(peripheral.call, inv, "list")
    if ok and list then
      for slot, it in pairs(list) do
        local k = itemKey(it)
        if (left[k] or 0) > 0 then
          left[k] = left[k] - toBarrel(inv, slot, math.min(it.count, left[k]), first)
          first = false
        end
      end
    end
  end
  for k, v in pairs(left) do
    if indexer.isFluid(k) and v > 0 then
      for _, tank in ipairs(M.cfg.recipe_tanks or {}) do
        local okF, n = pcall(peripheral.call, tank, "pullFluid", io.outFluid, v, k:sub(2))
        if okF and n then v = v - n end
        if v <= 0 then break end
      end
    end
  end

  local fluids = {}
  for k, v in pairs(inputs) do if indexer.isFluid(k) then fluids[k] = v end end
  local list = routed(byInput, fluids)
  -- stack size: how many runs fit a machine slot at once (executor.stackRuns)
  for _, e in ipairs(list) do e.maxCount = maxOf[e.key] end
  return {
    type = r.type, machine = r.machine, inputs = list, outputs = outputs, time = elapsed,
  }
end

return M

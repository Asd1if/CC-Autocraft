-- Storage index: item pools (vaults etc.) and fluid pools (tanks).
--
-- Keys: items are "name" or "name#nbt" (crafting tells NBT variants apart),
--       "name#*" matches any NBT variant (tools whose damage changes NBT),
--       fluids are "~name" (so minecraft:water the fluid never clashes with an item id),
--       "@group" is any item of a cfg.substitutes group ("@planks": any planks).
-- live_stock (M.stockList) merges NBT variants by name, as agreed.
--
-- Two pools: the main storage (what the player sees and takes from) and the craft storage
-- (cfg.craft_storage / craft_tanks, optional) where running orders keep their resources and
-- intermediates. Counts cover both; the stock list shows the main storage only.
--
-- Backends: storage that isn't a plain inventory (an AE2 / Refined Storage network through an
-- Advanced Peripherals bridge). Mods return them from the "storage.backends" filter; they belong
-- to the main storage. A backend is
--   { name, scan() -> items { { name, nbt, count, displayName } }, fluids { { name, amount } },
--     extract(name, nbt, n, to, toSlot) -> moved, insert(from, slot, n, itemName) -> moved,
--     extractFluid(name, n, to) -> moved, insertFluid(from, name, n) -> moved }
-- Taking: craft storage, inventories, then backends. Putting: craft storage (for orders),
-- inventories that already hold the item, then backends, then the other inventories.
local util = require("system.utils.util")
local log  = require("system.utils.log")
local api  = require("system.core.api")

local M = {
  storage = {}, tankNames = {},
  craft = {}, craftTanks = {}, isCraft = {}, -- craft storage pool
  invs = {},    -- inv name -> list() result
  tanks = {},   -- tank name -> tanks() result
  agg = nil,    -- cached aggregate, rebuilt when dirty
  names = {},   -- item id -> display name
  dirty = true,
  backends = {}, -- see above; .items / .fluids hold the last scan
}

local NAMES_FILE = "data/names.json"

function M.itemKey(name, nbt) return nbt and (name .. "#" .. nbt) or name end
function M.fluidKey(name) return "~" .. name end
function M.isFluid(key) return key:sub(1, 1) == "~" end
function M.anyKey(name) return name .. "#*" end
function M.isGroup(key) return key:sub(1, 1) == "@" end

-- Groups from cfg.substitutes: { planks = { "minecraft:oak_planks", ... } }. A recipe input
-- from a group stands for any member ("@planks"), unless the recipe's result names that
-- member's variant: oak slabs need oak planks, a chest takes any.
local function strip(id) return (id:gsub("^[^:]+:", "")) end

-- The part of a member's id that differs from the rest of its group: "oak" of oak_planks,
-- "dark_oak" of dark_oak_planks (words shared at the end by all members are cut off).
local function variant(name, members)
  local words = {}
  for w in strip(name):gmatch("[^_]+") do words[#words + 1] = w end
  local cut = #words - 1
  for _, m in ipairs(members) do
    local mw = {}
    for w in strip(m):gmatch("[^_]+") do mw[#mw + 1] = w end
    local same = 0
    while same < #words and same < #mw and words[#words - same] == mw[#mw - same] do same = same + 1 end
    cut = math.min(cut, same)
  end
  return table.concat(words, "_", 1, #words - math.max(0, cut))
end

local groupOf -- item id -> group name, built from cfg.substitutes
local function groups()
  if not groupOf then
    groupOf = {}
    for g, members in pairs(M.cfg and M.cfg.substitutes or {}) do
      if type(g) == "string" and type(members) == "table" then
        for _, id in ipairs(members) do groupOf[id] = g end
      end
    end
  end
  return groupOf
end

-- Members of a group, most in storage first.
function M.groupMembers(g)
  local list = {}
  for _, id in ipairs((M.cfg and M.cfg.substitutes or {})[g] or {}) do list[#list + 1] = id end
  local by = M.agg and M.agg.byName or {}
  table.sort(list, function(a, b)
    if (by[a] or 0) ~= (by[b] or 0) then return (by[a] or 0) > (by[b] or 0) end
    return a < b
  end)
  return list
end

-- The key a recipe input is planned and fetched by: "@group" when the item is in a group and
-- the recipe's result doesn't name its variant, otherwise the key itself.
function M.substitute(key, resultKey)
  if not key or M.isFluid(key) or M.isGroup(key) or key:find("#", 1, true) then return key end
  local g = groups()[key]
  if not g then return key end
  local v = variant(key, M.cfg.substitutes[g])
  if resultKey and strip(M.parseKey(resultKey)):find(v, 1, true) then return key end
  return "@" .. g
end

-- Whether an item key belongs to a wanted key: the same, "name#*", or "@group".
function M.matches(key, wanted)
  if key == wanted then return true end
  local name = M.parseKey(key)
  if wanted == name .. "#*" then return true end
  if M.isGroup(wanted) then return groups()[name] == wanted:sub(2) end
  return false
end

-- key -> name, nbt, isFluid
function M.parseKey(key)
  if M.isFluid(key) then return key:sub(2), nil, true end
  local name, nbt = key:match("^([^#]+)#(.+)$")
  if name then return name, nbt, false end
  return key, nil, false
end

function M.displayName(key)
  if M.isGroup(key) then return "Any " .. key:sub(2):gsub("_", " ") end
  local name, nbt, fluid = M.parseKey(key)
  local d = M.names[name] or util.formatName(name)
  if nbt and nbt ~= "*" then d = d .. "*" end
  return d
end

function M.init(cfg, extraExclude)
  M.cfg = cfg
  M.names = util.readJSON(NAMES_FILE) or {}
  groupOf = nil
  local ex = util.set(cfg.exclude)
  if cfg.encoder then ex[cfg.encoder] = true end
  for _, n in ipairs(cfg.recipe_tanks or {}) do ex[n] = true end
  for n in pairs(extraExclude or {}) do ex[n] = true end
  M.exclude = ex
  M.discover()
end

function M.discover()
  M.craft = util.findPeripherals(M.cfg.craft_storage, M.exclude)
  M.craftTanks = util.findPeripherals(M.cfg.craft_tanks, M.exclude)
  local ex = util.copy(M.exclude)
  for _, n in ipairs(M.craft) do ex[n] = true end
  for _, n in ipairs(M.craftTanks) do ex[n] = true end
  M.storage = util.findPeripherals(M.cfg.storage, ex)
  M.tankNames = util.findPeripherals(M.cfg.tanks, ex)
  M.isCraft = util.set(M.craft)
  for _, n in ipairs(M.craftTanks) do M.isCraft[n] = true end
  M.backends = api.filter("storage.backends", {}, M.cfg, M.exclude) or {}
  -- a bridge listed in cfg.storage is a backend, not an inventory
  local isBackend = {}
  for _, b in ipairs(M.backends) do isBackend[b.name] = true end
  for i = #M.storage, 1, -1 do if isBackend[M.storage[i]] then table.remove(M.storage, i) end end
  for i = #M.tankNames, 1, -1 do if isBackend[M.tankNames[i]] then table.remove(M.tankNames, i) end end
  log.info("storage: %d inventories, %d tanks, %d networks; craft storage: %d + %d",
    #M.storage, #M.tankNames, #M.backends, #M.craft, #M.craftTanks)
end

local function scanBackend(b)
  local ok, items, fluids = pcall(b.scan)
  if ok then
    b.items, b.fluids = items or {}, fluids or {}
    for _, it in ipairs(b.items) do
      if it.displayName and not M.names[it.name] then M.names[it.name] = it.displayName end
    end
  else
    log.warn("%s: %s", b.name, tostring(items))
  end
  M.dirty = true
end
M.scanBackend = scanBackend

-- Inventories / tanks to take from: craft storage first (that's where orders keep things).
local function itemSources()
  local all = {}
  for _, n in ipairs(M.craft) do all[#all + 1] = n end
  for _, n in ipairs(M.storage) do all[#all + 1] = n end
  return all
end

local function tankSources()
  local all = {}
  for _, n in ipairs(M.craftTanks) do all[#all + 1] = n end
  for _, n in ipairs(M.tankNames) do all[#all + 1] = n end
  return all
end

function M.scanInv(name)
  local ok, list = pcall(peripheral.call, name, "list")
  M.invs[name] = ok and list or {}
  M.dirty = true
end

function M.scanTank(name)
  local ok, list = pcall(peripheral.call, name, "tanks")
  M.tanks[name] = ok and list or {}
  M.dirty = true
end

function M.scan()
  local fns = {}
  local invs, tanks = itemSources(), tankSources()
  for _, n in ipairs(invs) do fns[#fns + 1] = function() M.scanInv(n) end end
  for _, n in ipairs(tanks) do fns[#fns + 1] = function() M.scanTank(n) end end
  for _, b in ipairs(M.backends) do fns[#fns + 1] = function() scanBackend(b) end end
  util.parallelBatches(fns, 32)
  -- forget peripherals that were removed
  local live = util.set(invs)
  for n in pairs(M.invs) do if not live[n] then M.invs[n] = nil end end
  live = util.set(tanks)
  for n in pairs(M.tanks) do if not live[n] then M.tanks[n] = nil end end
  M.dirty = true
end

local function aggregate()
  if not M.dirty and M.agg then return M.agg end
  local counts, byName, fluids, mainByName, mainFluids = {}, {}, {}, {}, {}
  for inv, list in pairs(M.invs) do
    local main = not M.isCraft[inv]
    for _, it in pairs(list) do
      local k = M.itemKey(it.name, it.nbt)
      counts[k] = (counts[k] or 0) + it.count
      byName[it.name] = (byName[it.name] or 0) + it.count
      if main then mainByName[it.name] = (mainByName[it.name] or 0) + it.count end
    end
  end
  for _, b in ipairs(M.backends) do
    for _, it in ipairs(b.items or {}) do
      if (it.count or 0) > 0 then
        local k = M.itemKey(it.name, it.nbt)
        counts[k] = (counts[k] or 0) + it.count
        byName[it.name] = (byName[it.name] or 0) + it.count
        mainByName[it.name] = (mainByName[it.name] or 0) + it.count
      end
    end
    for _, f in ipairs(b.fluids or {}) do
      if (f.amount or 0) > 0 then
        local k = M.fluidKey(f.name)
        fluids[k] = (fluids[k] or 0) + f.amount
        mainFluids[k] = (mainFluids[k] or 0) + f.amount
      end
    end
  end
  for tank, list in pairs(M.tanks) do
    local main = not M.isCraft[tank]
    for _, f in pairs(list) do
      if f.amount and f.amount > 0 then
        local k = M.fluidKey(f.name)
        fluids[k] = (fluids[k] or 0) + f.amount
        if main then mainFluids[k] = (mainFluids[k] or 0) + f.amount end
      end
    end
  end
  M.agg = { counts = counts, byName = byName, fluids = fluids, mainByName = mainByName, mainFluids = mainFluids }
  M.dirty = false
  return M.agg
end

-- Exact count for a key (items by name+nbt, fluids in mB).
function M.count(key)
  local a = aggregate()
  if M.isFluid(key) then return a.fluids[key] or 0 end
  if M.isGroup(key) then
    local n = 0
    for _, name in ipairs(M.groupMembers(key:sub(2))) do n = n + (a.byName[name] or 0) end
    return n
  end
  local name, nbt = M.parseKey(key)
  if nbt == "*" then return a.byName[name] or 0 end
  return a.counts[key] or 0
end

-- live_stock rows: { key, name, count, fluid } — main storage, items merged by name.
function M.stockList()
  local a = aggregate()
  local rows = {}
  for name, c in pairs(a.mainByName) do rows[#rows + 1] = { key = name, name = name, count = c, fluid = false } end
  for k, c in pairs(a.mainFluids) do rows[#rows + 1] = { key = k, name = k:sub(2), count = c, fluid = true } end
  return rows
end

function M.totals()
  local a = aggregate()
  local items, types = 0, 0
  for _, c in pairs(a.byName) do items = items + c; types = types + 1 end
  local ftypes = 0
  for _ in pairs(a.fluids) do ftypes = ftypes + 1 end
  return { items = items, types = types, fluids = ftypes, invs = #M.storage, tanks = #M.tankNames }
end

-- Durability left in each stored item of a "name#*" key, most first (for planning tools).
-- Damage changes the NBT hash, so it's cached per name#nbt and read once with getItemDetail.
M.dura = {}
function M.toolPoints(key)
  local name = M.parseKey(key)
  local pts = {}
  for _, inv in ipairs(itemSources()) do
    for slot, it in pairs(M.invs[inv] or {}) do
      if it.name == name then
        local k = M.itemKey(it.name, it.nbt)
        if M.dura[k] == nil then
          local ok, d = pcall(peripheral.call, inv, "getItemDetail", slot)
          M.dura[k] = ok and d and d.maxDamage and (d.maxDamage - (d.damage or 0)) or false
        end
        if M.dura[k] then
          for _ = 1, it.count do pts[#pts + 1] = M.dura[k] end
        end
      end
    end
  end
  table.sort(pts, function(a, b) return a > b end)
  return pts
end

-- Moves up to `count` of an item key from storage into inventory `to` (optional slot).
-- Craft storage first. Returns moved amount.
function M.extract(key, count, to, toSlot)
  if M.isGroup(key) then
    -- one kind per slot (a crafting slot can't hold oak and spruce); any mix without a slot
    local moved = 0
    for _, name in ipairs(M.groupMembers(key:sub(2))) do
      if moved >= count then break end
      if not toSlot or (aggregate().byName[name] or 0) >= count then
        moved = moved + M.extract(name, count - moved, to, toSlot)
        if toSlot and moved > 0 then break end
      end
    end
    if toSlot and moved == 0 then
      -- no single kind has enough: take the biggest pile, the caller sees the shortfall
      local first = M.groupMembers(key:sub(2))[1]
      if first then moved = M.extract(first, count, to, toSlot) end
    end
    return moved
  end
  local moved = M.extractCached(key, count, to, toSlot)
  if moved < count then
    -- the cached slot lists may be stale (something moved items meanwhile): rescan, retry once
    local fns = {}
    for _, inv in ipairs(itemSources()) do fns[#fns + 1] = function() M.scanInv(inv) end end
    util.parallelBatches(fns, 32)
    moved = moved + M.extractCached(key, count - moved, to, toSlot)
  end
  return moved
end

function M.extractCached(key, count, to, toSlot)
  local name, nbt = M.parseKey(key)
  local moved = 0
  for _, inv in ipairs(itemSources()) do
    local list = M.invs[inv] or {}
    for slot, it in pairs(list) do
      if moved >= count then break end
      if it.name == name and (nbt == "*" or it.nbt == nbt) then
        local ok, n = pcall(peripheral.call, inv, "pushItems", to, slot, count - moved, toSlot)
        n = ok and n or 0
        if n > 0 then
          moved = moved + n
          it.count = it.count - n
          if it.count <= 0 then list[slot] = nil end
          M.dirty = true
        end
      end
    end
    if moved >= count then break end
  end
  for _, b in ipairs(M.backends) do
    if moved >= count then break end
    for _, it in ipairs(b.items or {}) do
      if moved >= count then break end
      if it.name == name and (nbt == "*" or it.nbt == nbt) and (it.count or 0) > 0 then
        local ok, n = pcall(b.extract, it.name, it.nbt, math.min(it.count, count - moved), to, toSlot)
        n = ok and tonumber(n) or 0
        if n > 0 then
          moved = moved + n
          it.count = it.count - n
          M.dirty = true
        end
      end
    end
  end
  return moved
end

-- Pulls `limit` items from a slot of inventory `from` into storage (pass the exact count:
-- the loop only stops early once that many moved). Prefers inventories already holding the item.
-- pool = "craft": into the craft storage (main storage if it's full or not set up).
-- Returns moved amount.
function M.insert(from, fromSlot, limit, itemName, pool)
  local order = {}
  if pool == "craft" then
    for _, inv in ipairs(M.craft) do order[#order + 1] = inv end
  end
  if itemName then
    for _, inv in ipairs(M.storage) do
      for _, it in pairs(M.invs[inv] or {}) do
        if it.name == itemName then order[#order + 1] = inv break end
      end
    end
  end
  local moved, touched = 0, {}
  local function into(inv)
    if moved >= limit then return end
    local ok, n = pcall(peripheral.call, inv, "pullItems", from, fromSlot, limit - moved)
    n = ok and n or 0
    if n > 0 then moved = moved + n; touched[inv] = true end
  end
  for _, inv in ipairs(order) do into(inv) end
  -- then the networks (AE2 / RS), then any inventory with room
  if moved < limit and #M.backends > 0 then
    local name = itemName
    if not name then
      local ok, d = pcall(peripheral.call, from, "getItemDetail", fromSlot)
      name = ok and d and d.name
    end
    for _, b in ipairs(M.backends) do
      if moved >= limit or not name then break end
      local ok, n = pcall(b.insert, from, fromSlot, limit - moved, name)
      n = ok and tonumber(n) or 0
      if n > 0 then moved = moved + n; b.stale = true end
    end
  end
  for _, inv in ipairs(M.storage) do into(inv) end
  for inv in pairs(touched) do M.scanInv(inv) end
  for _, b in ipairs(M.backends) do
    if b.stale then b.stale = nil; scanBackend(b) end
  end
  return moved
end

-- Fluids (mB). Returns moved amount.
function M.extractFluid(key, amount, to)
  local name = key:sub(2)
  local moved = 0
  for _, tank in ipairs(tankSources()) do
    if moved >= amount then break end
    local ok, n = pcall(peripheral.call, tank, "pushFluid", to, amount - moved, name)
    if ok and n > 0 then moved = moved + n; M.scanTank(tank) end
  end
  for _, b in ipairs(M.backends) do
    if moved >= amount then break end
    local ok, n = pcall(b.extractFluid, name, amount - moved, to)
    n = ok and tonumber(n) or 0
    if n > 0 then moved = moved + n; scanBackend(b) end
  end
  return moved
end

function M.insertFluid(from, key, amount, pool)
  local name = key and key:sub(2)
  local moved = 0
  local order = {}
  if pool == "craft" then
    for _, t in ipairs(M.craftTanks) do order[#order + 1] = t end
  end
  -- tanks already holding this fluid first, so it doesn't spread over empty ones
  local holds = {}
  for _, t in ipairs(M.tankNames) do
    for _, f in pairs(M.tanks[t] or {}) do
      if name and f.name == name and (f.amount or 0) > 0 then holds[t] = true; order[#order + 1] = t break end
    end
  end
  local rest = {}
  for _, t in ipairs(M.tankNames) do if not holds[t] then rest[#rest + 1] = t end end
  local function into(tank)
    if amount and moved >= amount then return end
    local ok, n = pcall(peripheral.call, tank, "pullFluid", from, amount and (amount - moved) or nil, name)
    if ok and n > 0 then moved = moved + n; M.scanTank(tank) end
  end
  for _, tank in ipairs(order) do into(tank) end
  for _, b in ipairs(M.backends) do
    if name and amount and moved < amount then
      local ok, n = pcall(b.insertFluid, from, name, amount - moved)
      n = ok and tonumber(n) or 0
      if n > 0 then moved = moved + n; scanBackend(b) end
    end
  end
  for _, tank in ipairs(rest) do into(tank) end
  return moved
end

-- Moves up to n of a key from the main storage into the craft storage. Returns moved amount.
function M.stage(key, n)
  local moved = 0
  if M.isGroup(key) then
    for _, name in ipairs(M.groupMembers(key:sub(2))) do
      if moved >= n then break end
      moved = moved + M.stage(name, n - moved)
    end
    return moved
  end
  if M.isFluid(key) then
    for _, ct in ipairs(M.craftTanks) do
      for _, mt in ipairs(M.tankNames) do
        if moved >= n then break end
        local ok, got = pcall(peripheral.call, ct, "pullFluid", mt, n - moved, key:sub(2))
        if ok and got and got > 0 then moved = moved + got; M.scanTank(mt); M.scanTank(ct) end
      end
    end
    return moved
  end
  local name, nbt = M.parseKey(key)
  for _, inv in ipairs(M.storage) do
    if moved >= n then break end
    for slot, it in pairs(M.invs[inv] or {}) do
      if moved >= n then break end
      if it.name == name and (nbt == "*" or it.nbt == nbt) then
        local got = 0
        for _, ci in ipairs(M.craft) do
          if got >= math.min(it.count, n - moved) then break end
          local ok, c = pcall(peripheral.call, ci, "pullItems", inv, slot, math.min(it.count, n - moved) - got)
          if ok and c and c > 0 then got = got + c end
        end
        moved = moved + got
      end
    end
    M.scanInv(inv)
  end
  for _, b in ipairs(M.backends) do
    for _, it in ipairs(b.items or {}) do
      if moved >= n then break end
      if it.name == name and (nbt == "*" or it.nbt == nbt) and (it.count or 0) > 0 then
        for _, ci in ipairs(M.craft) do
          if moved >= n then break end
          local ok, c = pcall(b.extract, it.name, it.nbt, math.min(it.count, n - moved), ci)
          c = ok and tonumber(c) or 0
          if c > 0 then moved = moved + c; it.count = it.count - c; M.dirty = true end
        end
      end
    end
  end
  for _, ci in ipairs(M.craft) do M.scanInv(ci) end
  return moved
end

-- Everything in the craft storage back into the main storage (no order running).
function M.sweep()
  for _, inv in ipairs(M.craft) do
    for slot, it in pairs(M.invs[inv] or {}) do M.insert(inv, slot, it.count, it.name) end
    M.scanInv(inv)
  end
  for _, ct in ipairs(M.craftTanks) do
    for _, f in pairs(M.tanks[ct] or {}) do
      if f.amount and f.amount > 0 then M.insertFluid(ct, M.fluidKey(f.name), f.amount) end
    end
    M.scanTank(ct)
  end
end

-- Fetches display names for a few unknown items (getItemDetail is slow, so it's spread over time).
function M.learnNames(maxPerCall)
  local learned = 0
  for _, inv in ipairs(itemSources()) do
    for slot, it in pairs(M.invs[inv] or {}) do
      if learned >= (maxPerCall or 8) then break end
      if not M.names[it.name] then
        local ok, d = pcall(peripheral.call, inv, "getItemDetail", slot)
        M.names[it.name] = ok and d and d.displayName or util.formatName(it.name)
        learned = learned + 1
      end
    end
  end
  if learned > 0 then util.writeJSON(NAMES_FILE, M.names) end
  return learned
end

-- Background loop: full rescan every cfg.rescan seconds.
function M.loop()
  while true do
    local ok, err = pcall(M.scan)
    if not ok then log.warn("scan failed: %s", tostring(err)) end
    pcall(M.learnNames, 8)
    os.queueEvent("stock_updated")
    sleep(M.cfg.rescan or 10)
  end
end

return M

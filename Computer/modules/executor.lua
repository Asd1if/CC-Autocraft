-- Job queue and workers.
--
-- A job = one order (key x qty) with its plan. Orders form a queue and run one at a time:
-- "queued" -> "running" -> "done" | "failed" | "cancelled". Inside the running order, steps run
-- as soon as their machine/turtle is free and every dep is done or already running: a consumer
-- works with what its producers have made so far and waits for the rest (a pipeline).
-- A turtle step runs on one free turtle (other steps can use the other turtles at the same
-- time); a pool step is split between all free pool members.
-- Unfinished orders are saved to data/jobs.lua and planned again after a restart.
-- Reservation: a job reserves what its plan takes from storage, plus intermediates it produced,
-- so other orders planned meanwhile don't steal them. Reservations drop when the job ends.
-- With a craft storage set up, the reserve is also moved there when the job starts, and
-- intermediates are put there, so the player can't take them by hand. Final results go to the
-- main storage; once no job is running the craft storage is emptied back.
-- A fluid ordered with opts.deliver is poured into the encoder's recipe tanks when done
-- (M.deliverFluid, set by main.lua to encoder.deliverFluid).
local log     = require("modules.log")
local console = require("modules.console")
local net     = require("modules.net")
local tasks   = require("modules.tasks")
local indexer = require("modules.indexer")
local recipes = require("modules.recipes")
local planner = require("modules.planner")
local util    = require("modules.util")

local M = { jobs = {}, nextId = 1, busy = {}, turtles = {}, mb = {}, pools = {}, nextRestock = 0 }

M.TSLOT = { 1, 2, 3, 5, 6, 7, 9, 10, 11 } -- turtle crafting grid
local GRID_SLOT = {}
for _, s in ipairs(M.TSLOT) do GRID_SLOT[s] = true end

function M.init(cfg, multiblocks)
  M.cfg = cfg
  M.mb = multiblocks or {}
  M.pools = cfg.pools or {}
end

-- ---------------------------------------------------------------- turtles

-- Keyed by wired name: two turtles can share a computer id (copied in creative), so every
-- request carries the name and only that turtle answers (see M.ask).
function M.registerTurtle(id, name)
  local t = M.turtles[name] or { name = name }
  t.id, t.seen = id, os.clock()
  M.turtles[name] = t
end

-- A request to one turtle, addressed by its wired name.
function M.ask(t, msgType, payload, timeout)
  payload = payload or {}
  payload.name = t.name
  return net.request(t.id, msgType, payload, timeout)
end

local function alive(t) return t.name and os.clock() - t.seen < 60 end

function M.freeTurtle()
  for _, t in pairs(M.turtles) do
    if alive(t) and not t.busy then return t end
  end
end

function M.anyTurtle()
  for _, t in pairs(M.turtles) do if alive(t) then return t end end
end

local function itemKey(it) return indexer.itemKey(it.name, it.nbt) end

-- Per-slot consumption and per-key gains between two turtle inventory snapshots.
-- kept[s]: a grid slot whose item stayed (same name and count, NBT may differ) — a tool that
-- only lost durability. It is neither consumed nor a gain.
function M.diff(before, after)
  local consumed, gained, totals, kept = {}, {}, {}, {}
  for s = 1, 16 do
    local b, a = before[s], after[s]
    if GRID_SLOT[s] and b and a and a.name == b.name and a.count == b.count then
      kept[s] = true
      b, a = nil, nil
    end
    if b and (not a or itemKey(a) ~= itemKey(b)) then consumed[s] = b.count
    elseif b and a and a.count < b.count then consumed[s] = b.count - a.count end
    if b then totals[itemKey(b)] = (totals[itemKey(b)] or 0) - b.count end
    if a then totals[itemKey(a)] = (totals[itemKey(a)] or 0) + a.count end
  end
  for k, n in pairs(totals) do if n > 0 then gained[k] = n end end
  return consumed, gained, kept
end

-- Stack size of each key in a detailed turtle snapshot (craft{detail = true}).
function M.maxCounts(items)
  local m = {}
  for _, it in pairs(items or {}) do
    if it.maxCount then m[itemKey(it)] = it.maxCount end
  end
  return m
end

-- Turtle slots as console rows: "slot 5 > minecraft:stick x4".
function M.slotRows(items)
  local rows = {}
  for slot = 1, 16 do
    local it = items[slot]
    if it then rows[#rows + 1] = { "slot " .. slot, it.name .. " x" .. it.count } end
  end
  if #rows == 0 then rows[1] = { "(empty)" } end
  return rows
end

-- Empties the turtle into storage. items = known inventory snapshot (asks the turtle if nil).
-- pool = "craft" puts it into the craft storage. Errors if something stays inside: the next
-- craft would fail on it.
function M.clearTurtle(t, items, pool)
  if not items then
    local reply = M.ask(t, "inv", {}, 5)
    items = reply and reply.items or {}
  end
  for slot, it in pairs(items) do
    local moved = indexer.insert(t.name, slot, it.count, it.name, pool)
    if moved < it.count then
      error(("%s slot %d: %d %s did not fit into storage"):format(t.name, slot, it.count - moved, it.name), 0)
    end
  end
end

-- ---------------------------------------------------------------- machines

-- Inventory/tank names of one machine or multiblock (a pool member).
function M.memberIO(name)
  if M.mb[name] then return M.machineIO({ type = "multiblock", machine = name }) end
  return M.machineIO({ type = "machine", machine = name })
end

-- Inventory/tank names a recipe works with (a pool: its first member, used for the test).
function M.machineIO(r)
  if r.type == "pool" then
    local members = M.pools[r.machine] or error("unknown pool " .. tostring(r.machine))
    return M.memberIO(members[1] or error("pool " .. r.machine .. " is empty"))
  end
  if r.type == "multiblock" then
    local mb = M.mb[r.machine] or error("unknown multiblock " .. tostring(r.machine))
    local inItem  = mb.input_item or mb.item_input
    local outItem = mb.output_item or mb.item_output or inItem
    local inFluid = mb.input_fluid or mb.fluid_input or inItem
    local outFluid = mb.output_fluid or mb.fluid_output or outItem
    return { inItem = inItem, outItem = outItem, inFluid = inFluid, outFluid = outFluid }
  end
  return { inItem = r.machine, outItem = r.machine, inFluid = r.machine, outFluid = r.machine }
end

-- Counts by key in an inventory and a fluid container (either may be nil / not support it).
function M.snapshot(itemInv, fluidInv)
  local c = {}
  if itemInv then
    local ok, list = pcall(peripheral.call, itemInv, "list")
    if ok and list then
      for _, it in pairs(list) do local k = itemKey(it); c[k] = (c[k] or 0) + it.count end
    end
  end
  if fluidInv then
    local ok, list = pcall(peripheral.call, fluidInv, "tanks")
    if ok and list then
      for _, f in pairs(list) do
        if f.amount and f.amount > 0 then local k = indexer.fluidKey(f.name); c[k] = (c[k] or 0) + f.amount end
      end
    end
  end
  return c
end

-- Moves everything that isn't a recipe input out of a machine into storage: main outputs,
-- chance byproducts the test didn't see, NBT variants, leftovers of an earlier step.
-- Machines belong to autocraft, so nothing in their output is the player's. Returns key -> moved.
local function isInput(inKeys, k)
  if inKeys[k] then return true end
  for key in pairs(inKeys) do if indexer.matches(k, key) then return true end end
  return false
end

local function collect(io, inKeys, pool)
  local got = {}
  local ok, list = pcall(peripheral.call, io.outItem, "list")
  if ok and list then
    for slot, it in pairs(list) do
      local k = itemKey(it)
      if not isInput(inKeys, k) then
        local n = indexer.insert(io.outItem, slot, it.count, it.name, pool)
        if n > 0 then got[k] = (got[k] or 0) + n end
      end
    end
  end
  local fcur = M.snapshot(nil, io.outFluid)
  for k, amount in pairs(fcur) do
    if indexer.isFluid(k) and not inKeys[k] and amount > 0 then
      local n = indexer.insertFluid(io.outFluid, k, amount, pool)
      if n > 0 then got[k] = (got[k] or 0) + n end
    end
  end
  return got
end

-- ---------------------------------------------------------------- jobs

local function open(job) return job.status == "running" or job.status == "queued" end

function M.reserved(key)
  local n = 0
  for _, job in ipairs(M.jobs) do
    if open(job) then n = n + (job.reserve[key] or 0) end
  end
  return n
end

function M.avail(key)
  return indexer.count(key) - M.reserved(key)
end

local function unreserve(job, key, n)
  job.reserve[key] = math.max(0, (job.reserve[key] or 0) - n)
end

-- Outputs of a step that later steps consume stay reserved for this job as they arrive.
-- (A pool member's share of a step points to the step with s.parent.)
local function keep(job, s, key, n)
  s = s.parent or s
  if s == job.steps[#job.steps] or n <= 0 then return end
  for _, o in ipairs(s.recipe.outputs) do
    if o.key == key then job.reserve[key] = (job.reserve[key] or 0) + n return end
  end
end

-- Where a step's results and leftovers go: the craft storage, except for the last step.
local function poolFor(job, s)
  s = s.parent or s
  return s ~= job.steps[#job.steps] and "craft" or nil
end

local function depsRunning(s)
  for _, d in ipairs(s.deps) do if d.status == "run" then return true end end
  return false
end

-- Waits while producers are still running; fails the step if the job already failed.
local function waitForDeps(job)
  if job.error then error("stopped: " .. job.error, 0) end
  os.queueEvent("jobs_changed")
  sleep(1)
end

-- "Iron sword x4" / "Material Checklist x1" for an order target (key or clipboard list).
function M.label(target, qty)
  local name = type(target) == "table" and target.title or indexer.displayName(target)
  if type(target) == "string" and indexer.isFluid(target) then return name .. " " .. util.formatFluid(qty) end
  return ("%s x%d"):format(name, qty)
end

-- Auto-restock (cfg.restock = { [key] = minimum }): when no order is running, every
-- cfg.restock_interval seconds the first item below its minimum is ordered, as much of the
-- shortfall as storage allows. One order at a time, so player orders are never held up long.
function M.restock()
  local wants = M.cfg.restock or {}
  local keys = {}
  for key in pairs(wants) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local short = wants[key] - indexer.count(key)
    if short > 0 and recipes.hasRecipe(key) then
      local n = planner.maxCraftable(key, M.avail, recipes, short, indexer.toolPoints)
      if n > 0 then
        local job = M.submit(key, n, { auto = true })
        if job then
          log.info("restock: %s (below %d)", M.label(key, n), wants[key])
          return job
        end
      end
    end
  end
end

-- What an order lacks that has to be brought in: missing keys without a recipe. Craftable
-- ones only show up when the planner cut them off (ingot <-> block loops); listed only if
-- nothing else is missing. Returns { { key, n } } sorted by key.
function M.missingRows(plan)
  local raw, all = {}, {}
  for k, n in pairs(plan.missing) do
    all[#all + 1] = { k, n }
    if #recipes.forOutput(k) == 0 then raw[#raw + 1] = { k, n } end
  end
  local rows = #raw > 0 and raw or all
  table.sort(rows, function(a, b) return a[1] < b[1] end)
  return rows
end

-- Prints what an order lacks: "minecraft:iron_ingot > 8" per missing key.
function M.reportMissing(target, qty, plan)
  console.block(M.label(target, qty) .. ": not enough", colors.red, M.missingRows(plan))
end

-- Plans and queues an order (key or list); its reserve is held from now on.
-- Returns job, or nil + plan (to show what's missing). opts.auto = restock order.
function M.submit(key, qty, opts)
  local plan = planner.plan(key, qty, M.avail, recipes, indexer.toolPoints)
  if not plan.ok then return nil, plan end
  local job = {
    id = M.nextId, key = key, qty = qty, plan = plan, steps = plan.steps, auto = opts and opts.auto,
    deliver = opts and opts.deliver,
    status = "queued", reserve = planner.storageTakes(plan), started = os.clock(),
  }
  for _, s in ipairs(job.steps) do s.status, s.doneRuns = "wait", 0 end
  M.nextId = M.nextId + 1
  M.jobs[#M.jobs + 1] = job
  local ahead = -1
  for _, j in ipairs(M.jobs) do if open(j) then ahead = ahead + 1 end end
  log.info("job #%d: %s, %d steps", job.id, M.label(key, qty), #job.steps)
  console.line(("+ #%d %s%s%s"):format(job.id, job.auto and "restock: " or "", M.label(key, qty),
    ahead > 0 and (" (after %d)"):format(ahead) or ""), colors.lime)
  M.save()
  os.queueEvent("jobs_changed")
  return job
end

-- queued -> running. Steps wait until the reserve sits in the craft storage: moving it while a
-- step extracts from the same slots made the step find nothing.
local function start(job)
  job.status, job.started = "running", os.clock()
  job.staged = #indexer.craft == 0 and #indexer.craftTanks == 0
  if not job.staged then
    tasks.spawn(function()
      for key, n in pairs(job.reserve) do indexer.stage(key, n) end
      indexer.scan()
      job.staged = true
      os.queueEvent("jobs_changed")
    end, "stage")
  end
  os.queueEvent("jobs_changed")
end

-- running -> done / failed / cancelled; the craft storage is emptied before the next order.
local function deliver(job, label)
  if not (M.deliverFluid and type(job.key) == "string" and indexer.isFluid(job.key)) then return end
  local n = M.deliverFluid(job.key, job.qty)
  if n < job.qty then
    console.block(label .. ": encoder tanks are full", colors.orange,
      { { "poured", util.formatFluid(n) }, { "left in storage", util.formatFluid(job.qty - n) } })
  end
end

-- Whether a finished order of `target` goes into the encoder tanks (a fluid, tanks set up).
function M.canDeliver(target)
  return type(target) == "string" and indexer.isFluid(target) and #(M.cfg.recipe_tanks or {}) > 0
end

local function finish(job, status)
  job.status, job.reserve, job.ended = status, {}, os.clock()
  local label = ("#%d %s"):format(job.id, M.label(job.key, job.qty))
  if status == "done" then
    log.info("job %s done", label)
    console.line("v " .. label .. " done", colors.green)
  elseif status == "cancelled" then
    log.info("job %s cancelled", label)
    console.block(label .. ": cancelled", colors.orange, { { "items are going back to storage" } })
  else
    log.info("job %s failed: %s", label, tostring(job.error))
    console.block(label .. ": failed", colors.red, { { job.error or "?" } })
  end
  M.save()
  M.cleaning = true
  tasks.spawn(function()
    if status == "done" and job.deliver then deliver(job, label) end
    indexer.sweep()
    M.cleaning = false
    os.queueEvent("jobs_changed")
  end, "sweep")
  os.queueEvent("jobs_changed")
end

-- Cancels the running order (or the first queued one). Returns the job or nil.
function M.cancel()
  local target = M.activeJob()
  if not target then
    for _, j in ipairs(M.jobs) do if j.status == "queued" then target = j break end end
  end
  if not target then return nil end
  if target.status == "queued" then
    target.status, target.reserve, target.ended = "cancelled", {}, os.clock()
    console.line(("x #%d %s cancelled"):format(target.id, M.label(target.key, target.qty)), colors.orange)
    M.save()
  else
    target.cancelled, target.error = true, "cancelled"
    console.line(("x #%d %s: stopping..."):format(target.id, M.label(target.key, target.qty)), colors.orange)
  end
  os.queueEvent("jobs_changed")
  return target
end

local JOBS_FILE = "data/jobs.lua"

-- Unfinished orders (queued and running) in queue order, so a restart picks them up.
function M.save()
  if not fs or not fs.open then return end
  local list = {}
  for _, j in ipairs(M.jobs) do
    if open(j) then list[#list + 1] = { key = j.key, qty = j.qty, auto = j.auto, deliver = j.deliver } end
  end
  local h = fs.open(JOBS_FILE, "w")
  if not h then return end
  h.write(textutils.serialise(list))
  h.close()
end

-- Plans the saved orders again from what's in storage now: what was already made counts as
-- stock, so only the rest is crafted.
function M.restore()
  if not fs or not fs.exists or not fs.exists(JOBS_FILE) then return end
  local h = fs.open(JOBS_FILE, "r")
  local list = textutils.unserialise(h.readAll()) or {}
  h.close()
  if #list == 0 then return end
  console.line(("Restoring %d order(s) from before the restart"):format(#list), colors.yellow)
  for _, o in ipairs(list) do
    local job, plan = M.submit(o.key, o.qty, { auto = o.auto, deliver = o.deliver })
    if not job then M.reportMissing(o.key, o.qty, plan) end
  end
  M.save()
end

function M.progress(job)
  local done, total = 0, 0
  for _, s in ipairs(job.steps) do total = total + s.runs; done = done + (s.progress or s.doneRuns or 0) end
  return total == 0 and 1 or done / total
end

-- Puts n runs of a turtle recipe into the grid. On a shortfall everything placed goes back
-- (reserved again) and it returns nil + message.
local function fill(job, r, t, n)
  local placed = {}
  for i = 1, 9 do
    local g = r.grid[i]
    if g.key then
      local need = g.tool and 1 or g.count * n
      local moved = indexer.extract(g.key, need, t.name, M.TSLOT[i])
      if not g.tool then unreserve(job, g.key, moved); placed[g.key] = (placed[g.key] or 0) + moved end
      if moved < need then
        M.clearTurtle(t, nil, "craft")
        for key, c in pairs(placed) do job.reserve[key] = (job.reserve[key] or 0) + c end
        return nil, ("not enough %s (%d/%d)"):format(indexer.displayName(g.key), moved, need)
      end
    end
  end
  return true
end

local function runTurtle(job, s, t)
  local r = s.recipe
  local mainKey = recipes.mainKey(r)
  local per = recipes.yield(r, mainKey)
  -- recipes saved before maxCount was recorded: first craft one, learn the stack sizes
  local learn = false
  for _, o in ipairs(r.outputs) do if not o.maxCount then learn = true end end

  local perRun = {}
  for i = 1, 9 do
    local g = r.grid[i]
    if g.key then perRun[g.key] = (perRun[g.key] or 0) + (g.tool and 0 or g.count) end
  end

  M.clearTurtle(t)
  local left = s.runs
  while left > 0 do
    if job.error then error("stopped", 0) end
    local n = math.min(recipes.turtleBatch(r, M.cfg.batch), left)
    -- producers still running: craft what is there already, wait if nothing is
    while depsRunning(s) do
      local can = n
      for key, c in pairs(perRun) do
        local have = indexer.count(key)
        if c == 0 then
          if have < 1 then can = 0 end
        else
          can = math.min(can, math.floor(have / c))
        end
      end
      if can >= 1 then n = can break end
      waitForDeps(job)
    end
    local feeding = depsRunning(s)
    local filled, short = fill(job, r, t, n)
    if not filled then
      -- producers were running: another turtle took what was there, wait for more
      if not (feeding or depsRunning(s)) then error(short, 0) end
      waitForDeps(job)
    else
      local reply, err = M.ask(t, "craft", { count = n, detail = learn }, 15)
      if not reply then M.clearTurtle(t, nil, "craft"); error("turtle: " .. tostring(err), 0) end
      if not reply.ok then
        console.block(("%s: craft failed: %s"):format(t.name, tostring(reply.error)), colors.red, M.slotRows(reply.before or {}))
        M.clearTurtle(t, reply.after, "craft")
        error(("%s: craft failed: %s"):format(t.name, tostring(reply.error)), 0)
      end
      local _, gained = M.diff(reply.before, reply.after)
      M.clearTurtle(t, reply.after, poolFor(job, s))
      for k, c in pairs(gained) do keep(job, s, k, c) end
      if learn then
        local mc = M.maxCounts(reply.after)
        for _, o in ipairs(r.outputs) do o.maxCount = o.maxCount or mc[o.key] end
        recipes.save()
        learn = false
      end
      -- a tool can break mid-batch: count what was crafted, the next batch takes a new one
      local done = math.min(n, math.floor((gained[mainKey] or 0) / per))
      if done == 0 then
        error(("crafted %d/%d %s"):format(gained[mainKey] or 0, per * n, indexer.displayName(mainKey)), 0)
      end
      if done < n then
        for i = 1, 9 do
          local g = r.grid[i]
          if g.key and not g.tool then job.reserve[g.key] = (job.reserve[g.key] or 0) + g.count * (n - done) end
        end
      end
      left = left - done
      s.doneRuns = s.doneRuns + done
      os.queueEvent("jobs_changed")
    end
  end
end

local function runMachine(job, s)
  local r = s.recipe
  local io = s.io or M.machineIO(r)
  -- inputs are fed at most cfg.batch runs ahead of what came out
  local perRun, fed = {}, {}
  for _, inp in ipairs(r.inputs) do perRun[inp.key] = (perRun[inp.key] or 0) + inp.count; fed[inp.key] = 0 end
  local batch = math.max(1, M.cfg.batch or 16)
  -- inputs stay in the machine when it is also the output (depot, basin); separate output
  -- blocks (multiblocks) give everything back
  local inKeys = {}
  if io.inItem == io.outItem or io.inFluid == io.outFluid then
    for key in pairs(perRun) do inKeys[key] = true end
  end
  local mainKey = recipes.mainKey(r)
  local per = recipes.yield(r, mainKey)
  local expect = per * s.runs
  local pool = poolFor(job, s)

  local produced, last, lastOut = 0, os.clock(), os.clock()
  local timeout = M.cfg.craft_timeout or 60
  while produced < expect do
    if job.error then error("stopped: " .. job.error, 0) end
    local runs = math.min(s.runs, math.floor(produced / per) + batch)
    for key, c in pairs(perRun) do
      local n = c * runs - fed[key]
      if n > 0 then
        local moved
        if indexer.isFluid(key) then moved = indexer.extractFluid(key, n, io.inFluid)
        else moved = indexer.extract(key, n, io.inItem) end
        if moved > 0 then fed[key] = fed[key] + moved; unreserve(job, key, moved); last = os.clock() end
      end
    end
    sleep(0.5)
    local got = collect(io, inKeys, pool)
    for k, n in pairs(got) do
      if k == mainKey then produced = produced + n; lastOut = os.clock() end
      keep(job, s, k, n)
      last = os.clock()
    end
    s.doneRuns = math.min(s.runs, math.floor(produced / per))
    -- between outputs the bar moves by the time one run took in the test
    local inside = math.huge
    for key, c in pairs(perRun) do inside = math.min(inside, math.floor(fed[key] / c)) end
    if inside == math.huge then inside = s.runs end
    local inFlight = math.min(s.runs, inside) - s.doneRuns
    local partial = 0
    if inFlight > 0 and (r.time or 0) > 0 then
      partial = math.min(inFlight - 0.05, (os.clock() - lastOut) / r.time)
    end
    s.progress = s.doneRuns + math.max(0, partial)
    os.queueEvent("jobs_changed")
    -- waiting for a running producer is not idling
    if depsRunning(s) then last = os.clock() end
    if os.clock() - last > timeout then
      error(("%s idle for %ds (%d/%d)"):format(io.inItem, timeout, produced, expect), 0)
    end
  end
  -- byproducts can come out after the main result: drain until 2 s pass with nothing new
  local quiet = 0
  while quiet < 4 do
    sleep(0.5)
    local got = collect(io, inKeys, pool)
    if next(got) then
      quiet = 0
      for k, n in pairs(got) do keep(job, s, k, n) end
    else
      quiet = quiet + 1
    end
  end
end

-- A step split between pool members: each gets a share of the runs and
-- works it like a step of its own (sub.parent = s); the step's progress is their sum.
local function runSplit(job, s, workers, work)
  local subs, fns = {}, {}
  local n = #workers
  for i, w in ipairs(workers) do
    local share = math.floor(s.runs / n) + (i <= s.runs % n and 1 or 0)
    if share > 0 then
      local sub = { key = s.key, recipe = s.recipe, runs = share, deps = s.deps, doneRuns = 0, parent = s }
      subs[#subs + 1] = sub
      fns[#fns + 1] = function() work(sub, w); sub.finished = true end
    end
  end
  fns[#fns + 1] = function()
    while true do
      local done, progress, all = 0, 0, true
      for _, sub in ipairs(subs) do
        done = done + sub.doneRuns
        progress = progress + (sub.progress or sub.doneRuns)
        if not sub.finished then all = false end
      end
      s.doneRuns, s.progress = done, progress
      if all then return end
      sleep(0.5)
    end
  end
  parallel.waitForAll(table.unpack(fns))
end

local function runPool(job, s, members)
  runSplit(job, s, members, function(sub, name)
    sub.io = M.memberIO(name)
    runMachine(job, sub)
  end)
end

-- Everything in a machine (inputs too) back to storage: after a failed or cancelled step.
local function drain(io)
  for _, inv in ipairs({ io.inItem, io.outItem }) do
    local ok, list = pcall(peripheral.call, inv, "list")
    if ok and list then
      for slot, it in pairs(list) do indexer.insert(inv, slot, it.count, it.name, "craft") end
    end
  end
  for _, tank in ipairs({ io.inFluid, io.outFluid }) do
    for k, amount in pairs(M.snapshot(nil, tank)) do
      if indexer.isFluid(k) and amount > 0 then indexer.insertFluid(tank, k, amount, "craft") end
    end
  end
end

local function busyKey(name)
  return (M.mb[name] and "mb:" or "") .. name
end

-- Which resource a step needs and whether it's free. Returns a claim or nil.
-- A turtle step takes one free turtle, a pool step every free member (no more than it has runs).
local function claimFor(s)
  local r = s.recipe
  if r.type == "turtle" then
    local t = M.freeTurtle()
    if not t then return nil end
    t.busy = true
    return { turtle = t }
  elseif r.type == "pool" then
    local got = {}
    for _, name in ipairs(M.pools[r.machine] or {}) do
      if #got >= s.runs then break end
      if not M.busy[busyKey(name)] then got[#got + 1] = name end
    end
    if #got == 0 then return nil end
    local keys = {}
    for _, name in ipairs(got) do keys[#keys + 1] = busyKey(name); M.busy[busyKey(name)] = true end
    return { members = got, keys = keys }
  else
    local key = (r.type == "multiblock" and "mb:" or "") .. r.machine
    if not M.busy[key] then M.busy[key] = true; return { machine = key, io = M.machineIO(r) } end
  end
end

local function release(c)
  if c.turtle then c.turtle.busy = false end
  if c.machine then M.busy[c.machine] = nil end
  for _, k in ipairs(c.keys or {}) do M.busy[k] = nil end
end

local function runStep(job, s, claim)
  local ok, err = pcall(function()
    if claim.turtle then runTurtle(job, s, claim.turtle)
    elseif claim.members then runPool(job, s, claim.members)
    else runMachine(job, s) end
  end)
  if not ok then
    -- don't leave half-processed things in machines
    if claim.io then pcall(drain, claim.io) end
    for _, name in ipairs(claim.members or {}) do pcall(drain, M.memberIO(name)) end
  end
  release(claim)
  if ok then
    s.status, s.doneRuns, s.progress = "done", s.runs, nil
  elseif job.error then
    -- stopped because another step failed: keep that step's error as the job's
    s.status, s.error = "fail", "stopped"
  else
    s.status, s.error = "fail", tostring(err)
    job.error = indexer.displayName(s.key) .. ": " .. tostring(err)
    log.info("job #%d step %s failed: %s", job.id, indexer.displayName(s.key), tostring(err))
  end
  os.queueEvent("jobs_changed")
end

-- Deps already holding their machine can feed this step while it runs. A dep still waiting
-- for a machine can't: this step would sit on its own machine and maybe block that one.
local function depsReady(s)
  for _, d in ipairs(s.deps) do if d.status ~= "done" and d.status ~= "run" then return false end end
  return true
end

function M.schedule()
  local cur = M.activeJob()
  if cur then
    local allDone, anyRunning, anyFailed = true, false, false
    for _, s in ipairs(cur.steps) do
      if s.status == "fail" then anyFailed = true end
      if s.status == "wait" and cur.staged and not cur.error and depsReady(s) then
        local claim = claimFor(s)
        if claim then
          s.status = "run"
          tasks.spawn(runStep, "step", cur, s, claim)
        end
      end
      if s.status ~= "done" then allDone = false end
      if s.status == "run" then anyRunning = true end
    end
    if allDone then finish(cur, "done")
    elseif (anyFailed or cur.cancelled) and not anyRunning then
      finish(cur, cur.cancelled and "cancelled" or "failed")
    end
  elseif not M.cleaning then
    local nxt
    for _, j in ipairs(M.jobs) do if j.status == "queued" then nxt = j break end end
    if nxt then
      start(nxt)
    elseif M.cfg.restock and next(M.cfg.restock) and os.clock() >= M.nextRestock then
      M.nextRestock = os.clock() + (M.cfg.restock_interval or 30)
      M.restock()
    end
  end
  -- keep only the last finished jobs
  local finished = 0
  for i = #M.jobs, 1, -1 do
    if not open(M.jobs[i]) then
      finished = finished + 1
      if finished > 10 then table.remove(M.jobs, i) end
    end
  end
end

-- Rows for the queue on the monitor, at most `limit`: orders done in the last 10 s, the
-- running one, then the queued ones in order. Failures are reported in the terminal.
function M.queueRows(limit)
  local rows = {}
  for _, j in ipairs(M.jobs) do
    if j.status == "done" and os.clock() - j.ended < 10 then rows[#rows + 1] = j end
  end
  local cur = M.activeJob()
  if cur then rows[#rows + 1] = cur end
  for _, j in ipairs(M.jobs) do if j.status == "queued" then rows[#rows + 1] = j end end
  while #rows > limit do table.remove(rows, 1) end
  return rows
end

function M.activeJob()
  for i = #M.jobs, 1, -1 do
    if M.jobs[i].status == "running" then return M.jobs[i] end
  end
end

function M.loop()
  while true do
    M.schedule()
    local timer = os.startTimer(0.5)
    while true do
      local e, a = os.pullEvent()
      if (e == "timer" and a == timer) or e == "jobs_changed" then break end
    end
  end
end

-- for offline tests
M._runMachine = runMachine
M._runPool = runPool

return M

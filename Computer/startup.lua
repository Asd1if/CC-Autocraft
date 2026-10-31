-- STORAGE / AUTOCRAFT PC: index, live_stock UI, recipe encoder, planner, job queue.
--   config.lua        settings (made from system/default/config.lua on the first start)
--   data/             recipes, names, queue, log: everything the PC writes
--   mods/             your own mods (see MODS.md), system/mods/ holds the shipped ones
--   system/           the program itself: the installer replaces it on every update
local util     = require("system.utils.util")
local log      = require("system.utils.log")
local api      = require("system.core.api")
local modsys   = require("system.core.mods")
local net      = require("system.core.net")
local tasks    = require("system.core.tasks")
local indexer  = require("system.core.indexer")
local screen   = require("system.core.screen")
local tankpanel = require("system.core.tankpanel")
local recipes  = require("system.craft.recipes")
local planner  = require("system.craft.planner")
local executor = require("system.craft.executor")
local encoder  = require("system.craft.encoder")
local console  = require("system.utils.console")
local settings = require("system.core.settings")
local update   = require("system.core.update")

util.firstStart() -- config.lua, data/multiblock.json, mods/; moves an old data/config.lua

local cfg = util.loadConfig({
  main_TextScale = 1, fluid_TextScale = 0.5, storage = { "create:item_vault" }, tanks = { "create:fluid_tank" },
  exclude = {}, recipe_tanks = {}, craft_timeout = 60, rescan = 10, batch = 16, clipboard_skip_checked = true,
  craft_storage = {}, craft_tanks = {}, pools = {}, restock = {}, restock_interval = 30, debug = false, substitutes = {},
  mods_disabled = {}, gtceu_tier_up = true,
})
log.file = "data/autocraft.log"
log.level = cfg.debug_mode and 1 or 3 -- not debug: only WARN and ERROR reach the file
log.info("autocraft starting")

-- Start menu: Main (after 10 s without a key), Settings, Update
local choice = settings.startMenu(10)
if choice == "Settings" then
  settings.run({ cfg = cfg, mods = modsys.names() }) -- edits cfg in place, the start goes on with it
elseif choice == "Update" then
  local ok, err = pcall(update.run, cfg)
  if not ok then printError(err); print("Starting the old version in 5 s"); sleep(5) end
end

net.open(cfg.rednet_modem) -- nil: every modem, the wired one is enough

-- data/multiblock.json: blocks that belong to a multiblock are machines, not storage
local multiblocks, mbParts
local function readMultiblocks()
  multiblocks = util.readJSON("data/multiblock.json") or {}
  mbParts = {}
  for _, mb in pairs(multiblocks) do
    for _, field in ipairs({ "input_item", "output_item", "input_fluid", "output_fluid",
      "item_input", "item_output", "fluid_input", "fluid_output" }) do
      if mb[field] then mbParts[mb[field]] = true end
    end
    for _, name in ipairs(type(mb.inputs) == "table" and mb.inputs or {}) do mbParts[name] = true end
  end
end
readMultiblocks()

api.cfg, api.storage, api.recipes, api.planner, api.executor, api.encoder = cfg, indexer, recipes, planner, executor, encoder
api.net, api.tasks, api.util, api.log, api.console = net, tasks, util, log, console
modsys.load(api, _ENV)

recipes.load()
indexer.init(cfg, mbParts)
indexer.scan()
indexer.sweep() -- leftovers of orders from before a restart
executor.init(cfg, multiblocks)
encoder.init(cfg)
screen.init(cfg, multiblocks)
executor.deliverFluid = encoder.deliverFluid
recipes.matches, recipes.groupMembers, recipes.substitute = indexer.matches, indexer.groupMembers, indexer.substitute
recipes.parallel = executor.parallel
local hasTankMonitor = tankpanel.init(cfg, screen.monName)
api.emit("init")
executor.restore() -- orders that were unfinished when the PC stopped
log.info("%d recipes, %d item types", #recipes.list, indexer.totals().types)

-- New or removed blocks on the network (and ADD on the monitor): find storage, machines and
-- multiblocks again. Attach events come in bursts, so it waits a moment for the last one.
function api.rediscover()
  readMultiblocks()
  indexer.init(cfg, mbParts)
  executor.mb = multiblocks
  screen.multiblocks = multiblocks
  api.emit("peripherals")
  indexer.scan()
  os.queueEvent("stock_updated")
end

local function watchPeripherals()
  while true do
    local e = os.pullEvent()
    if e == "peripheral" or e == "peripheral_detach" or e == "autocraft_rediscover" then
      local timer = os.startTimer(1)
      repeat
        local ev, id = os.pullEvent()
      until ev == "timer" and id == timer
      api.rediscover()
    end
  end
end

net.on("turtle_hello", function(msg)
  local name = tostring(msg.payload.name)
  if not executor.turtles[name] then
    local same = {}
    for other, t in pairs(executor.turtles) do
      if t.id == msg.from then same[#same + 1] = other end
    end
    if #same > 0 then
      log.info("turtle %d online as %s (same id as %s: copied? works, addressed by name)", msg.from, name, table.concat(same, ", "))
    else
      log.info("turtle %d online as %s", msg.from, name)
    end
  end
  executor.registerTurtle(msg.from, msg.payload.name)
end)

tasks.forever(net.run, "net")
tasks.forever(indexer.loop, "indexer")
tasks.forever(executor.loop, "executor")
tasks.forever(screen.loop, "screen")
tasks.forever(watchPeripherals, "peripherals")
if hasTankMonitor then tasks.forever(tankpanel.loop, "tanks") end
tasks.run()

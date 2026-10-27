-- STORAGE / AUTOCRAFT PC: index, live_stock UI, recipe encoder, planner, job queue.
local log      = require("modules.log")
local util     = require("modules.util")
local net      = require("modules.net")
local tasks    = require("modules.tasks")
local indexer  = require("modules.indexer")
local recipes  = require("modules.recipes")
local executor = require("modules.executor")
local encoder  = require("modules.encoder")
local screen   = require("modules.screen")
local tankpanel = require("modules.tankpanel")

util.installDefaults("defaults", "data") -- first start: config.lua, multiblock.json

local cfg = util.loadConfig({
  text_scale = 1, storage = { "create:item_vault" }, tanks = { "create:fluid_tank" },
  exclude = {}, recipe_tanks = {}, craft_timeout = 60, rescan = 10, batch = 16, clipboard_skip_checked = true,
  craft_storage = {}, craft_tanks = {}, pools = {}, restock = {}, restock_interval = 30, debug = false, substitutes = {},
  recipe_tanks = {},
})
log.file = "data/autocraft.log"
log.level = cfg.debug and 1 or 3 -- not debug: only WARN and ERROR reach the file
log.info("autocraft starting")

net.open(cfg.modem) -- nil: every modem, the wired one is enough

local multiblocks = util.readJSON("data/multiblock.json") or {}
local mbParts = {}
for _, mb in pairs(multiblocks) do
  for _, field in ipairs({ "input_item", "output_item", "input_fluid", "output_fluid",
    "item_input", "item_output", "fluid_input", "fluid_output" }) do
    if mb[field] then mbParts[mb[field]] = true end
  end
end

recipes.load()
indexer.init(cfg, mbParts)
indexer.scan()
indexer.sweep() -- leftovers of orders from before a restart
executor.init(cfg, multiblocks)
encoder.init(cfg)
screen.init(cfg, multiblocks)
executor.deliverFluid = encoder.deliverFluid
recipes.matches, recipes.tagMembers = indexer.matches, indexer.tagMembers
local hasTankMonitor = tankpanel.init(cfg, screen.monName)
executor.restore() -- orders that were unfinished when the PC stopped
log.info("%d recipes, %d item types", #recipes.list, indexer.totals().types)

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
if hasTankMonitor then tasks.forever(tankpanel.loop, "tanks") end
tasks.run()

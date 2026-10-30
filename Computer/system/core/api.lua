-- The API mods get (system/mods/*.lua, mods/*.lua). One shared table: startup.lua fills in the
-- core modules, mods add hooks and buttons. See MODS.md in the repository for a full example.
--
--   api.cfg                       config.lua as loaded (mods read their own keys from it)
--   api.storage / recipes / planner / executor / encoder / net / tasks / util / log / console
--   api.on(event, fn)             subscribe; fn(...) gets the event's arguments
--   api.emit(event, ...)          call every subscriber (errors are logged, never fatal)
--   api.any(event, ...)           true if a subscriber returns true
--   api.filter(event, value, ...) each subscriber may return a new value (nil keeps it)
--   api.button{ label, onTouch, active }  a button on the bottom bar of the main monitor
--   api.ui.select(target)         show a plan for an item key or a list { title, items }
--   api.ui.message(text, color)   status line of the main monitor
--   api.ui.selected()             what the monitor shows now (key, list or nil)
--   api.rediscover()              find storage, machines and multiblocks again
--
-- Events the core sends:
--   "init"                         every module is ready (after the first storage scan)
--   "peripherals"                  the network changed (attach / detach, ADD pressed)
--   "recipe.encode"  (draft)       a tested recipe before it is saved: add fields to it
--   "machine.workers" (list, r)    filter: peripheral names that may run machine recipe r
--   "machine.keep"   (inv, item)   any: true leaves that item inside the machine (a circuit)
--   "machine.label"  (text, name)  filter: text after "[ID-n]" in the ADD menu (starts as "")
--   "storage.backends" (list, cfg, exclude)  filter: add storage that isn't an inventory (an
--                                  AE2 / RS bridge), see system/core/indexer.lua
--   "order.done" / "order.failed" / "order.cancelled" (job)
local log = require("system.utils.log")

local api = { hooks = {}, buttons = {}, ui = {}, mods = {} }

function api.on(event, fn)
  local list = api.hooks[event] or {}
  api.hooks[event] = list
  list[#list + 1] = fn
end

local function call(event, fn, ...)
  local ok, res = pcall(fn, ...)
  if not ok then log.error("hook '%s' failed: %s", event, tostring(res)) return nil end
  return res
end

function api.emit(event, ...)
  for _, fn in ipairs(api.hooks[event] or {}) do call(event, fn, ...) end
end

function api.any(event, ...)
  for _, fn in ipairs(api.hooks[event] or {}) do
    if call(event, fn, ...) == true then return true end
  end
  return false
end

function api.filter(event, value, ...)
  for _, fn in ipairs(api.hooks[event] or {}) do
    local v = call(event, fn, value, ...)
    if v ~= nil then value = v end
  end
  return value
end

-- b = { label = "[Clip]", onTouch = function() end, active = function() return bool end }
function api.button(b)
  api.buttons[#api.buttons + 1] = b
  return b
end

-- Replaced by the screen once it starts.
function api.ui.select() end
function api.ui.selected() end
function api.ui.message(text) log.info("%s", text) end

return api

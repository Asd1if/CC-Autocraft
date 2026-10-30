# Mods / Моды

A mod is one Lua file. Shipped mods live in `system/mods/` on the computer (`create.lua`, `gtceu.lua`), your own go into `mods/`: the installer never touches that folder. A file in `mods/` with the same name as a shipped one replaces it. Turn a mod off in `config.lua`: `mods_disabled = { "gtceu" }`.

Мод — один Lua-файл. Встроенные лежат в `system/mods/`, свои кладите в `mods/` — установщик эту папку не трогает. Файл в `mods/` с тем же именем заменяет встроенный. Выключить мод: `mods_disabled = { "gtceu" }` в `config.lua`.

## Skeleton / Шаблон
```lua
-- mods/notify.lua: says in chat when an order is done (Advanced Peripherals Chat Box)
local M = { name = "notify", description = "order messages in chat" }

function M.init(api)
  local box = peripheral.find("chatBox")
  if not box then return false end -- not needed here: the mod stays inactive
  api.on("order.done", function(job)
    box.sendMessage(api.executor.label(job.key, job.qty) .. " is ready", "Autocraft")
  end)
  api.on("order.failed", function(job)
    box.sendMessage(api.executor.label(job.key, job.qty) .. ": " .. tostring(job.error), "Autocraft")
  end)
end

return M
```
`init` runs once on start, before the first storage scan. Errors in a mod or a hook are printed and logged, the rest keeps running.

## The `api` table
| | |
|---|---|
| `api.cfg` | `config.lua` as loaded; a mod reads its own keys from it |
| `api.storage` | storage index: `count(key)`, `extract(key, n, to, slot)`, `insert(from, slot, n)`, `stockList()`, `displayName(key)` |
| `api.recipes`, `api.planner`, `api.executor`, `api.encoder` | crafting: recipe store, planner, order queue (`submit(key, qty)`, `cancel()`, `avail(key)`), encoder |
| `api.net`, `api.tasks`, `api.util`, `api.log`, `api.console` | rednet messages, `tasks.spawn(fn, name)` / `tasks.forever(fn, name)` for loops, helpers, log file, terminal messages |
| `api.on(event, fn)` | subscribe to an event |
| `api.emit(event, ...)`, `api.any(...)`, `api.filter(...)` | send your own events |
| `api.button{ label, onTouch, active }` | a button at the right end of the main monitor's bottom bar; `active()` lights it |
| `api.ui.select(target)` | show a plan: an item key or `{ title, items = { { key, count } } }` |
| `api.ui.selected()`, `api.ui.message(text, color)` | what the monitor shows; a status line message |
| `api.rediscover()` | find storage, machines and multiblocks again |
| `api.mods` | loaded mods by name (call another mod's functions) |

Item keys: `"minecraft:oak_planks"`, `"name#nbt"` for NBT variants, `"name#*"` any variant, `"~minecraft:water"` a fluid (mB), `"@planks"` any member of a substitute group.

## Events
| Event | Arguments | Kind |
|---|---|---|
| `init` | | after every module started |
| `peripherals` | | the network changed (block attached / detached, ADD pressed) |
| `recipe.encode` | `draft` | a tested recipe before it is saved: add your own fields |
| `machine.workers` | `list, recipe` | filter: return the peripheral names that may run a machine recipe (several = shared like a pool) |
| `machine.keep` | `inventory, item` | return `true` to leave an item inside a machine (a GregTech circuit) |
| `machine.label` | `text, name` | filter: text shown after `[ID-n]` in the ADD menu |
| `order.done`, `order.failed`, `order.cancelled` | `job` | `job.key`, `job.qty`, `job.error` |

`filter` hooks return a new value or `nil` to keep the current one; `any` hooks return `true` to say yes.

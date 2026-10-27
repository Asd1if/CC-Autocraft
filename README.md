# CC-Autocraft

**English** | [Русский](README.ru.md)

Storage and autocrafting for CC: Tweaked (Minecraft 1.21.1, NeoForge), built for Create and GregTech CEu. One computer with a monitor runs the storage and the crafting:

- the stock list on a monitor, with search, sorting, items and fluids;
- recipes are encoded by a **test craft**: lay the recipe into a barrel, pick turtle / machine / multiblock / machine pool, and the computer measures what was consumed and produced;
- a **craft tree** for any amount, with what is in stock, what will be crafted and what is missing;
- an **order queue** (FIFO, saved across restarts) where steps run in parallel on free turtles and machines;
- crafty turtles for crafting-table recipes, any Create / GregTech machine for the rest;
- tools that wear out (hammers, wrenches) are planned by durability;
- **tag substitutes**: a recipe encoded with oak planks takes any planks;
- auto-restock, Create clipboard orders, a small tank monitor for the encoder.

The [Mod](Mod) folder holds an EMI/JEI addon that lays a recipe from the recipe viewer into the encoder barrel (Fabric 1.20.1 / 1.21.1, Forge 1.20.1, NeoForge 1.21.1).

## Install
Run in game, on the storage computer and on each crafty turtle (the installer detects turtles):
```
wget run https://raw.githubusercontent.com/Asd1if/CC-Autocraft/main/install.lua
```
The same command updates. `data/` (recipes, config, queue) is never touched. Manual install: copy `Computer/` onto the computer and `Turtle/` onto the turtle.

The first start copies `defaults/config.lua` and `defaults/multiblock.json` into `data/`. Edit `data/config.lua`: it is a Lua table where every key is commented (in Russian).

## Wiring
```
             wired modem network (one cable)
 ┌───────────┬──────────┬──────────┬───────────┬──────────┬──────────┐
 Computer   storage    fluid      encoder     machines   crafty
 + monitor  (vaults)   tanks      barrel +    (Create,   turtle(s)
                                  recipe      GregTech)  + wired modem
                                  tanks
```
- The computer and every block it uses sit on one wired modem network. Right-click each modem so its ring turns red.
- Turtles take commands over the same cable (rednet works on wired modems). Wireless modems are optional.
- A turtle announces itself, there is nothing to configure. Several turtles work in parallel on different steps.
- A second small monitor (1x1 is enough) shows the encoder tanks and drains them into storage.

## Encoding a recipe
1. Lay one craft into the barrel grid: slots 4,5,6 / 13,14,15 / 22,23,24 (the middle 3x3 of a 27-slot barrel), and fluids into the recipe tanks.
2. On the monitor press **ADD**, then Turtle / Machine / Multiblock / Pool, then the machine.
3. The test runs once, the results come back to the barrel (slot 14 first), and the recipe is saved.

Items carrying a tag from `substitutes` in the config become "any item of that tag". Keep that list to tags that don't change the result: planks yes, logs no (a spruce log gives spruce planks).

## Monitor
- Tap an item to see its craft tree. `< << ][ >> >` is −1, −10, order, +10, +1, and `[N]` is the most you can make.
- An order always crafts the ordered item, even if storage has some. Ingredients come from storage, and so do fluids and items without a recipe.
- On the selected item with a recipe, `+` turns into a red `-`. Tap it twice within 5 s to delete that recipe.
- The queue shows on top of the list: green is done, yellow is crafting, orange is next, red is later. Tap a row to see its tree.
- **S** on the computer's keyboard searches; **Q** cancels the running order.
- `[Clip]` reads a Create clipboard (Material Checklist) through an Advanced Peripherals Block Reader and orders the whole list.
- Messages (order placed, done, missing items, failures) are printed in the computer's terminal.

## Config highlights (`data/config.lua`)
| Key | What |
|---|---|
| `storage`, `tanks` | storage inventories / tanks: a type (`create:item_vault`) or exact names |
| `craft_storage`, `craft_tanks` | separate storage for running orders, so the player can't take their items |
| `encoder`, `recipe_tanks` | the encoder barrel and its fluid tanks |
| `pools` | several identical machines under one name, a step is split between them |
| `restock` | minimum stock that is crafted automatically when nothing else runs |
| `substitutes` | tags that encode as "any item of the tag" |
| `batch` | crafts per turtle call / machine load-ahead (default 16) |
| `debug` | full log in `data/autocraft.log` (otherwise warnings and errors only) |

## When something breaks
The main loops (screen, network, storage, queue, tank monitor) restart after an error, at most 5 times a minute. The error and its stack go to `data/autocraft.log`. Please attach that part of the log to an issue.

## License
[MIT](LICENSE)

# CC-Autocraft

**English** | [Русский](README.ru.md)

Storage and autocrafting for CC: Tweaked (Minecraft 1.21.1, NeoForge), built for Create and GregTech CEu. One computer with a monitor runs the storage and the crafting:

- the stock list on a monitor, with search, sorting, items and fluids;
- recipes are encoded by a **test craft**: lay the recipe into a barrel, pick turtle / machine / multiblock / machine pool, and the computer measures what was consumed and produced;
- a **craft tree** for any amount, with what is in stock, what will be crafted and what is missing;
- an **order queue** (FIFO, saved across restarts) where steps run in parallel on free turtles and machines;
- crafty turtles for crafting-table recipes, any Create / GregTech machine for the rest;
- tools that wear out (hammers, wrenches) are planned by durability;
- **substitute groups**: a recipe encoded with oak planks takes any planks;
- auto-restock, a small tank monitor for the encoder;
- **mods**: Create clipboard orders, GregTech circuits and tiers, AE2 / Refined Storage as storage, and your own (see [MODS.md](MODS.md)).

Most machines of other mods work too: anything with an inventory the computer can reach. Machines that need items in several places at once (a Create deployer's hand + the depot under it) are multiblocks with several `inputs`, see below.

The [CC-Autocraft_Mod](CC-Autocraft_Mod) folder holds an EMI/JEI addon that lays a recipe from the recipe viewer into the encoder barrel (Fabric 1.20.1 / 1.21.1, Forge 1.20.1, NeoForge 1.21.1).

## Install
Run in game, on the storage computer and on each crafty turtle (the installer detects turtles):
```
wget run https://raw.githubusercontent.com/Asd1if/CC-Autocraft/main/install.lua
```
The same command updates: it replaces `system/` and never touches `config.lua`, `data/` or `mods/`. Manual install: copy `Computer/` onto the computer and `Turtle/` onto the turtle.

On the computer:
```
startup.lua      the program (runs on boot)
config.lua       settings, made from system/default/config.lua on the first start
data/            recipes, names, the order queue, the log, multiblock.json
mods/            your own mods
system/
  default/       config and multiblock.json templates
  core/          storage index, monitor, network, task scheduler, mod API and loader
  craft/         recipes, planner, order queue, recipe encoder
  mods/          shipped mods: create.lua, gtceu.lua, bridge.lua
  utils/         formatting, log, terminal messages
```
Edit `config.lua`: a Lua table where every key is commented (in Russian). An install from before this layout is moved over on the first start (`data/config.lua` becomes `config.lua`).

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
2. On the monitor press **ADD** (it also looks for newly connected machines), then Turtle / Machine / Multiblock / Pool, then the machine.
3. The test runs once, the results come back to the barrel (slot 14 first), and the recipe is saved.

Recipes stay as encoded. Groups in `substitutes` (below) make an input "any item of the group" when planning and crafting, for old recipes too.

## Monitor
- Tap an item to see its craft tree. `0/4 r3` means 3 more are in storage, but queued or running orders hold them. `< << ][ >> >` is −1, −10, order, +10, +1, and `[N]` is the most you can make.
- An order always crafts the ordered item, even if storage has some. Ingredients come from storage, and so do fluids and items without a recipe.
- On the selected item with a recipe, `+` turns into a red `-`. Tap it twice within 5 s to delete that recipe.
- The queue shows on top of the list: green is done, yellow is crafting, orange is next, red is later. Tap a row to see its tree.
- **S** on the computer's keyboard searches; **Q** cancels the running order.
- `[Clip]` (create mod) reads a Create clipboard (Material Checklist) through an Advanced Peripherals Block Reader and orders the whole list.
- Messages (order placed, done, missing items, failures) are printed in the computer's terminal.
- While an order waits, the top line says why: `Wait: Iron ingot: no free turtle`, `... create:press_0 busy`, `... not on the network`, `... moving items to the craft storage`. An order that stands still for `stall_timeout` fails with that reason, so the queue and restock go on.

## Config (`config.lua`)
| Key | What |
|---|---|
| `main_monitor` | main monitor name; `nil` = the biggest monitor |
| `fluid_monitor` | small monitor for the encoder tanks; `nil` = any other monitor, none = no panel |
| `main_TextScale`, `fluid_TextScale` | text scale of the two monitors (0.5 fits more) |
| `clipboard_reader` | Block Reader in front of the Create clipboard; `nil` = the first found |
| `clipboard_skip_checked` | ticked clipboard lines are not ordered |
| `rednet_modem` | modem for turtle commands; `nil` = every modem (the wired one is enough) |
| `debug_mode` | full log in `data/autocraft.log`; otherwise warnings and errors only |
| `craft_timeout` | seconds a machine may sit idle before the order fails |
| `stall_timeout` | seconds an order may stand still (nothing running, no progress) before it fails; `nil` = 3 x `craft_timeout` |
| `batch` | crafts per turtle call / machine load-ahead |
| `restock_interval` | seconds between auto-restock checks |
| `rescan` | seconds between full storage rescans |
| `storage`, `tanks` | storage inventories / tanks: a type (`create:item_vault`) or exact names |
| `exclude` | names that match the lists above but aren't storage |
| `craft_storage`, `craft_tanks` | separate storage for running orders (exact names); empty = off |
| `encoder`, `recipe_tanks` | the encoder barrel and its fluid tanks |
| `pools` | several identical machines under one name, a step is split between them |
| `restock` | `[item] = minimum`, crafted automatically when nothing else runs |
| `substitutes` | groups of interchangeable items, see below |
| `mods_disabled` | mods to turn off, e.g. `{ "gtceu" }` |
| `gtceu_tier_up` | a GregTech recipe tested on LV may run on MV, HV... (default `true`) |
| `gtceu_chips` | extra circuit NBT hashes: `["<hash>"] = number` |

Old key names (`monitor`, `encoder_monitor`, `text_scale`, `modem`, `debug`) are still read. Keys missing from `config.lua` come from `system/default/config.lua`.

## AE2 / Refined Storage (bridge mod)
Put an Advanced Peripherals **ME Bridge** or **RS Bridge** on the wired network: it becomes part of the main storage by itself, nothing to configure.
- Its items and fluids show in the stock list and count for crafting; orders take from it (straight into turtle slots and machines) and put results into it.
- New items go into the network; an item that already lies in a vault joins its pile there. The vaults can stay as a buffer or go.
- The bridge moves items to any peripheral on the cable, so it can stand anywhere on the network.
- `exclude = { "me_bridge_0" }` leaves one bridge out, `mods_disabled = { "bridge" }` all of them.
- Don't also list a vault that the network reads through a storage bus: it would be counted twice.
- Items with data (damaged tools, filled containers) are told apart by the bridge's fingerprint and don't merge with the same item in a vault.
- Written for the AP 0.8 / 1.21.1 API (`getItems`, `exportItem(filter, target)`, `importItem`); the older names are tried too.

## GregTech (gtceu mod)
- **Circuits**: put the programmed circuit into the machine's input bus/inventory. A recipe remembers the circuit of the machine it was tested on, and every machine of the same kind with the same circuit runs it too: they share the work like a pool, no config needed. The circuit always stays in the machine.
- **Tiers**: a recipe tested on an LV machine also runs on MV, HV... machines of the same kind and circuit (`gtceu_tier_up = false` turns it off). The tested machine goes first, then the lowest tiers.
- The ADD menu shows tier and circuit next to each machine: `[ID-3] LV c5`.

## Multiblocks and multi-input machines (`data/multiblock.json`)
```json
{
  "mixer_line": {
    "input_item": "create:depot_1",
    "output_item": "create:depot_2",
    "input_fluid": "create:fluid_tank_4",
    "output_fluid": "create:fluid_tank_5"
  },
  "casing": {
    "inputs": ["create:depot_0", "create:deployer_0"],
    "batch": 1
  }
}
```
- Only `input_item` (or `inputs`) is required. Without an output the result is looked for in the input block.
- `inputs`: several inventories that get different items, e.g. a depot and the deployer above it. When you encode, **each row of the barrel grid goes into one input**: row 1 (slots 4-6) -> `inputs[1]`, row 2 (13-15) -> `inputs[2]`, row 3 (22-24) -> `inputs[3]`. For a casing: log in row 1, andesite alloy in row 2. The recipe remembers where each item goes.
- Results are collected from every inventory of the machine (the depot here); inputs stay where they were put. The output defaults to `inputs[1]`.
- `batch`: how many runs are fed ahead (default `batch` from config.lua). Use 1 for deployers, so the hand holds one item at a time.
- Blocks listed here are machines, never storage. The ADD menu lists them under Multiblock; they work in `pools` too.

## Substitute groups
```lua
substitutes = {
  planks = { "minecraft:oak_planks", "minecraft:spruce_planks", ... },
  coal   = { "minecraft:coal", "minecraft:charcoal" },
  copper = { "minecraft:copper_ingot", "othermod:copper_ingot" },  -- your own
},
```
Any member of a group can replace any other in a recipe input, and the biggest pile in storage goes first. Presets ship for planks, wooden slabs, cobblestone and coal. If the result names the member's variant there is no substitution: an oak slab still needs oak planks, while a chest takes any planks.

## When something breaks
The main loops (screen, network, storage, queue, tank monitor) restart after an error, at most 5 times a minute. The error and its stack go to `data/autocraft.log`. Please attach that part of the log to an issue.

## License
[MIT](LICENSE)

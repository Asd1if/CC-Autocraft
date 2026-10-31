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
An install from before this layout is moved over on the first start (`data/config.lua` becomes `config.lua`).

## Start menu, Settings, Update
On boot the computer shows **Main / Settings / Update** (Up/Down, Enter); after 10 s without a key it starts (Main).
- **Settings** (also **M** on the keyboard while autocraft runs; crafting goes on): storage and tanks (by block type, or Enter on a type to pick single blocks), crafting (batch, timeouts, restock items), machines (pools, multiblocks, monitors), mods (on/off, GregTech tiers, debug log). Up/Down, Enter open/edit, Left/Right change a value, Backspace or Shift back. Saving rewrites `config.lua` (the old one stays as `config.lua.bak`); storage, machines and pools apply at once, monitors and mods after a restart (it asks).
- **Update** downloads the latest version from GitHub like `install.lua` (keeps `config.lua`, `data/`, `mods/`), sends the new turtle program to every turtle over the network (they reboot themselves) and reboots. Turtles installed before this version need `install.lua` once.
- `config.lua` is still a plain Lua table and can be edited by hand.

## Themes
Settings > Theme (the first row): Left/Right switch, the terminal and every monitor repaint at once; the turtles get it too and keep it after a reboot. One theme for everything.
- **default**: ComputerCraft's own colours.
- **dark**: soft graphite with muted pastel states.
- **amber**: a retro amber terminal; roles differ by brightness, errors stay red.
- **brass**: Create's materials: andesite background, brass frames, copper warnings, verdigris fluids.

Your own: `data/theme/<name>.lua` returning the colours to change, e.g. `return { black = 0x1B1F27, blue = 0x3B4F6E, lime = 0x8FC27A }`; slots left out keep the default. It shows up in the list next to the shipped ones. Every shipped theme keeps text at 4.5:1 contrast or more.

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
- The tree follows the orders: when it's empty it shows the order that runs now; a finished order stays 5 s (a failed one 30 s), then the tree clears or moves to the next order. An item you tapped is never replaced. Restock orders show only when no order of yours waits.
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
| `pools` | several identical machines under one name, a step is split between them in whole runs |
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
- **Tiers**: a recipe tested on an LV machine also runs on MV, HV... machines of the same kind and circuit (`gtceu_tier_up = false` turns it off). Higher tiers (faster) go first, the tested machine first within its tier.
- The ADD menu shows tier and circuit, machines with the same ones on one row: `[0,1,2,3] MV c5`. The test runs on the first; the recipe isn't tied to that ID, at craft time it runs on every machine of that kind and circuit on the network (new ones too).
- A step is split between the machines in whole runs: every free machine gets work, a portion is at most `batch` (config.lua) and never more than one stack of an ingredient per slot (9 per run: 7 runs, 63 items). 16 runs on four compressors: 4 each; a free machine takes the next portion. While the ingredients still come from a running step (ingots from a depot), each machine holds at most 2 runs, so what arrives is shared between them.

## Several recipes for one item
The fastest one is used first: test time per item, divided by the machines that share it (4 compressors make a 4 s recipe a 1 s one). If its ingredients run short, it makes what it can and slower recipes make the rest.

Stack sizes: a machine gets at most one stack of an ingredient per slot. Recipes saved before the stack size was recorded learn it from storage (`data/stacks.json`).

## Multiblocks and multi-input machines (`data/multiblock.json`)
GregTech multiblocks (EBF, chemical reactor...) are made in Settings > Machines > Multiblocks: input bus = input items, output bus = output items, input/output hatch = fluids; the circuit goes into the input bus.
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

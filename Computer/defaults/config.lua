-- Описание всех ключей — в README (раздел про конфиг). nil — найти самому.
return {
  -- ————————————————————————————————

  main_monitor = nil,
  fluid_monitor = nil,

  main_TextScale = 1,
  fluid_TextScale = 0.5,

  -- ————————————————————————————————

  clipboard_reader = nil,
  clipboard_skip_checked = true,

  rednet_modem = nil,
  debug_mode = false,

  craft_timeout = 60,
  batch = 16,
  restock_interval = 30,
  rescan = 10,

  -- ————————————————————————————————

  storage = { "create:item_vault" },
  tanks = { "create:fluid_tank" },
  exclude = {},

  craft_storage = {},
  craft_tanks = {},

  encoder = "minecraft:barrel_0",
  recipe_tanks = {},

  -- ————————————————————————————————

  pools = {
    -- press = { "create:mechanical_press_0", "create:mechanical_press_1" },
  },

  restock = {
    -- ["create:andesite_alloy"] = 256,
  },

  -- ————————————————————————————————

  substitutes = {
    planks = {
      "minecraft:oak_planks",
      "minecraft:spruce_planks",
      "minecraft:birch_planks",
      "minecraft:jungle_planks",
      "minecraft:acacia_planks",
      "minecraft:dark_oak_planks",
      "minecraft:mangrove_planks",
      "minecraft:cherry_planks",
      "minecraft:bamboo_planks",
      "minecraft:crimson_planks",
      "minecraft:warped_planks",
    },
    wooden_slabs = {
      "minecraft:oak_slab",
      "minecraft:spruce_slab",
      "minecraft:birch_slab",
      "minecraft:jungle_slab",
      "minecraft:acacia_slab",
      "minecraft:dark_oak_slab",
      "minecraft:mangrove_slab",
      "minecraft:cherry_slab",
      "minecraft:bamboo_slab",
      "minecraft:crimson_slab",
      "minecraft:warped_slab",
    },
    cobblestone = {
      "minecraft:cobblestone",
      "minecraft:cobbled_deepslate",
      "minecraft:blackstone",
    },
    coal = {
      "minecraft:coal",
      "minecraft:charcoal",
    },
  },

}

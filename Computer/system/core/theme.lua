-- Colour themes: the 16 palette slots of the terminal, every monitor and the turtles get new
-- RGB values, so the UI code keeps drawing with colors.blue, colors.lime... and only how they
-- look changes. One theme for everything; config.lua: theme = "dark". Settings > Theme
-- previews them live.
--
-- Roles of the slots (what the screens draw with each):
--   black background, blue frame/title bars (white text on it), gray buttons/dim text,
--   lightGray secondary text, white text, lime ok/selected/done, green items, cyan fluids,
--   yellow crafting/turtles/partial, orange warnings/next, red errors/later, pink multiblocks,
--   lightBlue pools, brown/magenta/purple fluid and tank accents.
--
-- Own themes: data/theme/<name>.lua returning { blue = 0x1E3A5F, lime = 0x8BD450, ... };
-- slots left out keep the default colour. They appear in Settings next to the shipped ones.
local M = { current = "default", DIR = "data/theme" }

M.BUILTIN = {
  -- ComputerCraft's own palette
  default = {},

  -- soft dark: graphite with a hint of blue, muted pastel states
  dark = {
    black = 0x1B1F27, gray = 0x4A5263, lightGray = 0x9AA3B2, white = 0xE3E6EB,
    blue = 0x3B4F6E, lightBlue = 0x8AB4D8, cyan = 0x6FB3BF,
    green = 0x6FA37F, lime = 0x8FC27A, yellow = 0xE3C27A, orange = 0xD99A6C, red = 0xD16D6D,
    pink = 0xC795B8, magenta = 0xB07AA8, purple = 0x8C7AB8, brown = 0x8F735A,
  },

  -- retro amber terminal: one hue, roles told apart by brightness; errors stay red-orange
  amber = {
    black = 0x140C02, gray = 0x4A3410, lightGray = 0xA87A32, white = 0xFFC66B,
    blue = 0x5C3A0C, lightBlue = 0xC9A066, cyan = 0xD9B77A,
    green = 0xE8A33D, lime = 0xFFE0A3, yellow = 0xFFD27A, orange = 0xF08A24, red = 0xE0462B,
    pink = 0xD98A5F, magenta = 0xC2703D, purple = 0x9C6A3A, brown = 0x7A5020,
  },

  -- Create's own materials: andesite casing, brass frame, copper warnings, verdigris fluids
  brass = {
    black = 0x24221F, gray = 0x4D4943, lightGray = 0xA39E94, white = 0xEDE6D6,
    blue = 0x7A5B26, lightBlue = 0x7FB2C4, cyan = 0x5FA8A0,
    green = 0x6E9C55, lime = 0x9CC45A, yellow = 0xE6C35C, orange = 0xD07A3F, red = 0xE36A55,
    pink = 0xC98B9B, magenta = 0xA86A8E, purple = 0x7D6699, brown = 0x8A6240,
  },
}
M.ORDER = { "default", "dark", "amber", "brass" }

M.SLOTS = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
  "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black" }

-- Own themes from data/theme/*.lua: name -> palette.
function M.custom()
  local out = {}
  if not (fs.exists(M.DIR) and fs.isDir(M.DIR)) then return out end
  for _, f in ipairs(fs.list(M.DIR)) do
    local name = f:match("^(.+)%.lua$")
    if name then
      local fn = loadfile(fs.combine(M.DIR, f), "t", {})
      local ok, t = pcall(fn or error)
      if ok and type(t) == "table" then out[name] = t end
    end
  end
  return out
end

-- Every theme name, shipped first.
function M.list()
  local list, seen = {}, {}
  for _, n in ipairs(M.ORDER) do list[#list + 1] = n; seen[n] = true end
  local own = {}
  for n in pairs(M.custom()) do if not seen[n] then own[#own + 1] = n end end
  table.sort(own)
  for _, n in ipairs(own) do list[#list + 1] = n end
  return list
end

-- Full palette of a theme: slot name -> 0xRRGGBB, or nil for "CC default".
function M.palette(name)
  local t = M.BUILTIN[name or "default"] or M.custom()[name] or {}
  local out = {}
  for _, slot in ipairs(M.SLOTS) do
    if type(t[slot]) == "number" then out[slot] = t[slot] end
  end
  return out
end

-- Paints one terminal-like object (term, a monitor, a window).
function M.paint(target, palette)
  if not (target and target.setPaletteColour) then return end
  for _, slot in ipairs(M.SLOTS) do
    local c = colors[slot]
    if palette[slot] then
      target.setPaletteColour(c, palette[slot])
    elseif term.nativePaletteColour then
      target.setPaletteColour(c, term.nativePaletteColour(c))
    end
  end
end

-- The terminal and every monitor on the network.
function M.applyScreens(name)
  M.current = name or "default"
  local p = M.palette(M.current)
  M.paint(term.native and term.native() or term, p)
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "monitor" then M.paint(peripheral.wrap(n), p) end
  end
end

-- Turtles: to = a computer id, or "*" for all. They keep it in a file for their next boot.
function M.sendTurtles(net, to)
  -- "theme", not "name": a turtle reads payload.name as the wired name it's addressed by
  pcall(net.send, to or "*", "theme", { theme = M.current, palette = M.palette(M.current) })
end

function M.apply(name, net)
  M.applyScreens(name)
  if net then M.sendTurtles(net) end
end

return M

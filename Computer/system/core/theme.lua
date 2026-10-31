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

  -- soft dark: graphite with a hint of blue, clear but calm colours for every state
  dark = {
    black = 0x1B1F27, gray = 0x4A5263, lightGray = 0x9AA3B2, white = 0xE3E6EB,
    blue = 0x3B4F6E, lightBlue = 0x86B8F0, cyan = 0x6FC6D6,
    green = 0x6FC08F, lime = 0x9DD67A, yellow = 0xF0CC6A, orange = 0xEE9A62, red = 0xEF6F6F,
    pink = 0xE59AC8, magenta = 0xC58AE0, purple = 0x9C8CE8, brown = 0xA9845F,
  },

  -- Create's own materials: andesite casing, brass frame, copper warnings, verdigris fluids
  brass = {
    black = 0x24221F, gray = 0x4D4943, lightGray = 0xA39E94, white = 0xEDE6D6,
    blue = 0x7A5B26, lightBlue = 0x78BFE0, cyan = 0x4FC2B0,
    green = 0x7DB85E, lime = 0xA6D65C, yellow = 0xE6C35C, orange = 0xD9803F, red = 0xE36A55,
    pink = 0xE59AB0, magenta = 0xC27BB0, purple = 0x9A86D0, brown = 0xA87A4F,
  },

  -- evening sky: plum background, coral, gold and mint against it
  sunset = {
    black = 0x2A1B2E, gray = 0x54405A, lightGray = 0xC2A9B8, white = 0xFFE8D6,
    blue = 0x6B3A6E, lightBlue = 0x8FB8F0, cyan = 0x5EC8D8,
    green = 0x7FD1A0, lime = 0xA8E07A, yellow = 0xFFD166, orange = 0xFF9E5E, red = 0xFF6B7A,
    pink = 0xF7A8C8, magenta = 0xD77FD0, purple = 0xA98BE8, brown = 0xB98060,
  },

  -- coral reef: deep navy water, turquoise fluids, coral errors, sand-yellow crafting
  reef = {
    black = 0x0F2233, gray = 0x35506A, lightGray = 0x9FB8C8, white = 0xF2F7F5,
    blue = 0x1F5F7A, lightBlue = 0x7FC4FF, cyan = 0x4FD6E0,
    green = 0x4FC28A, lime = 0x7EE0A1, yellow = 0xFFD86B, orange = 0xFF9F59, red = 0xFF6F61,
    pink = 0xFF9EC4, magenta = 0xE07BE0, purple = 0xA88BFF, brown = 0xC9935E,
  },

  -- northern lights: night-sky background, indigo frame, glowing green, cyan and violet
  aurora = {
    black = 0x101820, gray = 0x34404D, lightGray = 0x97A6B4, white = 0xE8F1F2,
    blue = 0x2E3F6B, lightBlue = 0x7AB8FF, cyan = 0x5EF0E6,
    green = 0x3DDC97, lime = 0x7CF29A, yellow = 0xF2E86D, orange = 0xFFA552, red = 0xFF5C8A,
    pink = 0xFF8AD8, magenta = 0xC77DFF, purple = 0x9D7BFF, brown = 0xC08B5C,
  },
}
M.ORDER = { "default", "dark", "brass", "sunset", "reef", "aurora" }

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

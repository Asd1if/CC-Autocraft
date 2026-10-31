-- Messages for the player in the computer's terminal, framed and coloured:
--
--   -----------------------------------
--   #3 Iron sword x4: not enough
--   minecraft:iron_ingot > 8
--   minecraft:stick > 1
--
-- With debug_mode = true in config.lua, blocks and lines also go to data/autocraft.log
-- (log.info: file only, not echoed), so the log alone shows what the terminal showed.
local log = require("system.utils.log")

local M = { paused = false, pending = {} }

-- While a full-screen terminal menu is open (Settings) messages wait and print after it.
function M.pause() M.paused = true end
function M.resume()
  M.paused = false
  local list = M.pending
  M.pending = {}
  for _, f in ipairs(list) do f() end
end

local out = write or io.write -- CC's write; plain Lua in offline tests

local function color(c)
  if term and term.isColor and term.isColor() then term.setTextColor(c) end
end

local function width()
  if term and term.getSize then return (term.getSize()) end
  return 35
end

-- title in `c`, then rows { left, right } as "left > right" (right may be nil).
function M.block(title, c, rows)
  if M.paused then M.pending[#M.pending + 1] = function() M.block(title, c, rows) end return end
  log.info("%s", title)
  for _, r in ipairs(rows or {}) do
    log.info("  %s", r[2] ~= nil and (tostring(r[1]) .. " > " .. tostring(r[2])) or tostring(r[1]))
  end
  color(colors.gray)
  print(("-"):rep(math.min(35, width())))
  color(c or colors.white)
  print(title)
  for _, r in ipairs(rows or {}) do
    color(colors.lightGray)
    if r[2] ~= nil then
      out(tostring(r[1]))
      color(colors.white)
      print(" > " .. tostring(r[2]))
    else
      print(tostring(r[1]))
    end
  end
  color(colors.white)
end

-- One coloured line without a frame.
function M.line(text, c)
  if M.paused then M.pending[#M.pending + 1] = function() M.line(text, c) end return end
  log.info("%s", text)
  color(c or colors.white)
  print(text)
  color(colors.white)
end

return M

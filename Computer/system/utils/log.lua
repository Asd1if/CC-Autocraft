-- Leveled logger: terminal + file with rotation.
-- echo: lowest level also printed to the terminal (player messages go through console.lua).
local log = { level = 2, echo = 3, file = nil, maxSize = 64 * 1024 }
local LEVELS = { "DEBUG", "INFO", "WARN", "ERROR" }

local function rotate(path)
  if fs.exists(path) and fs.getSize(path) > log.maxSize then
    if fs.exists(path .. ".1") then fs.delete(path .. ".1") end
    fs.move(path, path .. ".1")
  end
end

local function write(lvl, fmt, ...)
  if lvl < log.level then return end
  local line = ("[%s] %-5s %s"):format(textutils.formatTime(os.time(), true), LEVELS[lvl], fmt:format(...))
  if lvl >= log.echo then print(line) end
  if log.file then
    rotate(log.file)
    local h = fs.open(log.file, "a")
    h.writeLine(line)
    h.close()
  end
end

function log.debug(...) write(1, ...) end
function log.info(...)  write(2, ...) end
function log.warn(...)  write(3, ...) end
function log.error(...) write(4, ...) end

return log

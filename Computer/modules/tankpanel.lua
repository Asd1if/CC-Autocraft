-- Small monitor (1x1 is enough, text scale 0.5 = 15x10) next to the encoder: what is in each
-- recipe tank. Tapping a tank's line pours it back into storage, the bottom bar pours all.
-- Fluid orders from the main monitor end up in these tanks (encoder.deliverFluid).
--
--    Encoder tanks        (blue bar)
--   [1]> Water:40mB       index gray, ">" orange, name in the fluid's colour, amount white
--   [2]  empty
--   [All > storage]       (orange bar)
--
-- Redrawn every 2 s and on every storage rescan.
local indexer = require("modules.indexer")
local encoder = require("modules.encoder")
local util    = require("modules.util")
local log     = require("modules.log")

local M = { msg = nil, msgColor = colors.white, msgUntil = 0 }

local ALL = "All > storage"
local REFRESH = 2
local mon, W, H

local KNOWN = {
  water = colors.blue, lava = colors.orange, milk = colors.white, honey = colors.yellow,
  chocolate = colors.brown, steam = colors.lightGray, oil = colors.gray, creosote = colors.brown,
}
local PALETTE = { colors.cyan, colors.lime, colors.magenta, colors.pink, colors.purple,
  colors.lightBlue, colors.yellow, colors.green, colors.red }

-- Colour of a fluid: by a known word in its id, otherwise a stable pick from the palette.
local function fluidColor(key)
  for word, c in pairs(KNOWN) do
    if key:find(word, 1, true) then return c end
  end
  local h = 0
  for i = 1, #key do h = (h * 31 + key:byte(i)) % 9973 end
  return PALETTE[h % #PALETTE + 1]
end

-- First fluid in each recipe tank: { { tank, key, amount } }, key nil when empty.
local function tankRows()
  local rows = {}
  for _, tank in ipairs(M.cfg.recipe_tanks or {}) do
    local row = { tank = tank }
    local ok, list = pcall(peripheral.call, tank, "tanks")
    for _, f in pairs(ok and list or {}) do
      if f.amount and f.amount > 0 then row.key, row.amount = indexer.fluidKey(f.name), f.amount break end
    end
    rows[#rows + 1] = row
  end
  return rows
end

local function at(x, y, text, fg, bg)
  mon.setCursorPos(x, y)
  mon.setTextColor(fg)
  mon.setBackgroundColor(bg or colors.black)
  mon.write(text)
end

local function fit(s, w) return #s > w and s:sub(1, math.max(0, w)) or s end

local function bar(y, text, fg, bg)
  local s = fit(text, W)
  local left = math.floor((W - #s) / 2)
  at(1, y, (" "):rep(left) .. s .. (" "):rep(W - left - #s), fg, bg)
end

-- Tank rows start at y = 2; one line each, an empty line between them when there is room.
local function gap() return #(M.rows or {}) * 2 - 1 <= H - 2 and 2 or 1 end
local function rowY(i) return 1 + (i - 1) * gap() + 1 end

function M.draw()
  if not mon then return end
  mon.setBackgroundColor(colors.black)
  mon.clear()
  if M.msg and os.clock() < M.msgUntil then bar(1, M.msg, colors.black, M.msgColor)
  else bar(1, "Encoder tanks", colors.white, colors.blue) end
  for i, r in ipairs(M.rows or {}) do
    local y = rowY(i)
    if y >= H then break end
    local idx = "[" .. i .. "]"
    if r.key then
      local amount = util.formatFluid(r.amount)
      local room = W - #idx - 2 - 1 - #amount
      at(1, y, idx, colors.lightGray)
      at(#idx + 1, y, "> ", colors.orange)
      local name = fit(indexer.displayName(r.key), math.max(1, room))
      at(#idx + 3, y, name, fluidColor(r.key))
      at(#idx + 3 + #name, y, ":", colors.gray)
      at(#idx + 4 + #name, y, amount, colors.white)
    else
      at(1, y, idx, colors.gray)
      at(#idx + 1, y, fit("  empty", W - #idx), colors.gray)
    end
  end
  bar(H, ALL, colors.black, colors.orange)
end

local function say(text, color)
  M.msg, M.msgColor, M.msgUntil = text, color, os.clock() + 4
end

local function drain(rows)
  local moved, left = 0, 0
  for _, r in ipairs(rows) do
    if r.key then
      local n = encoder.drainTank(r.tank)
      moved, left = moved + n, left + (r.amount - n)
    end
  end
  if left > 0 then say("no room " .. util.formatFluid(left), colors.red)
  elseif moved > 0 then say("stored " .. util.formatFluid(moved), colors.lime) end
  if moved > 0 then os.queueEvent("stock_updated") end
end

function M.touch(x, y)
  if y == H then return drain(M.rows or {}) end
  for i, r in ipairs(M.rows or {}) do
    if y == rowY(i) and r.key then return drain({ r }) end
  end
end

function M.refresh()
  M.rows = tankRows()
  M.draw()
end

-- cfg.encoder_monitor, or the first monitor that is not the main one. Returns false if none.
function M.init(cfg, mainMonitor)
  M.cfg = cfg
  M.name = cfg.encoder_monitor
  if not M.name then
    for _, n in ipairs(peripheral.getNames()) do
      if peripheral.getType(n) == "monitor" and n ~= mainMonitor then M.name = n break end
    end
  end
  mon = M.name and peripheral.wrap(M.name)
  if not mon then return false end
  if mon.setTextScale then mon.setTextScale(0.5) end
  W, H = mon.getSize()
  log.info("tank monitor: %s", M.name)
  return true
end

-- Reading a tank waits for the game thread; a timer firing meanwhile never reaches this loop.
-- So the refresh goes by the clock (checked on every event) and the timer is renewed each time.
function M.loop()
  M.refresh()
  local due = os.clock() + REFRESH
  os.startTimer(REFRESH)
  while true do
    local e, a, b, c = os.pullEvent()
    if e == "monitor_touch" and a == M.name then
      local ok, err = pcall(M.touch, b, c)
      if not ok then say(tostring(err), colors.red) end
      M.refresh()
      due = os.clock() + REFRESH
    elseif e == "monitor_resize" and a == M.name then
      W, H = mon.getSize()
      M.draw()
    elseif e == "stock_updated" or os.clock() >= due then
      M.refresh()
      due = os.clock() + REFRESH
      os.startTimer(REFRESH)
    end
  end
end

return M

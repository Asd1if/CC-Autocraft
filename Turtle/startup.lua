-- CRAFTY TURTLE worker. Self-contained, no other files needed.
-- Items arrive over the wired modem (the storage PC pushes them into grid slots
-- 1,2,3,5,6,7,9,10,11), commands over rednet (protocol "aero") on every modem: the wired one
-- is enough, a wireless one is optional. The PC resends a request until it gets a reply;
-- repeats are answered from a cache, so a craft never runs twice:
--   inv            -> { ok, items }
--   craft{count, detail} -> { ok, error, before, after }   (turtle.craft(count))
--                     detail = true adds maxCount, damage, maxDamage (slow: one tick per slot)
--   theme{theme, palette} -> { ok }  colours of the PC's theme, kept in theme.txt for the next boot
--   update{body}   -> { ok, error }   new startup.lua from the PC (start menu > Update): checked
--                     that it compiles, written, then the turtle reboots
-- Results land from slot 16 on, so they don't mix with the grid.
-- Announces itself every 10 s so the storage PC learns its wired name.
local PROTOCOL = "aero"

local wired = peripheral.find("modem", function(_, m) return not m.isWireless() end)
local wiredName = wired and wired.getNameLocal()
if not wiredName then
  error("no wired modem (or it is off: right-click it until the ring is red): the storage PC can't reach this turtle", 0)
end
local opened = {}
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" then rednet.open(name); opened[#opened + 1] = name end
end
if not turtle.craft then error("needs a crafting table equipped (crafty turtle)", 0) end

local counter = 0
local session = os.epoch("utc") -- ids stay unique across restarts (see net.lua)
local function send(to, msgType, payload, re)
  counter = counter + 1
  local e = { type = msgType, id = os.getComputerID() .. ":" .. session .. ":" .. counter, re = re, payload = payload }
  if to == "*" then rednet.broadcast(e, PROTOCOL) else rednet.send(to, e, PROTOCOL) end
end

-- The PC's colour theme: palette = { slot name = 0xRRGGBB }, missing slots back to default.
local function paint(palette)
  if not term.setPaletteColour then return end
  for _, slot in ipairs({ "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black" }) do
    local c = colors[slot]
    if palette and type(palette[slot]) == "number" then term.setPaletteColour(c, palette[slot])
    else term.setPaletteColour(c, term.nativePaletteColour(c)) end
  end
end
if fs.exists("theme.txt") then
  local h = fs.open("theme.txt", "r")
  local t = textutils.unserialise(h.readAll())
  h.close()
  if type(t) == "table" then paint(t.palette) end
end

local GRID = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true, [7] = true,
  [9] = true, [10] = true, [11] = true }

local function snapshot(detail)
  local items = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      items[s] = { name = d.name, count = d.count, nbt = d.nbt }
      if detail then
        local full = turtle.getItemDetail(s, true)
        if full then
          items[s].maxCount, items[s].damage, items[s].maxDamage = full.maxCount, full.damage, full.maxDamage
        end
      end
    end
  end
  return items
end

local handlers = {
  inv = function()
    return { ok = true, items = snapshot() }
  end,
  craft = function(payload)
    payload = payload or {}
    local before = snapshot(payload.detail)
    -- turtle.craft looks at the whole 4x4 inventory: anything outside the grid breaks the recipe
    for s = 1, 16 do
      if before[s] and not GRID[s] then
        return { ok = false, error = ("slot %d is not empty (%s x%d)"):format(s, before[s].name, before[s].count),
          before = before, after = before }
      end
    end
    turtle.select(16)
    local ok, err = turtle.craft(payload.count or 1)
    return { ok = ok, error = err, before = before, after = snapshot(payload.detail) }
  end,
  theme = function(payload)
    payload = payload or {}
    paint(payload.palette)
    local h = fs.open("theme.txt", "w")
    h.write(textutils.serialise({ theme = payload.theme, palette = payload.palette }))
    h.close()
    return { ok = true }
  end,
  update = function(payload)
    local body = payload and payload.body
    if type(body) ~= "string" or body == "" then return { ok = false, error = "empty program" } end
    local fn, err = load(body, "startup.lua")
    if not fn then return { ok = false, error = err } end
    -- a resent update after the reboot: already this version
    local cur = fs.open("startup.lua", "r")
    local old = cur and cur.readAll()
    if cur then cur.close() end
    if old == body then return { ok = true } end
    local h = fs.open("startup.lua", "w")
    h.write(body)
    h.close()
    return { ok = true, reboot = true }
  end,
}

-- Last replies by request id: a resent request gets the same answer, nothing runs again.
local done, doneOrder = {}, {}

local function serve()
  while true do
    local from, e = rednet.receive(PROTOCOL)
    -- payload.name: the PC addresses one turtle by wired name (computer ids can repeat)
    local mine = type(e) == "table" and not (type(e.payload) == "table" and e.payload.name and e.payload.name ~= wiredName)
    if mine and handlers[e.type] then
      local key = from .. "/" .. tostring(e.id)
      local res = done[key]
      if not res then
        local ok
        ok, res = pcall(handlers[e.type], e.payload)
        if not ok then res = { ok = false, error = tostring(res) } end
        done[key] = res
        doneOrder[#doneOrder + 1] = key
        if #doneOrder > 16 then done[table.remove(doneOrder, 1)] = nil end
      end
      send(from, "reply", res, e.id)
      if res.reboot then
        print("updated by the storage PC, rebooting")
        sleep(1)
        os.reboot()
      end
    end
  end
end

local function announce()
  while true do
    send("*", "turtle_hello", { name = wiredName })
    sleep(10)
  end
end

print(("turtle worker %d as '%s' (rednet on %s)"):format(os.getComputerID(), wiredName, table.concat(opened, ", ")))
parallel.waitForAny(serve, announce)

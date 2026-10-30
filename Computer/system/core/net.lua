-- Messaging over rednet with request/reply.
--
-- Envelope: { type, id, re, payload }   (re = id of the request this replies to)
--
-- Runs over every modem: wired (the same cable the items go through) and wireless, whichever
-- the computer has. A request is resent with the same id until a reply comes; the receiver
-- answers repeats from a cache instead of doing the work twice (Turtle/main.lua).
--
-- Two ways to use it:
--   * simple: net.request / net.receive directly (turtle worker);
--   * service: net.on(type, handler) + run net.run() inside parallel / tasks.
--     Handlers run inside the receive loop: keep them short and never call net.request from them.
local log = require("system.utils.log")

local net = { PROTOCOL = "aero", handlers = {}, running = false }

local inbox = {}   -- messages received while net.request waited (simple mode)
local counter = 0
-- start time in the id: the counter restarts with the program, and the turtle keeps caching
-- replies by id, so "1:5" from the last run must not match "1:5" from this one
net.session = os.epoch("utc")

local function newId()
  counter = counter + 1
  return os.getComputerID() .. ":" .. net.session .. ":" .. counter
end

-- Opens the given modem (side or name), or every modem attached. Returns the opened names.
function net.open(side)
  local names = {}
  if side then
    names[1] = side
  else
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == "modem" then names[#names + 1] = name end
    end
  end
  if #names == 0 then error("net.open: no modem (a wired one on the storage cable is enough)", 2) end
  for _, n in ipairs(names) do rednet.open(n) end
  return names
end

-- to = computer id or "*" for broadcast. id: reuse one to resend. Returns the message id.
function net.send(to, msgType, payload, re, id)
  local e = { type = msgType, id = id or newId(), re = re, payload = payload }
  if to == "*" then rednet.broadcast(e, net.PROTOCOL) else rednet.send(to, e, net.PROTOCOL) end
  return e.id
end

local function receiveValid(timeout)
  local deadline = timeout and os.clock() + timeout
  while true do
    local left = deadline and deadline - os.clock()
    if left and left <= 0 then return nil end
    local sender, e = rednet.receive(net.PROTOCOL, left)
    if not sender then return nil end
    if type(e) == "table" and type(e.type) == "string" then
      return { from = sender, type = e.type, id = e.id, re = e.re, payload = e.payload }
    end
    log.debug("net: dropped malformed message from %s", tostring(sender))
  end
end

-- Simple mode receive. Optional msgType filter; non-matching messages stay in the inbox.
function net.receive(timeout, msgType)
  for i, msg in ipairs(inbox) do
    if not msgType or msg.type == msgType then return table.remove(inbox, i) end
  end
  local deadline = timeout and os.clock() + timeout
  while true do
    local left = deadline and deadline - os.clock()
    if left and left <= 0 then return nil end
    local msg = receiveValid(left)
    if not msg then return nil end
    if not msgType or msg.type == msgType then return msg end
    inbox[#inbox + 1] = msg
  end
end

function net.reply(msg, payload)
  return net.send(msg.from, "reply", payload, msg.id)
end

net.RESEND = 3 -- seconds without a reply before the same request goes out again

-- Sends and waits for the reply payload, resending (same id) every net.RESEND seconds.
-- Returns payload or nil + "timeout".
function net.request(to, msgType, payload, timeout)
  timeout = timeout or 5
  local id = net.send(to, msgType, payload)
  local deadline = os.clock() + timeout
  local resendAt = os.clock() + net.RESEND

  if net.running then
    local timer = os.startTimer(math.min(net.RESEND, timeout))
    while true do
      local ev, a, b = os.pullEvent()
      if ev == "aero_reply" and a == id then os.cancelTimer(timer) return b.payload end
      if ev == "timer" and a == timer then
        if os.clock() >= deadline then return nil, "timeout" end
        net.send(to, msgType, payload, nil, id)
        timer = os.startTimer(math.min(net.RESEND, deadline - os.clock()))
      end
    end
  end

  while true do
    local now = os.clock()
    if now >= deadline then return nil, "timeout" end
    if now >= resendAt then
      net.send(to, msgType, payload, nil, id)
      resendAt = now + net.RESEND
    end
    local msg = receiveValid(math.min(deadline, resendAt) - now)
    if msg then
      if msg.re == id and msg.from == to then return msg.payload end
      inbox[#inbox + 1] = msg
    end
  end
end

-- handler(msg) -> reply payload (or nil for no reply). "*" catches unknown types.
function net.on(msgType, handler)
  net.handlers[msgType] = handler
end

-- Service loop: dispatches requests to handlers, replies to waiting net.request calls.
-- A resent request (same sender and id) gets the cached reply: an order is never placed twice.
function net.run()
  net.running = true
  local done, order = {}, {}
  while true do
    local msg = receiveValid()
    if msg.re then
      os.queueEvent("aero_reply", msg.re, msg)
    else
      local handler = net.handlers[msg.type] or net.handlers["*"]
      local key = msg.from .. "/" .. tostring(msg.id)
      if done[key] then
        net.reply(msg, done[key])
      elseif handler then
        local ok, res = pcall(handler, msg)
        if not ok then
          log.error("net: handler '%s' failed: %s", tostring(msg.type), tostring(res))
          res = { ok = false, error = tostring(res) }
        end
        if res ~= nil then
          net.reply(msg, res)
          done[key] = res
          order[#order + 1] = key
          if #order > 32 then done[table.remove(order, 1)] = nil end
        end
      end
    end
  end
end

return net

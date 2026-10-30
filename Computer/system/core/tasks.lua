-- Dynamic coroutine scheduler: like parallel.waitForAll, but tasks can be spawned at any time
-- (crafting workers, test crafts) without blocking the UI.
--
--   tasks.spawn(net.run, "net")
--   tasks.spawn(uiLoop, "ui")
--   tasks.run()             -- never returns while tasks are alive
local log = require("system.utils.log")

local tasks = { list = {} }

-- fn(...) runs as its own task; errors are logged (with the stack), not fatal.
function tasks.spawn(fn, name, ...)
  local args = table.pack(...)
  local co = coroutine.create(function() return fn(table.unpack(args, 1, args.n)) end)
  local t = { co = co, name = name or "task", fresh = true, fn = fn, args = args }
  tasks.list[#tasks.list + 1] = t
  os.queueEvent("task_spawned")
  return co, t
end

-- A loop that must never stop (screen, net...): restarted after a crash, at most 5 times a
-- minute so a broken one doesn't spin.
function tasks.forever(fn, name, ...)
  local _, t = tasks.spawn(fn, name, ...)
  t.restart = { times = {} }
  return t
end

function tasks.count()
  return #tasks.list
end

local function step(t, ev)
  local ok, filter
  if t.fresh then
    t.fresh = false
    ok, filter = coroutine.resume(t.co)
  else
    ok, filter = coroutine.resume(t.co, table.unpack(ev, 1, ev.n))
  end
  if not ok then
    log.error("task '%s' crashed: %s", t.name, tostring(filter))
    log.warn("%s", debug.traceback(t.co)) -- WARN: reaches the file without debug mode
    local r = t.restart
    if r then
      local now = os.clock()
      while r.times[1] and now - r.times[1] > 60 do table.remove(r.times, 1) end
      if #r.times < 5 then
        r.times[#r.times + 1] = now
        log.error("task '%s' restarted", t.name)
        local fn, args = t.fn, t.args
        t.co = coroutine.create(function() return fn(table.unpack(args, 1, args.n)) end)
        t.fresh, t.filter = true, nil
        os.queueEvent("task_spawned")
      end
    end
  else
    t.filter = filter
  end
end

function tasks.run()
  local ev = { n = 0 }
  while true do
    -- iterate over a snapshot: tasks spawned now start on the next pass
    local current = { table.unpack(tasks.list) }
    for _, t in ipairs(current) do
      if t.fresh then
        step(t, ev)
      elseif coroutine.status(t.co) == "suspended"
        and (t.filter == nil or t.filter == ev[1] or ev[1] == "terminate") then
        step(t, ev)
      end
    end
    for i = #tasks.list, 1, -1 do
      if coroutine.status(tasks.list[i].co) == "dead" then table.remove(tasks.list, i) end
    end
    if #tasks.list == 0 then return end
    ev = table.pack(os.pullEventRaw())
    if ev[1] == "terminate" then error("Terminated", 0) end
  end
end

return tasks

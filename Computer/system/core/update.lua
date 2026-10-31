-- Update from GitHub (start menu > Update): the same as running install.lua again. Downloads
-- Computer/ into this computer (system/ and startup.lua are replaced; config.lua, data/ and
-- mods/ stay) and sends Turtle/startup.lua to every turtle over rednet: each one checks that it
-- compiles, writes it and reboots. Turtles that run a version without "update" get it by
-- install.lua once.
local net = require("system.core.net")

local M = { REPO = "Asd1if/CC-Autocraft", BRANCH = "main" }

local function get(url)
  local h, err = http.get(url)
  if not h then error("download failed: " .. url .. " (" .. tostring(err) .. ")", 0) end
  local body = h.readAll()
  h.close()
  return body
end

local function say(text, c)
  if term.isColor() then term.setTextColor(c or colors.white) end
  print(text)
  term.setTextColor(colors.white)
end

-- Sends the turtle program to every turtle; returns how many answered.
function M.sendTurtles(body, wait)
  local id = net.send("*", "update", { body = body })
  local got, deadline, resend = {}, os.clock() + (wait or 5), os.clock() + 1
  while os.clock() < deadline do
    local msg = net.receive(math.max(0.1, math.min(resend, deadline) - os.clock()), "reply")
    if msg and msg.re == id and not got[msg.from] then
      got[msg.from] = true
      local p = msg.payload or {}
      say(("  turtle %d: %s"):format(msg.from, p.ok and "updated" or ("failed: " .. tostring(p.error))),
        p.ok and colors.lime or colors.red)
    end
    if os.clock() >= resend then net.send("*", "update", { body = body }, nil, id); resend = os.clock() + 1 end
  end
  local n = 0
  for _ in pairs(got) do n = n + 1 end
  return n
end

function M.run(cfg)
  if not http then say("HTTP is off in the ComputerCraft config: can't update", colors.red) return false end
  say(("Fetching the file list of %s (%s)..."):format(M.REPO, M.BRANCH), colors.yellow)
  local tree = textutils.unserialiseJSON(get(("https://api.github.com/repos/%s/git/trees/%s?recursive=1")
    :format(M.REPO, M.BRANCH)))
  if not tree or not tree.tree then error("unexpected answer from GitHub", 0) end
  local files, turtlePath = {}, nil
  for _, e in ipairs(tree.tree) do
    if e.type == "blob" and e.path:sub(1, 9) == "Computer/" then
      local dest = e.path:sub(10)
      local top = dest:match("^[^/]+")
      if top ~= "data" and top ~= "mods" and dest ~= "config.lua" then files[#files + 1] = { src = e.path, dest = dest } end
    elseif e.path == "Turtle/startup.lua" then
      turtlePath = e.path
    end
  end
  if #files == 0 then error("no files in Computer/", 0) end
  -- everything first: a failed download leaves the old install as it was
  for i, f in ipairs(files) do
    say(("[%d/%d] %s"):format(i, #files, f.dest), colors.lightGray)
    f.body = get(("https://raw.githubusercontent.com/%s/%s/%s"):format(M.REPO, M.BRANCH, f.src))
  end
  local turtleBody = turtlePath and get(("https://raw.githubusercontent.com/%s/%s/%s"):format(M.REPO, M.BRANCH, turtlePath))
  if fs.exists("system") then fs.delete("system") end
  for _, f in ipairs(files) do
    local dir = fs.getDir(f.dest)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(f.dest, "w")
    h.write(f.body)
    h.close()
  end
  say(("Computer: %d files updated"):format(#files), colors.lime)
  if turtleBody then
    say("Sending the update to the turtles...", colors.yellow)
    local ok = pcall(net.open, cfg and cfg.rednet_modem)
    local n = ok and M.sendTurtles(turtleBody) or 0
    if n == 0 then say("  no turtle answered: run install.lua on them", colors.orange) end
  end
  say("Rebooting in 3 s...", colors.yellow)
  sleep(3)
  os.reboot()
end

return M

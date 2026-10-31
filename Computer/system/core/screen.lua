-- Storage monitor, in the style of the old gui.lua: blue cell frame with gaps, big ADD made of
-- cells, 3x2 icon buttons, craft tree top-left, stock list right, order counter at the bottom.
-- Geometry is derived from the monitor size, so any monitor works (old layout = 49x25).
--
--  y1  messages                    |
--  y2  craft tree                  | progress of the running job
--  y3                              |=  stock list           [count+]
--      ...                         |   ...
--  H-12 ---- controls box ----     |
--  H-11 add menu       [sort]      |
--  H-5 - - - - - -     [mode]      |
--  H-4 A D D           [up]        |
--  H   A D D           [down]      |=  < << ][ >> > [N]   [mod buttons]
--
-- Mods add buttons to the right end of the bottom bar (api.button), e.g. [Clip] of the create
-- mod. ADD also looks for new machines on the network (api.rediscover).
-- Search: press S on the computer's keyboard and type in its terminal; the list shows only
-- matching items, its first row "Search: ..." clears the filter when tapped.
-- Queue: up to 3 rows on top of the list: green done, yellow crafting now, orange next,
-- red after that. Q on the computer's keyboard cancels the running order.
local util     = require("system.utils.util")
local tasks    = require("system.core.tasks")
local log      = require("system.utils.log")
local indexer  = require("system.core.indexer")
local recipes  = require("system.craft.recipes")
local planner  = require("system.craft.planner")
local executor = require("system.craft.executor")
local encoder  = require("system.craft.encoder")
local console  = require("system.utils.console")
local api      = require("system.core.api")

local M = {}

local C = {
  bg = colors.black, frame = colors.blue, btn = colors.gray, text = colors.white,
  dim = colors.gray, sel = colors.lime, warn = colors.orange, err = colors.red,
  ok = colors.lime, item = colors.green, fluid = colors.cyan,
  sortCount = colors.orange, sortCraft = colors.yellow,
  turtle = colors.yellow, machine = colors.lime, multiblock = colors.pink, pool = colors.lightBlue,
  qDone = colors.lime, qRun = colors.yellow, qNext = colors.orange, qLater = colors.red,
  partial = colors.yellow, todo = colors.lightGray,
}

-- big letters, 3 cells wide, 5 tall (same shapes as the old gui)
local BIG = {
  A = { ".#.", "###", "#.#", "###", "#.#" },
  D = { "...", "##.", "#.#", "#.#", "##." },
}

local S = {
  mode = "item", sort = "count", scroll = 0,
  selected = nil, amount = 1, plan = nil, job = nil, treePage = 0,
  menu = nil,   -- { state = "type"|"mod"|"machine"|"id", type, list, scroll, ... }
  panel = nil,  -- overlay in the list area: numpad / outputs / testing
  msg = nil, msgColor = C.text, msgUntil = 0,
  filter = nil,  -- search text (lower case) or nil
  typing = false, -- the terminal is reading input (search, fluid amounts)
  items = {},
}

local mon, win, W, H, g

-- ---------------------------------------------------------------- drawing helpers

local function at(x, y, text, fg, bg)
  if y < 1 or y > H or x > W then return end
  if x < 1 then text = text:sub(2 - x); x = 1 end
  text = text:sub(1, W - x + 1)
  win.setTextColor(fg or C.text)
  win.setBackgroundColor(bg or C.bg)
  win.setCursorPos(x, y)
  win.write(text)
end

local function cell(x, y, bg) at(x, y, " ", C.text, bg) end

local function fill(x1, y1, x2, y2, bg)
  for y = y1, y2 do at(x1, y, (" "):rep(math.max(0, x2 - x1 + 1)), C.text, bg) end
end

local function fit(s, w)
  if #s <= w then return s end
  if w <= 1 then return s:sub(1, w) end
  return s:sub(1, w - 1) .. "~"
end

local function pad(s, w) return fit(s, w) .. (" "):rep(math.max(0, w - #fit(s, w))) end

local function message(text, color, seconds)
  S.msg, S.msgColor, S.msgUntil = text, color or C.text, os.clock() + (seconds or 8)
  log.info("%s", text)
end

local function displayCount(key, n)
  if indexer.isFluid(key) then return util.formatFluid(n) end
  return util.formatCount(n)
end

-- ---------------------------------------------------------------- geometry

local function layout()
  local mw, mh = mon.getSize()
  win = window.create(mon, 1, 1, mw, mh, false)
  -- leave the last column and row empty: same 1-cell margin as on the left
  W, H = mw - 1, mh - 1
  local fx = math.max(20, math.floor(W * 0.45))
  g = {
    fx = fx, listX = fx + 1, listW = W - fx - 1, listY = 3, listH = H - 3,
    cx = fx - 6, iconX = fx - 4,
    treeX = 2, treeW = fx - 2, treeY = 2, treeH = math.max(3, H - 14),
    boxY = H - 12, menuX = 2, menuY = H - 11, menuW = fx - 9, menuH = 5,
    sepY = H - 5, addY = H - 4,
    sortY = H - 10, modeY = H - 7, upY = H - 4, downY = H - 1,
  }
end

-- ---------------------------------------------------------------- data

local function refreshItems()
  local rows = indexer.stockList()
  local list = {}
  local seen = {}
  local function match(key)
    if not S.filter then return true end
    return key:lower():find(S.filter, 1, true) or indexer.displayName(key):lower():find(S.filter, 1, true)
  end
  for _, r in ipairs(rows) do
    if (S.mode == "fluid") == r.fluid and match(r.key) then
      local craft = recipes.hasRecipe(r.key)
      if S.sort == "count" or craft then
        list[#list + 1] = { key = r.key, count = r.count, craft = craft }
      end
      seen[r.key] = true
    end
  end
  -- things we can craft but have none of
  for key in pairs(recipes.byOutput) do
    if not seen[key] and (S.mode == "fluid") == indexer.isFluid(key) and match(key) then
      list[#list + 1] = { key = key, count = 0, craft = true }
    end
  end
  for _, e in ipairs(list) do e.sortName = indexer.displayName(e.key):lower() end
  table.sort(list, function(a, b) -- most first, equal counts A-Z by shown name
    if a.count ~= b.count then return a.count > b.count end
    if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    return a.key < b.key
  end)
  S.items = list
  S.scroll = math.max(0, math.min(S.scroll, #list - 1))
end

local function replan()
  if not S.selected then S.plan = nil return end
  -- the page is kept (drawTree clamps it): rescans replan every few seconds
  S.plan = planner.plan(S.selected, S.amount, executor.avail, recipes, indexer.toolPoints)
end

-- ---------------------------------------------------------------- tree

-- One line per node, drawn in segments:
--   Precision mechanism   0/40     name coloured by status, count right-aligned
--   +-Brass casing        0/40     branches dim; "`-" = last child
--   | +-Andesite alloy   40/40
--   | `-\15 Wrench          1/2    \15 = tool (not used up, wears down)
-- Colours: green done, yellow running, grey waiting, orange can't finish, red missing.
local function nodeColor(n)
  if n.group then return n.missing > 0 and C.warn or C.text, 0 end
  local have = n.stock + n.virtual
  if not n.craft then
    if n.missing > 0 then return C.err, have end
    return C.text, have
  end
  local st = n.craft.step
  local per = recipes.yield(st.recipe, n.key)
  local done = have + math.min(n.need - have, (st.doneRuns or 0) * per)
  if st.status == "fail" then return C.err, done end
  if done >= n.need then return C.ok, done end
  if n.missing > 0 then return C.warn, done end
  if st.status == "run" then return C.partial, done end
  return C.todo, done
end

local function treeLines(plan)
  local lines = {}
  local function walk(n, branch, last, isRoot)
    local color, done = nodeColor(n)
    local lead = isRoot and "" or (branch .. (last and "`-" or "+-"))
    local mark = n.tool and "\15 " or ""
    local count = n.group and (#n.children .. " items")
      or (displayCount(n.key, done) .. "/" .. displayCount(n.key, n.need))
    -- more is in storage, but queued/running orders hold it: "0/4 r3"
    local held = (not n.group and not plan.job and done < n.need) and executor.reserved(n.key) or 0
    if held > 0 then count = count .. " r" .. displayCount(n.key, held) end
    local w = g.treeW - 1 -- one free cell before the frame
    local room = math.max(2, w - #lead - #mark - #count - 1)
    local name = fit(n.label or indexer.displayName(n.key), room)
    if indexer.isFluid(n.key) and color == C.text then color = C.fluid end
    local gap = (" "):rep(math.max(1, w - #lead - #mark - #name - #count))
    lines[#lines + 1] = {
      { lead, C.dim }, { mark, C.fluid }, { name, color }, { gap, C.text },
      { count, (not n.group and done >= n.need) and C.ok or color },
    }
    local child = isRoot and "" or (branch .. (last and "  " or "| "))
    for i, c in ipairs(n.children) do walk(c, child, i == #n.children, false) end
  end
  walk(plan.root, "", true, true)
  return lines
end

local function drawTree()
  fill(g.treeX, g.treeY, g.treeX + g.treeW - 1, g.treeY + g.treeH - 1, C.bg)
  local plan = (S.job and S.job.plan) or S.plan
  if plan then plan.job = S.job and S.job.plan == plan end
  if not plan then
    at(g.treeX, g.treeY, "No item selected", C.dim)
    return
  end
  local lines = treeLines(plan)
  local per = g.treeH - 1
  local pages = math.max(1, math.ceil(#lines / per))
  S.treePage = math.max(0, math.min(S.treePage, pages - 1))
  for i = 1, per do
    local l = lines[S.treePage * per + i]
    if l then
      local x = g.treeX
      for _, seg in ipairs(l) do
        local text = seg[1]:sub(1, g.treeX + g.treeW - x)
        if #text > 0 then at(x, g.treeY + i - 1, text, seg[2]) end
        x = x + #text
      end
    end
  end
  local navY = g.treeY + g.treeH - 1
  if pages > 1 then
    at(g.treeX, navY, "<", C.dim)
    at(g.treeX + g.treeW - 1, navY, ">", C.dim)
    local p = ("pg %d/%d"):format(S.treePage + 1, pages)
    at(g.treeX + math.floor((g.treeW - #p) / 2), navY, p, C.text)
  end
  if S.job and S.job.error then
    at(g.treeX, navY, pad(S.job.error, g.treeW), C.err)
  end
end

-- ---------------------------------------------------------------- frame / controls

local function drawFrame()
  local f, fx = C.frame, g.fx
  -- list frame corners
  for _, p in ipairs({ { fx, 2 }, { fx, 3 }, { fx + 1, 2 }, { W, 2 }, { W, 3 }, { W - 1, 2 },
    { fx + 1, H }, { fx, H - 1 }, { fx, H }, { W, H }, { W, H - 1 }, { W - 1, H } }) do
    cell(p[1], p[2], f)
  end
  local b = g.boxY
  -- controls box: left line, right line, top edge (gaps like the old frame)
  for y = b, H do
    local o = y - b
    if o ~= 2 and o ~= 5 and o ~= 10 then cell(g.cx, y, f) end
  end
  for y = b, H - 3 do
    local o = y - b
    if o ~= 2 and o ~= 6 then cell(fx, y, f) end
  end
  for x = g.cx, fx do
    local o = x - g.cx
    if o ~= 3 and o ~= 4 then cell(x, b, f) end
  end
  -- dashed separator above ADD
  for x = 2, g.cx do
    if x ~= 4 and x ~= 9 and x ~= g.cx - 2 then cell(x, g.sepY, f) end
  end

  -- 3x2 icons: sort, item/fluid mode, page up, page down
  local ix = g.iconX
  local function icon(y, rows, accent)
    for r = 1, 2 do
      for c = 1, 3 do
        local ch = rows[r]:sub(c, c)
        if ch == "W" then cell(ix + c - 1, y + r - 1, colors.white)
        elseif ch == "c" then cell(ix + c - 1, y + r - 1, accent)
        elseif ch == "g" then cell(ix + c - 1, y + r - 1, C.btn) end
      end
    end
  end
  icon(g.sortY, { "WWc", "Wcc" }, S.sort == "count" and C.sortCount or C.sortCraft)
  icon(g.modeY, { "Wcc", "WWc" }, S.mode == "item" and C.item or C.fluid)
  icon(g.upY, { ".g.", "ggg" })
  icon(g.downY, { "ggg", ".g." })

  -- big ADD
  local x = 2
  for _, ch in ipairs({ "A", "D", "D" }) do
    for r, row in ipairs(BIG[ch]) do
      for c = 1, 3 do
        if row:sub(c, c) == "#" then cell(x + c - 1, g.addY + r - 1, S.menu and C.ok or colors.white) end
      end
    end
    x = x + 4
  end
end

-- ---------------------------------------------------------------- add menu

-- Pool members (cfg.pools) as a set: they show up as their pool, not one by one.
local function poolMembers()
  local set = {}
  for _, members in pairs(M.cfg.pools or {}) do
    for _, n in ipairs(members) do set[n] = true end
  end
  return set
end

local function availableMachines()
  local skip = util.copy(indexer.exclude)
  for n in pairs(poolMembers()) do skip[n] = true end
  for _, n in ipairs(indexer.storage) do skip[n] = true end
  for _, n in ipairs(indexer.tankNames) do skip[n] = true end
  for n in pairs(indexer.isCraft) do skip[n] = true end
  for _, t in pairs(executor.turtles) do if t.name then skip[t.name] = true end end
  local out = {}
  for _, name in ipairs(peripheral.getNames()) do
    if not skip[name] and name:find(":") then
      local m = peripheral.wrap(name)
      if m and (m.list or m.tanks) then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

local function menuOptions()
  local m = S.menu
  if m.state == "type" then
    return {
      { label = "Turtle", color = executor.anyTurtle() and C.turtle or C.dim, value = "turtle" },
      { label = "Machine", color = C.machine, value = "machine" },
      { label = "Multiblock", color = C.multiblock, value = "multiblock" },
      { label = "Pool", color = next(M.cfg.pools or {}) and C.pool or C.dim, value = "pool" },
    }
  end
  local out = {}
  for _, v in ipairs(m.list) do out[#out + 1] = { label = v.label, color = C.text, value = v.value } end
  return out
end

local function drawMenu()
  fill(g.menuX, g.menuY, g.menuX + g.menuW - 1, g.menuY + g.menuH - 1, C.bg)
  if not S.menu then return end
  local opts = menuOptions()
  for i = 1, g.menuH do
    local o = opts[S.menu.scroll + i]
    if o then at(g.menuX, g.menuY + i - 1, fit(o.label, g.menuW), o.color) end
  end
end

-- ---------------------------------------------------------------- list / panels

local QUEUE_ROWS = 3

-- Rows above the item list: the order queue, then the search line. Returns how many.
local function drawListHead()
  local y = g.listY
  local queued = 0
  S.queueAt = {}
  for _, j in ipairs(executor.queueRows(QUEUE_ROWS)) do
    S.queueAt[y] = j
    local color, right
    if j.status == "done" then color, right = C.qDone, "done"
    elseif j.status == "running" then
      color, right = C.qRun, math.min(99, math.floor(executor.progress(j) * 100)) .. "%"
    else
      queued = queued + 1
      color, right = queued == 1 and C.qNext or C.qLater, "wait"
    end
    local left = ("#%d %s%s"):format(j.id, j.auto and "+" or "", executor.label(j.key, j.qty))
    at(g.listX, y, pad(left, g.listW - #right - 1), color)
    at(W - #right, y, right, color)
    y = y + 1
  end
  if S.filter then
    at(g.listX, y, pad("Search: " .. S.filter, g.listW - 3), C.warn)
    at(W - 3, y, "[x]", C.err)
    y = y + 1
  end
  return y - g.listY
end

local function drawList()
  fill(g.listX, g.listY, W - 1, H - 1, C.bg)
  local p = S.panel
  if p then return p.draw() end
  local off = drawListHead()
  S.listOff = off
  S.minusAt = nil
  if S.filter and #S.items == 0 then at(g.listX, g.listY + off, "nothing found", C.dim) end
  for i = 1, g.listH - 1 - off do
    local e = S.items[S.scroll + i]
    if not e then break end
    local sel = e.key == S.selected
    local count = displayCount(e.key, e.count)
    local suffix = "[" .. count .. (e.craft and "+" or " ") .. "]"
    local nameW = g.listW - #suffix - (sel and 2 or 0)
    local name = pad(indexer.displayName(e.key), nameW)
    local y = g.listY + off + i - 1
    local x = g.listX
    if sel then at(x, y, "> ", C.sel); x = x + 2 end
    at(x, y, name, sel and C.sel or (indexer.isFluid(e.key) and C.fluid or C.text))
    at(x + nameW, y, "[", C.dim)
    at(x + nameW + 1, y, count, e.count == 0 and C.err or C.text)
    if sel and e.craft then
      -- the selected item's "+" turns into "-": tap it to delete the recipe
      at(x + nameW + 1 + #count, y, "-", C.err)
      S.minusAt = { x = x + nameW + 1 + #count, y = y, key = e.key }
    else
      at(x + nameW + 1 + #count, y, e.craft and "+" or " ", C.ok)
    end
    at(x + nameW + 2 + #count, y, "]", C.dim)
  end
end

-- Mod buttons, right to left from the frame; S.buttonsAt = { { x1, x2, button } }.
local function drawButtons()
  S.buttonsAt = {}
  local x = W - 1
  for _, b in ipairs(api.buttons) do
    x = x - #b.label
    local on = b.active and b.active()
    at(x, H, b.label, on and C.sel or C.text)
    S.buttonsAt[#S.buttonsAt + 1] = { x, x + #b.label - 1, b }
    x = x - 1
  end
  return W - 1 - x - 1 -- width taken
end

local function drawCounter()
  fill(g.listX, H, W - 1, H, C.bg)
  if S.panel then return end
  local taken = drawButtons()
  if not S.selected then return end
  local x = g.listX
  if S.job and S.job.status == "running" then
    at(x, H, "< << ][ >> > [CRAFTING]", C.dim)
    return
  end
  local ok = S.plan and S.plan.ok
  at(x, H, "< << ][ >> > ", ok and C.text or C.err)
  local shown = type(S.selected) == "string" and displayCount(S.selected, S.amount) or tostring(S.amount)
  at(x + 13, H, "[" .. shown .. "]", ok and C.text or C.err)
  if S.plan and not ok then
    local hint = S.maxHint and (" max " .. S.maxHint) or " tap [N]=max"
    local hx = x + 15 + #shown
    at(hx, H, fit(hint, math.max(0, W - 2 - taken - hx)), C.dim)
  end
end

local function drawProgress()
  fill(g.fx + 2, 2, W - 2, 2, C.bg)
  local job = executor.activeJob()
  if not job then return end
  local barW = math.max(4, W - g.fx - 8)
  local p = executor.progress(job)
  local filled = math.floor(barW * p)
  -- a running job shows at most 99%: "100%" would touch the frame corner
  local pct = math.min(99, math.floor(p * 100))
  at(g.fx + 2, 2, "[" .. ("\127"):rep(filled) .. ("-"):rep(barW - filled) .. "]" .. pct .. "%", C.ok)
end

local function drawStatus()
  fill(1, 1, g.fx - 1, 1, C.bg)
  if S.msg and os.clock() < S.msgUntil then at(2, 1, fit(S.msg, g.fx - 2), S.msgColor) return end
  -- otherwise why the running order waits: "Wait: Iron ingot: no free turtle"
  local why = executor.why(executor.activeJob())
  if why then at(2, 1, fit("Wait: " .. why, g.fx - 2), C.warn) end
end

function M.draw()
  win.setVisible(false)
  win.setBackgroundColor(C.bg)
  win.clear()
  drawFrame()
  drawStatus()
  drawProgress()
  drawTree()
  drawMenu()
  drawList()
  drawCounter()
  win.setVisible(true)
end

-- ---------------------------------------------------------------- recipe test flow

local function finishRecipe(draft)
  local function save(mainKey)
    for _, o in ipairs(draft.outputs) do o.main = (o.key == mainKey) or nil end
    api.emit("recipe.encode", draft)
    local r = recipes.add(draft)
    message(("Saved: %s (%s)"):format(indexer.displayName(recipes.mainKey(r)), r.type), C.ok)
    refreshItems()
    S.panel = nil
  end
  if #draft.outputs == 0 then message("No result detected", C.err); S.panel = nil return end
  if #draft.outputs == 1 then return save(draft.outputs[1].key) end
  -- several results: pick the main one (others are kept as byproducts)
  S.panel = {
    draw = function()
      at(g.listX, g.listY, "Main result?", C.warn)
      for i, o in ipairs(draft.outputs) do
        at(g.listX, g.listY + 1 + i, fit(("%s x%s"):format(indexer.displayName(o.key), displayCount(o.key, o.count)), g.listW), C.text)
      end
    end,
    touch = function(_, y)
      local o = draft.outputs[y - g.listY - 1]
      if o then save(o.key) end
    end,
  }
end

local function runTest(kind, machine, fluids)
  local label = kind == "turtle" and "turtle" or machine
  local started = os.clock()
  S.panel = {
    draw = function()
      at(g.listX, g.listY, fit("Testing " .. label .. "...", g.listW), C.warn)
      at(g.listX, g.listY + 1, ("%.1fs"):format(os.clock() - started), C.dim)
    end,
    touch = function() end,
  }
  tasks.spawn(function()
    local ok, res = pcall(function()
      if kind == "turtle" then
        local t = executor.freeTurtle() or error("no free turtle", 0)
        t.busy = true
        local ok2, r = pcall(encoder.testTurtle, t)
        t.busy = false
        if not ok2 then error(r, 0) end
        return r
      end
      return encoder.testMachine({ type = kind, machine = machine }, fluids, function() os.queueEvent("jobs_changed") end)
    end)
    if ok then finishRecipe(res) else message("Test failed: " .. tostring(res), C.err, 15); S.panel = nil end
    os.queueEvent("jobs_changed")
  end, "test")
end

-- mB typed in the terminal: "250", "1b" / "1.5B" = buckets, "" = skip. nil if not a number.
local function parseAmount(text)
  text = text:gsub("%s", ""):lower()
  if text == "" then return 0 end
  local n, unit = text:match("^([%d%.]+)(b?)$")
  n = tonumber(n)
  if not n then return nil end
  return math.floor(unit == "b" and n * 1000 or n)
end
M.parseAmount = parseAmount

-- Asks mB for each fluid in the recipe tanks in the computer's terminal, then runs the test:
--   water: 1B > 250        (Enter = skip this fluid)
local function askFluids(kind, machine)
  local queue, seen = {}, {}
  for _, f in ipairs(encoder.readTanks()) do
    if not seen[f.key] then seen[f.key] = true; queue[#queue + 1] = f end
  end
  if #queue == 0 then return runTest(kind, machine, {}) end
  S.panel = {
    draw = function()
      at(g.listX, g.listY, fit("Fluid amounts: type them", g.listW), C.fluid)
      at(g.listX, g.listY + 1, fit("in the computer terminal", g.listW), C.fluid)
    end,
    touch = function() end,
  }
  tasks.spawn(function()
    local amounts = {}
    S.typing = true
    print()
    print(("Recipe fluids for %s: mB, \"1b\" = 1000, Enter = skip"):format(kind == "turtle" and "turtle" or machine))
    for _, f in ipairs(queue) do
      local n
      repeat
        term.setTextColor(colors.cyan)
        write(("%s: %s > "):format(util.stripMod(f.name), displayCount(f.key, f.amount)))
        term.setTextColor(colors.white)
        n = parseAmount(read())
        if not n then print("  a number please, e.g. 250 or 1b") end
      until n
      amounts[f.key] = math.min(n, f.amount)
    end
    S.typing = false
    runTest(kind, machine, amounts)
    os.queueEvent("jobs_changed")
  end, "fluids")
end

local function startTest(kind, machine)
  S.menu = nil
  if kind == "turtle" then
    if not executor.anyTurtle() then message("No turtle online", C.err) return end
    return runTest("turtle")
  end
  askFluids(kind, machine)
end

local function menuPick(o)
  local m = S.menu
  if m.state == "type" then
    m.type = o.value
    if o.value == "turtle" then return startTest("turtle") end
    if o.value == "pool" then
      local list = {}
      for name, members in pairs(M.cfg.pools or {}) do
        list[#list + 1] = { label = ("%s (%d)"):format(name, #members), value = name }
      end
      table.sort(list, function(a, b) return a.label < b.label end)
      if #list == 0 then message("No pools in config.lua", C.err); S.menu = nil return end
      m.state, m.list, m.scroll = "id", list, 0
      return
    end
    if o.value == "multiblock" then
      local list, inPool = {}, poolMembers()
      for name in pairs(M.multiblocks) do
        if not inPool[name] then list[#list + 1] = { label = name, value = name } end
      end
      table.sort(list, function(a, b) return a.label < b.label end)
      if #list == 0 then message("data/multiblock.json is empty", C.err); S.menu = nil return end
      m.state, m.list, m.scroll = "id", list, 0
      return
    end
    local mods = {}
    m.machines = availableMachines()
    for _, name in ipairs(m.machines) do mods[util.getMod(name)] = true end
    local list = {}
    for mod in pairs(mods) do list[#list + 1] = { label = mod:gsub("^%l", string.upper), value = mod } end
    table.sort(list, function(a, b) return a.label < b.label end)
    if #list == 0 then message("No machines on the network", C.err); S.menu = nil return end
    m.state, m.list, m.scroll = "mod", list, 0
  elseif m.state == "mod" then
    -- machines with the same label (a mod's "MV c5") are one row: "[0,1,2,3] MV c5"; the
    -- test runs on the first, the recipe runs on all of them (api "machine.workers")
    local types, names = {}, {}
    for _, name in ipairs(m.machines) do
      if util.getMod(name) == o.value then names[#names + 1] = name end
    end
    api.emit("machine.labels", names)
    for _, name in ipairs(m.machines) do
      if util.getMod(name) == o.value then
        local _, machine, id = util.parsePeripheralName(name)
        types[machine] = types[machine] or {}
        local extra = api.filter("machine.label", "", name)
        table.insert(types[machine], { value = name, id = id or 0, extra = extra })
      end
    end
    local list = {}
    for machine, all in pairs(types) do
      table.sort(all, function(a, b) return a.id < b.id end)
      local ids, byExtra = {}, {}
      for _, e in ipairs(all) do
        local g = e.extra ~= "" and byExtra[e.extra]
        if g then
          g.ids[#g.ids + 1] = e.id
        else
          g = { value = e.value, id = e.id, extra = e.extra, ids = { e.id } }
          ids[#ids + 1] = g
          if e.extra ~= "" then byExtra[e.extra] = g end
        end
      end
      for _, g in ipairs(ids) do
        local head = #g.ids > 1 and ("[" .. table.concat(g.ids, ",") .. "]") or ("[ID-" .. g.id .. "]")
        g.label = head .. (g.extra ~= "" and (" " .. g.extra) or "")
      end
      list[#list + 1] = { label = util.formatName(machine), value = ids }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    m.state, m.list, m.scroll = "machine", list, 0
  elseif m.state == "machine" then
    if #o.value == 1 then return startTest("machine", o.value[1].value) end
    m.state, m.list, m.scroll = "id", o.value, 0
  elseif m.state == "id" then
    startTest(m.type, o.value)
  end
end

-- ---------------------------------------------------------------- touch

local function inRect(x, y, x1, y1, x2, y2) return x >= x1 and x <= x2 and y >= y1 and y <= y2 end

local function scroll(dir)
  if S.menu and S.menu.state ~= "type" then
    local maxS = math.max(0, #menuOptions() - g.menuH)
    S.menu.scroll = math.max(0, math.min(maxS, S.menu.scroll + dir))
  else
    local page = g.listH - 1
    S.scroll = math.max(0, math.min(math.max(0, #S.items - page), S.scroll + dir * page))
  end
end

local function order()
  if not S.selected then return end
  local job, plan = executor.submit(S.selected, S.amount, { deliver = executor.canDeliver(S.selected) })
  if job then
    S.job = job
    message(("Order #%d: %s"):format(job.id, executor.label(job.key, job.qty)), C.ok)
  else
    S.plan = plan
    executor.reportMissing(S.selected, S.amount, plan)
    message("Not enough resources: see the terminal", C.err, 15)
  end
end

-- Tree of an order (running or queued) instead of the selected item's plan.
-- "-" next to the selected item: the first tap asks, a second one within 5 s deletes the
-- recipe the tree uses (the first of several; the next one takes its place).
local function deleteRecipe(key)
  local r = recipes.forOutput(key)[1]
  if not r then return end
  local what = r.type == "turtle" and "turtle" or tostring(r.machine)
  local c = S.confirmDel
  if not (c and c.key == key and os.clock() < c.till) then
    S.confirmDel = { key = key, till = os.clock() + 5 }
    message(("Tap - again: delete %s recipe (%s)"):format(indexer.displayName(key), what), C.warn, 5)
    return
  end
  S.confirmDel = nil
  recipes.remove(r.id)
  local left = #recipes.forOutput(key)
  message(("Deleted %s recipe (%s), %d left"):format(indexer.displayName(key), what, left), C.ok)
  refreshItems()
  if left == 0 and S.sort ~= "count" and S.selected == key then S.selected, S.plan = nil, nil end
  replan()
end

local function showJob(job)
  S.job, S.selected, S.amount, S.maxHint, S.treePage = job, job.key, job.qty, nil, 0
end

local function isFluidSel() return type(S.selected) == "string" and indexer.isFluid(S.selected) end

local function setAmount(n)
  S.amount = math.max(1, math.min(99999, n))
  S.maxHint = nil
  replan()
end

function M.touch(x, y)
  -- big ADD toggles the menu
  if inRect(x, y, 2, g.addY, 12, H) then
    if S.menu then S.menu = nil else
      S.menu = { state = "type", scroll = 0 }
      os.queueEvent("autocraft_rediscover") -- machines connected since the last look
    end
    return
  end
  -- icons
  if inRect(x, y, g.iconX, g.upY, g.iconX + 2, g.upY + 1) then return scroll(-1) end
  if inRect(x, y, g.iconX, g.downY, g.iconX + 2, g.downY + 1) then return scroll(1) end
  if inRect(x, y, g.iconX, g.sortY, g.iconX + 2, g.sortY + 1) then
    S.sort = S.sort == "count" and "craftable" or "count"; S.scroll = 0; refreshItems() return
  end
  if inRect(x, y, g.iconX, g.modeY, g.iconX + 2, g.modeY + 1) then
    S.mode = S.mode == "item" and "fluid" or "item"; S.scroll = 0; refreshItems() return
  end
  -- add menu lines
  if S.menu and inRect(x, y, g.menuX, g.menuY, g.menuX + g.menuW - 1, g.menuY + g.menuH - 1) then
    local o = menuOptions()[S.menu.scroll + y - g.menuY + 1]
    if o then menuPick(o) end
    return
  end
  -- overlay panel in the list area
  if S.panel and inRect(x, y, g.listX, g.listY, W - 1, H) then return S.panel.touch(x, y) end
  -- tree paging
  if y == g.treeY + g.treeH - 1 and inRect(x, y, g.treeX, y, g.treeX + g.treeW - 1, y) then
    if x <= g.treeX + 2 then S.treePage = S.treePage - 1 elseif x >= g.treeX + g.treeW - 3 then S.treePage = S.treePage + 1 end
    return
  end
  -- mod buttons on the bottom bar
  if y == H and not S.panel then
    for _, b in ipairs(S.buttonsAt or {}) do
      if x >= b[1] and x <= b[2] then
        if not (S.job and S.job.status == "running") then b[3].onTouch() end
        return
      end
    end
  end
  -- counter: < << ][ >> > [N]
  if y == H and S.selected and x >= g.listX then
    if S.job and S.job.status == "running" then return end
    local o = x - g.listX
    local step = isFluidSel() and 100 or 1 -- fluids: 100 mB / 1 B steps
    if o == 0 then setAmount(S.amount - step)
    elseif o == 2 or o == 3 then setAmount(S.amount - 10 * step)
    elseif o == 5 or o == 6 then order()
    elseif o == 8 or o == 9 then setAmount(S.amount + 10 * step)
    elseif o == 11 then setAmount(S.amount + step)
    elseif o >= 13 then
      local max = planner.maxCraftable(S.selected, executor.avail, recipes, 99999, indexer.toolPoints)
      if max > 0 then setAmount(max) else S.maxHint = 0 end
    end
    return
  end
  -- stock list
  local off = S.listOff or 0
  if S.filter and y == g.listY + off - 1 and inRect(x, y, g.listX, y, W - 1, y) then
    S.filter, S.scroll = nil, 0
    refreshItems()
    return
  end
  -- a queue row (or the progress bar) shows that order's tree
  if S.queueAt and S.queueAt[y] and x >= g.listX then return showJob(S.queueAt[y]) end
  if y == 2 and x > g.fx and executor.activeJob() then return showJob(executor.activeJob()) end
  if y < g.listY + off then return end
  local m = S.minusAt
  if m and y == m.y and x >= m.x and x <= m.x + 1 then return deleteRecipe(m.key) end
  if inRect(x, y, g.listX, g.listY, W - 1, g.listY + g.listH - 2) then
    local e = S.items[S.scroll + y - g.listY - off + 1]
    if e then
      S.selected, S.amount, S.job, S.maxHint, S.treePage = e.key, indexer.isFluid(e.key) and 1000 or 1, nil, nil, 0
      replan()
    end
    return
  end
  -- tapping elsewhere closes the menu
  if S.menu then S.menu = nil end
end

-- ---------------------------------------------------------------- loop

function M.init(cfg, multiblocks)
  M.cfg = cfg
  M.multiblocks = multiblocks or {}
  M.monName = cfg.main_monitor
  if not M.monName then
    -- the biggest monitor: a small one may be the encoder's tank panel
    local best = 0
    for _, n in ipairs(peripheral.getNames()) do
      if peripheral.getType(n) == "monitor" then
        local w, h = peripheral.call(n, "getSize")
        if w * h > best then M.monName, best = n, w * h end
      end
    end
    if not M.monName then error("no monitor", 0) end
  end
  mon = peripheral.wrap(M.monName) or error("monitor not found: " .. M.monName, 0)
  if mon.setTextScale then mon.setTextScale(cfg.main_TextScale or 1) end
  mon.setCursorBlink(false)
  layout()
  refreshItems()
  api.ui.message = function(text, color) message(text, color) end
  api.ui.selected = function() return S.selected end
  api.ui.select = function(target)
    S.selected, S.job, S.maxHint, S.treePage = target, nil, nil, 0
    S.amount = type(target) == "string" and indexer.isFluid(target) and 1000 or 1
    replan()
    os.queueEvent("jobs_changed")
  end
end

-- for previews/tests: show a given state
M.state = S

-- The tree follows the orders by itself: a finished order stays 5 s (a failed one 30 s), then
-- the tree clears or shows the order that runs now. A new order replaces an empty tree or a
-- finished one, never an item you are looking at. Restock orders show only when no order of
-- yours is waiting.
local CLEAR_AFTER = { done = 5, cancelled = 5, failed = 30 }
local function finished(job) return job and CLEAR_AFTER[job.status] ~= nil end

function M.autoTree()
  local job = S.job
  if finished(job) then
    job.clearAt = job.clearAt or (os.clock() + CLEAR_AFTER[job.status])
    if os.clock() < job.clearAt then return end
    S.job, S.selected, S.plan, S.treePage, S.maxHint = nil, nil, nil, 0, nil
  end
  if S.job or S.selected or S.menu or S.panel then return end
  local active = executor.activeJob()
  if not active then return end
  if active.auto then
    for _, j in ipairs(executor.jobs) do
      if not j.auto and (j.status == "queued" or j.status == "running") then return end
    end
  end
  S.job, S.selected, S.amount, S.maxHint, S.treePage = active, active.key, active.qty, nil, 0
end

function M.refresh()
  refreshItems()
  if S.selected and not (S.job and S.job.status == "running") then replan() end
end

function M.loop()
  M.draw()
  -- a timer that fires while a peripheral call waits is lost: redraw by the clock instead
  local due = os.clock() + 1
  os.startTimer(1)
  while true do
    local e, a, b, c = os.pullEvent()
    if e == "monitor_touch" and a == M.monName then
      local ok, err = pcall(M.touch, b, c)
      if not ok then message("UI error: " .. tostring(err), C.err) end
      M.draw()
    elseif e == "char" and (a == "q" or a == "Q") and not S.typing then
      if not executor.cancel() then message("Nothing to cancel", C.dim) end
      M.draw()
    elseif e == "char" and (a == "m" or a == "M") and not S.typing then
      -- Settings in the terminal; crafting goes on meanwhile
      S.typing = true
      tasks.spawn(function()
        local settings, console = require("system.core.settings"), require("system.utils.console")
        console.pause()
        local ok, saved, restart = pcall(settings.run, { cfg = api.cfg, mods = require("system.core.mods").names() })
        if ok and saved then
          executor.pools = api.cfg.pools or {}
          if api.rediscover then api.rediscover() end
          if restart then
            local a = settings.ask("Monitors/mods changed: restart now? (y/n) ", "y")
            if a == "y" or a == "Y" then os.reboot() end
          end
        end
        term.clear(); term.setCursorPos(1, 1)
        console.resume()
        if not ok then printError(saved) end
        if ok and saved then message("Settings saved", C.ok) end
        S.typing = false
        os.queueEvent("jobs_changed")
      end, "settings")
    elseif e == "char" and (a == "s" or a == "S") and not S.typing then
      S.typing = true
      tasks.spawn(function()
        term.setTextColor(colors.yellow)
        write("Search (Enter = show all): ")
        term.setTextColor(colors.white)
        local q = read():gsub("^%s+", ""):gsub("%s+$", ""):lower()
        S.typing = false
        S.filter, S.scroll = q ~= "" and q or nil, 0
        refreshItems()
        os.queueEvent("jobs_changed")
      end, "search")
    elseif e == "monitor_resize" and a == M.monName then
      layout(); M.draw()
    elseif e == "stock_updated" then
      M.refresh(); M.draw()
    elseif e == "jobs_changed" then
      local job = S.job
      if job and (job.status == "done" or job.status == "failed" or job.status == "cancelled") and not job.notified then
        job.notified = true
        if job.status == "done" then message("Done: " .. executor.label(job.key, job.qty), C.ok) end
        if job.status == "failed" then message("Failed: see the terminal", C.err, 20) end
        if job.status == "cancelled" then message("Cancelled: " .. executor.label(job.key, job.qty), C.warn) end
      end
      M.autoTree()
      M.draw()
    elseif os.clock() >= due then
      M.autoTree()
      M.draw()
      due = os.clock() + 1
      os.startTimer(1)
    end
  end
end

return M

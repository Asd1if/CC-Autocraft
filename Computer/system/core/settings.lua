-- Settings menu in the computer's terminal: everything config.lua and data/multiblock.json
-- hold, without editing files. Opens from the start menu (Main / Settings / Update) or with M
-- while autocraft runs.
--   Up/Down  move         Enter  open / edit       Left/Right  change a value in place
--   Backspace or Shift  back (on the first page: leave, asking to save if something changed)
-- Saving rewrites config.lua (the old one is kept as config.lua.bak) with the same sections.
-- Storage, machines and pools apply at once; monitors, the modem and mods after a restart.
local util = require("system.utils.util")
local theme = require("system.core.theme")

local M = {}

-- ---------------------------------------------------------------- config.lua text

-- Key order and sections of the written file; keys not listed go to the end.
M.SECTIONS = {
  { "Мониторы", { "main_monitor", "fluid_monitor", "main_TextScale", "fluid_TextScale", "theme" } },
  { "Clipboard, сеть, лог", { "clipboard_reader", "clipboard_skip_checked", "rednet_modem", "debug_mode" } },
  { "Крафт", { "craft_timeout", "stall_timeout", "batch", "restock_interval", "rescan" } },
  { "Склад", { "storage", "tanks", "exclude", "craft_storage", "craft_tanks", "encoder", "recipe_tanks" } },
  { "Машины и автоподдержание", { "pools", "restock" } },
  { "Моды", { "mods_disabled", "gtceu_tier_up", "gtceu_chips" } },
  { "Взаимозаменяемые предметы", { "substitutes" } },
}

M.COMMENTS = {
  stall_timeout = "заказ, в котором ничего не движется столько секунд, падает (nil = 3 x craft_timeout)",
  gtceu_tier_up = "рецепт с LV-машины может идти на MV, HV... того же типа и с той же платой",
  mods_disabled = "выключенные моды: { \"gtceu\" }",
  exclude = "блоки, которые никогда не склад и не машина",
  theme = "default, dark, amber, brass или своя из data/theme/<имя>.lua",
}

-- Keys startup.lua adds itself (old names, internal defaults): not written.
M.SKIP = { debug = true }

local function isIdent(k) return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end

-- A value as Lua source, tables over several lines at `indent`.
function M.serialize(v, indent)
  indent = indent or ""
  local tv = type(v)
  if tv == "string" then return ("%q"):format(v) end
  if tv ~= "table" then return tostring(v) end
  if next(v) == nil then return "{}" end
  local inner = indent .. "  "
  local parts = {}
  if isArray(v) then
    local flat, len = true, 0
    for _, x in ipairs(v) do
      if type(x) == "table" then flat = false end
      parts[#parts + 1] = M.serialize(x, inner)
      len = len + #parts[#parts] + 2
    end
    if flat and len < 60 then return "{ " .. table.concat(parts, ", ") .. " }" end
    return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. ",\n" .. indent .. "}"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local name = isIdent(k) and k or ("[" .. M.serialize(k) .. "]")
    parts[#parts + 1] = name .. " = " .. M.serialize(v[k], inner)
  end
  return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. ",\n" .. indent .. "}"
end

-- The whole config.lua for cfg.
function M.configText(cfg)
  local out = { "-- Описание всех ключей — в README (раздел про конфиг). nil — найти самому.",
    "-- Файл переписывается меню Settings (M в терминале); прошлый — config.lua.bak.", "return {" }
  local done = {}
  local function key(k)
    done[k] = true
    local line = "  " .. k .. " = " .. M.serialize(cfg[k], "  ") .. ","
    if M.COMMENTS[k] then line = line .. " -- " .. M.COMMENTS[k] end
    out[#out + 1] = line
  end
  for _, sec in ipairs(M.SECTIONS) do
    out[#out + 1] = ""
    out[#out + 1] = "  -- ———— " .. sec[1]
    for _, k in ipairs(sec[2]) do key(k) end
  end
  local rest = {}
  for k in pairs(cfg) do
    if not done[k] and not M.SKIP[k] and isIdent(k) then rest[#rest + 1] = k end
  end
  table.sort(rest)
  if #rest > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "  -- ———— Прочее"
    for _, k in ipairs(rest) do key(k) end
  end
  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = deepCopy(x) end
  return c
end
M.deepCopy = deepCopy

local function same(a, b) return M.serialize(a) == M.serialize(b) end

function M.save(cfg, multiblocks)
  if fs.exists("config.lua") then
    if fs.exists("config.lua.bak") then fs.delete("config.lua.bak") end
    fs.copy("config.lua", "config.lua.bak")
  end
  local h = fs.open("config.lua", "w")
  h.write(M.configText(cfg))
  h.close()
  if multiblocks then util.writeJSON("data/multiblock.json", multiblocks) end
end

-- ---------------------------------------------------------------- terminal UI

local function size() return term.getSize() end

local function draw(title, rows, cur, top, hint)
  local w, h = size()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow)
  term.write(title:sub(1, w))
  local view = h - 3
  for i = 0, view - 1 do
    local r = rows[top + i]
    if not r then break end
    term.setCursorPos(1, 3 + i)
    local sel = top + i == cur
    term.setBackgroundColor(sel and colors.gray or colors.black)
    term.setTextColor(r.color or (sel and colors.white or colors.lightGray))
    local right = r.value and tostring(r.value) or ""
    local left = (sel and "> " or "  ") .. r.text
    local room = w - #right - 1
    if #left > room then left = left:sub(1, room - 2) .. ".." end
    term.write(left .. (" "):rep(w - #left - #right) .. right)
  end
  term.setBackgroundColor(colors.black)
  term.setCursorPos(1, h)
  term.setTextColor(colors.gray)
  term.write((hint or "Enter open  <> change  Bksp back"):sub(1, w))
end

-- Text typed on the last line; default shown. Returns the text (nil if empty and no default).
function M.ask(prompt, default)
  local w, h = size()
  term.setCursorPos(1, h)
  term.setBackgroundColor(colors.black)
  term.clearLine()
  term.setTextColor(colors.yellow)
  term.write(prompt)
  term.setTextColor(colors.white)
  local s = read(nil, nil, nil, default and tostring(default) or nil)
  s = s and s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  return s
end

local function isBack(k) return k == keys.backspace or k == keys.leftShift or k == keys.rightShift end

-- A page: build() -> rows { text, value, color, enter(), left(), right() }. A handler returning
-- "back" leaves the page. Returns when the player goes back.
function M.page(title, build, hint)
  local cur, top = 1, 1
  while true do
    local rows = build()
    local _, h = size()
    local view = h - 3
    cur = math.max(1, math.min(cur, #rows))
    if cur < top then top = cur end
    if cur >= top + view then top = cur - view + 1 end
    draw(title, rows, cur, top, hint)
    local _, k = os.pullEvent("key")
    local r = rows[cur]
    local res
    if k == keys.up then cur = cur > 1 and cur - 1 or #rows
    elseif k == keys.down then cur = cur < #rows and cur + 1 or 1
    elseif k == keys.pageUp then cur = math.max(1, cur - view)
    elseif k == keys.pageDown then cur = math.min(#rows, cur + view)
    elseif k == keys.enter and r and r.enter then res = r.enter()
    elseif k == keys.left and r and (r.left or r.enter) then res = (r.left or r.enter)()
    elseif k == keys.right and r and (r.right or r.enter) then res = (r.right or r.enter)()
    elseif isBack(k) then return end
    if res == "back" then return end
  end
end

-- ---------------------------------------------------------------- value rows

local function boolRow(text, t, k, default)
  local function flip()
    local v = t[k]
    if v == nil then v = default end
    t[k] = not v
  end
  local v = t[k]
  if v == nil then v = default end
  return { text = text, value = v and "on" or "off", color = v and colors.lime or colors.red,
    enter = flip, left = flip, right = flip }
end

-- step: Left/Right; Enter types it. nilable: empty input = nil (shown as `none`).
local function numRow(text, t, k, step, min, nilable, none)
  local function add(d)
    return function()
      local v = (t[k] or 0) + d
      if min and v < min then v = nilable and nil or min end
      t[k] = v
    end
  end
  return { text = text, value = t[k] == nil and (none or "auto") or t[k],
    left = add(-step), right = add(step),
    enter = function()
      local s = M.ask(text .. ": ", t[k])
      local n = tonumber(s)
      if n then t[k] = (min and n < min) and min or n
      elseif nilable and not s then t[k] = nil end
    end }
end

-- ---------------------------------------------------------------- peripherals

-- Peripherals on the network: kind "items" (have list), "tanks" (have tanks), "any" (either),
-- "monitor". Returns sorted names and name -> first type.
local function candidates(kind)
  local names, types = {}, {}
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    local p = peripheral.wrap(name)
    local ok
    if kind == "monitor" then ok = t == "monitor"
    elseif kind == "items" then ok = p and p.list ~= nil and t ~= "turtle"
    elseif kind == "tanks" then ok = p and p.tanks ~= nil
    else ok = p and (p.list ~= nil or p.tanks ~= nil) end
    if ok then names[#names + 1] = name; types[name] = t end
  end
  table.sort(names)
  return names, types
end

local function indexOf(list, v)
  for i, x in ipairs(list) do if x == v then return i end end
end

local function summary(list)
  local n = #(list or {})
  if n == 0 then return "none" end
  if n == 1 then return list[1] end
  return n .. " entries"
end

-- Many peripherals, chosen by type (every block of that type, new ones too) or by name.
-- list holds both kinds of entries, like config.lua's storage = { "create:item_vault" }.
function M.pickMany(title, list, kind)
  local names, types = candidates(kind)
  local byType, order = {}, {}
  for _, n in ipairs(names) do
    local t = types[n]
    if not byType[t] then byType[t] = {}; order[#order + 1] = t end
    table.insert(byType[t], n)
  end
  table.sort(order)
  local function has(v) return indexOf(list, v) ~= nil end
  local function remove(v) local i = indexOf(list, v) if i then table.remove(list, i) end end

  local function typePage(t)
    M.page(title .. " > " .. t, function()
      local rows = {}
      for _, n in ipairs(byType[t]) do
        local whole = has(t)
        local on = whole or has(n)
        local function toggle()
          if whole then
            remove(t)
            for _, o in ipairs(byType[t]) do if o ~= n then list[#list + 1] = o end end
          elseif on then remove(n)
          else list[#list + 1] = n end
        end
        rows[#rows + 1] = { text = (on and "[x] " or "[ ] ") .. n, color = on and colors.lime or nil,
          enter = toggle, left = toggle, right = toggle }
      end
      return rows
    end, "Enter toggle  Bksp back")
  end

  M.page(title, function()
    local rows = {}
    for _, t in ipairs(order) do
      local some = 0
      for _, n in ipairs(byType[t]) do if has(n) then some = some + 1 end end
      local mark = has(t) and "[x] " or (some > 0 and "[~] " or "[ ] ")
      local function toggle()
        if has(t) then remove(t)
        else
          for _, n in ipairs(byType[t]) do remove(n) end
          list[#list + 1] = t
        end
      end
      rows[#rows + 1] = { text = mark .. t, value = #byType[t] .. " blocks",
        color = has(t) and colors.lime or (some > 0 and colors.yellow or nil),
        enter = function() typePage(t) end, left = toggle, right = toggle }
    end
    -- entries that aren't on the network now: kept, shown so they can be removed
    for _, v in ipairs(list) do
      if not byType[v] and not types[v] then
        rows[#rows + 1] = { text = "[x] " .. v, value = "offline", color = colors.orange,
          enter = function() remove(v) end }
      end
    end
    if #rows == 0 then rows[1] = { text = "nothing of this kind on the network" } end
    return rows
  end, "Enter blocks  <> whole type  Bksp back")
end

-- One peripheral (or none = found automatically).
function M.pickOne(title, t, k, kind, noneText)
  local names = candidates(kind)
  M.page(title, function()
    local rows = { { text = (t[k] == nil and "(*) " or "( ) ") .. (noneText or "auto"),
      enter = function() t[k] = nil return "back" end } }
    for _, n in ipairs(names) do
      rows[#rows + 1] = { text = (t[k] == n and "(*) " or "( ) ") .. n, color = t[k] == n and colors.lime or nil,
        enter = function() t[k] = n return "back" end }
    end
    return rows
  end, "Enter choose  Bksp back")
end

-- ---------------------------------------------------------------- items

-- Item ids the player may mean: known names and recipe outputs.
local function knownItems()
  local set = {}
  for k in pairs(util.readJSON("data/names.json") or {}) do set[k] = true end
  for _, r in ipairs(util.readJSON("data/recipes.json") or {}) do
    for _, o in ipairs(r.outputs or {}) do
      if type(o.key) == "string" and o.key:sub(1, 1) ~= "~" then set[o.key] = true end
    end
  end
  local list = {}
  for k in pairs(set) do list[#list + 1] = k end
  table.sort(list)
  return list
end

local function pickItem(title)
  local q = M.ask("Search item: ")
  if not q then return nil end
  q = q:lower()
  local found = {}
  for _, k in ipairs(knownItems()) do
    if k:lower():find(q, 1, true) then found[#found + 1] = k end
  end
  if #found == 0 and q:find(":") then return q end
  local chosen
  M.page(title .. " (" .. #found .. ")", function()
    local rows = {}
    for _, k in ipairs(found) do
      rows[#rows + 1] = { text = k, enter = function() chosen = k return "back" end }
    end
    if #rows == 0 then rows[1] = { text = "nothing found, type the full id (mod:item)" } end
    return rows
  end, "Enter choose  Bksp back")
  return chosen
end

-- ---------------------------------------------------------------- pages

local function storagePage(c)
  M.page("Settings > Storage & tanks", function()
    return {
      { text = "Storage (items)", value = summary(c.storage), enter = function()
        c.storage = c.storage or {}; M.pickMany("Storage", c.storage, "items") end },
      { text = "Tanks", value = summary(c.tanks), enter = function()
        c.tanks = c.tanks or {}; M.pickMany("Tanks", c.tanks, "tanks") end },
      { text = "Craft storage (items)", value = summary(c.craft_storage), enter = function()
        c.craft_storage = c.craft_storage or {}; M.pickMany("Craft storage", c.craft_storage, "items") end },
      { text = "Craft tanks", value = summary(c.craft_tanks), enter = function()
        c.craft_tanks = c.craft_tanks or {}; M.pickMany("Craft tanks", c.craft_tanks, "tanks") end },
      { text = "Exclude", value = summary(c.exclude), enter = function()
        c.exclude = c.exclude or {}; M.pickMany("Exclude", c.exclude, "any") end },
      { text = "Encoder barrel", value = c.encoder or "auto", enter = function()
        M.pickOne("Encoder barrel", c, "encoder", "items") end },
      { text = "Recipe tanks", value = summary(c.recipe_tanks), enter = function()
        c.recipe_tanks = c.recipe_tanks or {}; M.pickMany("Recipe tanks", c.recipe_tanks, "tanks") end },
    }
  end)
end

local function restockPage(c)
  c.restock = c.restock or {}
  M.page("Settings > Crafting > Restock", function()
    local keysList = {}
    for k in pairs(c.restock) do keysList[#keysList + 1] = k end
    table.sort(keysList)
    local rows = { { text = "+ Add item", color = colors.lime, enter = function()
      local k = pickItem("Restock: item")
      if k then c.restock[k] = tonumber(M.ask("Keep in storage: ", 64)) or 64 end
    end } }
    for _, k in ipairs(keysList) do
      local function add(d) return function() c.restock[k] = math.max(1, c.restock[k] + d) end end
      rows[#rows + 1] = { text = k, value = c.restock[k], left = add(-16), right = add(16), enter = function()
        local n = tonumber(M.ask(k .. " (0 = remove): ", c.restock[k]))
        if n then c.restock[k] = n > 0 and n or nil end
      end }
    end
    return rows
  end, "Enter edit  <> -/+16  Bksp back")
end

local function craftPage(c)
  M.page("Settings > Crafting", function()
    local n = 0
    for _ in pairs(c.restock or {}) do n = n + 1 end
    return {
      numRow("Batch (runs fed at once)", c, "batch", 1, 1),
      numRow("Craft timeout, s", c, "craft_timeout", 10, 10),
      numRow("Stall timeout, s", c, "stall_timeout", 30, 30, true, "3 x craft timeout"),
      numRow("Rescan storage, s", c, "rescan", 5, 1),
      numRow("Restock check, s", c, "restock_interval", 10, 5),
      { text = "Restock items", value = n .. " items", enter = function() restockPage(c) end },
    }
  end)
end

local function poolPage(c, name)
  M.page("Pools > " .. name, function()
    local members = c.pools[name]
    local rows = {
      { text = "Members", value = summary(members), enter = function() M.pickMany("Pool " .. name, members, "any") end },
      { text = "Delete pool", color = colors.red, enter = function() c.pools[name] = nil return "back" end },
    }
    for _, m in ipairs(members) do rows[#rows + 1] = { text = "  " .. m, color = colors.gray } end
    return rows
  end)
end

local FIELDS = {
  { "input_item", "Input items (bus)", "items" },
  { "output_item", "Output items (bus)", "items" },
  { "input_fluid", "Input fluids (hatch)", "tanks" },
  { "output_fluid", "Output fluids (hatch)", "tanks" },
}

local function multiblockPage(mbs, name)
  M.page("Multiblocks > " .. name, function()
    local mb = mbs[name]
    if not mb then return { { text = "deleted" } } end
    local rows = {}
    for _, f in ipairs(FIELDS) do
      rows[#rows + 1] = { text = f[2], value = mb[f[1]] or "none", enter = function()
        M.pickOne(name .. ": " .. f[2], mb, f[1], f[3], "none") end }
    end
    rows[#rows + 1] = { text = "Extra inputs (deployer...)", value = summary(mb.inputs), enter = function()
      mb.inputs = mb.inputs or {}
      M.page(name .. ": inputs in grid-row order", function()
        local r = { { text = "+ Add input", color = colors.lime, enter = function()
          local t = {}
          M.pickOne("Add input", t, "v", "items", "cancel")
          if t.v then mb.inputs[#mb.inputs + 1] = t.v end
        end } }
        for i, v in ipairs(mb.inputs) do
          r[#r + 1] = { text = ("row %d: %s"):format(i, v), value = "Enter removes",
            enter = function() table.remove(mb.inputs, i) end }
        end
        return r
      end)
      if #mb.inputs == 0 then mb.inputs = nil end
    end }
    rows[#rows + 1] = numRow("Batch (runs fed ahead)", mb, "batch", 1, 1, true, "config batch")
    rows[#rows + 1] = { text = "Delete multiblock", color = colors.red, enter = function() mbs[name] = nil return "back" end }
    return rows
  end)
end

local function machinesPage(c, mbs)
  M.page("Settings > Machines", function()
    return {
      { text = "Pools", value = (function() local n = 0 for _ in pairs(c.pools or {}) do n = n + 1 end return n end)(),
        enter = function()
          c.pools = c.pools or {}
          M.page("Settings > Machines > Pools", function()
            local rows = { { text = "+ New pool", color = colors.lime, enter = function()
              local n = M.ask("Pool name: ")
              if n then c.pools[n] = c.pools[n] or {}; poolPage(c, n) end
            end } }
            local names = {}
            for n in pairs(c.pools) do names[#names + 1] = n end
            table.sort(names)
            for _, n in ipairs(names) do
              rows[#rows + 1] = { text = n, value = #c.pools[n] .. " machines", enter = function() poolPage(c, n) end }
            end
            return rows
          end)
        end },
      { text = "Multiblocks (GT, Create lines)", value = (function() local n = 0 for _ in pairs(mbs) do n = n + 1 end return n end)(),
        enter = function()
          M.page("Settings > Machines > Multiblocks", function()
            local rows = { { text = "+ New multiblock", color = colors.lime, enter = function()
              local n = M.ask("Multiblock name: ")
              if n then mbs[n] = mbs[n] or {}; multiblockPage(mbs, n) end
            end } }
            local names = {}
            for n in pairs(mbs) do names[#names + 1] = n end
            table.sort(names)
            for _, n in ipairs(names) do
              rows[#rows + 1] = { text = n, value = mbs[n].input_item or (mbs[n].inputs and mbs[n].inputs[1]) or "no input",
                enter = function() multiblockPage(mbs, n) end }
            end
            return rows
          end)
        end },
      { text = "Main monitor", value = c.main_monitor or "auto", enter = function()
        M.pickOne("Main monitor", c, "main_monitor", "monitor") end },
      { text = "Fluid monitor", value = c.fluid_monitor or "auto", enter = function()
        M.pickOne("Fluid monitor", c, "fluid_monitor", "monitor") end },
      numRow("Main monitor text scale", c, "main_TextScale", 0.5, 0.5),
      numRow("Fluid monitor text scale", c, "fluid_TextScale", 0.5, 0.5),
    }
  end)
end

local function modsPage(c, modNames)
  c.mods_disabled = c.mods_disabled or {}
  M.page("Settings > Mods", function()
    local rows = {}
    for _, name in ipairs(modNames) do
      local function flip()
        local i = indexOf(c.mods_disabled, name)
        if i then table.remove(c.mods_disabled, i) else c.mods_disabled[#c.mods_disabled + 1] = name end
      end
      local on = not indexOf(c.mods_disabled, name)
      rows[#rows + 1] = { text = "Mod " .. name, value = on and "on" or "off", color = on and colors.lime or colors.red,
        enter = flip, left = flip, right = flip }
    end
    rows[#rows + 1] = boolRow("GregTech: higher tiers take LV recipes", c, "gtceu_tier_up", true)
    rows[#rows + 1] = boolRow("Clipboard: skip checked lines", c, "clipboard_skip_checked", true)
    rows[#rows + 1] = boolRow("Debug log", c, "debug_mode", false)
    return rows
  end)
end

-- Keys whose change needs a restart (read once at start).
M.RESTART = { "main_monitor", "fluid_monitor", "main_TextScale", "fluid_TextScale", "rednet_modem",
  "mods_disabled", "gtceu_tier_up", "debug_mode", "encoder", "recipe_tanks" }

-- The menu. opts.cfg: the live config (edited on a copy), opts.mods: mod names.
-- Returns "saved" (config.lua and multiblock.json written, opts.cfg updated in place),
-- needs restart (bool) — or nil when nothing was saved.
function M.run(opts)
  local live = opts.cfg
  local c = deepCopy(live)
  local mbs = util.readJSON("data/multiblock.json") or {}
  local mbsBefore = deepCopy(mbs)
  local result
  -- Theme: Left/Right (or Enter) switch it, the screens repaint at once as a preview
  local function cycle(d)
    return function()
      local list = theme.list()
      local i = indexOf(list, c.theme or "default") or 1
      c.theme = list[(i - 1 + d) % #list + 1]
      theme.applyScreens(c.theme)
    end
  end
  M.page("Settings", function()
    return {
      { text = "Theme", value = "< " .. (c.theme or "default") .. " >", color = colors.yellow,
        enter = cycle(1), left = cycle(-1), right = cycle(1) },
      { text = "Storage & tanks", enter = function() storagePage(c) end },
      { text = "Crafting", enter = function() craftPage(c) end },
      { text = "Machines", enter = function() machinesPage(c, mbs) end },
      { text = "Mods", enter = function() modsPage(c, opts.mods or {}) end },
      { text = "Save and exit", color = colors.lime, enter = function() result = "save" return "back" end },
      { text = "Exit without saving", color = colors.red, enter = function() result = "discard" return "back" end },
    }
  end, "Enter open  Bksp leave")
  local changed = not same(c, live) or not same(mbs, mbsBefore)
  if not result and changed then
    local a = M.ask("Save changes? (y/n) ", "y")
    result = (a == "y" or a == "Y" or a == "yes") and "save" or "discard"
  end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  if result ~= "save" or not changed then
    theme.applyScreens(live.theme) -- the preview goes back
    return nil
  end
  if opts.net then theme.sendTurtles(opts.net) end
  local restart = false
  for _, k in ipairs(M.RESTART) do if not same(c[k], live[k]) then restart = true end end
  M.save(c, not same(mbs, mbsBefore) and mbs or nil)
  for k in pairs(live) do live[k] = nil end
  for k, v in pairs(c) do live[k] = v end
  return "saved", restart
end

-- ---------------------------------------------------------------- start menu

-- Main / Settings / Update; Main after `wait` seconds without a key. Returns the choice.
function M.startMenu(wait)
  wait = wait or 10
  local items = { "Main", "Settings", "Update" }
  local cur, left = 1, wait
  local timer = os.startTimer(1)
  while true do
    local w = size()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    term.write("CC-Autocraft")
    for i, it in ipairs(items) do
      term.setCursorPos(1, 2 + i)
      term.setBackgroundColor(i == cur and colors.gray or colors.black)
      term.setTextColor(i == cur and colors.white or colors.lightGray)
      local text = (i == cur and "> " or "  ") .. it
      term.write(text .. (" "):rep(w - #text))
    end
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 7)
    term.setTextColor(colors.gray)
    term.write(("Main in %ds. Up/Down, Enter"):format(left))
    local e, k = os.pullEvent()
    if e == "timer" and k == timer then
      left = left - 1
      if left <= 0 then break end
      timer = os.startTimer(1)
    elseif e == "key" then
      left = wait
      if k == keys.up then cur = cur > 1 and cur - 1 or #items
      elseif k == keys.down then cur = cur < #items and cur + 1 or 1
      elseif k == keys.enter then
        term.clear(); term.setCursorPos(1, 1)
        return items[cur]
      end
    end
  end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  return "Main"
end

return M

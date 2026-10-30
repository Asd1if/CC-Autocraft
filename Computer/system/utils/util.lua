-- Small helpers: JSON files, names, counts, peripheral lookup, config.
local util = {}

function util.readJSON(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local data = textutils.unserialiseJSON(h.readAll())
  h.close()
  return data
end

function util.writeJSON(path, data)
  local h = fs.open(path, "w")
  h.write(textutils.serialiseJSON(data))
  h.close()
end

-- "create:item_vault_3" -> mod "create", machine "item_vault", id 3
function util.parsePeripheralName(name)
  local mod, rest = name:match("^([^:]+):(.+)$")
  if not mod then return nil end
  local machine, id = rest:match("^(.-)_(%d+)$")
  return mod, machine or rest, tonumber(id)
end

function util.stripMod(id)
  return (id:gsub("^[^:]+:", ""))
end

function util.getMod(id)
  return id:match("^([^:]+):") or "minecraft"
end

-- "create:andesite_alloy" -> "Andesite alloy"
function util.formatName(id)
  local name = util.stripMod(id):gsub("[_/]", " ")
  return (name:gsub("^%l", string.upper))
end

-- 999, 1.2k, 12.4k, 150k, 3.3m: rounded down, so it never shows more than there is.
local function short(v, unit)
  if v >= 100 then return math.floor(v) .. unit end
  local s = ("%.1f"):format(math.floor(v * 10) / 10):gsub("%.0$", "")
  return s .. unit
end

function util.formatCount(n)
  if n < 1000 then return tostring(n) end
  if n < 1000000 then return short(n / 1000, "k") end
  if n < 1000000000 then return short(n / 1000000, "m") end
  return short(n / 1000000000, "g")
end

-- Fluids in mB: 500mB, 1.5B, 24B, 2.4kB, 1.2MB.
function util.formatFluid(mb)
  if mb < 1000 then return mb .. "mB" end
  local b = mb / 1000
  if b < 1000 then return short(b, "B") end
  if b < 1000000 then return short(b / 1000, "kB") end
  return short(b / 1000000, "MB")
end

function util.set(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

-- Peripherals matching entries of `specs` (a type like "create:item_vault" or an exact name),
-- minus anything in the `exclude` set. Sorted by name.
function util.findPeripherals(specs, exclude)
  exclude = exclude or {}
  local want = util.set(specs)
  local out = {}
  for _, name in ipairs(peripheral.getNames()) do
    if not exclude[name] then
      local match = want[name]
      if not match then
        for _, t in ipairs({ peripheral.getType(name) }) do
          if want[t] then match = true break end
        end
      end
      if match then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

-- Runs functions through parallel.waitForAll in chunks (CC limits how much runs at once).
function util.parallelBatches(fns, size)
  size = size or 32
  for i = 1, #fns, size do
    parallel.waitForAll(table.unpack(fns, i, math.min(#fns, i + size - 1)))
  end
end

function util.copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- First start (and the first start after an update from the old layout):
--   system/default/config.lua -> config.lua (an old data/config.lua is moved there instead),
--   system/default/multiblock.json -> data/multiblock.json, an empty mods/ folder.
-- Existing files are never overwritten: the installer replaces system/, never these.
function util.firstStart()
  for _, dir in ipairs({ "data", "mods" }) do
    if not fs.exists(dir) then fs.makeDir(dir) end
  end
  if not fs.exists("config.lua") then
    if fs.exists("data/config.lua") then fs.move("data/config.lua", "config.lua")
    elseif fs.exists("system/default/config.lua") then fs.copy("system/default/config.lua", "config.lua") end
  end
  if not fs.exists("data/multiblock.json") and fs.exists("system/default/multiblock.json") then
    fs.copy("system/default/multiblock.json", "data/multiblock.json")
  end
end

-- config.lua (a commented Lua table); an old data/config.json is still read if there's none.
local function readLuaConfig(path)
  if not fs.exists(path) then return nil end
  local fn, err = loadfile(path, "t", {})
  if not fn then error(path .. ": " .. tostring(err), 0) end
  return fn()
end

-- Old key names (and common misspellings) still read: new name <- old names.
local RENAMED = {
  main_monitor = { "monitor" },
  fluid_monitor = { "encoder_monitor", "flued_monitor" },
  main_TextScale = { "text_scale" },
  rednet_modem = { "modem" },
  debug_mode = { "debug", "dedug_mode" },
}

-- config.lua; keys it lacks come from system/default/config.lua (new keys after an update),
-- then from `defaults`.
function util.loadConfig(defaults)
  local cfg = readLuaConfig("config.lua") or readLuaConfig("data/config.lua") or util.readJSON("data/config.json") or {}
  for new, olds in pairs(RENAMED) do
    for _, old in ipairs(olds) do
      if cfg[new] == nil and cfg[old] ~= nil then cfg[new] = cfg[old] end
    end
  end
  local shipped = readLuaConfig("system/default/config.lua") or {}
  for _, layer in ipairs({ shipped, defaults or {} }) do
    for k, v in pairs(layer) do
      if cfg[k] == nil then cfg[k] = v end
    end
  end
  return cfg
end

return util

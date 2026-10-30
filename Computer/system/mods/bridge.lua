-- Mod: AE2 / Refined Storage as storage, through an Advanced Peripherals ME Bridge or RS Bridge
-- (AP 0.8 / 1.21.1 API, shared by both bridges; 0.7 names are tried as a fallback).
--
-- Every bridge on the wired network becomes part of the main storage: its items and fluids show
-- in the stock list and count for crafting, orders take from it and put results into it. The
-- bridge moves items straight to/from any peripheral on the network (turtles, machines, the
-- craft storage), so it can stand anywhere on the cable.
-- config.lua: exclude = { "me_bridge_0" } leaves one out, mods_disabled = { "bridge" } all.
--
-- Items with data components (damaged tools, filled containers) are told apart by the bridge's
-- fingerprint: "name#<fingerprint>". They don't merge with the same item lying in a vault,
-- whose CC hash differs, so keep such items in one kind of storage.
local M = { name = "bridge", description = "AE2 / Refined Storage through ME / RS Bridge" }

M.TYPES = { me_bridge = true, meBridge = true, rs_bridge = true, rsBridge = true }

-- The bridge's answer as an amount: AP returns a number, newer versions a table.
local function amount(res)
  if type(res) == "number" then return res end
  if type(res) == "table" then return tonumber(res.count or res.amount or res.transferred or res[1]) or 0 end
  return 0
end

local function call(p, names, ...)
  for _, n in ipairs(names) do
    if p[n] then return p[n](...) end
  end
  error("bridge has none of " .. table.concat(names, "/"), 0)
end

local function hasData(it)
  return type(it.components) == "table" and next(it.components) ~= nil or (it.nbt and it.nbt ~= "")
end

-- One storage backend (see system/core/indexer.lua) for a bridge peripheral.
function M.backend(name)
  local p = peripheral.wrap(name)
  local b = { name = name }

  -- filter for one item kind: by fingerprint when it carries data, else by name only
  local function filter(itemName, fp, count, extra)
    local f = fp and { fingerprint = fp } or { name = itemName }
    f.count = count
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end

  function b.scan()
    if p.isOnline and p.isOnline() == false then error("network offline", 0) end
    local items, fluids = {}, {}
    for _, it in ipairs(call(p, { "getItems", "listItems" }, {}) or {}) do
      local n = tonumber(it.count or it.amount) or 0
      if n > 0 then
        items[#items + 1] = { name = it.name, count = n, displayName = it.displayName,
          nbt = hasData(it) and it.fingerprint or nil }
      end
    end
    local ok, list = pcall(call, p, { "getFluids", "listFluids", "listFluid" }, {})
    for _, f in ipairs(ok and list or {}) do
      local n = tonumber(f.count or f.amount) or 0
      if n > 0 then fluids[#fluids + 1] = { name = f.name, amount = n } end
    end
    return items, fluids
  end

  function b.extract(itemName, fp, n, to, toSlot)
    local f = filter(itemName, fp, n, toSlot and { toSlot = toSlot } or nil)
    if p.exportItem then return amount(p.exportItem(f, to)) end
    return amount(p.exportItemToPeripheral(f, to))
  end

  function b.insert(from, slot, n, itemName)
    local f = filter(itemName, nil, n, { fromSlot = slot })
    if p.importItem then return amount(p.importItem(f, from)) end
    return amount(p.importItemFromPeripheral(f, from))
  end

  function b.extractFluid(fluid, n, to)
    if not p.exportFluid then return 0 end
    return amount(p.exportFluid({ name = fluid, count = n }, to))
  end

  function b.insertFluid(from, fluid, n)
    if not p.importFluid then return 0 end
    return amount(p.importFluid({ name = fluid, count = n }, from))
  end

  return b
end

function M.init(api)
  api.on("storage.backends", function(list, _, exclude)
    for _, name in ipairs(peripheral.getNames()) do
      if not (exclude or {})[name] then
        for _, t in ipairs({ peripheral.getType(name) }) do
          if M.TYPES[t] then list[#list + 1] = M.backend(name) break end
        end
      end
    end
    return list
  end)
end

return M

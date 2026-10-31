-- Mod: GregTech CEu Modern.
--
-- Chip ID: a programmed circuit lying in a machine's input bus/inventory is part of the
-- machine's setup. A recipe remembers the circuit of the machine it was tested on (r.chip = the
-- circuit's NBT hash, false = none), and every machine of the same kind with the same circuit
-- runs it too: they form a pool on their own, the runs are split between the free ones.
-- The circuit always stays in the machine (autocraft never takes it out with the results).
--
-- Tier: "gtceu:lv_electric_furnace_0" is an LV electric furnace. A recipe tested on LV may run
-- on MV, HV... machines of the same kind and circuit (config.lua: gtceu_tier_up = false keeps
-- it on the tier it was tested on). The tested machine comes first, then the lowest tiers.
--
-- The ADD menu shows tier and circuit next to each machine: "[ID-3] LV c5".
local util = require("system.utils.util")

local M = { name = "gtceu", description = "GregTech circuits and tiers" }

local CIRCUIT = "gtceu:programmed_circuit"

M.TIERS = { ulv = 0, lv = 1, mv = 2, hv = 3, ev = 4, iv = 5, luv = 6, zpm = 7, uv = 8, uhv = 9,
  uev = 10, uiv = 11, uxv = 12, opv = 13, max = 14 }

-- Circuit NBT hash -> its number (the hashes CC shows for programmed circuits 0..32).
-- config.lua: gtceu_chips = { ["<hash>"] = n } adds or overrides entries.
M.CHIPS = {
  ["ad0ac2cdf646644c3b06f2de1fc6894c"] = 0,
  ["2f0eaa46331854247963f193b385a9c3"] = 1,
  ["d3efb6f62c113da0c42048aef4b8b803"] = 2,
  ["d009a22f06bca83db0e373efe68f9586"] = 3,
  ["236a18a75613e813a837d0859ce44b3b"] = 4,
  ["99c6a0cf861be9bb86943299ab26fc5f"] = 5,
  ["e61d93226ec25a873381f6f65e52ec9b"] = 6,
  ["7df1801d048aa41b14814337494c946b"] = 7,
  ["65426174b28f3e9d1f64b7a547888acb"] = 8,
  ["d42b93031932ce30d8b116972e10812f"] = 9,
  ["d8cbf08b757e6b2e5027c642247d51ec"] = 10,
  ["eaa5be8a9d484ac8a36da658334d4cfb"] = 11,
  ["c9c82b8d11af99dcb0a7d9ad7a8da0ed"] = 12,
  ["89b6aaaabb18fdd0e5ac7cfb8c93d2ca"] = 13,
  ["3db3679106deff3bc2e02d7d5e6125dd"] = 14,
  ["951843314b12691272f22292c383da8d"] = 15,
  ["14b3c9139de19e3f856911e995aff0a9"] = 16,
  ["29895118229ea3c8df99d6aabf74d570"] = 17,
  ["b10d3805ba6791b0aa99a6fae7083aa3"] = 18,
  ["3a2f9ebca473a5a8c32319deade7eb3d"] = 19,
  ["984bace4fb3f692fb7802730a5c41248"] = 20,
  ["d1299bcd8a5a1bb553b89a5d60bc9b65"] = 21,
  ["ff019e29f1ab51f7df186a99e253362f"] = 22,
  ["50c2930699283adf303af32e1c14484a"] = 23,
  ["f6473b086addbf86f9fa168e19d8175b"] = 24,
  ["778c250e092f05ad7156a63ca4d4c1fd"] = 25,
  ["e5de432e06c3980a30aaf4b18d798b83"] = 26,
  ["08d59c85b4dae474c1d57a10270f8cad"] = 27,
  ["3da0d9033424a9da70807f3c1c92ddd3"] = 28,
  ["71924d5e0069766bd45ef30bfa12575d"] = 29,
  ["a606bab3d2ff05588b7776636132ba56"] = 30,
  ["f8ee067ae43b21713f9445253dc50ea0"] = 31,
  ["b42bf02e2466cdfbaec693eec0adbc78"] = 32,
}

-- "gtceu:lv_electric_furnace_3" -> "electric_furnace", 1. A GregTech block without a tier:
-- its name, nil. Not GregTech: nil.
function M.parse(name)
  local mod, machine = util.parsePeripheralName(name)
  if mod ~= "gtceu" then return nil end
  local t, base = machine:match("^(%a+)_(.+)$")
  if t and M.TIERS[t] then return base, M.TIERS[t] end
  return machine, nil
end

-- The circuit in a machine: its NBT hash, or false. Read at most every few seconds per machine
-- (the scheduler asks often while a step waits for a free machine).
local cache = {}
function M.chip(name, fresh)
  local c = cache[name]
  if c and not fresh and os.clock() - c.at < 5 then return c.chip end
  local chip = false
  local ok, list = pcall(peripheral.call, name, "list")
  for _, it in pairs(ok and list or {}) do
    if it.name == CIRCUIT then chip = it.nbt or "" break end
  end
  cache[name] = { chip = chip, at = os.clock() }
  return chip
end

-- Reads the circuits of many machines at once (one list() per machine takes a tick; one
-- after another they lag with dozens of machines). Entries are names or { name = }.
function M.prefetch(list, fresh)
  local fns = {}
  for _, e in ipairs(list) do
    local name = type(e) == "table" and e.name or e
    local c = cache[name]
    if fresh or not c or os.clock() - c.at >= 5 then
      fns[#fns + 1] = function() M.chip(name, true) end
    end
  end
  util.parallelBatches(fns, 32)
end

-- "c5" for circuit 5, "c?1a2b" for an unknown hash, "" for none.
function M.chipLabel(chip)
  if not chip then return "" end
  local n = M.CHIPS[chip]
  return n and ("c" .. n) or ("c?" .. chip:sub(1, 4))
end

-- Machines that can run recipe r, the tested one first, then by tier and name. nil: not ours.
function M.workers(r, names, tierUp)
  local base, tier = M.parse(r.machine)
  if not base then return nil end
  local chip = r.chip
  if chip == nil then chip = M.chip(r.machine) end -- recipe saved before this mod
  local cand = {}
  for _, name in ipairs(names) do
    local b, t = M.parse(name)
    local tierOk = (t == tier) or (tierUp and t and tier and t > tier)
    if b == base and tierOk then cand[#cand + 1] = { name = name, tier = t or 0 } end
  end
  M.prefetch(cand)
  local out = {}
  for _, w in ipairs(cand) do
    if M.chip(w.name) == chip then out[#out + 1] = w end
  end
  table.sort(out, function(a, b)
    if (a.name == r.machine) ~= (b.name == r.machine) then return a.name == r.machine end
    if a.tier ~= b.tier then return a.tier < b.tier end
    return a.name < b.name
  end)
  local list = {}
  for _, w in ipairs(out) do list[#list + 1] = w.name end
  return #list > 0 and list or nil
end

local function tierName(t)
  for k, v in pairs(M.TIERS) do if v == t then return k:upper() end end
  return ""
end

function M.init(api)
  for hash, n in pairs(api.cfg.gtceu_chips or {}) do M.CHIPS[hash] = n end

  api.on("machine.keep", function(_, item) return item.name == CIRCUIT end)

  api.on("recipe.encode", function(draft)
    if draft.type == "machine" and draft.machine and M.parse(draft.machine) then
      draft.chip = M.chip(draft.machine, true)
    end
  end)

  api.on("machine.workers", function(list, r)
    local skip = api.storage.exclude or {}
    local names = {}
    for _, n in ipairs(peripheral.getNames()) do
      if not skip[n] then names[#names + 1] = n end
    end
    return M.workers(r, names, api.cfg.gtceu_tier_up ~= false)
  end)

  api.on("machine.label", function(text, name)
    local base, tier = M.parse(name)
    if not base then return nil end
    local parts = {}
    if tier then parts[#parts + 1] = tierName(tier) end
    local chip = M.chipLabel(M.chip(name))
    if chip ~= "" then parts[#parts + 1] = chip end
    return table.concat(parts, " ")
  end)

  api.on("peripherals", function() cache = {} end)

  -- the ADD menu asks for many labels at once: read their circuits in parallel first
  api.on("machine.labels", function(names) M.prefetch(names, true) end)
end

return M

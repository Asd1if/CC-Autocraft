-- Recipe store (data/recipes.json).
--
-- recipe = {
--   id, type = "turtle" | "machine" | "multiblock",
--   machine  = peripheral name (machine) or multiblock.json key (multiblock), nil for turtle,
--   grid     = { [1..9] = { key, count, maxCount, tool = true|nil, cost, maxDamage } or {} }   -- turtle only, positions kept
--   inputs   = { { key, count } }   -- per one run; fluid keys "~name" in mB
--   tools    = { { key, cost, maxDamage } }   -- turtle only: stays in the grid and only loses
--              durability, `cost` points per run; key "name#*" (any damage). Old saves: plain keys
--   outputs  = { { key, count, main = true|nil, maxCount } }   -- byproducts are planned too;
--              maxCount is the stack size seen in the test (1 = unstackable, crafted one by one)
--   priority = 1 (lower = tried first), time = seconds measured in the test
-- }
local util = require("modules.util")
local log  = require("modules.log")

local M = { list = {}, byOutput = {}, path = "data/recipes.json", backup = "data/recipes.json.bak" }

local function reindex()
  M.byOutput = {}
  for _, r in ipairs(M.list) do
    for _, o in ipairs(r.outputs) do
      local t = M.byOutput[o.key] or {}
      t[#t + 1] = r
      M.byOutput[o.key] = t
    end
  end
  -- main-output recipes first, then by priority
  for key, t in pairs(M.byOutput) do
    table.sort(t, function(a, b)
      local am, bm = M.mainKey(a) == key, M.mainKey(b) == key
      if am ~= bm then return am end
      return (a.priority or 1) < (b.priority or 1)
    end)
  end
end

function M.load()
  M.list = util.readJSON(M.path)
  if not M.list and fs.exists(M.backup) then
    -- recipes.json was deleted or overwritten: take the copy from the previous save
    log.warn("%s missing, loading %s", M.path, M.backup)
    M.list = util.readJSON(M.backup)
  end
  M.list = M.list or {}
  -- JSON turns empty grid slots into empty tables/arrays; normalise
  for _, r in ipairs(M.list) do
    if r.grid then
      for i = 1, 9 do
        if type(r.grid[i]) ~= "table" or not r.grid[i].key then r.grid[i] = {} end
      end
    end
  end
  reindex()
end

-- The previous file is kept as recipes.json.bak.
function M.save()
  if fs.exists(M.path) then
    if fs.exists(M.backup) then fs.delete(M.backup) end
    fs.copy(M.path, M.backup)
  end
  util.writeJSON(M.path, M.list)
end

function M.mainKey(r)
  for _, o in ipairs(r.outputs) do if o.main then return o.key end end
  return r.outputs[1] and r.outputs[1].key
end

-- How many `key` one run of r produces.
function M.yield(r, key)
  local n = 0
  for _, o in ipairs(r.outputs) do if o.key == key or o.key .. "#*" == key then n = n + o.count end end
  return n
end

function M.forOutput(key)
  local name, any = key:match("^(.+)#(%*)$")
  if any then return M.byOutput[name] or {} end
  return M.byOutput[key] or {}
end

-- Runs per turtle.craft call: limited by cap, by how many fit into a grid slot and by the
-- results' stack size (unstackable results go one by one, the rest would drop on the ground).
-- Outputs with unknown maxCount (recipes saved before it was recorded) count as unstackable.
function M.turtleBatch(r, cap)
  local batch = cap or 16
  for i = 1, 9 do
    local g = r.grid[i]
    if g.key and not g.tool then batch = math.min(batch, math.floor((g.maxCount or 64) / g.count)) end
  end
  for _, o in ipairs(r.outputs) do
    batch = math.min(batch, math.floor((o.maxCount or 1) / o.count))
  end
  return math.max(1, batch)
end

function M.hasRecipe(key)
  return M.byOutput[key] ~= nil
end

function M.add(r)
  local main = M.mainKey(r)
  local nextId = 1
  for _, x in ipairs(M.list) do nextId = math.max(nextId, (x.id or 0) + 1) end
  r.id = nextId
  r.priority = r.priority or (#M.forOutput(main) + 1)
  M.list[#M.list + 1] = r
  reindex()
  M.save()
  return r
end

function M.remove(id)
  for i, r in ipairs(M.list) do
    if r.id == id then table.remove(M.list, i) break end
  end
  reindex()
  M.save()
end

return M

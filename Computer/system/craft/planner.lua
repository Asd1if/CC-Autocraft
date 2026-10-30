-- Recursive craft planner. Pure logic: no peripherals, so it can be tested offline.
--
-- plan(target, qty, avail, recipes, points) -> {
--   ok, root = node, steps = { step... } (children before parents), missing = { key = n } }
-- node = { key, need, stock, virtual, missing, craft = { recipe, runs, step } | nil, children,
--   unpack = true (crafted by taking a block apart), mixed = true (children are parts) }
-- step = { id, key, recipe, runs, deps = { step... } }
-- target = an item key, or a list { title, items = { { key, count } } } (a clipboard): then the
-- root is a group node (group = true, label = title) with one child per item x qty.
--
-- Rules: take from stock first, then from leftovers/byproducts of earlier steps ("virtual"),
-- then craft. The ordered item itself (each item of a list) is always crafted when it has a
-- recipe: an order means "make this", storage stock of it is left alone. Fluids and items
-- without a recipe are still taken from stock. Recipes are tried by priority; the first one that fully succeeds wins.
-- If none succeeds alone, recipes are combined: each makes as much as storage allows, the next
-- one the rest (5 ingots in stock, 1 iron block, raw iron for the rest). Such a node is `mixed`,
-- its children are one part per recipe. Still short: the highest-priority recipe is kept so the
-- tree shows what's missing (red).
-- A recipe that takes a compacted block apart (iron block -> 9 ingots, the reverse of a recipe
-- that packs them) marks its node `unpack`, the tree shows it.
-- Cycles (ingot <-> block) are cut: an item can't be crafted from itself further down.
-- Tools (recipe.tools = { { key, cost, maxDamage } }) aren't used up, they lose durability:
-- each run costs `cost` points. points(key) lists the durability left in each tool in storage,
-- most first; tools are taken until the plan's runs are covered, and missing points become new
-- tools to craft (maxDamage each). A tool with unknown durability is needed once per plan.
local M = {}

-- Expansions a plan may spend combining recipes (each try plans a subtree).
M.MIX_BUDGET = 400

function M.plan(target, qty, avail, recipes, points)
  local stock, virtual, steps, journal, spare = {}, {}, {}, {}, {}
  local budget = M.MIX_BUDGET

  local function get(k)
    if stock[k] == nil then stock[k] = math.max(0, avail(k) or 0) end
    return stock[k]
  end
  local function setStock(k, v)
    local old = get(k)
    journal[#journal + 1] = function() stock[k] = old end
    stock[k] = v
  end
  local function addVirtual(k, step, amount)
    local list = virtual[k] or {}
    virtual[k] = list
    local e = { step = step, amount = amount }
    list[#list + 1] = e
    journal[#journal + 1] = function() table.remove(list) end
  end
  local function setVirtual(e, v)
    local old = e.amount
    journal[#journal + 1] = function() e.amount = old end
    e.amount = v
  end
  local function pushStep(s)
    steps[#steps + 1] = s
    journal[#journal + 1] = function() steps[#steps] = nil end
  end
  local function setSpare(k, v)
    local old = spare[k]
    journal[#journal + 1] = function() spare[k] = old end
    spare[k] = v
  end
  local function mark() return #journal end
  local function rollback(m)
    for i = #journal, m + 1, -1 do journal[i](); journal[i] = nil end
  end

  local need, expand

  local function isUnpack(r)
    return recipes.isUnpack and recipes.isUnpack(r) or nil
  end

  -- q of k from several recipes, each as much as it can (halving the runs until a try plans
  -- without missing items). Returns part nodes, or nil if together they still fall short.
  local function mix(rs, k, q, path, depth)
    local parts = {}
    for _, r in ipairs(rs) do
      local per = recipes.yield(r, k)
      local runs = per > 0 and math.ceil(q / per) or 0
      while q > 0 and runs >= 1 and budget > 0 do
        local amount = math.min(q, runs * per)
        local m = mark()
        local craft, children, missing = expand(r, k, amount, path, depth)
        if missing == 0 then
          parts[#parts + 1] = { key = k, need = amount, stock = 0, virtual = 0, missing = 0,
            craft = craft, children = children, deps = {}, unpack = isUnpack(r) }
          q = q - amount
          runs = math.min(runs, math.ceil(q / per))
        else
          rollback(m)
          runs = math.floor(runs / 2)
        end
      end
      if q == 0 then return parts end
    end
  end

  -- Tool node for `runs` crafts, or nil when tools this plan already holds have enough left.
  local function needTool(t, runs, path, depth)
    local k = t.key
    if not t.maxDamage or t.maxDamage <= 0 then
      if spare[k] then return nil end
      setSpare(k, math.huge)
      return need(k, 1, path, depth)
    end
    local p = (t.cost or 1) * runs
    if spare[k] and p <= spare[k] then setSpare(k, spare[k] - p) return nil end
    p = p - (spare[k] or 0)
    local node = { key = k, need = 0, stock = 0, virtual = 0, missing = 0, children = {}, deps = {} }
    local pts = points and points(k) or {}
    local total, s = math.max(0, avail(k) or 0), get(k)
    while p > 0 and s > 0 do
      p = p - (pts[total - s + 1] or t.maxDamage)
      s = s - 1
      node.stock = node.stock + 1
    end
    setStock(k, s)
    node.need = node.stock
    if p > 0 then
      local n = math.ceil(p / t.maxDamage)
      local c = need(k, n, path, depth)
      node.need = node.need + n
      node.virtual, node.missing, node.craft, node.children, node.deps = c.virtual, c.missing, c.craft, c.children, c.deps
      p = p - n * t.maxDamage
    end
    setSpare(k, -p)
    return node
  end

  expand = function(r, k, q, path, depth)
    budget = budget - 1
    local per = recipes.yield(r, k)
    local runs = math.ceil(q / per)
    local children, missing, deps = {}, 0, {}
    local nodes = {}
    for _, t in ipairs(r.tools or {}) do
      if type(t) == "string" then t = { key = t } end
      local c = needTool(t, runs, path, depth + 1)
      if c then c.tool = true; nodes[#nodes + 1] = c end
    end
    for _, inp in ipairs(r.inputs) do
      local key = recipes.inputKey and recipes.inputKey(r, inp.key) or inp.key
      nodes[#nodes + 1] = need(key, inp.count * runs, path, depth + 1)
    end
    for _, c in ipairs(nodes) do
      children[#children + 1] = c
      missing = missing + c.missing
      if c.craft then deps[#deps + 1] = c.craft.step end
      for _, d in ipairs(c.deps) do deps[#deps + 1] = d end
    end
    local step = { key = k, recipe = r, runs = runs, deps = deps }
    pushStep(step)
    for _, o in ipairs(r.outputs) do
      local amt = o.count * runs
      if recipes.matches and recipes.matches(o.key, k) then amt = math.max(0, amt - q); q = 0
      elseif not recipes.matches and (o.key == k or o.key .. "#*" == k) then amt = amt - q end
      if amt > 0 then addVirtual(o.key, step, amt) end
    end
    return { recipe = r, runs = runs, step = step }, children, missing
  end

  need = function(k, q, path, depth, ordered)
    local node = { key = k, need = q, stock = 0, virtual = 0, missing = 0, children = {}, deps = {} }
    local fresh = ordered and k:sub(1, 1) ~= "~" and #recipes.forOutput(k) > 0

    local s = fresh and 0 or get(k)
    local take = math.min(s, q)
    if take > 0 then setStock(k, s - take); node.stock = take; q = q - take end

    if q > 0 and virtual[k] and not fresh then
      for _, e in ipairs(virtual[k]) do
        if q == 0 then break end
        if e.amount > 0 then
          local t = math.min(e.amount, q)
          setVirtual(e, e.amount - t)
          node.virtual = node.virtual + t
          node.deps[#node.deps + 1] = e.step
          q = q - t
        end
      end
    end
    if q == 0 then return node end

    local rs = recipes.forOutput(k)
    if #rs == 0 or path[k] or depth > 64 then
      node.missing = q
      return node
    end

    path[k] = true
    local craft, children, missing
    for _, r in ipairs(rs) do
      local m = mark()
      craft, children, missing = expand(r, k, q, path, depth)
      if missing == 0 then break end
      rollback(m)
      craft = nil
    end
    if not craft and #rs > 1 then
      local m = mark()
      local parts = mix(rs, k, q, path, depth)
      if parts then
        path[k] = nil
        node.mixed, node.children = true, parts
        for _, p in ipairs(parts) do node.deps[#node.deps + 1] = p.craft.step end
        return node
      end
      rollback(m)
    end
    if not craft then craft, children, missing = expand(rs[1], k, q, path, depth) end
    path[k] = nil

    node.craft, node.children, node.missing = craft, children, missing
    node.unpack = isUnpack(craft.recipe)
    return node
  end

  local root
  if type(target) == "table" then
    root = { key = target.title, label = target.title, group = true, need = #target.items,
      stock = 0, virtual = 0, missing = 0, children = {}, deps = {} }
    for _, it in ipairs(target.items) do
      local c = need(it.key, it.count * qty, {}, 0, true)
      root.children[#root.children + 1] = c
      root.missing = root.missing + c.missing
    end
  else
    root = need(target, qty, {}, 0, true)
  end

  local missingMap = {}
  local function collect(n)
    if n.missing > 0 and not n.craft then missingMap[n.key] = (missingMap[n.key] or 0) + n.missing end
    for _, c in ipairs(n.children) do collect(c) end
  end
  collect(root)

  for i, s in ipairs(steps) do s.id = i end
  return { ok = root.missing == 0, root = root, steps = steps, missing = missingMap, key = target, qty = qty }
end

-- Largest amount that plans without missing items (0 if none). cap limits the search.
function M.maxCraftable(target, avail, recipes, cap, points)
  cap = cap or 4096
  if not M.plan(target, 1, avail, recipes, points).ok then return 0 end
  local lo, hi = 1, 2
  while hi <= cap and M.plan(target, hi, avail, recipes, points).ok do lo, hi = hi, hi * 2 end
  hi = math.min(hi, cap + 1)
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if M.plan(target, mid, avail, recipes, points).ok then lo = mid else hi = mid end
  end
  return lo
end

-- Storage takes per key (what a job must reserve). The ordered items' own stock takes are
-- skipped (the root, or each item of a list): what's in storage doesn't need reserving.
function M.storageTakes(plan)
  local takes = {}
  local function walk(n, isRoot)
    if not isRoot and n.stock > 0 then takes[n.key] = (takes[n.key] or 0) + n.stock end
    for _, c in ipairs(n.children) do walk(c, n.group) end
  end
  walk(plan.root, true)
  return takes
end

return M

-- Mod: Create. Adds the [Clip] button to the main monitor: a Create clipboard as an order list, read with an Advanced Peripherals Block Reader facing a
-- placed clipboard (Material Checklist from the schematicannon, or any clipboard whose lines
-- have item icons).
--
-- getBlockData().components["create:clipboard_content"].pages = { { entry... } }
-- entry = { icon = { id, count }, item_amount, checked = 0|1, text } ; ">>>" lines have no icon.
-- Title: components["minecraft:custom_name"] (JSON text).
--
-- read() -> target = { title, items = { { key, count } }, skipped = n } for planner/executor.
-- config.lua: clipboard_reader (Block Reader name, nil = find), clipboard_skip_checked.
local M = { name = "create", description = "Create clipboard as an order list" }

local TITLES = { ["create.materialChecklist"] = "Material Checklist" }

-- [Clip] reads the clipboard: the whole list becomes the selection (the counter multiplies it).
function M.init(api)
  M.cfg = api.cfg
  api.button({
    label = "[Clip]",
    active = function() return type(api.ui.selected()) == "table" end,
    onTouch = function()
      local list, err = M.read()
      if not list then api.ui.message("Clipboard: " .. tostring(err), colors.red) return end
      api.ui.select(list)
      local note = list.skipped > 0 and (", %d ticked skipped"):format(list.skipped) or ""
      api.ui.message(("%s: %d items%s"):format(list.title, #list.items, note), colors.lime)
    end,
  })
end

function M.find()
  local name = M.cfg and M.cfg.clipboard_reader
  if name then return peripheral.isPresent(name) and name or nil end
  local p = peripheral.find("block_reader") or peripheral.find("blockReader")
  return p and peripheral.getName(p)
end

local function title(json)
  if type(json) ~= "string" then return nil end
  local tr = json:match('"translate"%s*:%s*"([^"]+)"')
  if tr then return TITLES[tr] or tr end
  return json:match('"text"%s*:%s*"([^"]+)"')
end

-- Pure: block data -> target. skipChecked leaves out lines ticked on the clipboard.
function M.parse(data, skipChecked)
  local comps = type(data) == "table" and data.components or {}
  local content = comps["create:clipboard_content"]
  if type(content) ~= "table" or type(content.pages) ~= "table" then return nil, "not a clipboard" end
  local items, index, skipped = {}, {}, 0
  for _, page in ipairs(content.pages) do
    for _, e in ipairs(page) do
      local id = type(e.icon) == "table" and e.icon.id
      local n = tonumber(e.item_amount) or 0
      if id and n > 0 then
        if skipChecked and e.checked == 1 then
          skipped = skipped + 1
        elseif index[id] then
          index[id].count = index[id].count + n
        else
          index[id] = { key = id, count = n }
          items[#items + 1] = index[id]
        end
      end
    end
  end
  if #items == 0 and skipped == 0 then return nil, "no item lines on the clipboard" end
  return { title = title(comps["minecraft:custom_name"]) or "Clipboard", items = items, skipped = skipped }
end

function M.read()
  local name = M.find()
  if not name then return nil, "no block reader" end
  local ok, data = pcall(peripheral.call, name, "getBlockData")
  if not ok then return nil, tostring(data) end
  return M.parse(data, M.cfg.clipboard_skip_checked ~= false)
end

return M

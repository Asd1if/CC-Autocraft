-- Mod loader. Shipped mods live in system/mods/, the player's own in mods/ (the installer never
-- touches that folder); a file in mods/ with the same name replaces the shipped one.
-- config.lua: mods_disabled = { "gtceu" } turns a mod off.
--
-- A mod file returns { name, description, init = function(api) end }. init returning false
-- means "not needed here" (no machines of that mod on the network): the mod stays inactive.
local log     = require("system.utils.log")
local console = require("system.utils.console")
local util    = require("system.utils.util")

local M = { DIRS = { "system/mods", "mods" } }

local function files()
  local byName, order = {}, {}
  for _, dir in ipairs(M.DIRS) do
    if fs.exists(dir) and fs.isDir(dir) then
      local list = fs.list(dir)
      table.sort(list)
      for _, f in ipairs(list) do
        local name = f:match("^(.+)%.lua$")
        if name then
          if not byName[name] then order[#order + 1] = name end
          byName[name] = fs.combine(dir, f)
        end
      end
    end
  end
  return byName, order
end

-- Names of every mod file (shipped and own), enabled or not.
function M.names()
  local _, order = files()
  return order
end

-- Loads and starts every mod. env: the environment mods run in (startup's, so require works).
function M.load(api, env)
  local disabled = util.set(api.cfg.mods_disabled)
  local byName, order = files()
  for _, name in ipairs(order) do
    if disabled[name] then
      log.info("mod %s: disabled in config.lua", name)
    else
      local path = byName[name]
      local ok, mod = pcall(function()
        local fn, err = loadfile(path, "t", env)
        if not fn then error(err, 0) end
        return fn()
      end)
      if not ok or type(mod) ~= "table" then
        console.block("Mod " .. name .. " failed to load", colors.red, { { tostring(ok and "not a table" or mod) } })
      else
        mod.name = mod.name or name
        local started, res = true, nil
        if mod.init then started, res = pcall(mod.init, api) end
        if not started then
          console.block("Mod " .. name .. " failed to start", colors.red, { { tostring(res) } })
        elseif res ~= false then
          api.mods[mod.name] = mod
          log.info("mod %s loaded (%s)", mod.name, path)
        else
          log.info("mod %s: not needed here", mod.name)
        end
      end
    end
  end
end

return M

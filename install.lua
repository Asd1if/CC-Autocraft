-- CC-Autocraft installer / updater. Run on the computer or the turtle:
--   wget run https://raw.githubusercontent.com/Asd1if/CC-Autocraft/main/install.lua
-- Arguments: "computer" or "turtle" to skip the question, and optionally a branch.
-- Downloads Computer/ or Turtle/ from GitHub into the root of this computer. system/ is replaced
-- as a whole; config.lua, data/ (recipes, queue, names) and mods/ (your own mods) are never
-- touched, so running it again is an update. Files of the old layout (main.lua, modules/,
-- defaults/) are removed; the first start moves an old data/config.lua to config.lua.
local REPO = "Asd1if/CC-Autocraft"
local args = { ... }
local kind = args[1]
local branch = args[2] or "main"

local function ask()
  if turtle then
    print("This is a turtle: installing the turtle worker.")
    return "turtle"
  end
  write("Install the storage computer? (y/n) ")
  local a = read():lower()
  if a == "y" or a == "yes" or a == "" then return "computer" end
  return nil
end

kind = kind and kind:lower() or ask()
if kind ~= "computer" and kind ~= "turtle" then
  print("Nothing installed. Usage: install computer | turtle [branch]")
  return
end
local folder = kind == "computer" and "Computer" or "Turtle"

local function get(url)
  local h, err = http.get(url)
  if not h then error("download failed: " .. url .. " (" .. tostring(err) .. ")", 0) end
  local body = h.readAll()
  h.close()
  return body
end

print(("Fetching the file list of %s (%s)..."):format(REPO, branch))
local tree = textutils.unserialiseJSON(get(("https://api.github.com/repos/%s/git/trees/%s?recursive=1"):format(REPO, branch)))
if not tree or not tree.tree then error("unexpected answer from GitHub", 0) end

local files = {}
for _, e in ipairs(tree.tree) do
  if e.type == "blob" and e.path:sub(1, #folder + 1) == folder .. "/" then
    local dest = e.path:sub(#folder + 2)
    local top = dest:match("^[^/]+")
    if top ~= "data" and top ~= "mods" and dest ~= "config.lua" then files[#files + 1] = { src = e.path, dest = dest } end
  end
end
if #files == 0 then error("no files found in " .. folder .. "/", 0) end

-- download everything first: a failed download leaves the old install as it was
for i, f in ipairs(files) do
  print(("[%d/%d] %s"):format(i, #files, f.dest))
  f.body = get(("https://raw.githubusercontent.com/%s/%s/%s"):format(REPO, branch, f.src))
end

-- everything shipped earlier, so files removed from the repository don't linger
local OLD = kind == "computer" and { "system", "main.lua", "modules", "defaults" } or { "main.lua" }
for _, path in ipairs(OLD) do
  if fs.exists(path) then fs.delete(path) end
end

for _, f in ipairs(files) do
  local dir = fs.getDir(f.dest)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(f.dest, "w")
  h.write(f.body)
  h.close()
end

print()
print(("Installed %d files. Reboot to start (startup.lua)."):format(#files))
if kind == "computer" then
  print("Settings: config.lua (made on the first start). Your own mods go to mods/.")
end

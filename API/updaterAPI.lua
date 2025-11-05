-- updaterAPI.lua
-- Thin facade to integrate an external installer/manifest flow later.
-- For now, it exposes no-op/safe operations with user feedback strings.

local M = {}

local function getRoot()
  local fullPath = "/" .. fs.getDir(shell.getRunningProgram())
  if fullPath:sub(-1) == "/" then fullPath = fullPath:sub(1, -2) end
  local rootPos = string.find(fullPath, "/PixelCorp")
  if rootPos then
      return string.sub(fullPath, 1, rootPos + #"/PixelCorp" - 1)
  end
  if fs.exists("/PixelCorp") then return "/PixelCorp" end
  return fullPath
end
local root = getRoot()

local VERSIONS_DIR = root.."/versions"
local MANIFEST = VERSIONS_DIR.."/versions.json"   -- optional

local json = textutils

local function readVersions()
  if fs.exists(MANIFEST) then
    local f = fs.open(MANIFEST, "r"); local data = f.readAll(); f.close()
    local ok, parsed = pcall(json.unserialize, data)
    if ok and type(parsed)=="table" and type(parsed.list)=="table" then
      return parsed.list, parsed.latest or parsed.list[#parsed.list]
    end
  end
  -- Default placeholder
  return { "dev" }, "dev"
end

function M.getVersionList()
  local list, latest = readVersions()
  return list, latest
end

-- Update to latest (placeholder). Returns ok,msg
function M.updateLatest()
  -- Stub: you can replace this with shell.run("/installer.lua", "--update") etc.
  if fs.exists(root.."/installer.lua") then
    local ok, err = pcall(function() shell.run(fs.combine(root, "installer.lua"), "--update") end)
    return ok, ok and "Installer launched" or (err or "Installer error")
  end
  return false, "No installer.lua found. (stub)"
end

-- Repair current version (placeholder). Returns ok,msg
function M.repairCurrent()
  if fs.exists(root.."/installer.lua") then
    local ok, err = pcall(function() shell.run(fs.combine(root, "installer.lua"), "--repair") end)
    return ok, ok and "Repair launched" or (err or "Installer error")
  end
  return false, "No installer.lua found. (stub)"
end

-- Pin a specific version (placeholder). Returns ok,msg
function M.switchTo(version)
  if not version or version == "" then return false, "Version missing" end
  -- In a real flow, you would fetch that version/build here.
  if version == "dev" then
    return true, "Switched to dev (no-op)."
  end
  return false, "Version not available (stub)."
end

return M

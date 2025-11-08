local M = {}

-- ---------- Paths / constants ----------
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

local OWNER  = "ClassicBiz"
local REPO   = "PixelCorp---Lua-based-Tycoon-Game"

local VERSIONS_DIR = root.."/versions"
local MANIFEST     = VERSIONS_DIR.."/versions.json"
local ENTRY        = "PixelCorp.lua"

local json = textutils

-- ---------- Helpers ----------
local function ensureDir(p) if not fs.exists(p) then fs.makeDir(p) end end
local function join(a,b)
  if a=="" or a=="/" then return "/"..b end
  if a:sub(-1)=="/" then return a..b end
  return a.."/"..b
end

local function httpGet(url_primary, alt_path, ver)
  local tries = {
    url_primary,                                         
    ("https://cdn.jsdelivr.net/gh/%s/%s@%s/%s")
      :format(OWNER, REPO, ver or "main", alt_path or ""),
    ("https://github.com/%s/%s/raw/%s/%s")
      :format(OWNER, REPO, ver or "main", alt_path or "")
  }
  for _, u in ipairs(tries) do
    if u and u ~= "" then
      local ok, res = pcall(function()
        return http.get(u, {["User-Agent"]="CC-PixelCorp"})
      end)
      if ok and res then
        local body = res.readAll(); res.close()
        if body and #body > 0 then return body end
      end
    end
  end
  return nil, "HTTP failed after mirrors"
end

local function writeFile(path, data)
  ensureDir(fs.getDir(path))
  local f = fs.open(path, "w")
  if not f then return false, "cannot open "..path end
  f.write(data) f.close()
  return true
end

local function readVersions()
  if fs.exists(MANIFEST) then
    local f = fs.open(MANIFEST, "r"); local data = f.readAll(); f.close()
    local ok, parsed = pcall(json.unserialize, data)
    if ok and type(parsed)=="table" and type(parsed.list)=="table" then
      return parsed.list, parsed.latest or parsed.list[#parsed.list]
    end
  end
  return { "main" }, "main"
end

function M.getVersionList()
  return readVersions()
end

-- ---------- Core updater ----------
local function fetchFile(repoRel, destRel, ver)
  local RAW_BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, ver or "main")
  local primary  = RAW_BASE .. repoRel
  local data, e  = httpGet(primary, repoRel, ver)
  if not data then error(e or ("Failed to download: "..repoRel)) end
  local out = join(root, destRel or repoRel)
  local ok, e2 = writeFile(out, data)
  if not ok then error(e2) end
end

local DEFAULT_FILES = {
  [ENTRY] = ENTRY,
}

-- Download everything listed in install_manifest.txt (repo-side), else fallback to DEFAULT_FILES.
local function downloadVersion(ver)
  ver = ver or "main"
  ensureDir(root)
  local manURL = ("https://raw.githubusercontent.com/%s/%s/%s/install_manifest.txt"):format(OWNER, REPO, ver)
  local man, _ = httpGet(manURL, "install_manifest.txt", ver)
  if man then
    local n=0
    for line in man:gmatch("[^\r\n]+") do
      local rel = line:gsub("^%s+",""):gsub("%s+$","")
      if rel ~= "" and rel:sub(1,1) ~= "#" then
        fetchFile(rel, rel, ver); n = n + 1
      end
    end
    return true, ("Installed via manifest ("..n.." files)")
  else
    local n=0
    if not DEFAULT_FILES[ENTRY] then DEFAULT_FILES[ENTRY] = ENTRY end
    for src, dst in pairs(DEFAULT_FILES) do fetchFile(src, dst, ver); n=n+1 end
    return true, (ENTRY.." Installed "..n.." file(s) (fallback)")
  end
end

-- Public API
function M.updateLatest(ver)
  ver = ver or "main"
  if not http then return false, "HTTP API is disabled in CC config." end
  local ok, msg = pcall(function() return downloadVersion(ver) end)
  if ok then
    return true, "Update completed"
  else
    return false, tostring(msg)
  end
end

function M.updateLatestAndRestart(ver)
  local ok, msg = M.updateLatest(ver)
  if not ok then return ok, msg end
  pcall(function() shell.run(join(root, ENTRY)) end)
  return true, "Updated and relaunched"
end

function M.repairCurrent(ver)
  return M.updateLatest(ver)
end

function M.switchTo(version)
  if not version or version == "" then return false, "Version missing" end
  ensureDir(VERSIONS_DIR)
  local f = fs.open(VERSIONS_DIR.."/selected.json", "w")
  f.write(json.serialize({ selected = version }))
  f.close()
  return true, "Pinned version "..version
end

return M

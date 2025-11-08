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


local API_BASE = "https://api.github.com"
local UA = "PixelCity-Updater/1.0"   -- GitHub API requires a User-Agent
local CACHE_PATH = root.."/versions/remote_versions.json"
local CACHE_TTL  = 600  -- seconds (10 min) to avoid rate limiting

local function _readFile(p)
  if not fs.exists(p) then return nil end
  local f = fs.open(p, "r"); local d = f.readAll(); f.close(); return d
end
local function _writeFile(p, s)
  fs.makeDir(fs.getDir(p)); local f = fs.open(p, "w"); f.write(s); f.close()
end
local function _jsonDecode(s)
  local ok, t = pcall(textutils.unserializeJSON, s)
  if ok then return t end
  -- fallback for older CC if needed
  ok, t = pcall(textutils.unserialize, s)
  return ok and t or nil
end
local function _jsonEncode(t)
  local ok, s = pcall(textutils.serializeJSON, t)
  if ok then return s end
  return textutils.serialize(t)
end

local function _httpJSON(url)
  local h = {["User-Agent"]=UA, ["Accept"]="application/vnd.github+json"}
  local ok, res = pcall(http.get, url, h)
  if not ok or not res then return nil, "http failed" end
  local body = res.readAll(); res.close()
  local t = _jsonDecode(body)
  if type(t) ~= "table" then return nil, "bad json" end
  return t
end

local function _fetchRepoMeta()
  local url = string.format("%s/repos/%s/%s", API_BASE, OWNER, REPO)
  local t = _httpJSON(url); if not t then return { default_branch = "main" } end
  return { default_branch = t.default_branch or "main" }
end

local function _fetchBranches()
  local url = string.format("%s/repos/%s/%s/branches?per_page=100", API_BASE, OWNER, REPO)
  local t = _httpJSON(url) or {}
  local out = {}
  for _,b in ipairs(t) do table.insert(out, { name=b.name, type="branch" }) end
  return out
end

local function _fetchTags()
  local url = string.format("%s/repos/%s/%s/tags?per_page=100", API_BASE, OWNER, REPO)
  local t = _httpJSON(url) or {}
  local out = {}
  for _,g in ipairs(t) do table.insert(out, { name=g.name, type="tag" }) end
  return out
end

local function _loadCached()
  local s = _readFile(CACHE_PATH); if not s then return nil end
  local t = _jsonDecode(s); if type(t) ~= "table" then return nil end
  if (t.ts or 0) + CACHE_TTL < os.epoch("utc")/1000 then return nil end
  return t
end

local function _saveCache(list, latest)
  _writeFile(CACHE_PATH, _jsonEncode({ ts = math.floor(os.epoch("utc")/1000), list = list, latest = latest }))
end

function M.getVersionList()

  local c = _loadCached()
  if c and type(c.list)=="table" and #c.list>0 then return c.list, (c.latest or c.list[1]) end

  local ok, list, latest = pcall(function()
    local meta = _fetchRepoMeta()
    local branches = _fetchBranches()
    local tags     = _fetchTags()

    local seen, out = {}, {}
    local function add(name, kind)
      if not name or seen[name] then return end
      seen[name] = true
      table.insert(out, {name=name, kind=kind})
    end
    for _,b in ipairs(branches) do add(b.name, "branch") end
    for _,g in ipairs(tags)     do add(g.name, "tag")    end

    table.sort(out, function(a,b)
      local function rank(x)
        if x.name == meta.default_branch then return 0 end
        if x.name == "develop" then return 1 end
        return (x.kind == "branch") and 2 or 3
      end
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      return a.name:lower() < b.name:lower()
    end)

    local flat = {}
    for _,v in ipairs(out) do table.insert(flat, v.name) end
    local lat = meta.default_branch or flat[1] or "main"
    _saveCache(flat, lat)
    return flat, lat
  end)
  if ok and list and #list > 0 then return list, latest end

  local p = root.."/versions/versions.json"
  local t = _jsonDecode(_readFile(p) or "") or {}
  if type(t.list)=="table" and #t.list>0 then return t.list, (t.latest or t.list[1]) end
  return {"main"}, "main"
end

function M.switchTo(ver)
  fs.makeDir(root.."/versions")
  _writeFile(root.."/versions/selected.json", _jsonEncode({ selected = ver }))
end

function M.readSelected()
  local t = _jsonDecode(_readFile(root.."/versions/selected.json") or "")
  return (t and t.selected) or nil
end
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

return M

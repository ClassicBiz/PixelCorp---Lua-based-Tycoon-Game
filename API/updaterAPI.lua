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

-- Optional: settings to persist installed version/ref
local ok_settings, settingsAPI = pcall(function() return require(getRoot().."/API/settingsAPI") end)

local VERSIONS_DIR = root.."/versions"
local MANIFEST     = VERSIONS_DIR.."/versions.json"
<<<<<<< HEAD
=======
local VERSION_FILE = VERSIONS_DIR.."/.version"
>>>>>>> 52c40b5160b49a22fadef8e888dcdd0a911ebadf
local ENTRY        = "PixelCorp.lua"

local json = textutils

-- ===== Remote version discovery (branches + tags) =========================
local API_BASE   = "https://api.github.com"
local UA         = "PixelCorp-Updater/1.0"    -- GitHub API wants a User-Agent
local CACHE_PATH = VERSIONS_DIR.."/remote_versions.json"
local CACHE_TTL  = 600  -- 10 minutes

local function ensureDir(p) if p and p ~= "" and not fs.exists(p) then fs.makeDir(p) end end
local function _readAll(p)
  if not fs.exists(p) then return nil end
  local f = fs.open(p, "r"); local d = f.readAll(); f.close(); return d
end
local function _writeAll(p, s)
  ensureDir(fs.getDir(p)); local f = fs.open(p, "w"); f.write(s); f.close()
end
local function _jdecode(s)
  local ok,t = pcall(json.unserializeJSON, s); if ok then return t end
  ok,t = pcall(json.unserialize, s); return ok and t or nil
end
local function _jencode(t)
  local ok,s = pcall(json.serializeJSON, t); if ok then return s end
  return json.serialize(t)
end

local function _httpJSON(url)
  if not http then return nil end
  local headers = {["User-Agent"]=UA, ["Accept"]="application/vnd.github+json"}
  local ok, res = pcall(http.get, url, headers)
  if not ok or not res then return nil end
  local body = res.readAll(); res.close()
  local t = _jdecode(body)
  return (type(t)=="table") and t or nil
end

local function _fetchRepoMeta()
  local url = ("%s/repos/%s/%s"):format(API_BASE, OWNER, REPO)
  local t = _httpJSON(url)
  return { default_branch = (t and t.default_branch) or "main" }
end
local function _fetchBranches()
  local url = ("%s/repos/%s/%s/branches?per_page=100"):format(API_BASE, OWNER, REPO)
  local t = _httpJSON(url) or {}
  local out = {}
  for _,b in ipairs(t) do table.insert(out, { name=b.name, kind="branch" }) end
  return out
end
local function _fetchTags()
  local url = ("%s/repos/%s/%s/tags?per_page=100"):format(API_BASE, OWNER, REPO)
  local t = _httpJSON(url) or {}
  local out = {}
  for _,g in ipairs(t) do table.insert(out, { name=g.name, kind="tag" }) end
  return out
end

local function _loadCache()
  local s = _readAll(CACHE_PATH); if not s then return nil end
  local t = _jdecode(s); if type(t)~="table" then return nil end
  local now = math.floor(os.epoch("utc")/1000)
  if (t.ts or 0) + CACHE_TTL < now then return nil end
  return t
end
local function _saveCache(list, latest)
  local now = math.floor(os.epoch("utc")/1000)
  _writeAll(CACHE_PATH, _jencode({ ts = now, list = list, latest = latest }))
end

function M.getVersionList()
  -- cached live list first
  local c = _loadCache()
  if c and type(c.list)=="table" and #c.list>0 then
    return c.list, (c.latest or c.list[1])
  end

  -- live from GitHub
  if http then
    local ok, list, latest = pcall(function()
      local meta     = _fetchRepoMeta()
      local branches = _fetchBranches()
      local tags     = _fetchTags()

      -- merge unique
      local seen, arr = {}, {}
      local function add(v)
        if v and v.name and not seen[v.name] then seen[v.name]=true; table.insert(arr, v) end
      end
      for _,b in ipairs(branches) do add(b) end
      for _,g in ipairs(tags)     do add(g) end

      -- sort: default branch, then 'develop', other branches alpha, then tags alpha
      table.sort(arr, function(a,b)
        local function rank(x)
          if x.name == meta.default_branch then return 0 end
          if x.name == "develop" then return 1 end
          return (x.kind=="branch") and 2 or 3
        end
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return a.name:lower() < b.name:lower()
      end)

      local flat = {}; for _,v in ipairs(arr) do table.insert(flat, v.name) end
      local lat = meta.default_branch or flat[1] or "main"
      _saveCache(flat, lat)
      return flat, lat
    end)
    if ok and list and #list>0 then return list, latest end
  end

  -- fallback manifest (optional)
  local p = root.."/versions/versions.json"
  local t = _jdecode(_readAll(p) or "") or {}
  if type(t.list)=="table" and #t.list>0 then return t.list, (t.latest or t.list[1]) end

  -- last resort
  return {"main"}, "main"
end

function M.switchTo(ver)
  ensureDir(VERSIONS_DIR)
  _writeAll(VERSIONS_DIR.."/selected.json", _jencode({ selected = ver }))
end
function M.readSelected()
  local t = _jdecode(_readAll(VERSIONS_DIR.."/selected.json") or "")
  return (t and t.selected) or nil
end

-- ---------- Helpers ----------
local function join(a,b)
  if a=="" or a=="/" then return "/"..b end
  if a:sub(-1)=="/" then return a..b end
  return a.."/"..b
end
local function writeFile(path, data)
  ensureDir(fs.getDir(path))
  local f = fs.open(path, "w")
  if not f then return false, "cannot open "..path end
  f.write(data) f.close()
  return true
end

-- URL helpers
local function _join_url(a, b)
  if not a or a == "" then return b end
  if not b or b == "" then return a end
  if a:sub(-1) == "/" then a = a:sub(1, -2) end
  if b:sub(1, 1) == "/" then b = b:sub(2) end
  return a .. "/" .. b
end
local function _url_escape_path(p)
  return (tostring(p or ""):gsub(" ", "%%20"):gsub("%[", "%%5B"):gsub("%]", "%%5D"))
end

-- Robust GET used by installer: tries raw, refs/heads, refs/tags + mirrors
-- Returns body, used_url OR nil, error
local function httpGetPath(ver, rel_path)
  if not http then return nil, "HTTP API disabled (enable it in CC config)" end
  local rel = _url_escape_path(rel_path or "")
  local v   = tostring(ver or "main")

  local tries = {}
  local function addRaw(verPath) table.insert(tries, _join_url(("https://raw.githubusercontent.com/%s/%s/%s"):format(OWNER, REPO, verPath), rel)) end
  local function addCDN(uBase)   table.insert(tries, _join_url(uBase, rel)) end

  if v:match("^refs/") then
    addRaw(v)
  else
    addRaw(v)
    addRaw("refs/heads/"..v)
    addRaw("refs/tags/"..v)
  end
  addCDN(("https://cdn.jsdelivr.net/gh/%s/%s@%s"):format(OWNER, REPO, v))
  addCDN(("https://github.com/%s/%s/raw/%s"):format(OWNER, REPO, v))
  addCDN(("https://cdn.statically.io/gh/%s/%s/%s"):format(OWNER, REPO, v))

  local last_err = nil
  for _, u in ipairs(tries) do
    local ok, res = pcall(function()
      return http.get(u, { ["User-Agent"]="CC-PixelCorp", ["Accept"]="*/*" })
    end)
    if ok and res then
      local body = res.readAll(); res.close()
      if body and #body > 0 then return body, u end
      last_err = "empty body from "..u
    else
      last_err = "failed GET "..u
    end
  end
  return nil, last_err or "HTTP failed after mirrors"
end

-- ---------- Core updater ----------
local function fetchFile(repoRel, destRel, ver)
  local data, used  = httpGetPath(ver, repoRel)
  if not data then error(("Failed to download '%s' for version '%s'"):format(tostring(repoRel), tostring(ver))) end
  local out = join(root, destRel or repoRel)
  local ok, e2 = writeFile(out, data)
  if not ok then error(e2) end
  return used
end

local DEFAULT_FILES = { [ENTRY] = ENTRY }

-- Download everything listed in install_manifest.txt (repo-side), else fallback to DEFAULT_FILES.
local function downloadVersion(ver)
  local last_used_url = nil
  ver = ver or "main"
  ensureDir(root)
  local man, _ = httpGetPath(ver, "install_manifest.txt")
  if man then
    local n=0
    for line in man:gmatch("[^\r\n]+") do
      local rel = line:gsub("^%s+",""):gsub("%s+$","")
      if rel ~= "" and rel:sub(1,1) ~= "#" then
        last_used_url = fetchFile(rel, rel, ver); n = n + 1
      end
    end
    return true, ("Installed via manifest ("..n.." files)"), last_used_url
  else
    local n=0
    if not DEFAULT_FILES[ENTRY] then DEFAULT_FILES[ENTRY] = ENTRY end
    for src, dst in pairs(DEFAULT_FILES) do last_used_url = fetchFile(src, dst, ver); n=n+1 end
    return true, (ENTRY.." Installed "..n.." file(s) (fallback)"), last_used_url
  end
end

-- Extract version from installed PixelCorp.lua
<<<<<<< HEAD
=======

-- Write compact .version file alongside selected.json
local function writeVersionMeta(meta)
  local tbl = {
    selected_ref      = meta.selected_ref,
    installed_ref     = meta.installed_ref or meta.selected_ref,
    installed_version = meta.installed_version,
    last_update_url   = meta.last_update_url,
    last_update_epoch = math.floor(os.epoch("utc")/1000),
  }
  _writeAll(VERSION_FILE, _jencode(tbl))
end

>>>>>>> 52c40b5160b49a22fadef8e888dcdd0a911ebadf
local function detectInstalledVersion()
  local s = _readAll(join(root, ENTRY)); if not s then return nil end
  local v = s:match('[Vv][Ee][Rr][Ss][Ii][Oo][Nn]%s*=%s*["\']([^"\']+)["\']')
        or s:match('Version%s*[:=]%s*([%d%.]+)')
        or s:match('PC[_-]?VERSION%s*=%s*["\']([^"\']+)["\']')
  return v
end

-- Public API
function M.updateLatest(ver)
  ver = ver or "main"
  if not http then return false, "HTTP API is disabled in CC config." end
  local ok, msg = pcall(function() return downloadVersion(ver) end)
  if ok then
    local v = detectInstalledVersion()
    if v then
      return true, ("Update completed. Detected version: "..v)
    else
      return true, "Update completed (version unknown)"
    end
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

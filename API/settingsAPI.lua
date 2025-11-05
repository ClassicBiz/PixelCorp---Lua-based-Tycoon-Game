-- settingsAPI.lua
-- Small helper to persist user settings to /config/.settings

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
local json = textutils

local CFG_DIR = root.."/config"
local CFG_PATH = CFG_DIR.."/.settings"

local defaults = {
  general = {
    difficulty = "medium",     -- easy, medium, hard
    navigation = "sidebar",    -- dropdown, sidebar
    tutorial = true,
    autosave = false,          -- placeholder
  },
  profile = {
    last_loaded = "profile1",
  },
  version = {
    current = "dev",
    channel = "stable",
  }
}

local function ensureDir()
  if not fs.exists(CFG_DIR) then fs.makeDir(CFG_DIR) end
end

-- Auto-initialize settings file if missing or unreadable
local function _init_file()
  ensureDir()
  if not fs.exists(CFG_PATH) then
    local ok = pcall(function()
      local f = fs.open(CFG_PATH, "w")
      f.write(json.serialize(deepcopy(defaults)))
      f.close()
    end)
  end
end
_init_file()




local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k,v in pairs(t) do r[k] = deepcopy(v) end
  return r
end

local function merge(dst, src)
  for k,v in pairs(src or {}) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      merge(dst[k], v)
    else
      if dst[k] == nil then dst[k] = v end
    end
  end
end

function M.load()
  ensureDir()
  if fs.exists(CFG_PATH) then
    local f = fs.open(CFG_PATH, "r"); local data = f.readAll(); f.close()
    local ok, parsed = pcall(json.unserialize, data)
    if ok and type(parsed)=="table" then
      local s = deepcopy(defaults)
      merge(s, parsed)
      return s
    end
  end
  local d = deepcopy(defaults); M.save(d); return d
end

function M.save(state)
  ensureDir()
  local s = state or M.load()
  local f = fs.open(CFG_PATH, "w")
  f.write(json.serialize(s))
  f.close()
  return true
end

function M.set(path, value)
  local s = M.load()
  local ref = s
  for i=1,#path-1 do
    local k = path[i]
    ref[k] = ref[k] or {}
    ref = ref[k]
  end
  ref[path[#path]] = value
  M.save(s)
end

function M.get(path, fallback)
  local s = M.load()
  local ref = s
  for i=1,#path do
    ref = ref[path[i]]
    if ref == nil then return fallback end
  end
  return ref
end

return M

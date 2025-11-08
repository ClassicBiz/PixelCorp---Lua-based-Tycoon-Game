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

-- === settings core ===
local SETTINGS_PATH = CFG_DIR.."/.settings"

local DEFAULTS = {
  general = {
    difficulty = "medium",   -- "easy" | "medium" | "hard"
    navigation = "sidebar",  -- "sidebar" | "dropdown"
    tutorial   = true,
    autosave   = false,
  },
  profile = {
    last_loaded = "profile1",
  },
  version = {
    current = "dev",
  },
}

local _cache = nil

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k,v in pairs(t) do r[k] = deepcopy(v) end
  return r
end

local function ensureDir()
  if not fs.exists(CFG_DIR) then fs.makeDir(CFG_DIR) end
end

local function merge(dst, src)
  for k,v in pairs(src or {}) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

local function _readFile()
  if not fs.exists(SETTINGS_PATH) then return deepcopy(DEFAULTS) end
  local fh = fs.open(SETTINGS_PATH, "r")
  local data = fh.readAll(); fh.close()
  local parsed = textutils.unserialize(data) or {}
  return merge(deepcopy(DEFAULTS), parsed)
end

local function _writeFile(tbl)
  ensureDir()
  local fh = fs.open(SETTINGS_PATH, "w")
  fh.write(textutils.serialize(tbl))
  fh.close()
end

function M.load()
  _cache = _readFile()
  return deepcopy(_cache)
end

local function _get(path, def)
  if not _cache then M.load() end
  local t = _cache
  for _,k in ipairs(path or {}) do
    if type(t) ~= "table" then return def end
    t = t[k]
  end
  if t == nil then return def end
  return t
end

local function _set(path, value)
  if not _cache then M.load() end
  local t = _cache
  for i = 1, #path-1 do
    local k = path[i]
    t[k] = t[k] or {}
    t = t[k]
  end
  t[path[#path]] = value
  _writeFile(_cache)
end

function M.get(path, def) return _get(path, def) end
function M.set(path, val)  _set(path, val); return true end

function M.save(tbl)
  _cache = merge(deepcopy(DEFAULTS), tbl or {})
  _writeFile(_cache)
  return true
end

-- === difficulty helpers ===
local DIFF = {
  easy   = { customers_per_hour = 7, bank_interest_daily = 0.0060, starting_cash = 450, upgrade_cost_scale = 0.85, stock_bias = -1, loan_interest = 0.10, xp_curve_mult = 0.75 },
  medium = { customers_per_hour = 4, bank_interest_daily = 0.0030, starting_cash = 350, upgrade_cost_scale = 1.00, stock_bias =  0, loan_interest = 0.20, xp_curve_mult = 1.00 },
  hard   = { customers_per_hour = 2, bank_interest_daily = 0.0015, starting_cash = 250, upgrade_cost_scale = 1.50, stock_bias =  1, loan_interest = 0.30, xp_curve_mult = 1.50 },
}

local function _cur()
  local name = tostring(M.get({"general","difficulty"}, "medium")):lower()
  return DIFF[name] or DIFF.medium
end

function M.difficultyName()    return (M.get({"general","difficulty"}, "medium")) end
function M.customersPerHour()  return _cur().customers_per_hour end
function M.bankDailyRate()     return _cur().bank_interest_daily end
function M.startingCash()      return _cur().starting_cash end
function M.upgradeCostScale()  return _cur().upgrade_cost_scale end
function M.stockBias()         return _cur().stock_bias end
function M.loanInterest()      return _cur().loan_interest end
function M.xpCurveMult()       return _cur().xp_curve_mult end

-- toggles
function M.navMode()         return tostring(M.get({"general","navigation"}, "sidebar")) end
function M.tutorialEnabled() return M.get({"general","tutorial"}, true) == true end
function M.autosaveEnabled() return M.get({"general","autosave"}, false) == true end

return M
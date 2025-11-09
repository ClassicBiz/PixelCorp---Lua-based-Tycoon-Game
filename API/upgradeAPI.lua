local U = {}

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
local saveAPI   = require(root.."/API/saveAPI")
local settingsOK, settingsAPI = pcall(require, root.."/API/settingsAPI")
local economyAPI = require(root.."/API/economyAPI")


U.catalog = {
  seating     = { level_cap = 4, one_time = false, min_level = 3, req_levels  = {3, 17, 33}, cost = function(lvl) return 40 + 80*lvl end },
  marketing   = { level_cap = 10, one_time = false, min_level = 5,req_levels  = {5, 9, 15, 19, 24, 29, 32, 36, 40, 44},  cost = function(lvl) return math.floor(50 * (2^lvl)) end },
  awning      = { level_cap = 4, one_time = false, min_level = 7, req_levels  = {7, 14, 21, 29}, cost = function(lvl) return 30 + 80*lvl end },
  ice_shaver  = { level_cap = 5, one_time = true , min_level = 10, req_levels  = {10, 15, 22, 28, 35}, cost = function(_)  return 250 end },
  juicer      = { level_cap = 3,  one_time = true , min_level = 5, cost = function(_)  return 150 end },
}

U.catalog.exp_boost = {
  level_cap   = 5,
  one_time    = false,
  min_level   = 10,                        
  req_levels  = {10, 20, 30, 35, 40},       
  multipliers = {1.5, 2.25, 3.5, 4.25, 5.0},
  cost = function(lvl)                       
    local base = 150
    return math.floor(base * (1.8 ^ (lvl)))
  end
}

U.stageCatalogs = {
  lemonade_stand = U.catalog,
  warehouse = {
    shelving     = { level_cap=5,  one_time=false, min_level=55,  req_levels={55,60,65,70,75}, cost=function(l) return 100 + 120*l end },
    pallet_jack  = { level_cap=1,  one_time=true,  min_level=65,                              cost=function(_) return 450 end },
    forklift     = { level_cap=1,  one_time=true,  min_level=62,                             cost=function(_) return 2200 end },
    loading_dock = { level_cap=3,  one_time=false, min_level=59, req_levels={59,70,80},      cost=function(l) return 600 + 400*l end },
    exp_boost    = U.catalog.exp_boost,
  }
}

local _activeStage = "lemonade_stand"
local function _activeCatalog()
  return U.stageCatalogs[_activeStage] or U.catalog
end

-- ---- Storage helpers ----
local function _state()
  local st = saveAPI.get()
  st.upgrades = st.upgrades or { seating=0, marketing=0, awning=0, ice_shaver=false, juicer=false, exp_boost=0 }
  return st.upgrades
end

function U.level(key)
  local u = _state()
  local v = u[key]
  return (type(v)=="number") and v or 0
end

local function _playerLevel()
  local mod = package.loaded["/API/levelAPI"]
  if mod and mod.getLevel then return mod.getLevel() end
  local s = saveAPI.get()
  return (s.level and s.level.level) or 1
end

function U.has(key)
  local u = _state()
  local v = u[key]
  return (v == true) or ((type(v)=="number") and v > 0)
end

function U.minLevel(key)
  local def = U.catalog[key]; return (def and def.min_level) or 1
end

function U.canPurchase(key)
  local def = _activeCatalog()[key]
  local u = _state()

  local playerL = _playerLevel()
  local minL = def.min_level or 1
  if playerL < minL then
    return false, ("Requires player lvl %d"):format(minL)
  end

  if def.one_time then
    if u[key] == true then return false, "Already owned" end
  else
    local lvl = U.level(key)
    if lvl >= def.level_cap then return false, "Max level" end
  end

  if key == "exp_boost" then
    local nextTier = U.level("exp_boost") + 1
    local need = def.req_levels[nextTier] or 999
    if playerL < need then
      return false, ("Requires player lvl %d"):format(need)
    end
  end

  return true, nil
end

function U.cost(key)
  local def = _activeCatalog()[key]
  local lvl = U.level(key)
  local base = def.cost(lvl)
  local scale = 1.0
  if settingsOK and settingsAPI and settingsAPI.upgradeCostScale then
    scale = tonumber(settingsAPI.upgradeCostScale()) or 1.0
  end
  return math.floor(base * scale + 0.5)
end

function U.purchase(key, spendFn)
  local ok, why = U.canPurchase(key)
  if not ok then return false, why end
  local c = U.cost(key)
  if not (spendFn and spendFn(c)) then return false, "Not enough money" end

  local def = U.catalog[key]
  local u = _state()

  if def.one_time then
    u[key] = true
  else
    u[key] = U.level(key) + 1
  end

  saveAPI.save()
  economyAPI.recordExpense("upgrade", tonumber(c), tostring(def))
  return true, (def.one_time and "Purchased" or ("Level "..tostring(u[key])))
end

function U.setStage(progressKey)
  _activeStage = tostring(progressKey or "lemonade_stand")
end

-- Swap all reads to use active catalog
function U.isVisibleAtLevel(key, playerLevel)
  local def = _activeCatalog()[key]; if not def then return false end
  local minL = def.min_level or 1
  return (playerLevel or 1) >= minL
end

function U.catalogKeys()
  local keys = {}
  for k,_ in pairs(_activeCatalog()) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end
function U.stageKeys() return U.catalogKeys() end


-- ======= Game effect helpers =======
function U.expBoostFactor()
  local def = U.catalog.exp_boost
  if not def then return 1.0 end
  local lvl = U.level("exp_boost")
  return def.multipliers[lvl] or 1.0
end

function U.priceSlopeFactor()
  local lvl = U.level("awning")
  local f = 1 - 0.12 * lvl
  if f < 0.01 then f = 0.01 end
  return f
end

function U.buyProbabilityFactor()
  local lvl = U.level("seating")
  return 1 + 0.07 * lvl
end

function U.customersPerHourFactor()
  local lvl = U.level("marketing")
  return 1 + 0.15 * lvl
end

function U.fruitReqDelta()
  return U.has("juicer") and -1 or 0
end

function U.allowShavedIceSubstitution()
  return U.has("ice_shaver")
end

-- Shown/hidden in UI by level

function U.nextEffectLabel(key)
  local lvlNext = U.level(key) + 1
  if key == "seating"    then return ("Buy chance x%.2f"):format(1 + 0.07*lvlNext) end
  if key == "marketing"  then return ("Customers/hr x%.2f"):format(1 + 0.15*lvlNext) end
  if key == "awning"     then return ("Price tolerance x%.2f"):format(1 - 0.12*lvlNext) end
  if key == "ice_shaver" then return "Unlock: Shaved Ice crafting" end
  if key == "juicer"     then return "Fruit req −1 (crafting)" end
  if key == "exp_boost"  then
    local def = _activeCatalog()
    local m = def.multipliers[lvlNext] or def.multipliers[#def.multipliers]
    return ("XP boost x%.2f"):format(m)
  end
  return ""
end

return U

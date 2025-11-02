-- TOP OF FILE
local saveAPI   = require("/API/saveAPI")

local U = {}

-- Catalog: add min_level to each; keep your costs as is
U.catalog = {
  seating     = { level_cap = 4, one_time = false, min_level = 3, req_levels  = {3, 17, 33}, cost = function(lvl) return 40 + 40*lvl end },
  marketing   = { level_cap = 10, one_time = false, min_level = 5,req_levels  = {5, 9, 15, 19, 24, 29, 32, 36, 40, 44},  cost = function(lvl) return math.floor(25 * (1.8^lvl)) end },
  awning      = { level_cap = 4, one_time = false, min_level = 7, req_levels  = {7, 14, 21, 29}, cost = function(lvl) return 30 + 40*lvl end },
  ice_shaver  = { level_cap = 5, one_time = true , min_level = 10, req_levels  = {10, 15, 22, 28, 35}, cost = function(_)  return 60 end },
  juicer      = { level_cap = 3,  one_time = true , min_level = 5, cost = function(_)  return 120 end },
}

-- EXP Boost: 5 tiers with level requirements per tier
U.catalog.exp_boost = {
  level_cap   = 5,
  one_time    = false,
  min_level   = 10,                         -- shown in UI from level 10+
  req_levels  = {10, 20, 30, 35, 40},       -- required player level for L1..L5
  multipliers = {1.5, 2.25, 3.5, 4.25, 5.0},
  cost = function(lvl)                       -- lvl is current level (0-based indexing into next tier)
    local base = 150
    return math.floor(base * (1.8 ^ (lvl)))
  end
}

-- ---- Storage helpers (ensure exp_boost slot exists) ----
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
  -- use loaded module if present
  local mod = package.loaded["/API/levelAPI"]
  if mod and mod.getLevel then return mod.getLevel() end
  -- fallback: read from save
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

-- Locking/gating check
function U.canPurchase(key)
  local def = U.catalog[key]; if not def then return false, "Unknown upgrade" end
  local u = _state()

  -- Global min_level gate
  local playerL = _playerLevel()
  local minL = def.min_level or 1
  if playerL < minL then
    return false, ("Requires player lvl %d"):format(minL)
  end

  -- One-time or level-capped
  if def.one_time then
    if u[key] == true then return false, "Already owned" end
  else
    local lvl = U.level(key)
    if lvl >= def.level_cap then return false, "Max level" end
  end

  -- Special per-tier gates for EXP boost
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
  local def = U.catalog[key]; if not def then return 0 end
  local lvl = U.level(key)
  return def.cost(lvl)
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
  return true, (def.one_time and "Purchased" or ("Level "..tostring(u[key])))
end

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
function U.isVisibleAtLevel(key, playerLevel)
  local def = U.catalog[key]; if not def then return false end
  local minL = def.min_level or 1
  return (playerLevel or 1) >= minL
end

function U.nextEffectLabel(key)
  local lvlNext = U.level(key) + 1
  if key == "seating"    then return ("Buy chance x%.2f"):format(1 + 0.07*lvlNext) end
  if key == "marketing"  then return ("Customers/hr x%.2f"):format(1 + 0.15*lvlNext) end
  if key == "awning"     then return ("Price tolerance x%.2f"):format(1 - 0.12*lvlNext) end
  if key == "ice_shaver" then return "Unlock: Shaved Ice crafting" end
  if key == "juicer"     then return "Fruit req −1 (crafting)" end
  if key == "exp_boost"  then
    local def = U.catalog.exp_boost
    local m = def.multipliers[lvlNext] or def.multipliers[#def.multipliers]
    return ("XP boost x%.2f"):format(m)
  end
  return ""
end

return U

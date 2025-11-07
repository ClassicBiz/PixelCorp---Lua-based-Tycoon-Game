-- API/levelAPI.lua
-- Level progression + XP rules for crafting and selling.
-- Persists via saveAPI. Max level 250. Stage unlock thresholds handled here.


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
local stageAPI  = require(root.."/API/stageAPI")
local upgradeAPI = require(root.."/API/upgradeAPI")
local settingsOK, settingsAPI = pcall(require, root.."/API/settingsAPI")

local levelAPI = {}

-- Default flat XP per sale before multipliers (tweakable)
local BASE_SALE_XP = 10

-- ========= XP tables by stage & rarity =========
-- Rarity keys: "common","uncommon","rare","unique","legendary","mythical","relic","masterwork","divine"
local XP_TABLE = {
  lemonade = { common=0.5,  uncommon=0.75, rare=1,    unique=1.5,  legendary=2,   mythical=3,   relic=4,   masterwork=5,  divine=10 },
  warehouse = { common=1,    uncommon=2.5,  rare=3.75, unique=5,    legendary=6.5, mythical=8,   relic=10,  masterwork=15, divine=20 },
  factory =   { common=2,    uncommon=4,    rare=7,    unique=10,   legendary=13,  mythical=16,  relic=20,  masterwork=30, divine=40 },
  tower =     { common=4,    uncommon=8,    rare=15,   unique=20,   legendary=26,  mythical=32,  relic=40,  masterwork=60, divine=80 },
}

-- Permanent additive sale multipliers granted by unlocked stages.
-- These ADD to a baseline 1x, not multiply. (e.g., at factory: 1 + 3.5 + 5.5 = 10x before recipe bonus)
local STAGE_PERM_SALE_BONUS = {
  lemonade = 0.0,    -- baseline world, no extra
  warehouse = 3.5,
  factory = 5.5,
  tower = 8.0,
}

-- Stage unlock thresholds (inclusive)
local UNLOCKS = { warehouse=50, factory=100, tower=175 }

-- Item/feature unlocks by level (initial set)
local ITEM_UNLOCKS = {
  [2]  = {"berries"},
  [3]  = {"seating"},
  [4]  = {"honey"},
  [5]  = {"ice_shaver"},
  [7]  = {"golden_cups"},  -- glass cups
  [10] = {"juicer"},
  [13] = {"mangos"},
  [15] = {"awning"},
}


-- XP curve: XP required to advance from level L to L+1.
-- Smoothly increases; tweakable. Approximately 100 -> 2k over the range.
local function xp_to_next(level)
  local m = (settingsAPI.xpCurveMult and settingsAPI.xpCurveMult()) or 1.0
  local v
  if level < 10  then v = 60 + 6*level
  elseif level < 50  then v = 120 + math.floor(8.5 * level)
  elseif level < 100 then v = 500 + math.floor(9.5 * level)
  elseif level < 175 then v = 1100 + math.floor(11 * level)
  else                  v = 2000 + math.floor(12.5 * level)
  end
  return math.max(1, math.floor(v * m + 0.5))
end

-- Initialize save structure
local function _ensure()
  local s = saveAPI.get()
  s.level = s.level or { xp=0, level=1, products={} }
  s.level.products = s.level.products or {}
  s.level.unlocks = s.level.unlocks or {}
  s.level._lastLevel = s.level._lastLevel or 1
  saveAPI.save(s)
  return s
end

function levelAPI.get()
  return _ensure().level
end

function levelAPI.getLevel()
  return _ensure().level.level or 1
end

function levelAPI.getXP()
  return _ensure().level.xp or 0
end

-- Recompute level from total XP
local function _recalc_level(total_xp)
  local lvl = 1
  local need = xp_to_next(lvl)
  local remaining = total_xp
  while lvl < 250 and remaining >= need do
    remaining = remaining - need
    lvl = lvl + 1
    need = xp_to_next(lvl)
  end
  return lvl, need, remaining
end

-- Unlock stages when hitting thresholds
local function _applyUnlocks(lvl)
  if lvl >= UNLOCKS.tower then stageAPI.unlock("tower") end
  if lvl >= UNLOCKS.factory then stageAPI.unlock("factory") end
  if lvl >= UNLOCKS.warehouse then stageAPI.unlock("warehouse") end
end


-- Unlock helpers
local function _applyItemUnlocksUpTo(level)
  local s = _ensure()
  s.level.unlocks = s.level.unlocks or {}
  for L = 1, level do
    local list = ITEM_UNLOCKS[L]
    if list then
      for _,k in ipairs(list) do s.level.unlocks[k] = true end
    end
  end
  saveAPI.save(s)
end

local function _getProductMultiBase(productKey, stageKey)
  local s = _ensure()
  s.level.product_multi = s.level.product_multi or {}
  local pm = tonumber(s.level.product_multi[productKey] or 0) or 0
  if pm > 0 then return pm end

  -- Backfill from existing craftXP if present (keeps old saves working)
  local craftXP = tonumber(s.level.products[productKey] or 0) or 0
  if craftXP > 0 then
    pm = craftXP / 10
    s.level.product_multi[productKey] = pm
    saveAPI.save(s)
    return pm
  end

  return 0
end

function levelAPI.isUnlocked(key)
  local s = _ensure()
  return (s.level.unlocks or {})[key] == true
end

function levelAPI.getUnlocks()
  return (_ensure().level.unlocks) or {}
end

-- Add raw XP, clamp, recompute level, and unlock stages if needed.
function levelAPI.addXP(amount, reason)
  if type(amount) ~= "number" or amount <= 0 then return levelAPI.getLevel(), levelAPI.getXP() end
  local s = _ensure()
  s.level.xp = math.max(0, (s.level.xp or 0) + amount)
  local old = s.level.level or 1
  local newLvl = _recalc_level(s.level.xp)
  s.level.level = newLvl
  s.level._lastLevel = old
  saveAPI.save(s)
  if newLvl > old then _applyUnlocks(newLvl); _applyItemUnlocksUpTo(newLvl) end
  return newLvl, s.level.xp
end

-- ====== Crafting XP ======
-- rarities: array like { "common","rare","uncommon","unique" } (base, fruit, sweet, topping)
-- stageKey: "lemonade" | "warehouse" | "factory" | "tower"
local function _stageKeyOrCurrent(stageKey)
  if stageKey and XP_TABLE[stageKey] then return stageKey end
  local st = stageAPI.getCurrentStage and stageAPI.getCurrentStage() or "lemonade"
  return XP_TABLE[st] and st or "lemonade"
end

function levelAPI.xpForRarities(rarities, stageKey)
  local sk = _stageKeyOrCurrent(stageKey)
  local t  = XP_TABLE[sk]
  local sum = 0
  if type(rarities) == "table" then
    for _,r in ipairs(rarities) do
      local v = t[r] or 0
      sum = sum + v
    end
  end
  return sum
end

-- Record craft XP by product name for later sale multipliers
local function _recordProductXP(prod, xp)
  if not prod or xp <= 0 then return end
  local s = _ensure()
  s.level.products[prod] = xp
  saveAPI.save(s)
end

-- Public: call after a product is crafted
-- productName: string, rarities: array of rarity strings
function levelAPI.onCraft(productName, rarities, stageKey)
  local xp = levelAPI.xpForRarities(rarities, stageKey)
  if xp > 0 then
    local boost = (upgradeAPI and upgradeAPI.expBoostFactor and upgradeAPI.expBoostFactor()) or 1.0
    xp = math.floor(xp * boost + 0.5)
    levelAPI.addXP(xp, "craft")
    _recordProductXP(productName, xp)
  end
  return xp
end

-- ====== Sales XP ======
-- Sale multiplier = 1.0 (baseline) + additive stage bonuses for all UNLOCKED stages up to current
--                 + (craftXP / 10) as a decimal bonus derived from the recipe.
-- Grant = baseSaleXP (defaults to 1) * multiplier.
local function _sumUnlockedStageBonus()
  local flat = 1.0
  local unlocked = stageAPI.getUnlocked and stageAPI.getUnlocked() or {}
  for k, v in pairs(STAGE_PERM_SALE_BONUS) do
    if k ~= "lemonade" and unlocked[k] then flat = flat + v end
  end
  return flat
end

function levelAPI.saleMultiplierForProduct(productKey, stageKey)
  local stageFlat = _sumUnlockedStageBonus()   -- e.g., lemonade 1.0 baseline + unlocked stage adds
  local perProduct = _getProductMultiBase(productKey, stageKey)

  local boost = 1.0
  if upgradeAPI and upgradeAPI.expBoostFactor then
    boost = tonumber(upgradeAPI.expBoostFactor()) or 1.0
  end

  local productBonus = perProduct * boost
  return stageFlat + productBonus
end

function levelAPI.onSale(productKey, baseSaleXP, stageKey)
  if type(baseSaleXP) ~= "number" or baseSaleXP <= 0 then baseSaleXP = 10 end
  local mult = levelAPI.saleMultiplierForProduct(productKey, stageKey)
  local grant = baseSaleXP * mult
  levelAPI.addXP(grant, "sale")
  return grant, mult
end

-- Simple helpers for UI
function levelAPI.getProgress()
  local s = _ensure()
  local lvl, need, remainder = _recalc_level(s.level.xp or 0)
  return { level = lvl, xpInto = remainder, xpToNext = need }
end

function levelAPI.debugReset()
  local s = _ensure()
  s.level = { xp=0, level=1, products={} }
  saveAPI.save(s)
end


-- Configure/get base flat XP per sale
function levelAPI.setBaseSaleXP(n)
  if type(n) == "number" and n > 0 then BASE_SALE_XP = n end
end
function levelAPI.getBaseSaleXP()
  return BASE_SALE_XP
end

return levelAPI

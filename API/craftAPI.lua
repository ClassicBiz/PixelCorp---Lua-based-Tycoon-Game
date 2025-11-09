local craftAPI = {}

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
local inventoryAPI = require(root.."/API/inventoryAPI")
local economyAPI = require(root.."/API/economyAPI")
local itemsAPI = require(root.."/API/itemsAPI")
local saveAPI = require(root.."/API/saveAPI")
local stageAPI = require(root.."/API/stageAPI")
local levelAPI = require(root.."/API/levelAPI")
local upgradeAPI = require(root.."/API/upgradeAPI")

local RARITY_ORDER = { "common","uncommon","rare","unique","legendary","mythical","relic","masterwork","divine" }
local _ridx = {}; for i,r in ipairs(RARITY_ORDER) do _ridx[r]=i end

local function rarity_of(label_or_id)
  if not label_or_id or label_or_id=="None" then return "common" end
  local it = itemsAPI.getByName(label_or_id) or itemsAPI.getById(label_or_id)
  local r = (it and it.rarity) or itemsAPI.rarityByName(label_or_id) or "common"
  r = string.lower(r); return _ridx[r] and r or "common"
end

function craftAPI.determineProductRarity(baseName, fruitName, sweetName, toppingName)
  local max = 1
  for _,comp in ipairs({baseName, fruitName, sweetName, toppingName}) do
    if comp and comp~="None" then
      local ri = _ridx[rarity_of(comp)] or 1
      if ri > max then max = ri end
    end
  end
  return RARITY_ORDER[max] or "common"
end

function craftAPI.generateProductName(fruitName, sweetName, toppingName, productType)
  productType = productType or "Lemonade"
  local parts = {}
  if productType == "Italian Ice" then
    local sA = itemsAPI.aliasByName(sweetName)
    local tA = toppingName and itemsAPI.aliasByName(toppingName) or nil
    if sA and sA ~= "" then table.insert(parts, sA) end
    if tA and tA ~= "" and tA ~= "ice" and tA ~= "ice cubes" and tA ~= "shaved ice" then table.insert(parts, tA) end
    table.insert(parts, "Italian Ice")
    return table.concat(parts, " ")
  else
    local sweetAlias = itemsAPI.aliasByName(sweetName)
    local fruitAlias = itemsAPI.aliasByName(fruitName)
    local topAlias   = (toppingName and itemsAPI.aliasByName(toppingName)) or nil
    if sweetName ~= "Sugar" and sweetAlias and sweetAlias ~= "" then table.insert(parts, sweetAlias) end
    if fruitName ~= "Lemon" and fruitAlias and fruitAlias ~= "" then table.insert(parts, fruitAlias) end
    if topAlias and toppingName ~= "Ice Cubes" and toppingName ~= "None" then table.insert(parts, topAlias) end
    table.insert(parts, "Lemonade")
    return table.concat(parts, " ")
  end
end

local function _composeProductKey(productType, baseId, fruitId, sweetId, topId)
  local function nz(x) return x or "none" end
  local t = (productType or "Lemonade"):gsub("%s+","_"):lower()
  return ("drink:%s|base=%s|fruit=%s|sweet=%s|top=%s")
    :format(t, nz(baseId), nz(fruitId), nz(sweetId), nz(topId))
end

local function _prettyFromPackKey(key)
  local t, cont, cush, acc = key:match("^pack:(.-)|container=(.-)|cushion=(.-)|acc=(.-)$")
  if not t then return nil end

  local function name(id)
    if not id or id == "none" then return nil end
    return itemsAPI.nameById(id) or id
  end

  local parts = {}
  if cont and cont ~= "none" then table.insert(parts, itemsAPI.aliasById(cont) or name(cont)) end
  if acc  and acc  ~= "none" then table.insert(parts, itemsAPI.aliasById(acc)  or name(acc))  end
  table.insert(parts, "Pack")
  return table.concat(parts, " ")
end

function craftAPI.prettyNameFromKey(key)
  local drink = key:match("^drink:")
  if drink then
  local t, b, f, s, tp = key:match("^drink:(.-)|base=(.-)|fruit=(.-)|sweet=(.-)|top=(.-)$")
  if not t then return key end

  local function name(id)
    if not id or id == "none" then return nil end
    return itemsAPI.nameById(id) or id
  end

  local function normalizeProductType(raw)
    raw = raw or ""
    raw = raw:gsub("_", " "):lower()
    if raw == "italian ice" then return "Italian Ice" end
    return raw:gsub("^%l", string.upper)
  end

  local productType = normalizeProductType(t)
  local baseName    = name(b)
  local fruitName   = name(f)
  local sweetName   = name(s)
  local topName     = name(tp)

  return craftAPI.generateProductName(fruitName, sweetName, topName, productType)
    else
    local pretty = _prettyFromPackKey(key)
    if pretty then return pretty end
    return key
  end
end


local function labelToKey(label)
  if not label or label == "" then return nil end
  return itemsAPI.idByName(label)
end

function craftAPI.craftItem(productType, baseName, fruitName, sweetName, toppingName)
  local function trim(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
  local productTypeLabel = trim(productType)
  local ptLower          = productTypeLabel:lower()
  local isItalian        = (ptLower == "italian ice")
  local function labelToKeySafe(name)
    if not name or name == "" or name == "None" then return nil end
    return labelToKey(name)
  end
  local baseKey    = labelToKeySafe(baseName)
  local fruitKey   = labelToKeySafe(fruitName)
  local sweetKey   = labelToKeySafe(sweetName)
  local toppingKey = labelToKeySafe(toppingName)
  local cupsNeeded    = itemsAPI.craftReqByName(baseName) or 0
  local fruitNeeded   = itemsAPI.craftReqByName(fruitName) or 0
  local sweetNeeded   = itemsAPI.craftReqByName(sweetName) or 0
  local toppingNeeded = (toppingKey and itemsAPI.craftReqByName(toppingName)) or 0
  ---------------------------------------------------------------------------
  -- ITALIAN ICE BRANCH
  ---------------------------------------------------------------------------
  if isItalian then
    local iceId = itemsAPI.idByName("Ice Cubes")
    if not (upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution()) or not iceId then
      return false, "Italian Ice requires the Ice Shaver (and Ice Cubes)"
    end
    fruitKey    = iceId
    fruitName   = "Ice Cubes"
    fruitNeeded = 2

    if not (itemsAPI.isSyrup and itemsAPI.isSyrup(sweetKey or sweetName)) then
      return false, "Italian Ice requires a syrup/nectar/honey/molasses"
    end

    if toppingKey then
      local t = itemsAPI.getById(toppingKey) or itemsAPI.getByName(toppingName)
      if t and t.type == "fruit" then
        toppingNeeded = 1
      end
    end
  else
    -------------------------------------------------------------------------
    -- LEMONADE BRANCH
    -------------------------------------------------------------------------
    fruitNeeded = math.max(0, fruitNeeded + ((upgradeAPI and upgradeAPI.fruitReqDelta and upgradeAPI.fruitReqDelta()) or 0))
    if upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution() then
      if toppingName == "Shaved Ice" then
        local iceId = itemsAPI.idByName("Ice Cubes")
        if iceId then
        toppingKey    = iceId
        toppingName   = "Ice Cubes"
        toppingNeeded = 2
        end
      end
    end
  end

  local inv = (inventoryAPI.getPlayerInventory and inventoryAPI.getPlayerInventory()) or {}
  local haveBase  = tonumber(inv[baseKey]  or 0)
  local haveFruit = tonumber(inv[fruitKey] or 0)
  local haveSweet = tonumber(inv[sweetKey] or 0)
  local haveTop   = tonumber(inv[toppingKey] or 0)
  if (haveBase  < cupsNeeded)
    or (haveFruit < fruitNeeded)
    or (haveSweet < sweetNeeded)
    or (toppingKey and (haveTop < toppingNeeded)) then
    return false, "Not enough ingredients to craft."
  end

  inventoryAPI.add(baseKey,  -cupsNeeded)
  inventoryAPI.add(fruitKey, -fruitNeeded)
  inventoryAPI.add(sweetKey, -sweetNeeded)
  if toppingKey then inventoryAPI.add(toppingKey, -toppingNeeded) end

  local productKey   = _composeProductKey(productTypeLabel, baseKey, fruitKey, sweetKey, toppingKey)
  local productLabel = craftAPI.generateProductName(fruitName, sweetName, toppingName, productTypeLabel)

  inventoryAPI.add(productKey, 5)

  -- === XP/Leveling: compute rarities used and grant craft XP ===
  local rarities = {}
  local function rarityOf(label_or_id)
  if not label_or_id or label_or_id == "" or label_or_id == "None" then return "common" end
  local it = itemsAPI.getByName(label_or_id) or itemsAPI.getById(label_or_id)
  local r  = (it and it.rarity) or itemsAPI.rarityByName(label_or_id) or "common"
  r = string.lower(r)
  return r
  end
  table.insert(rarities, rarityOf(baseKey))
  table.insert(rarities, rarityOf(fruitKey))
  table.insert(rarities, rarityOf(sweetKey))
  if toppingKey then table.insert(rarities, rarityOf(toppingKey)) end

  local stageKey = (stageAPI and stageAPI.getCurrentStage and stageAPI.getCurrentStage()) or "lemonade"

  local craftXP = 0
  if levelAPI and levelAPI.onCraft then
  local ok, xp = pcall(function() return levelAPI.onCraft(productKey, rarities, stageKey) end)
  if ok and type(xp) == "number" then craftXP = xp end
  pcall(function() levelAPI.onCraft(productLabel, rarities, stageKey) end)
  end

  do
      local s = saveAPI.get()
      s.level = s.level or {}
      s.level.product_multi = s.level.product_multi or {}
      s.level.product_multi[productKey] = (tonumber(craftXP) or 0) / 10
      saveAPI.save(s)
  end

  return true, productKey, productLabel
end


function craftAPI.computeCraftPrice(baseLabel, fruitLabel, sweetLabel, toppingLabel)
  local function base(name)
    if not name or name == "" or name == "None" then return 0 end
    return tonumber(itemsAPI.baseValueByName(name)) or 0
  end
  return base(baseLabel) + base(fruitLabel) + base(sweetLabel) + base(toppingLabel)
end

function craftAPI.dismantleProduct(productName, quantity)
  if type(quantity) ~= "number" then quantity = 1 end
  local inv = inventoryAPI.getAll()
  if not inv[productName] or inv[productName] < quantity then return false, "Not enough product to dismantle" end
  inventoryAPI.add(productName, -quantity)
  inventoryAPI.add("cups", quantity)
  return true
end

return craftAPI

local itemsAPI = {}

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
local saveAPI = require(root.."/API/saveAPI")

local ITEMS_PATH = root.."/config/items.json"

local _cache = nil
local function _load()
  if _cache then return _cache end
  local f = fs.open(ITEMS_PATH, "r")
  if not f then error("itemsAPI: missing "..ITEMS_PATH) end
  local data = f.readAll()
  f.close()
  local ok, arr
  if textutils.unserializeJSON then
    ok, arr = pcall(textutils.unserializeJSON, data)
  else
    ok, arr = pcall(textutils.unserialize, data)
  end
  if not ok or type(arr) ~= "table" then error("itemsAPI: invalid JSON in "..ITEMS_PATH) end
  _cache = arr
  return _cache
end

local function _byId()
  local map = {}
  for _,it in ipairs(_load()) do map[it.id] = it end
  return map
end

local function _byName()
  local map = {}
  for _,it in ipairs(_load()) do map[it.name] = it end
  return map
end

-- Rarity weight table
local _RARITY_WEIGHT = {
  common=1.00, uncommon=0.85, rare=0.70, unique=0.55,
  legendary=0.40, mythical=0.28, relic=0.18, masterwork=0.12, divine=0.08
}


RARITY_COLOR = {
  common    = colors.gray,
  uncommon  = colors.lightGray,
  rare      = colors.green,
  unique    = colors.blue,
  legendary = colors.yellow,
  mythical  = colors.orange,
  relic     = colors.purple,
  masterwork= colors.magenta,
  divine    = colors.pink
}

-- === Alias helpers ===
local function _aliasOf(it)
  if not it then return nil end
  return (it.alias and tostring(it.alias)) or (it.name and tostring(it.name)) or it.id
end

function itemsAPI.aliasById(id)
  return _aliasOf(itemsAPI.getById(id)) or id
end

function itemsAPI.aliasByName(name)
  return _aliasOf(itemsAPI.getByName(name)) or name
end
function itemsAPI.marketValueRangeById(id)
  local it = itemsAPI.getById(id)
  if not it then return {min=1, max=1} end
  local mv = it.market_value
  if type(mv) == "table" and #mv >= 2 then
    return { min = tonumber(mv[1]) or 1, max = tonumber(mv[2]) or (tonumber(mv[1]) or 1) }
  end
  local base = tonumber(it.base_value or 1) or 1
  return { min = math.max(1, math.floor(base * 0.75)), max = math.max(1, math.ceil(base * 1.5)) }
end

function itemsAPI.itemRarityColor(id_or_item)
  local r = nil
  if not id_or_item then r = "common" end
  if type(id_or_item) == "table" then
    r = id_or_item.rarity or id_or_item.r or r
  elseif type(id_or_item) == "string" then
    if itemsAPI and itemsAPI.getById then
      local it = itemsAPI.getById(id_or_item)
      if it and it.rarity then r = it.rarity end
    end
    if not r and itemsAPI and itemsAPI.getByName then
      local it2 = itemsAPI.getByName(id_or_item)
      if it2 and it2.rarity then r = it2.rarity end
    end
  end
  r = (r and tostring(r):lower()) or "common"
  return RARITY_COLOR[r] or colors.white
end

function itemsAPI.rarityWeightById(id)
  local it = itemsAPI.getById(id)
  local r = it and string.lower(it.rarity or "common") or "common"
  return _RARITY_WEIGHT[r] or 1.0
end

function itemsAPI.getAll() return _load() end

function itemsAPI.getById(id)
  return _byId()[id]
end

function itemsAPI.getByName(name)
  return _byName()[name]
end

function itemsAPI.listByType(t)
  local out = {}
  for _,it in ipairs(_load()) do
    if it.type == t then table.insert(out, it) end
  end
  return out
end

function itemsAPI.isPurchasable(id)
  local it = itemsAPI.getById(id); return it and it.purchasable == true
end

function itemsAPI.marketPool()
  local pool = {}
  for _,it in ipairs(_load()) do
    if it.purchasable then
      pool[it.id] = { min = it.market_min or 0, max = it.market_max or 0 }
    end
  end
  return pool
end

function itemsAPI.craftReqByName(name)
  local it = itemsAPI.getByName(name); if not it then return 0 end
  return tonumber(it.craft_req or 0) or 0
end

function itemsAPI.baseValueByName(name)
  local it = itemsAPI.getByName(name); if not it then return 0 end
  return tonumber(it.base_value or 0) or 0
end

function itemsAPI.rarityByName(name)
  local it = itemsAPI.getByName(name); if not it then return "common" end
  return it.rarity or "common"
end

function itemsAPI.idByName(name)
  local it = itemsAPI.getByName(name); return it and it.id or nil
end

function itemsAPI.nameById(id)
  local it = itemsAPI.getById(id); return it and it.name or nil
end

function itemsAPI.levelReqById(id)
  local it = itemsAPI.getById(id)
  return it and (tonumber(it.level) or 0) or 0
end

function itemsAPI.isUnlockedForLevel(id, level)
  return (tonumber(level) or 0) >= itemsAPI.levelReqById(id)
end

function itemsAPI.baseValueById(id)
  local it = itemsAPI.getById(id)
  if not it then return 0 end
  return tonumber(it.base_value or 0) or 0
end

function itemsAPI.isSyrup(id_or_name)
  if not id_or_name then return false end
  local it = itemsAPI.getById(id_or_name) or itemsAPI.getByName(id_or_name)
  if not it then return false end
  local n = (it.name or it.id or ""):lower()
  return n:find("syrup", 1, true) or n:find("nectar", 1, true) or n:find("honey", 1, true) or n:find("molasses", 1, true)
end

return itemsAPI

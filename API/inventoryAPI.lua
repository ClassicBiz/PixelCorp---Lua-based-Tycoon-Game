local inventoryAPI = {}


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
local timeAPI    = require(root.."/API/timeAPI")
local economyAPI = require(root.."/API/economyAPI")
local itemsAPI   = require(root.."/API/itemsAPI")
local saveAPI    = require(root.."/API/saveAPI")

-- Business day rollover at 06:00
local function _effectiveDay()
  local day  = timeAPI.getDay and timeAPI.getDay() or nil
  local hour = timeAPI.getHour and timeAPI.getHour() or nil
  if day == nil or hour == nil then
    local s = saveAPI.get(); local t = s.time or {}
    day  = tonumber(t.day  or 0) or 0
    hour = tonumber(t.hour or 0) or 0
  end
  return (hour < 6) and math.max(0, day - 1) or day
end

local function _weekBucket(d) return math.floor((d or 0)/7) end

-- rarity-weighting
local BASE_SPAWN_CHANCE = 0.75
local MIN_QTY, MAX_QTY  = 1, 40
local function _shouldSpawn(weight)
  local p = BASE_SPAWN_CHANCE * (weight or 1.0)
  if p < 0.05 then p = 0.05 elseif p > 0.95 then p = 0.95 end
  return math.random() < p
end
local function _weightedQty(minQty, maxQty, weight)
  minQty = tonumber(minQty)
  maxQty = tonumber(maxQty)
  if maxQty < minQty then maxQty = minQty end
  local span = maxQty - minQty
  local cappedMax = minQty + math.floor(span * math.max(0, math.min(1, weight or 1)))
  if cappedMax < minQty then cappedMax = minQty end
  return math.random(minQty, cappedMax)
end

-- The one canonical refresher
local function _refreshMarketIfNeeded()
  local s = saveAPI.get()
  s.market = s.market or {}
  s.market.stock   = s.market.stock   or {}
  s.market.prices  = s.market.prices  or {}

  local effDay   = _effectiveDay()
  local weekBuck = _weekBucket(effDay)

  local lastStockDay  = tonumber(s.market.last_stock_day) or -9999
  local lastPriceBuck = tonumber(s.market.last_price_weekbuck) or -9999

  local needStockRefresh = (effDay   ~= lastStockDay)
  local needPriceRefresh = (weekBuck ~= lastPriceBuck)

  if not (needStockRefresh or needPriceRefresh) then return end

    for _, it in ipairs(itemsAPI.getAll()) do
        if it.purchasable then
            if needPriceRefresh then
                local band  = itemsAPI.marketValueRangeById(it.id)
                local price = math.random(band.min, band.max)
                s.market.prices[it.id] = price
                if economyAPI and economyAPI.setPrice then economyAPI.setPrice(it.id, price) end
            end
            if needStockRefresh then
                local minQ = tonumber(it.market_min)
                local maxQ = tonumber(it.market_max)
                if maxQ < minQ then maxQ = minQ end

                local mustSpawn = (minQ > 0)      -- <-- force spawn when min > 0
                local weight    = itemsAPI.rarityWeightById(it.id)
                local okSpawn   = mustSpawn or _shouldSpawn(weight)

                if okSpawn then
                    local qty = math.random(minQ, maxQ)   -- always respect [min,max]
                    s.market.stock[it.id] = qty
                else
                    s.market.stock[it.id] = 0
                end
            end
        end
    end
    if needPriceRefresh then s.market.last_price_weekbuck = weekBuck end
    if needStockRefresh then s.market.last_stock_day      = effDay   end
    saveAPI.save(s)
end



local function _ensure()
  local p = saveAPI.get().player
  p.inventory = p.inventory or {}
  -- initialize all items present in items.json
  for _, it in ipairs(itemsAPI.getAll()) do
    local id = it.id
    if p.inventory[id] == nil then p.inventory[id] = 0 end
  end
  saveAPI.save()
  return p.inventory
end


-- Item definitions with rarity
-- itemPool now from itemsAPI.marketPool()

function inventoryAPI.getAllStockItems()
  local out = {}
  for _, it in ipairs(itemsAPI.getAll()) do
    if it.purchasable then table.insert(out, it.id) end
  end
  table.sort(out)
  return out
end

local function _ensureInventory()
  local s = saveAPI.get()
  s.player = s.player or {}
  s.player.inventory = s.player.inventory or {}
  local inv = s.player.inventory
  -- seed every item in items.json
  for _, it in ipairs(itemsAPI.getAll()) do
    if inv[it.id] == nil then inv[it.id] = 0 end
  end
  saveAPI.save(s)
  return inv
end

-- Fix this: return player.inventory, not root .inventory
function inventoryAPI.getPlayerInventory()
    return _ensureInventory()
end

function inventoryAPI.getAll()
  local inv = _ensureInventory()
  local out = {}
  for k, v in pairs(inv) do out[k] = tonumber(v) or 0 end
  -- in case new items were added to JSON after save
  for _, it in ipairs(itemsAPI.getAll()) do
    if out[it.id] == nil then out[it.id] = 0 end
  end
  return out
end

local function _ensureMarket(stage)
    local market = saveAPI.get().market or {}
    market[stage] = market[stage] or { availableStock = {}, lastRefreshedDay = -1 }
    saveAPI.get().market = market
    return market[stage]
end

function inventoryAPI.getQty(item)
    return _ensureInventory()[item] or 0
end

function inventoryAPI.setQty(item, qty)
    _ensureInventory()[item] = math.max(0, qty or 0)
    saveAPI.save()
end

function inventoryAPI.add(item, amount)
    local inv = _ensureInventory()
    inv[item] = math.max(0, (inv[item] or 0) + (amount or 0))
    saveAPI.save()
    return inv[item]
end

function inventoryAPI.getAvailableStock()
  _refreshMarketIfNeeded()
  local s = saveAPI.get(); s.market = s.market or {}; s.market.stock = s.market.stock or {}
  return s.market.stock
end

function inventoryAPI.getMarketPrice(id)
  _refreshMarketIfNeeded()
  local s = saveAPI.get(); s.market = s.market or {}; s.market.prices = s.market.prices or {}
  local p = s.market.prices[id]
  if type(p) ~= "number" or p < 1 then
    local band = itemsAPI.marketValueRangeById(id)
    p = math.max(1, math.random(band.min, band.max))
    s.market.prices[id] = p
    saveAPI.save(s)
    if economyAPI and economyAPI.setPrice then economyAPI.setPrice(id, p) end
  end
  return p
end

function inventoryAPI.refreshMarketStock(_effDay)
  -- We ignore the param and just perform the modern refresh
  _refreshMarketIfNeeded()
  -- Returning the current stock can be handy for callers that used the old return.
  return inventoryAPI.getAvailableStock()
end


function inventoryAPI.buyFromMarket(id, qty)
  _refreshMarketIfNeeded()
  local s = saveAPI.get()
  s.market = s.market or {}; s.market.stock = s.market.stock or {}; s.market.prices = s.market.prices or {}
  s.player = s.player or {}; s.player.inventory = s.player.inventory or {}
  qty = math.max(1, tonumber(qty) or 1)

  local available = tonumber(s.market.stock[id] or 0) or 0
  if available < qty then return false, "Not enough stock." end

  local price = inventoryAPI.getMarketPrice(id)  -- single source of truth
  local cost  = price * qty
  local ok = (economyAPI and economyAPI.spendMoney and economyAPI.spendMoney(cost, ("Buy %s x%d"):format(itemsAPI.nameById(id) or id, qty)))
  if not ok then return false, "Insufficient funds." end

  s.market.stock[id] = available - qty
  s.player.inventory[id] = (tonumber(s.player.inventory[id] or 0) or 0) + qty
  saveAPI.save(s)
  return true, ("Purchased for $%d."):format(cost)
end

return inventoryAPI

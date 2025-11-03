local economyAPI = {}

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

-- Weekly-fluctuating ranges for BASE MATERIALS only
local PRICES = {
  lemons = { min = 2, max = 4 },
  sugar  = { min = 1, max = 3 },
  cups   = { min = 1, max = 2 },
  ice    = { min = 1, max = 2 }
}

-- Local cache for ad-hoc product prices (session only; persistence lives in saveAPI)
local productPrices = {}

-- --- Weekly material price table generation ---
local function reseedPrices()
  local seed = math.floor(os.epoch("utc") / (1000 * 60 * 60 * 24 * 7)) -- change weekly
  math.randomseed(seed)
  local p = {}
  for item, range in pairs(PRICES) do
    p[item] = math.random(range.min, range.max)
  end
  return p
end

local function ensurePriceTable()
  local s = saveAPI.get()
  s.meta = s.meta or {}
  s.meta.prices = s.meta.prices or reseedPrices()
  saveAPI.setState(s)
  return s.meta.prices
end

-- --- Public API ---

-- Returns a price for either a crafted PRODUCT or a MATERIAL:
-- 1) If a product price exists in save (s.economy.prices[name]) -> use it
-- 2) Else if cached in this session -> use cache
-- 3) Else if it’s a base material -> use weekly table
-- 4) Else -> 0
function economyAPI.getPrice(name)
  local s = saveAPI.get()
  local ep = (s.economy and s.economy.prices) or {}
  if ep[name] ~= nil then return ep[name] end
  if productPrices[name] ~= nil then return productPrices[name] end

  -- Fall back to material weekly prices
  local weekly = ensurePriceTable()
  return weekly[name] or 0
end

-- Sets a PRODUCT price and persists it
function economyAPI.setPrice(name, price)
  productPrices[name] = tonumber(price) or 0
  local s = saveAPI.get()
  s.economy = s.economy or {}
  s.economy.prices = s.economy.prices or {}
  s.economy.prices[name] = productPrices[name]
  saveAPI.setState(s)
end

function economyAPI.reseedWeekly()
  local s = saveAPI.get()
  s.meta = s.meta or {}
  s.meta.prices = reseedPrices()
  saveAPI.setState(s)
end

-- Money helpers (unchanged behavior)
function economyAPI.addMoney(amount, reason)
  local current = saveAPI.getPlayerMoney()
  saveAPI.setPlayerMoney(current + (amount or 0))
--  print("[Income] +$" .. tostring(amount or 0) .. " - " .. (reason or ""))
end

function economyAPI.spendMoney(amount, reason)
  amount = tonumber(amount) or 0
  local current = saveAPI.getPlayerMoney()
  if current < amount then return false, "Not enough funds." end
  saveAPI.setPlayerMoney(current - amount)
  --print("[Expense] -$" .. amount .. " - " .. (reason or ""))
  return true
end

function economyAPI.getBalance()
  return saveAPI.getPlayerMoney()
end

function economyAPI.canAfford(amount)
  return saveAPI.getPlayerMoney() >= (tonumber(amount) or 0)
end

return economyAPI

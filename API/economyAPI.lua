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

local function round2(x) x = tonumber(x) or 0; return math.floor(x*100 + 0.5)/100 end
local function ceil2(x)  x = tonumber(x) or 0; return math.ceil(x*100)/100 end

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


-- ===== Loans =====
-- Stored under saveAPI state: s.finance.loans.active = array of loan objects
local function _ensureFinance()
  local s = saveAPI.get()
  s.finance = s.finance or {}
  s.finance.loans = s.finance.loans or { active = {} }

  -- normalize to a single active loan
  local act = s.finance.loans.active or {}
  -- prefer the last unpaid loan (if any), else keep the newest paid (harmless)
  local keep
  for i = #act, 1, -1 do
    local L = act[i]
    if (tonumber(L.remaining_principal or 0) or 0) > 0 then keep = L; break end
  end
  keep = keep or act[#act]
  if keep then s.finance.loans.active = { keep } else s.finance.loans.active = {} end

  saveAPI.setState(s)
  return s.finance.loans
end

local function _today()
  local s = saveAPI.get(); local t = s.time or {year=1,month=1,day=1}
  return { year=t.year, month=t.month, day=t.day }
end

-- Create a weekly loan with flat daily principal and simple daily interest on that principal slice.
-- params: { id, name, principal, days=7, interest=0.20, unlockLevel=1, unlockStage="lemonade_stand" }
function economyAPI.createLoan(params)
  params = params or {}
  local loans = _ensureFinance()

  -- block if an unpaid loan exists
  for _, L in ipairs(loans.active) do
    if (tonumber(L.remaining_principal or 0) or 0) > 0 then
      return false, "Active loan exists"
    end
  end

  local principal = tonumber(params.principal or 0) or 0
  if principal <= 0 then return false, "Invalid principal" end

  local days = tonumber(params.days or 7) or 7
  local dailyPrincipal = ceil2(principal / days)         -- 2-dec, ceilings
  if dailyPrincipal <= 0 then dailyPrincipal = 0.01 end  -- avoid zero slice

  local loan = {
    id = tostring(params.id or ("LN"..tostring(os.epoch("utc")%100000))),
    name = params.name or "Loan",
    principal = principal,
    remaining_principal = principal,
    baseDaily = dailyPrincipal,          -- keep legacy name for UI
    dailyPrincipal = dailyPrincipal,     -- new explicit field
    interest = tonumber(params.interest or 0) or 0.0, -- e.g., 0.20
    days_total = days,
    days_paid = 0,
    started_on = (function()
      local t = saveAPI.get().time or {year=1,month=1,day=1}
      return { year=t.year, month=t.month, day=t.day }
    end)(),
    stage = params.unlockStage or "lemonade_stand",
    unlockLevel = tonumber(params.unlockLevel or 1) or 1,
  }

  loans.active = { loan }                 -- enforce single-loan array
  economyAPI.addMoney(principal, "Loan proceeds")  -- credit funds
  saveAPI.save()
  return true, loan.id
end

function economyAPI.hasActiveLoan()
  local loans = _ensureFinance()
  for _, L in ipairs(loans.active) do
    if (tonumber(L.remaining_principal or 0) or 0) > 0 then return true end
  end
  return false
end

function economyAPI.listLoans()
  local loans = _ensureFinance()
  return loans.active
end

function economyAPI.getLoanById(id)
  for _, L in ipairs(economyAPI.listLoans()) do if L.id == id then return L end end
  return nil
end

-- Attempt to process one day's payment for all loans. Uses current player money.
-- Daily charge = baseDaily + baseDaily*interest; principal reduced by baseDaily only.
function economyAPI.processDailyLoans()
  local loans = _ensureFinance()
  local paid_any = false

  for _, L in ipairs(loans.active) do
    local rem = tonumber(L.remaining_principal or 0) or 0
    if rem > 0 and (L.days_paid or 0) < (L.days_total or 7) then
      local dp = tonumber(L.dailyPrincipal or L.baseDaily or 0) or 0
      if dp <= 0 then
        dp = ceil2((tonumber(L.principal or 0) or 0) / (tonumber(L.days_total or 7) or 7))
        L.dailyPrincipal, L.baseDaily = dp, dp
      end
      local slice  = math.min(dp, rem)                -- last day clamps
      local rate   = tonumber(L.interest or 0) or 0
      local charge = round2(slice * (1 + rate))       -- cents

      if charge > 0 and economyAPI.canAfford(charge) then
        economyAPI.spendMoney(charge, "Loan daily payment")
        L.remaining_principal = round2(rem - slice)
        if L.remaining_principal < 0 then L.remaining_principal = 0 end
        L.days_paid = (L.days_paid or 0) + 1
        paid_any = true
      end
    end
  end

  if paid_any then saveAPI.save() end
  return paid_any
end

-- Pay off a specific loan immediately (principal only; no future interest)
function economyAPI.payoffLoan(loanId)
  local loans = _ensureFinance()
  for i, L in ipairs(loans.active) do
    if L.id == loanId then
      local due = tonumber(L.remaining_principal or 0) or 0
      if due <= 0 then return false, "Already paid" end
      if not economyAPI.canAfford(due) then return false, "Not enough funds" end
      economyAPI.spendMoney(due, "Loan payoff")
      L.remaining_principal = 0
      L.days_paid = L.days_total
      saveAPI.save()
      return true, "Loan paid"
    end
  end
  return false, "Loan not found"
end

-- Remove fully paid loans (housekeeping)
function economyAPI.cleanupLoans()
  local loans = _ensureFinance()
  local keep = {}
  for _, L in ipairs(loans.active) do
    if (tonumber(L.remaining_principal or 0) or 0) > 0 then table.insert(keep, L) end
  end
  loans.active = keep
  if #loans.active > 1 then loans.active = { loans.active[#loans.active] } end
  saveAPI.save()
end

return economyAPI

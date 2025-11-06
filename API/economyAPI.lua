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

local function round2(x) x = tonumber(x) or 0; return math.floor(x*100 + 0.5)/100 end
local function ceil2(x)  x = tonumber(x) or 0; return math.ceil(x*100)/100 end

function economyAPI.getPrice(name)
  local s = saveAPI.get()
  local ep = (s.economy and s.economy.prices) or {}
  if ep[name] ~= nil then return ep[name] end
  if productPrices[name] ~= nil then return productPrices[name] end
  local weekly = ensurePriceTable()
  return weekly[name] or 0
end

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

-- Money helpers
function economyAPI.getMoney()
  return saveAPI.getPlayerMoney()
end

function economyAPI.addMoney(amount, reason)
  local current = saveAPI.getPlayerMoney()
  saveAPI.setPlayerMoney(current + (amount or 0))
end

function economyAPI.spendMoney(amount, reason)
  amount = tonumber(amount) or 0
  local current = saveAPI.getPlayerMoney()
  if current < amount then return false, "Not enough funds." end
  saveAPI.setPlayerMoney(current - amount)
  return true
end

function economyAPI.getBalance()
  return saveAPI.getPlayerMoney()
end

function economyAPI.canAfford(amount)
  return saveAPI.getPlayerMoney() >= (tonumber(amount) or 0)
end

-- ===== Loans =====
local function _ensureFinance()
  local s = saveAPI.get()
  s.finance = s.finance or {}
  s.finance.loans = s.finance.loans or { active = {} }

  -- normalize to a single active loan (keep most recent unpaid if multiple exist)
  local act = s.finance.loans.active or {}
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

-- Create loan
function economyAPI.createLoan(params)
  params = params or {}
  local loans = _ensureFinance()

  for _, L in ipairs(loans.active) do
    if (tonumber(L.remaining_principal or 0) or 0) > 0 then
      return false, "Active loan exists"
    end
  end

  local principal = tonumber(params.principal or 0) or 0
  if principal <= 0 then return false, "Invalid principal" end

  local days = tonumber(params.days or 7) or 7
  local dailyPrincipal = ceil2(principal / days)
  if dailyPrincipal <= 0 then dailyPrincipal = 0.01 end

  local loan = {
    id = tostring(params.id or ("LN"..tostring(os.epoch("utc")%100000))),
    name = params.name or "Loan",
    principal = principal,
    remaining_principal = principal,
    baseDaily = dailyPrincipal,
    dailyPrincipal = dailyPrincipal,
    interest = tonumber(params.interest or 0) or 0.0,
    days_total = days,
    days_paid = 0,
    started_on = (function()
      local t = saveAPI.get().time or {year=1,month=1,day=1}
      return { year=t.year, month=t.month, day=t.day }
    end)(),
    stage = params.unlockStage or "lemonade_stand",
    unlockLevel = tonumber(params.unlockLevel or 1) or 1,
  }

  loans.active = { loan }
  economyAPI.addMoney(principal, "Loan proceeds")
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
      local slice  = math.min(dp, rem)
      local rate   = tonumber(L.interest or 0) or 0
      local charge = round2(slice * (1 + rate))

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

-- ===== Stocks =====
local function _ensureStocks()
  local s = saveAPI.get()
  s.finance = s.finance or {}
  s.finance.stocks = s.finance.stocks or { defs = nil, last = {}, hist = {}, holdings = {}, state = {}, seeded = false }
  local M = s.finance.stocks

  -- one-time RNG seed
  if not M.seeded then
    math.randomseed((os.epoch and os.epoch("utc") or os.clock()*1000) % 2^31)
    M.seeded = true
  end

  -- define tickers once
  if not M.defs then
    M.defs = {
      { sym="SHQ", name="SharkQ",   min=20,  max=400  },
      { sym="GLX", name="Galaxia",  min=40,  max=900  },
      { sym="VTX", name="Vertex",   min=60,  max=1500 },
      { sym="ATC", name="Aetica",   min=200, max=3000 },
    }
  end

  -- ensure per-symbol structures always exist (even across updates)
  M.last     = M.last     or {}
  M.hist     = M.hist     or {}
  M.holdings = M.holdings or {}
  M.state    = M.state    or {}

  for _, d in ipairs(M.defs) do
    local sym = d.sym
    local mid = (d.min + d.max) * 0.5

    -- start a little off the dead center so the first chart isn’t flat
    if M.last[sym] == nil then
      local jitter = (math.random() - 0.5) * (d.max - d.min) * 0.02  -- ~±2% of range
      M.last[sym] = mid + jitter
    end

    if M.hist[sym] == nil then
      M.hist[sym] = {}
      for i = 1, 30 do table.insert(M.hist[sym], M.last[sym]) end
    end

    if M.holdings[sym] == nil then
      M.holdings[sym] = 0
    end

    -- NEW: per-symbol simulation state (trend / volatility / shock)
    if M.state[sym] == nil then
      M.state[sym] = {
        trend = 0.0,   -- persistent drift per step
        vol   = 1.0,   -- volatility multiplier
        shock = 0.0,   -- transient jump/dip that decays
      }
    end
  end

  saveAPI.setState(s)
  return M
end

function economyAPI.stepStocks()
  local M = _ensureStocks()

  -- Tunables (feel free to tweak)
  local TREND_PERSIST   = 0.90   -- how much of last trend carries forward
  local TREND_NUDGE     = 0.06   -- random nudge applied to trend each step (scaled by range)
  local VOL_MEANREV     = 0.95   -- vol moves toward 1.0
  local VOL_JITTER      = 0.08   -- random vol perturbation
  local BASE_NOISE_PCT  = 0.007  -- baseline noise as % of (max-min) per step
  local STEP_CAP_PCT    = 0.06   -- cap total one-step move as % of (max-min)
  local EPS_PCT         = 0.02   -- keep at least 2% away from hard min/max
  local SHOCK_PROB      = 0.03   -- 3% chance per step of a shock event
  local SHOCK_MAG_PCT   = 0.10   -- shock size up to 10% of range
  local SHOCK_DECAY     = 0.80   -- shock decays by 20% each step

  for _, d in ipairs(M.defs) do
    local sym, minP, maxP = d.sym, d.min, d.max
    local range = (maxP - minP)
    local mid   = (minP + maxP) * 0.5
    local eps   = range * EPS_PCT

    local p0    = tonumber(M.last[sym] or mid) or mid
    local S     = (M.state and M.state[sym]) or { trend=0.0, vol=1.0, shock=0.0 }
    M.state     = M.state or {}
    M.state[sym]= S

    -- 1) persistent trend (AR(1) w/ small random nudge)
    local nudge = (math.random() - 0.5) * (range * TREND_NUDGE)
    S.trend = TREND_PERSIST * S.trend + nudge

    -- bias trend slightly by distance from mid so we can get prolonged runs,
    -- but still not anchor too hard to the midpoint
    local bias = (p0 - mid) / range      -- -0.5..+0.5 roughly
    S.trend = S.trend - bias * (range * 0.01)  -- gentle tug back

    -- 2) volatility regime (vol wanders around 1.0)
    S.vol = VOL_MEANREV * S.vol + (1 - VOL_MEANREV) * 1.0
    S.vol = S.vol + (math.random() - 0.5) * VOL_JITTER
    if S.vol < 0.5 then S.vol = 0.5 end
    if S.vol > 2.0 then S.vol = 2.0 end

    -- 3) rare shock (positive or negative), then decays
    if math.random() < SHOCK_PROB and math.abs(S.shock) < range * 0.02 then
      local dir = (math.random() < 0.5) and -1 or 1
      S.shock = dir * (range * (math.random() * SHOCK_MAG_PCT))
    else
      S.shock = S.shock * SHOCK_DECAY
      if math.abs(S.shock) < 0.001 then S.shock = 0.0 end
    end

    -- 4) base noise scaled by vol
    local baseNoise = (math.random() - 0.5) * (range * BASE_NOISE_PCT) * S.vol

    -- Proposed move
    local delta = S.trend + baseNoise + S.shock

    -- Cap total one-step move
    local cap = range * STEP_CAP_PCT
    if delta >  cap then delta =  cap end
    if delta < -cap then delta = -cap end

    local p1 = p0 + delta

    -- 5) soft bounds + bounce the trend if we get close to edges
    if p1 < (minP + eps) then
      p1 = minP + eps
      S.trend = math.abs(S.trend)        -- bounce upward
      S.shock = 0.0
    elseif p1 > (maxP - eps) then
      p1 = maxP - eps
      S.trend = -math.abs(S.trend)       -- bounce downward
      S.shock = 0.0
    end

    -- write back
    M.last[sym] = p1
    local H = M.hist[sym]; table.insert(H, p1); if #H > 60 then table.remove(H, 1) end  -- keep 60 pts now
  end

  saveAPI.save()
end

function economyAPI.getStocks()
  local M = _ensureStocks()
  local out = {}
  for _,d in ipairs(M.defs) do
    table.insert(out, { sym=d.sym, name=d.name, price=M.last[d.sym], min=d.min, max=d.max })
  end
  return out
end

function economyAPI.getStock(sym)
  local M = _ensureStocks()
  sym = tostring(sym)
  local p = M.last[sym]; local h = M.hist[sym] or {}
  return { price=p, history=h, qty=(M.holdings[sym] or 0) }
end

function economyAPI.buyStock(sym, qty)
  local M = _ensureStocks(); sym = tostring(sym); qty = math.max(1, math.floor(qty or 0))
  local price = M.last[sym]; if not price then return false, "Unknown symbol" end
  local cost  = round2(price * qty)
  if not economyAPI.canAfford(cost) then return false, "Insufficient funds" end
  economyAPI.spendMoney(cost, "Buy "..sym)
  M.holdings[sym] = (M.holdings[sym] or 0) + qty
  saveAPI.save()
  return true, qty
end

function economyAPI.buyMax(sym)
  local M = _ensureStocks(); sym = tostring(sym)
  local price = M.last[sym]; if not price or price <= 0 then return false, "Bad price" end
  local cash = economyAPI.getMoney()
  local qty  = math.floor(cash / price)
  if qty <= 0 then return false, "Insufficient funds" end
  return economyAPI.buyStock(sym, qty)
end

function economyAPI.sellStock(sym, qty)
  local M = _ensureStocks(); sym = tostring(sym); qty = math.max(1, math.floor(qty or 0))
  local have = M.holdings[sym] or 0
  if qty > have then return false, "Not enough shares" end
  local price = M.last[sym] or 0
  local proceeds = round2(price * qty)
  M.holdings[sym] = have - qty
  economyAPI.addMoney(proceeds, "Sell "..sym)
  saveAPI.save()
  return true, qty
end

function economyAPI.sellAll(sym)
  local M = _ensureStocks(); sym = tostring(sym)
  local have = M.holdings[sym] or 0
  if have <= 0 then return false, "No shares" end
  return economyAPI.sellStock(sym, have)
end

return economyAPI

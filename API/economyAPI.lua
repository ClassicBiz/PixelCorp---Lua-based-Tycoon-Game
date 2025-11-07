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
local saveAPI      = require(root.."/API/saveAPI")
local settingsOK, settingsAPI = pcall(require, root.."/API/settingsAPI")

-- Example market (kept simple)
local PRICES = { lemons={min=2,max=4}, sugar={min=1,max=3}, cups={min=1,max=2}, ice={min=1,max=2} }
local productPrices = {}

-- Difficulty-biased random sampler
local function _biased(minv, maxv)
  local r = math.random()
  local bias = (settingsAPI.stockBias and settingsAPI.stockBias()) or 0
  if bias == "low"  then r = r*r           -- weights toward 0 -> lower prices
  elseif bias == "high" then r = 1 - (r*r) -- weights toward 1 -> higher prices
  end
  return math.floor( minv + (maxv - minv) * r + 0.5 )
end

local function reseedPrices()
  local seed = math.floor(os.epoch("utc") / (1000 * 60 * 60 * 24 * 7))
  math.randomseed(seed)
  local p = {}
  for item, range in pairs(PRICES) do
    p[item] = _biased(range.min, range.max)
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

function economyAPI.getMoney() return saveAPI.getPlayerMoney() end
function economyAPI.addMoney(amount) saveAPI.setPlayerMoney(saveAPI.getPlayerMoney() + (amount or 0)) end
function economyAPI.spendMoney(amount)
  amount = tonumber(amount) or 0
  local current = saveAPI.getPlayerMoney()
  if current < amount then return false, "Not enough funds." end
  saveAPI.setPlayerMoney(current - amount); return true
end
function economyAPI.getBalance() return saveAPI.getPlayerMoney() end
function economyAPI.canAfford(amount) return saveAPI.getPlayerMoney() >= (tonumber(amount) or 0) end

-- ===== Loans =====
local function _ensureFinance()
  local s = saveAPI.get()
  s.finance = s.finance or {}
  s.finance.loans = s.finance.loans or { active = {} }
  local act = s.finance.loans.active or {}
  local keep; for i = #act, 1, -1 do local L = act[i]; if (tonumber(L.remaining_principal or 0) or 0) > 0 then keep = L; break end end
  keep = keep or act[#act]
  if keep then s.finance.loans.active = { keep } else s.finance.loans.active = {} end
  saveAPI.setState(s); return s.finance.loans
end

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

  local rate = tonumber(params.interest or 0)
  if not rate and settingsOK and settingsAPI.loanInterest then
    rate = settingsAPI.loanInterest()
  end
  if not rate then rate = 0.20 end

  local loan = {
    id = tostring(params.id or ("LN"..tostring(os.epoch("utc")%100000))),
    name = params.name or "Loan",
    principal = principal,
    remaining_principal = principal,
    baseDaily = dailyPrincipal,
    dailyPrincipal = dailyPrincipal,
    interest = rate,
    days_total = days, days_paid = 0,
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
  for _, L in ipairs(economyAPI.listLoans()) do
    if (L.remaining_principal or 0) > 0 then return true end
  end
  return false
end
function economyAPI.listLoans() return _ensureFinance().active end
function economyAPI.getLoanById(id) for _,L in ipairs(economyAPI.listLoans()) do if L.id == id then return L end end end

function economyAPI.processDailyLoans()
  local loans = _ensureFinance()
  local paid_any = false
  for _, L in ipairs(loans.active) do
    local rem = tonumber(L.remaining_principal or 0) or 0
    if rem > 0 and (L.days_paid or 0) < (L.days_total or 7) then
      local dp = tonumber(L.dailyPrincipal or L.baseDaily or 0) or 0
      if dp <= 0 then dp = ceil2((tonumber(L.principal or 0) or 0) / (tonumber(L.days_total or 7) or 7)); L.dailyPrincipal = dp; L.baseDaily = dp end
      local slice  = math.min(dp, rem)
      local rate   = tonumber(L.interest or 0) or 0
      local charge = round2(slice * (1 + rate))
      if charge > 0 and economyAPI.canAfford(charge) then
        economyAPI.spendMoney(charge, "Loan daily payment")
        L.remaining_principal = round2(rem - slice); if L.remaining_principal < 0 then L.remaining_principal = 0 end
        L.days_paid = (L.days_paid or 0) + 1; paid_any = true
      end
    end
  end
  if paid_any then saveAPI.save() end
  return paid_any
end

function economyAPI.payoffLoan(loanId)
  local loans = _ensureFinance()
  for _, L in ipairs(loans.active) do
    if L.id == loanId then
      local due = tonumber(L.remaining_principal or 0) or 0
      if due <= 0 then return false, "Already paid" end
      if not economyAPI.canAfford(due) then return false, "Not enough funds" end
      economyAPI.spendMoney(due, "Loan payoff")
      L.remaining_principal = 0; L.days_paid = L.days_total; saveAPI.save(); return true, "Loan paid"
    end
  end
  return false, "Loan not found"
end

function economyAPI.cleanupLoans()
  local loans = _ensureFinance()
  local keep = {}
  for _, L in ipairs(loans.active) do if (tonumber(L.remaining_principal or 0) or 0) > 0 then table.insert(keep, L) end end
  loans.active = keep; if #loans.active > 1 then loans.active = { loans.active[#loans.active] } end
  saveAPI.save()
end

-- ===== Stocks =====
local function _ensureStocks()
  local s = saveAPI.get()
  s.finance = s.finance or {}
  s.finance.stocks = s.finance.stocks or { defs = nil, last = {}, hist = {}, holdings = {}, state = {}, seeded = false }
  local M = s.finance.stocks

  if not M.seeded then
    math.randomseed((os.epoch and os.epoch("utc") or os.clock()*1000) % 2^31)
    M.seeded = true
  end

  if not M.defs then
    M.defs = {
      { sym="SHQ", name="SharkQ",   min=20,  max=400  },
      { sym="GLX", name="Galaxia",  min=40,  max=900  },
      { sym="VTX", name="Vertex",   min=60,  max=1500 },
      { sym="ATC", name="Aetica",   min=200, max=3000 },
    }
  end
  M.last     = M.last     or {}
  M.hist     = M.hist     or {}
  M.holdings = M.holdings or {}
  M.state    = M.state    or {}
  for _, d in ipairs(M.defs) do
    local sym = d.sym
    local mid = (d.min + d.max) * 0.5
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

  -- Regime + randomness tunables
  local BASE_NOISE_PCT  = 0.010  -- baseline noise (↑ from 0.007)
  local STEP_CAP_PCT    = 0.08   -- max move per step (↑ from 0.06)
  local EPS_PCT         = 0.02   -- soft distance from min/max
  local SHOCK_PROB      = 0.04   -- shock chance (↑ from 0.03)
  local SHOCK_MAG_PCT   = 0.12   -- shock size (↑ from 0.10)
  local SHOCK_DECAY     = 0.78   -- shock decay

  -- Two regimes: 0=calm, 1=storm. Storm has higher vol + looser trend persistence.
  local REGIME_P        = { calm = 0, storm = 1 }
  local REGIME_PERSIST  = { [0]=0.95, [1]=0.88 }  -- trend persistence by regime
  local REGIME_VOLJIT   = { [0]=0.06, [1]=0.12 }  -- vol jitter by regime
  local REGIME_NOISE    = { [0]=1.0,  [1]=1.8  }  -- noise multiple by regime
  local REGIME_SWITCH_P = { toStorm=0.06, toCalm=0.08 } -- Markov switch per step

  for _, d in ipairs(M.defs) do
    local sym, minP, maxP = d.sym, d.min, d.max
    local range = (maxP - minP); if range <= 0 then range = 1 end
    local mid   = (minP + maxP) * 0.5
    local eps   = range * EPS_PCT

    local p0    = tonumber(M.last[sym] or mid) or mid
    local S     = M.state[sym]
    S.regime = (S.regime ~= nil) and S.regime or REGIME_P.calm
    S.flipAge = (S.flipAge or 0) + 1

    if S.regime == REGIME_P.calm then
      if math.random() < REGIME_SWITCH_P.toStorm then S.regime = REGIME_P.storm end
    else
      if math.random() < REGIME_SWITCH_P.toCalm then S.regime = REGIME_P.calm end
    end

    local TREND_PERSIST = REGIME_PERSIST[S.regime]
    local TREND_NUDGE   = 0.08                              -- ↑ from 0.06
    local nudge         = (math.random() - 0.5) * (range * TREND_NUDGE)

    local bias = (p0 - mid) / range
    S.trend = TREND_PERSIST * (S.trend or 0) + nudge - bias * (range * 0.008)

    local baseFlipP = 0.015
    local hazard    = math.min(0.20, baseFlipP * (1 + S.flipAge / 8))  -- caps at 20%
    if math.random() < hazard then
      S.trend = -S.trend * (0.7 + math.random() * 0.5) -- flip & damp a bit
      S.flipAge = 0
    end
    local VOL_MEANREV = 0.94
    local VOL_JITTER  = REGIME_VOLJIT[S.regime]
    S.vol = VOL_MEANREV * (S.vol or 1.0) + (1 - VOL_MEANREV) * 1.0
    S.vol = S.vol + (math.random() - 0.5) * VOL_JITTER
    if S.vol < 0.5 then S.vol = 0.5 elseif S.vol > 2.2 then S.vol = 2.2 end
    if math.random() < SHOCK_PROB and math.abs(S.shock or 0) < range * 0.025 then
      local dir = (math.random() < 0.5) and -1 or 1
      S.shock = dir * (range * (0.5 + math.random()*0.5) * SHOCK_MAG_PCT) -- 50–100% of MAG
    else
      S.shock = (S.shock or 0) * SHOCK_DECAY
      if math.abs(S.shock) < 0.001 then S.shock = 0.0 end
    end
    local noiseMul = REGIME_NOISE[S.regime]
    local baseNoise = (math.random() - 0.5) * (range * BASE_NOISE_PCT) * S.vol * noiseMul
    local delta = S.trend + baseNoise + S.shock
    local cap   = range * STEP_CAP_PCT
    if delta >  cap then delta =  cap end
    if delta < -cap then delta = -cap end
    local p1 = p0 + delta
    if p1 < (minP + eps) then
      p1 = minP + eps
      S.trend = math.abs(S.trend or 0) * (0.6 + math.random()*0.5)
      S.shock = 0.0
      S.flipAge = 0
    elseif p1 > (maxP - eps) then
      p1 = maxP - eps
      S.trend = -math.abs(S.trend or 0) * (0.6 + math.random()*0.5)
      S.shock = 0.0
      S.flipAge = 0
    end
    M.last[sym] = p1
    local H = M.hist[sym]; table.insert(H, p1); if #H > 60 then table.remove(H, 1) end
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

-- ===== Bank =====
local function _ensureBank()
  local s = saveAPI.get()
  s.finance = s.finance or {}
  local daily = (settingsAPI.bankDailyRate and settingsAPI.bankDailyRate()) or 0.003
  s.finance.bank = s.finance.bank or { savings = 0, last_interest_day = 0, interest_rate_daily = daily }
  s.finance.bank.interest_rate_daily = daily
  return s.finance.bank, s
end

local function _bankDayIndex(t)
  if not t then return 0 end
  local y = tonumber(t.year or 0) or 0
  local m = tonumber(t.month or 1) or 1
  local d = tonumber(t.day or 1) or 1
  return y*360 + (m-1)*30 + (d-1)
end

function economyAPI.accrueSavingsInterest()
  local B, s = _ensureBank()
  local nowIdx = _bankDayIndex(s.time)
  if (B.last_interest_day or 0) == nowIdx then return false end

  local activeLoan = false
  for _,L in ipairs(economyAPI.listLoans()) do if (L.remaining_principal or 0) > 0 then activeLoan = true; break end end

  if not activeLoan then
    local r = tonumber(B.interest_rate_daily or 0.0) or 0.0
    if r > 0 and (B.savings or 0) > 0 then
      local add = math.floor((B.savings * r) + 0.5)
      if add > 0 then B.savings = B.savings + add end
    end
  end

  B.last_interest_day = nowIdx; saveAPI.save(); return true
end

function economyAPI.getBankBalances()
  local s = saveAPI.get()
  s.economy = s.economy or {}
  s.economy.bank = s.economy.bank or { savings = 0 }
  return saveAPI.getPlayerMoney(), tonumber(s.economy.bank.savings or 0) or 0
end

local function _addChecking(delta)
  saveAPI.setPlayerMoney(saveAPI.getPlayerMoney() + (tonumber(delta) or 0))
end
local function _addSavings(delta)
  local s = saveAPI.get()
  s.economy = s.economy or {}
  s.economy.bank = s.economy.bank or { savings = 0 }
  s.economy.bank.savings = (tonumber(s.economy.bank.savings or 0) or 0) + (tonumber(delta) or 0)
  saveAPI.setState(s)
end

local function _clamp(n) n = math.floor(tonumber(n or 0) or 0); if n < 0 then n = 0 end; return n end

local function _acct(a)
  a = tostring(a or ""):lower()
  if a:find("sav", 1, true) then return "savings" end
  return "checking"
end

-- Deposit: checking -> selected
function economyAPI.deposit(n, account)
  n = _clamp(n); if n <= 0 then return false, "Amount?" end
  local acct = _acct(account)
  if acct == "savings" then
    if economyAPI.hasActiveLoan() then return false, "Disabled while is loan active" end
    if saveAPI.getPlayerMoney() < n then return false, "    Insufficient checking" end
    _addChecking(-n); _addSavings(n); return true
  elseif acct == "checking" then
    -- move from savings -> checking
    local _, sav = economyAPI.getBankBalances()
    if sav < n then return false, "    Insufficient savings" end
    _addSavings(-n); _addChecking(n); return true
  end
end

-- Withdraw: selected -> other
function economyAPI.withdraw(n, account)
  n = _clamp(n); if n <= 0 then return false, "Amount?" end
  local acct = _acct(account)
  if acct == "savings" then
    -- savings -> checking (allowed)
    local _, sav = economyAPI.getBankBalances()
    if sav < n then return false, "    Insufficient savings" end
    _addSavings(-n); _addChecking(n); return true
  elseif acct == "checking" then
    -- checking -> savings (blocked while loan active)
    if economyAPI.hasActiveLoan() then return false, "Disabled while is loan active" end
    if saveAPI.getPlayerMoney() < n then return false, "    Insufficient checking" end
    _addChecking(-n); _addSavings(n); return true
  end
end




return economyAPI

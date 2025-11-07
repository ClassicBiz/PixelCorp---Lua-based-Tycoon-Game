
local M = {}
-- --- Root resolution & deps ---
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
local basalt = require(root.."/API/basalt")
local timeAPI = require(root.."/API/timeAPI")
local stageAPI = require(root.."/API/stageAPI")
local saveAPI    = require(root.."/API/saveAPI")
local licenseAPI = require(root.."/API/licenseAPI")
local economyAPI = require(root.."/API/economyAPI")
local levelAPI   = require(root.."/API/levelAPI")
local itemsAPI   = require(root.."/API/itemsAPI")
local upgradeAPI = require(root.."/API/upgradeAPI")
local inventoryAPI = require(root.."/API/inventoryAPI")
local eventAPI = require(root.."/API/eventAPI")
local settingsOK, settingsAPI = pcall(require, root.."/API/settingsAPI")
-- --- State container ---
M.refs = {
  mainFrame = nil,
  displayFrame = nil,
  topBar = nil,
  sidebar = nil,
  inventoryOverlay = nil,
  tabBar = nil,
  loading = nil,  
  speedButtons = {},
  timeThread = nil,
}

local DEV = { built=false, els={}, licInfo=nil, licBtn=nil, stgInfo=nil, stgBtn=nil }
local _licBusy, _stgBusy = false, false

-- Decide current stage and next stage definition
local function _stageGraph()
  local s = saveAPI.get() or {}
  local cur = ((s.player or {}).progress) or "odd_jobs"
  -- your stage graph (use your real one if different)
  return {
    odd_jobs       = { name="Odd Jobs",       next="lemonade_stand", req_lvl=0,    req_lic="lemonade", cost=100  },
    lemonade_stand = { name="Lemonade Stand", next="warehouse",      req_lvl=50,   req_lic="warehouse", cost=5000 },
    warehouse      = { name="Warehouse",      next="factory",        req_lvl=125,  req_lic="factory",   cost=50000 },
    factory        = { name="Factory",        next="highrise",       req_lvl=200,  req_lic="highrise",  cost=250000 },
    highrise       = { name="High-Rise Corporation" }
  }
end

function M.progressToArt(progress)
  if progress == "lemonade_stand" then return "lemonade"
  elseif progress == "warehouse"   then return "office"
  elseif progress == "factory"     then return "factory"
  elseif progress == "highrise"    then return "tower"
  else return "base" end
end

-- === World Interaction Helpers =========================================
-- ephemeral label that disappears after ttl seconds
local ActivePickups = { set = {}, count = 0 }

local function _addPickup(lbl)
  if not lbl then return end
  if not ActivePickups.set[lbl] then
    ActivePickups.set[lbl] = true
    ActivePickups.count = ActivePickups.count + 1
  end
end

local function _removePickup(lbl)
  if not lbl then return end
  if ActivePickups.set[lbl] then
    ActivePickups.set[lbl] = nil
    ActivePickups.count = math.max(0, ActivePickups.count - 1)
  end
end

function M.getActivePickups()
  return ActivePickups.count
end


function M._spawnPickup(parent, x, y, text, fg, ttl, onClick)
  ttl = ttl or 6
  local lbl = parent:addLabel()
      :setPosition(x, y)
      :setText(text or "*")
      :setForeground(fg or colors.lime)
      :setZIndex(130)

  -- track it as active
  _addPickup(lbl)

  -- click to claim
  if onClick then
    lbl:onClick(function()
      pcall(onClick)
      _removePickup(lbl)
      pcall(function() lbl:hide(); lbl:remove() end)
    end)
  end

  -- auto fade (simple blink then remove)
  local th = parent:addThread()
  th:start(function()
    local t = 0
    while t < ttl do
      os.sleep(0.25); t = t + 0.25
      if lbl and lbl.setForeground then
        lbl:setForeground((t % 0.5 < 0.25) and fg or colors.white)
      end
    end
    _removePickup(lbl)
    pcall(function() lbl:hide(); lbl:remove() end)
  end)

  return lbl
end

-- very light customer “walk-up” animation (1 char that moves, then poof)
function M.spawnCustomer(parent)
  local W,H = term.getSize()
  local y = H - 3
  local lbl = parent:addLabel():setPosition(W-2, y):setText("@"):setForeground(colors.gray):setZIndex(8)
  local th  = parent:addThread()
  th:start(function()
    local x = W-2
    while x > 8 do
      x = x - 1
      if lbl and lbl.setPosition then lbl:setPosition(x, y) end
      os.sleep(0.05)
    end
    -- little sparkle when they “buy”
    if lbl and lbl.setText then lbl:setText("*"):setForeground(colors.yellow) end
    os.sleep(0.15)
    pcall(function() lbl:hide(); lbl:remove() end)
  end)
end

-- --- Toast manager (re-usable, single runner) ---
local TextToasts = { items = {}, runner = nil, root = nil, max_active = 24 }
local function _startToastRunner(rootFrame)
  if TextToasts.runner then return end
  TextToasts.root = rootFrame
  local th = TextToasts.root:addThread()
  TextToasts.runner = th
  th:start(function()
    while true do
      local now = os.clock()
      for i = #TextToasts.items, 1, -1 do
        local it = TextToasts.items[i]
        if now >= (it.t1 or 0) then
          if it.lbl and it.lbl.remove then pcall(function() it.lbl:remove() end) end
          table.remove(TextToasts.items, i)
        end
      end
      os.sleep(0.05)
    end
  end)
end

local function safeText(str, maxLen)
  local t = tostring(str or "")
  t = t:gsub("[\0-\8\11\12\14-\31]", " ")
  t = t:gsub("\t", " ")
  t = t:gsub("\r?\n", " ")
  if maxLen and #t > maxLen then t = t:sub(1, maxLen) end
  return t
end

function M.spawnToast(parent, text, x, y, color, duration)
  if not parent or not parent.addLabel then return end
  if not TextToasts or not TextToasts.runner then
    _startToastRunner(M.refs.mainFrame or parent)
  end

  if #TextToasts.items >= (TextToasts.max_active or 24) then
    local it = table.remove(TextToasts.items, 1)
    if it and it.lbl and it.lbl.remove then pcall(function() it.lbl:remove() end) end
  end

  local px = tonumber(x) or 1
  local py = tonumber(y) or 1
  local pw = (parent.getSize and select(1, parent:getSize())) or term.getSize()
  local avail = math.max(1, pw - (px - 1))

  local txt = safeText(tostring(text or ""), avail)

  local lbl = parent:addLabel()
      :setPosition(px, py)
      :setSize(#txt, 1)
      :setText(txt)
      :setForeground(color or colors.white)
      :setZIndex(8)

  table.insert(TextToasts.items, { lbl = lbl, t1 = os.clock() + (tonumber(duration) or 2.0) })
  return lbl
end

local function _addDev(el) table.insert(DEV.els, el); return el end
local function _clearDev()
  for _,el in ipairs(DEV.els) do
    if el and el.remove then pcall(function() el:remove() end) end
    if el and el.destroy then pcall(function() el:destroy() end) end
  end
  DEV.els, DEV.licInfo, DEV.licBtn, DEV.stgInfo, DEV.stgBtn = {}, nil, nil, nil, nil
  DEV._licBound, DEV._stgBound = false, false
  DEV.built = false
end

local function _nextLicense()
  local order = { "lemonade","warehouse","factory","highrise" }
  for _,id in ipairs(order) do
    if not licenseAPI.has(id) then
      local L = licenseAPI.licenses[id] or { name=id, cost=0 }
      return id, L
    end
  end
  return nil, nil
end

local function _fmtMoney(n) return ("$%s"):format(tostring(n or 0)) end

function M.refreshDevLicenses()
  if not DEV.built then return end
  local id, L = _nextLicense()
  local txt, btn, enabled
  if not id then
    txt = "Next License:\n  All licenses acquired."
    btn = "Done"
    enabled = false
  else
    txt = ("Next License:\n  %s  (%s)"):format(L.name or id, _fmtMoney(L.cost))
    enabled = (not licenseAPI.has(id)) and economyAPI.canAfford(L.cost)
    btn = ("Buy %s License"):format(L.name or id)
  end

  DEV.licInfo:setText(txt):setPosition(10,4)
  DEV.licBtn
    :setText(btn)
    :setBackground(enabled and colors.blue or colors.lightGray)
    :setForeground(enabled and colors.white or colors.gray)
    :setPosition(10,6)
    :setSize(34,3)
  if not DEV._licBound then
    DEV._licBound = true
    DEV.licBtn:onClick(function()
      if _licBusy then return end
      local curId, curL = _nextLicense()
      if not curId then return end
      if licenseAPI.has(curId) then return M.refreshDevLicenses() end
      if not economyAPI.canAfford(curL.cost) then return M.toast("displayFrame","Not enough money",18,5,colors.red,1.2) end

      _licBusy = true
      local ok, msg = licenseAPI.purchase(curId)
      M.toast("displayFrame", msg or (ok and "License purchased" or "Purchase failed"),
              18,5, ok and colors.green or colors.red,1.2)
      M.refreshDevLicenses()
      M.refreshDevStage()
      pcall(function() if refreshUI then refreshUI() end end)

      _licBusy=false
    end)
  end
end

function M.refreshDevStage()
  if not DEV.built then return end
  local s = saveAPI.get() or {}; s.player = s.player or {}
  local graph = _stageGraph()
  local curKey = s.player.progress or "odd_jobs"
  local curDef = graph[curKey]
  local lvl = (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1

  local info, btn, enabled, nextKey, needLvl, needLic, cost
  if curDef and curDef.next then
    nextKey = curDef.next
    local nextDef = graph[nextKey]
    needLvl = tonumber(curDef.req_lvl or 0) or 0
    needLic = tostring(curDef.req_lic or "")
    cost    = tonumber(curDef.cost or 0) or 0

    local hasLic = (needLic == "") or licenseAPI.has(needLic)
    enabled = hasLic and (lvl >= needLvl) and economyAPI.canAfford(cost)

    info = ("Next Stage:\n  %s  Req: Lvl %d%s\n  Cost: %s")
           :format(nextDef.name or nextKey, needLvl, (needLic~="" and (", License: "..needLic) or ""), _fmtMoney(cost))
    btn  = ("Unlock %s"):format(nextDef.name or nextKey)
  else
    info, btn, enabled = "Next Stage:\n  Max stage reached.", "Done", false
  end
  DEV.stgInfo:setText(info):setPosition(10,12)
  DEV.stgBtn
    :setText(btn)
    :setPosition(10,14)
    :setSize(34,3)
    :setBackground(enabled and colors.blue or colors.lightGray)
    :setForeground(enabled and colors.white or colors.gray)
  if not DEV._stgBound then
    DEV._stgBound = true
    DEV.stgBtn:onClick(function()
      if _stgBusy then return end
      local state = saveAPI.get() or {}; state.player = state.player or {}
      local g = _stageGraph(); local cur = state.player.progress or "odd_jobs"
      local def = g[cur]; if not def or not def.next then return end
      local needLvl = tonumber(def.req_lvl or 0) or 0
      local needLic = tostring(def.req_lic or "")
      local cost    = tonumber(def.cost or 0) or 0
      local lvlNow  = (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1
      local hasLic  = (needLic == "") or licenseAPI.has(needLic)
      if lvlNow < needLvl then return M.toast("displayFrame","Higher level required",18,5,colors.red,1.2) end
      if not hasLic then   return M.toast("displayFrame","Required license missing",18,5,colors.red,1.2) end
      if not economyAPI.canAfford(cost) then return M.toast("displayFrame","Not enough money",18,5,colors.red,1.2) end
      _stgBusy=true
      economyAPI.spendMoney(cost)
      state.player.progress = def.next
      saveAPI.setState(state)
      local artKey = M.progressToArt(def.next)
      if M._onStageChanged then pcall(function() M._onStageChanged(def.next) end) end
        if stageAPI.setStage then stageAPI.setStage(artKey) end
        stageAPI.refreshBackground(M.refs.displayFrame)
      M.toast("displayFrame","Stage unlocked!",18,5,colors.green,1.2)
      M.refreshDevStage()
      pcall(function() if refreshUI then refreshUI() end end)
      _stgBusy=false
    end)
  end
end

function M.buildDevelopmentPage()
  if DEV.built then return end
  local f = M.ensurePage("development") 
  _clearDev()

  -- stacked layout
  DEV.licInfo = _addDev(f:addLabel():setText("Next License:"):setPosition(2, 4))
  DEV.licBtn  = _addDev(f:addButton():setText("Buy License"):setPosition(2, 7):setSize(27, 3))

  DEV.stgInfo = _addDev(f:addLabel():setText("Next Stage:"):setPosition(2, 12))
  DEV.stgBtn  = _addDev(f:addButton():setText("Unlock Stage"):setPosition(2, 15):setSize(27, 3))

  DEV.built = true
  M.refreshDevLicenses()
  M.refreshDevStage()
end

function M.showDevelopment()
  if not DEV.built then M.buildDevelopmentPage() end
  -- Re-enable and reveal any previously hidden dev widgets
  for _, el in ipairs(DEV.els or {}) do
    pcall(function() if el.enable then el:enable() end end)
    pcall(function() if el.show then el:show() end end)
  end
  M.refreshDevLicenses()
  M.refreshDevStage()
  M.showPage("development")
end

function M.killDevelopment()
  _clearDev()
end

function M.disableDevelopment()
  for _,el in ipairs(DEV.els or {}) do
    pcall(function() if el.disable then el:disable() end end)
    pcall(function() if el.hide then el:hide() end end)
  end
end
-- ===== Stock Page (draws on displayFrame) =====
local STOCK = { built=false, els={}, catIdx=1, epoch=0, qsel={}, refs={} }
local STOCK_CATS  = { base="Cups", fruit="Fruit", sweet="Sweetener", topping="Toppings" }
local STOCK_ORDER = { "base","fruit","sweet","topping" }

local function _rarityColor(it) return (itemsAPI.itemRarityColor and itemsAPI.itemRarityColor(it)) or colors.white end
local function _clearStock()
  for _,el in ipairs(STOCK.els) do
    pcall(function() if el.disable then el:disable() end end)
    pcall(function() if el.hide then el:hide() end end)
    pcall(function() if el.remove then el:remove() end end)
    pcall(function() if el.destroy then el:destroy() end end)
  end
  STOCK.els = {}
end

function M.killStock() _clearStock(); STOCK.built=false end
function M.hideStock()
  for _,el in ipairs(STOCK.els) do
    pcall(function() if el.disable then el:disable() end end)
    pcall(function() if el.hide then el:hide() end end)
  end
end

local function _add(el) table.insert(STOCK.els, el); return el end

function M.buildStockPage()
  STOCK.epoch = STOCK.epoch + 1
  local __epoch = STOCK.epoch
  _clearStock()

  local f = M.refs.displayFrame
  local W, H = f:getSize()
  local SCREEN_HEIGHT = H + 2

  local catKey   = STOCK_ORDER[STOCK.catIdx] or "base"
  local catTitle = (STOCK_CATS[catKey] or catKey):upper()

  local ddCat = _add(f:addDropdown()
      :setPosition(3,4)          
      :setSize(12,1)
      :setZIndex(20)
      :setBackground(colors.lightBlue)
      :setForeground(colors.black)
      :setSelectionColor(colors.lightBlue, colors.blue)
      :hide())

  for i, key in ipairs(STOCK_ORDER) do
    ddCat:addItem(STOCK_CATS[key] or key)
  end

  pcall(function()
    if ddCat.setSelectedItem then ddCat:setSelectedItem(STOCK.catIdx)
    elseif ddCat.selectItem     then ddCat:selectItem(STOCK.catIdx)
    elseif ddCat.setValue       then ddCat:setValue(STOCK_CATS[STOCK_ORDER[STOCK.catIdx]] or catTitle)
    end
  end)

  ddCat:onChange(function(self, value)
    if __epoch ~= STOCK.epoch then return end
    local i = 1
    if self.getItemIndex then
      i = self:getItemIndex()
    elseif type(value) == "number" then
      i = value
    else

      local txt = tostring(value or "")
      for k = 1, #STOCK_ORDER do
        if (STOCK_CATS[STOCK_ORDER[k]] or STOCK_ORDER[k]) == txt then i = k; break end
      end
    end
    if i < 1 or i > #STOCK_ORDER then i = 1 end
    STOCK.catIdx = i
    M.buildStockPage()
    M.showStock()
    M.softRefreshStockLabels()
  end)

  local L = (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1
  local items = {}
  for _, it in ipairs(itemsAPI.listByType(catKey)) do
    if it.purchasable and itemsAPI.isUnlockedForLevel(it.id, L) then table.insert(items, it) end
  end
  table.sort(items, function(a,b)
    local ra = itemsAPI.levelReqById(a.id); local rb = itemsAPI.levelReqById(b.id)
    if ra ~= rb then return ra < rb end
    return (a.name or a.id) < (b.name or b.id)
  end)
  local marketStock = inventoryAPI.getAvailableStock()
  local row = 0
  for _, it in ipairs(items) do
    row = row + 1
    local y = 4 + row
    local id    = it.id
    local name  = it.name or id
    local price = inventoryAPI.getMarketPrice(id)
    local amt   = marketStock[id] or 0
    local qtyToBuy =  1
    local nameLabel = _add(f:addLabel():setText(("| %s"):format(name)):setPosition(1,y):setZIndex(10):hide())
    pcall(function() nameLabel:setForeground(_rarityColor(it)) end)

    _add(f:addLabel():setText("(    ea)"):setPosition(16,y):setZIndex(10):hide())
    local priceLabel = _add(f:addLabel():setText(("$%d"):format(price)):setPosition(18,y):setZIndex(10):hide())
    pcall(function() priceLabel:setForeground(colors.yellow) end)

    local stockLabel= _add(f:addLabel():setText("|In Stock: "..amt):setPosition(24,y):setZIndex(10):hide())
    STOCK.refs[id] = STOCK.refs[id] or {}
    STOCK.refs[id].stockLabel = stockLabel
    STOCK.refs[id].priceLabel = priceLabel

    local buyBtn = _add(f:addButton():setText("Buy"):setPosition(38,y):setBackground(colors.blue):setSize(5,1):setZIndex(10):hide()
      :onClick(function()
        if __epoch ~= STOCK.epoch then return end
        if not stageAPI.isUnlocked("lemonade") then
          M.toast("displayFrame", "Unlock Lemonade Stand first", 14,5, colors.red, 1.2)
          return
        end
        local ok, msg = inventoryAPI.buyFromMarket(id, qtyToBuy)
        if ok then M.toast("displayFrame", (qtyToBuy.." "..name.." bought!"), 17,5, colors.blue,1.0)
        else M.toast("displayFrame", msg or "Purchase failed.", 18,5, colors.red,1.0) end
        local newStock = inventoryAPI.getAvailableStock()
        local newPrice = inventoryAPI.getMarketPrice(id)
        if stockLabel and stockLabel.setText then stockLabel:setText("|In Stock: "..(newStock[id] or 0)) end
        if priceLabel and priceLabel.setText then priceLabel:setText(("$%d"):format(newPrice)) end
      end))
    if not stageAPI.isUnlocked("lemonade") then buyBtn:setBackground(colors.lightGray):setForeground(colors.white) else buyBtn:setBackground(colors.blue):setForeground(colors.black) end
    local qtyLabel = _add(f:addLabel():setText(tostring(qtyToBuy)):setPosition(46,y):setZIndex(10):hide())
    _add(f:addButton():setText("<"):setPosition(44,y):setBackground(colors.white):setSize(1,1):setZIndex(15):hide()
      :onClick(function() if __epoch ~= STOCK.epoch then return end; qtyToBuy = math.max(1, qtyToBuy - 1); STOCK.qsel[id]=qtyToBuy; qtyLabel:setText(tostring(qtyToBuy)) end))
    _add(f:addButton():setText(">"):setPosition(48,y):setBackground(colors.white):setSize(1,1):setZIndex(15):hide()
      :onClick(function() if __epoch ~= STOCK.epoch then return end; qtyToBuy = qtyToBuy + 1; STOCK.qsel[id]=qtyToBuy; qtyLabel:setText(tostring(qtyToBuy)) end))
  end

  STOCK.built = true
end

function M.showStock()
  if not STOCK.built then M.buildStockPage() end
  for _,el in ipairs(STOCK.els) do
    pcall(function() if el.enable then el:enable() end end)
    pcall(function() if el.show   then el:show()   end end)
  end
end

function M.softRefreshStockLabels()
  if not STOCK.built then return end
  local marketStock = inventoryAPI.getAvailableStock()
  for id, ref in pairs(STOCK.refs or {}) do
    local ok1, lbl1 = pcall(function() return ref.stockLabel end)
    local ok2, lbl2 = pcall(function() return ref.priceLabel end)
    if ok1 and lbl1 and lbl1.setText then
      local amt = marketStock[id] or 0
      pcall(function() lbl1:setText("|In Stock: "..tostring(amt)) end)
    end
    if ok2 and lbl2 and lbl2.setText then
      local price = inventoryAPI.getMarketPrice(id)
      pcall(function() lbl2:setText(("$%d"):format(price)) end)
    end
  end
end

function M.refreshStock()
  if not STOCK.built then
    M.buildStockPage()
    M.showStock()
    return
  end
  M.buildStockPage()
  M.showStock()
end

-- --- Loading overlay ---
local function buildLoading(mainFrame)
  local W,H = term.getSize()
  local f = mainFrame:addFrame():show()
      :setSize(W, H)
      :setPosition(1, 1)
      :setBackground(colors.lightGray)
      :setZIndex(100)

  local label = f:addLabel()
      :setText("Loading...")
      :setPosition(math.floor(W/2)-10, math.floor(H/2)-1)
      :setForeground(colors.white)

  local pl = f:addLabel()
      :setText("0%")
      :setPosition(math.floor(W/2)-1, math.floor(H/2)+0)
      :setForeground(colors.white)
      :setZIndex(101)

  local bar = f:addProgressbar()
      :setDirection(0)
      :setPosition(math.floor(W/2)-12, math.floor(H/2))
      :setSize(25, 1)
      :setProgressBar(colors.blue, " ")
      :setBackground(colors.gray)
      :setProgress(0)

  return { frame = f, label = label, progressLabel = pl, bar = bar }
end

function M.setLoading(text, pct)
  if not M.refs.loading then return end
  if text then M.refs.loading.label:setText(text) end
  if pct then
    pct = math.max(0, math.min(100, math.floor(pct)))
    M.refs.loading.bar:setProgress(pct)
    M.refs.loading.progressLabel:setText(tostring(pct).."%")
  end
end

function M.hideLoading()
  if M.refs.loading and M.refs.loading.frame then
    M.refs.loading.frame:hide()
  end
end

-- --- Base layout ---
function M.createBaseLayout()
  local W, H = term.getSize()
  local mainFrame = basalt.createFrame():setSize(W, H)

  local topBar = mainFrame:addFrame()
      :setSize(W, 3)
      :setPosition(1, 1)
      :setBackground(colors.gray)
      :hide()

  local displayFrame = mainFrame:addFrame()
      :setSize(W+1, H - 2)
      :setPosition(0, 3)
      :setZIndex(0)
      :hide()

          local mode = tostring((settingsAPI and settingsAPI.navMode and settingsAPI.navMode()) or "sidebar")
  if mode == "sidebar" then

    local SIDEBAR_W = 16
    sidebar = mainFrame:addScrollableFrame()
        :setBackground(colors.lightGray)
        :setPosition(W, 4)
        :setSize(SIDEBAR_W, H - 3)
        :setZIndex(25)
        :setDirection("vertical")

    local function _sidebarExpandedX() return W - (SIDEBAR_W - 1) end
    local function _sidebarHiddenX()   return W end


    function M.openSidebar()
      if not sidebar then return end
      sidebar:setPosition(_sidebarExpandedX(), 4)
          local closeBtn = sidebar:addButton()
        :setText(">")
        :setPosition(1, 1)
        :setSize(1, 17)
        :setBackground(colors.lightGray)
        :setForeground(colors.black)
        :onClick(function() M.closeSidebar() end)
    end

    function M.closeSidebar()
      if not sidebar then return end
      sidebar:setPosition(_sidebarHiddenX(), 4)
        local openBtn = sidebar:addButton()
        :setText("<")
        :setPosition(1, 1)
        :setSize(1, 17)
        :setBackground(colors.lightGray)
        :setForeground(colors.black)
        :onClick(function() M.openSidebar() end)
    end

    sidebar:onGetFocus(function(self)
      M.openSidebar()
    end)
    sidebar:onLoseFocus(function(self)
      M.closeSidebar()
    end)
  else
      navDD = displayFrame:addDropdown()
        :setPosition(2, 2)   -- left edge of the top bar; adjust if you want
        :setSize(14, 1)
        :setBackground(colors.lightBlue)
        :setForeground(colors.black)
        :setSelectionColor(colors.white, colors.cyan)
                :setZIndex(25)
  end
  -- Inventory overlay shell
  local inventoryOverlay = mainFrame:addMovableFrame()
      :setSize(42, 16)
      :setPosition((W - 40) / 2, 3)
      :setBackground(colors.lightGray)
      :setZIndex(45)
      :hide()
  inventoryOverlay:addLabel():setText("Inventory"):setPosition(2, 1)
  inventoryOverlay:addButton()
      :setText(" x ")
      :setPosition(40, 1)
      :setSize(3, 1)
      :setBackground(colors.red)
      :setForeground(colors.white)
      :onClick(function() inventoryOverlay:hide() end)

  -- HUD labels 
  local timeLabel  = topBar:addLabel():setText("Time: --"):setPosition(2, 1)
  local moneyLabel = topBar:addLabel():setText("Money: $0"):setPosition(32, 2)
  local stageLabel = topBar:addLabel():setText("Stage: --"):setPosition(25, 1)
  local moneyPlus = topBar:addButton():setText("Bank"):setPosition(27,2):setSize(4,1):setBackground(colors.gray):setForeground(colors.green)
  :onClick(function()
    if M.openFinanceModal then M.openFinanceModal() end
    if M._onMoneyPlus then pcall(M._onMoneyPlus) end
  end)
  local levelLabel = topBar:addLabel():setText("lvl 1"):setPosition(1,3):setForeground(colors.yellow)
  local levelBarLabel = topBar:addLabel():setText("|----------| 0%"):setPosition(7,3):setForeground(colors.blue)

  -- Speed buttons
  function M.updateSpeedButtons()
    local speedButtons = M.refs.speedButtons or {}
    local current = timeAPI.getSpeed()
    for mode, btn in pairs(speedButtons) do
      if mode == current then
        if mode == "pause" then btn:setBackground(colors.red)
        elseif mode == "normal" then btn:setBackground(colors.green)
        elseif mode == "2x" then btn:setBackground(colors.blue)
        elseif mode == "4x" then btn:setBackground(colors.orange)
        end
        btn:setForeground(colors.white)
      else
        btn:setBackground(colors.lightGray):setForeground(colors.gray)
      end
    end
  end

  local function updateSpeedButtonColors(speedButtons)
    local current = timeAPI.getSpeed()
    for mode, btn in pairs(speedButtons) do
      if mode == current then
        if mode == "pause" then btn:setBackground(colors.red)
        elseif mode == "normal" then btn:setBackground(colors.green)
        elseif mode == "2x" then btn:setBackground(colors.blue)
        elseif mode == "4x" then btn:setBackground(colors.orange)
        end
        btn:setForeground(colors.white)
      else
        btn:setBackground(colors.lightGray):setForeground(colors.gray)
      end
    end

  end

  
  local speedButtons = {}
  speedButtons["pause"] = topBar:addButton():setText("II"):setPosition(W - 44, 2):setSize(4,1)
      :onClick(function() timeAPI.setSpeed("pause"); updateSpeedButtonColors(speedButtons) end)
  speedButtons["normal"] = topBar:addButton():setText(">"):setPosition(W - 40, 2):setSize(4,1)
      :onClick(function() timeAPI.setSpeed("normal"); updateSpeedButtonColors(speedButtons) end)
  speedButtons["2x"] = topBar:addButton():setText(">>"):setPosition(W - 36, 2):setSize(4,1)
      :onClick(function() timeAPI.setSpeed("2x"); updateSpeedButtonColors(speedButtons) end)

  -- A single button that is either ">>>" (4x) or "Skip" depending on time.
  local rightBtn = topBar:addButton():setPosition(W - 32, 2):setSize(4,1)

  local function inSkipWindow()
    local t = timeAPI.getTime()
    local h, m = t.hour or 0, t.minute or 0
    return (h >= 20) or (h < 5) or (h == 5 and m < 30)
  end

  local function refreshRightBtn()
    if inSkipWindow() then
      speedButtons["skip"] = rightBtn
      speedButtons["4x"] = nil
      rightBtn:setText("Skip")
      rightBtn:onClick(function()
        if M._onSkipNight then M._onSkipNight() end
      end)
    else
      speedButtons["4x"] = rightBtn
      speedButtons["skip"] = nil
      rightBtn:setText(">>>")
      rightBtn:onClick(function()
        timeAPI.setSpeed("4x"); updateSpeedButtonColors(speedButtons)
      end)
    end
  end

  function M._refreshSkipOr4x()
    refreshRightBtn()
  end

  local function updateSpeedButtonColors(speedButtons)
    refreshRightBtn()
    local current = timeAPI.getSpeed()
    for mode, btn in pairs(speedButtons) do
      if mode == current then
        if mode == "pause" then btn:setBackground(colors.red)
        elseif mode == "normal" then btn:setBackground(colors.green)
        elseif mode == "2x" then btn:setBackground(colors.blue)
        elseif mode == "4x" then btn:setBackground(colors.orange)
        elseif mode == "skip" then btn:setBackground(colors.purple or colors.blue)
        end
        btn:setForeground(colors.white)
      else
        btn:setBackground(colors.lightGray):setForeground(colors.gray)
      end
    end
  end

  updateSpeedButtonColors(speedButtons)
  M.updateSpeedButtons = function()
    updateSpeedButtonColors(speedButtons)
  end

  local pauseBtn = topBar:addButton()
      :setText("Pause")
      :setPosition(W - 50, 2)
      :setSize(6, 1)
      :setBackground(colors.red)
      :setForeground(colors.white)

  local borderMenu = mainFrame:addFrame()
      :setSize(30, 14)
      :setPosition((W - 30) / 2, 5)
      :setBackground(colors.lightGray)
      :hide()

  local pauseMenu = borderMenu:addFrame()
      :setSize(28, 12)
      :setPosition(2, 2)
      :setBackground(colors.white)
      :setZIndex(50)
  pauseMenu:addLabel():setText("[--------------------------]"):setPosition(1, 1):setForeground(colors.black)
  pauseMenu:addLabel():setText("Pause Menu"):setPosition(10, 1):setForeground(colors.gray)
  local function showPause() borderMenu:show(); pauseMenu:show() end
  local function hidePause() borderMenu:hide(); pauseMenu:hide() end
  local pauseResumeBtn = pauseMenu:addButton()
    :setText("Resume")
    :setPosition(3, 3)
    :setSize(24, 1)
    :setBackground(colors.green)
    :setForeground(colors.white)
    :onClick(function() hidePause(); if M._onPauseResume then M._onPauseResume() end end)
local pauseSaveBtn = pauseMenu:addButton()
    :setText("Save Game")
    :setPosition(3, 5)
    :setSize(24, 1)
    :setBackground(colors.blue)
    :setForeground(colors.white)
    :onClick(function() if M._onPauseSave then M._onPauseSave() end end)
local pauseLoadBtn = pauseMenu:addButton()
    :setText("Load Game")
    :setPosition(3, 7)
    :setSize(24, 1)
    :setBackground(colors.blue)
    :setForeground(colors.white)
    :onClick(function() if M._onPauseLoad then M._onPauseLoad() end end)
local pauseSettingsBtn = pauseMenu:addButton()
    :setText("Settings")
    :setPosition(3, 9)
    :setSize(24, 1)
    :setBackground(colors.blue)
    :setForeground(colors.white)
    :onClick(function() if M._onPauseSettings then M._onPauseSettings() end end)
local pauseQuitBtn = pauseMenu:addButton()
    :setText("Quit to Main Menu")
    :setPosition(3, 11)
    :setSize(24, 1)
    :setBackground(colors.red)
    :setForeground(colors.white)
    :onClick(function() if M._onPauseQuitToMenu then M._onPauseQuitToMenu() end end)

pauseBtn:onClick(function() showPause(); if M._onPauseOpen then M._onPauseOpen() end end)
  local invBtn = topBar:addButton()
      :setText("| INV |")
      :setPosition(34, 3)
      :setSize(7, 1)
      :setBackground(colors.gray)
      :setForeground(colors.white)
      :onClick(function() if M._onTopInv then M._onTopInv() end end)
  local craftBtn = topBar:addButton()
      :setText("| CRAFT |")
      :setPosition(42, 3)
      :setSize(9, 1)
      :setBackground(colors.gray)
      :setForeground(colors.orange)
      :onClick(function() if M._onTopCraft then M._onTopCraft() end end)

  -- Expose everything
  M.refs.mainFrame = mainFrame
  M.refs.displayFrame = displayFrame
  M.refs.topBar = topBar
  M.refs.sidebar = sidebar
  M.refs.navDD = navDD
  M.refs.inventoryOverlay = inventoryOverlay
  M.refs.loading = buildLoading(mainFrame)
  M.refs.speedButtons = speedButtons
  M.refs.labels = {
    timeLabel = timeLabel, moneyLabel = moneyLabel, stageLabel = stageLabel,
    levelLabel = levelLabel, levelBarLabel = levelBarLabel
  }
  M.refs.pause = {
    border = borderMenu, content = pauseMenu,
    show = showPause, hide = hidePause, button = pauseBtn
  }
  M.refs.frames = { root = mainFrame, topbar = topBar, display = displayFrame, overlay = inventoryOverlay, pause = pauseMenu }


  -- Make them available globally for legacy code that referenced globals
  _G.mainFrame        = mainFrame
  _G.topBar           = topBar
  _G.sidebar          = sidebar
  _G.displayFrame     = displayFrame
  _G.inventoryOverlay = inventoryOverlay
  _G.spawnToast       = M.spawnToast
  _G.pauseMenu        = pauseMenu

  return M.refs
end

function M.showRoot()
  if M.refs.topBar then M.refs.topBar:show() end
  if M.refs.displayFrame then M.refs.displayFrame:show() end
  if M.refs.sidebar then M.refs.sidebar:show() end
end

function M.setHUDTime(text)      if M.refs.labels and M.refs.labels.timeLabel then M.refs.labels.timeLabel:setText(text) end end
function M.setHUDMoney(text)     if M.refs.labels and M.refs.labels.moneyLabel then M.refs.labels.moneyLabel:setText(text) end end
function M.setHUDStage(text)     if M.refs.labels and M.refs.labels.stageLabel then M.refs.labels.stageLabel:setText(text) end end
function M.setHUDLevel(text)     if M.refs.labels and M.refs.labels.levelLabel then M.refs.labels.levelLabel:setText(text) end end
function M.setHUDLevelBar(text)  if M.refs.labels and M.refs.labels.levelBarLabel then M.refs.labels.levelBarLabel:setText(text) end end

local _moneyHud = { text = "Money: $0" }

function M.setHUDMoney(text)
  if M.refs.labels and M.refs.labels.moneyLabel then
    M.refs.labels.moneyLabel:setText(text)
  end
  _moneyHud.text = tostring(text or "")
end

function M.getMoneyTail()
  local lbl = M.refs.labels and M.refs.labels.moneyLabel
  if not lbl then return 1, 1 end
  local x0, y0 = 1, 1
  if lbl.getPosition then x0, y0 = lbl:getPosition() end
  local tailX = x0 + #_moneyHud.text
  return tailX, y0
end

function M.getFrame(name)
  if not name then return M.refs.mainFrame end
  if M.refs.frames and M.refs.frames[name] then return M.refs.frames[name] end
  return M.refs.mainFrame
end

function M.toast(where, text, x, y, color, duration)
  if type(where) == "table" and where.addLabel then
    return M.spawnToast(where, text, x, y, color, duration)
  end
  local target = M.getFrame(where)
  if where == "pause" then target = M.refs.topBar or target end
  return M.spawnToast(target, text, x, y, color, duration)
end

function M.refreshStageBackground()
    stageAPI.refreshBackground(M.refs.displayFrame)
end

function M.onPauseResume(fn) M._onPauseResume = fn end
function M.onPauseOpen(fn) M._onPauseOpen = fn end
function M.onPauseSave(fn) M._onPauseSave = fn end
function M.onPauseLoad(fn) M._onPauseLoad = fn end
function M.onPauseSettings(fn) M._onPauseSettings = fn end
function M.onPauseQuitToMenu(fn) M._onPauseQuitToMenu = fn end
function M.onSkipNight(fn) M._onSkipNight = fn end
function M.onStageChanged(fn) M._onStageChanged = fn end

function M.onTopInv(fn) M._onTopInv = fn end
function M.onTopCraft(fn) M._onTopCraft = fn end

local _pages = _pages or {}
local NO_CONTAINER = { development = true, stock = true, main = true, upgrades = true } 

function M.ensurePage(name)
  if not name or name == "" then return M.refs.displayFrame end
  if NO_CONTAINER[name] then
    return M.refs.displayFrame
  end

  if _pages[name] and _pages[name].frame then return _pages[name].frame end

  local W, H = term.getSize()
  local f = M.refs.displayFrame:addFrame()
      :setSize(W, H - 2)
      :setPosition(1, 1)
      :setZIndex(10)
      :hide()

      stageAPI.refreshBackground(f)

  _pages[name] = { frame = f, built = false }
  return f
end

function M.showPage(name)
  if NO_CONTAINER[name] then return end
  local p = _pages[name]; if p and p.frame then p.frame:show() end
end

function M.hidePage(name)
  if NO_CONTAINER[name] then return end
  local p = _pages[name]; if p and p.frame then p.frame:hide() end
end

function M.teardownPage(name)
  local p = _pages[name]
  if p and p.frame then pcall(function() p.frame:removeChildren() end); p.built = false end
end

function M.pageBuilt(name)        return _pages[name] and _pages[name].built end
function M.setPageBuilt(name, v)  if _pages[name] then _pages[name].built = not not v end end
function M.getPageFrame(name)     return (NO_CONTAINER[name] and M.refs.displayFrame) or (_pages[name] and _pages[name].frame) end

function M.onMoneyPlus(fn) M._onMoneyPlus = fn
  M.openFinanceModal()
end

  local loanBtnById  = {}
  local loanPosById  = {}
  local loanInfoById = {}
  local payoffBtnById= {}

-- Finance modal (Bank / Loans / Stocks)
function M.openFinanceModal()
  local W,H = term.getSize()
  local border = M.refs.mainFrame:addFrame()
      :setSize(46,16):setPosition(3, 3)
      :setBackground(colors.lightGray):setZIndex(140)

  local box = border:addFrame()
      :setSize(44,14):setPosition(2,2)
      :setBackground(colors.white):setZIndex(141)

  box:addLabel():setText("Finance"):setPosition(17,1):setForeground(colors.gray)

  local tabs = box:addMenubar()
      :setPosition(6,2):setSize(33,1)
      :setScrollable(false)
      :addItem("- Bank -"):addItem("= Loans ="):addItem("- Stocks -")

  local pages = {
    bank   = box:addFrame():setPosition(2,4):setSize(44,11):setBackground(colors.white):hide(),
    loans  = box:addFrame():setPosition(2,4):setSize(44,11):setBackground(colors.white):hide(),
    stocks = box:addFrame():setPosition(2,4):setSize(44,12):setBackground(colors.white):hide(),
  }

  local function show(k)
    for _,f in pairs(pages) do if f.hide then f:hide() end end
    pages[k]:show()
  end

  tabs:onChange(function(self, idx)
    local i = (self.getItemIndex and self:getItemIndex()) or idx or 1
    if     i == 1 then show("bank")
    elseif i == 2 then show("loans")
    else               show("stocks")
    end
  end)

  border:addButton():setText(" X ")
      :setPosition(43,1):setSize(3,1)
      :setBackground(colors.red):setForeground(colors.white)
      :onClick(function() border:hide(); border:remove() end)

  ----------------------------------------------------------------
  -- LOANS TAB
  ----------------------------------------------------------------
  local loansF = pages.loans
  local loanRate = (settingsAPI.loanInterest and settingsAPI.loanInterest()) or 0.20
  if loanRate == 0.1 then loanRate = 10 elseif loanRate == 0.2 then loanRate = 20 elseif loanRate == 0.3 then loanRate = 30 end
  loansF:addLabel():setText("Available Loans (7-day term, "..loanRate.."% simple):"):setPosition(1,1):setForeground(colors.black)
  local Lvl = (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1
  local stageUnlocked = (stageAPI and stageAPI.isUnlocked and stageAPI.isUnlocked("lemonade")) or true

  local defs = {
    { name="$500 Week Loan",   id="loan_500",  principal=500,  unlockLevel=1,  requiresStage=stageUnlocked },
    { name="$1000 Week Loan",  id="loan_1000", principal=1000, unlockLevel=15, requiresStage=stageUnlocked },
    { name="$1500 Week Loan",  id="loan_1500", principal=1500, unlockLevel=30, requiresStage=stageUnlocked },
    { name="$2500 Week Loan",  id="loan_2500", principal=2500, unlockLevel=45, requiresStage=stageUnlocked },
  }

  local loanBtnById, loanPosById, loanInfoById, payoffBtnById = {}, {}, {}, {}

  local function refreshLoanButtons()
    local activeById = {}
    local list = {}
    if economyAPI and economyAPI.listLoans then list = economyAPI.listLoans() end
    for _, L in ipairs(list) do
      if (L.remaining_principal or 0) > 0 and L.id then
        activeById[tostring(L.id)] = L
      end
    end

    for idx, d in ipairs(defs) do
      local yRow = 2 + (idx - 1) * 2 + 1
      loanPosById[d.id] = yRow

      local unlocked = d.requiresStage and (Lvl >= d.unlockLevel)

      local btn = loanBtnById[d.id]
      if not btn then
        btn = loansF:addButton()
        loanBtnById[d.id] = btn
        btn:onClick(function()
          if not unlocked then return end
          local loanRate = (settingsAPI.loanInterest and settingsAPI.loanInterest()) or 0.20
          local ok2, res = economyAPI.createLoan({
            id=d.id, name=d.name, principal=d.principal, days=7, interest=loanRate,
            unlockLevel=d.unlockLevel, unlockStage="lemonade_stand"
          })
          if ok2 then
            refreshButtons()
            M.refreshBalances()
            M.toast(loansF, "Loan of $"..d.principal.." taken out for 7 days", 4, 11, colors.green, 2)
          else
            M.toast(loansF, res or "Active loan exists", 10, 11, colors.red, 1.5)
          end
          refreshLoanButtons()
        end)
      end

      btn:setPosition(2, yRow):setSize(32, 1)
      isActive = (activeById[d.id] ~= nil)
      if isActive then
        btn:setText("Taken - pay off to reapply")
        btn:setBackground(colors.lightGray):setForeground(colors.gray)
        btn:disable()
      else
        btn:setText(unlocked and ("Take " .. d.name) or ("Locked (Lvl " .. d.unlockLevel .. ")"))
        btn:setBackground(unlocked and colors.blue or colors.lightGray)
        btn:setForeground(unlocked and colors.white or colors.gray)
        if unlocked then btn:enable() else btn:disable() end
      end
    end

    for _, lbl in pairs(loanInfoById)  do if lbl and lbl.remove then pcall(function() lbl:remove() end) end end
    for _, pb  in pairs(payoffBtnById) do if pb  and pb.remove  then pcall(function() pb:remove()  end) end end
    loanInfoById, payoffBtnById = {}, {}

    local function dailyCharge(L)
      local dp = tonumber(L.dailyPrincipal or L.baseDaily or 0) or 0
      if dp <= 0 then
        local pr = tonumber(L.principal or 0) or 0
        local d  = tonumber(L.days_total or 7) or 7
        dp = math.ceil((pr / d) * 100) / 100
      end
      local r = tonumber(L.interest or 0) or 0
      return math.floor((dp * (1 + r)) * 100 + 0.5) / 100
    end

    for id, L in pairs(activeById) do
      local yRow = (loanPosById[id] or 2) + 1
      loanInfoById[id] = loansF:addLabel()
        :setText(("|Daily: $%.2f|Rem: $%.2f|%d/%d")
          :format(dailyCharge(L), tonumber(L.remaining_principal or 0) or 0, L.days_paid or 0, L.days_total or 7))
        :setPosition(2, yRow)
        :setForeground(colors.black)

      payoffBtnById[id] = loansF:addButton()
        :setText("Pay Off")
        :setPosition(35, yRow-1)
        :setSize(9, 1)
        :setBackground(colors.green)
        :setForeground(colors.white)
        :onClick(function()
          local remaining = L.remaining_principal
          local ok, msg = economyAPI.payoffLoan(L.id)
          M.toast(loansF, ok and "Remaining Loan of $"..tonumber(remaining or 0).." Paid in Full." or (msg or "Failed"), 4, 11, ok and colors.green or colors.red, 1.8)
          refreshLoanButtons()
          refreshButtons()
          M.refreshBalances()
        end)
    end
  end

  refreshLoanButtons()

local bankF = pages.bank
if bankF and bankF.removeChildren then bankF:removeChildren() end
bankF:addLabel():setText("---] PixelCity Bank [---")
      :setPosition(9,1):setForeground(colors.black)

local chkLbl = bankF:addLabel():setPosition(2,3):setText("Checking: $0"):setForeground(colors.black)
local savLbl = bankF:addLabel():setPosition(2,4):setText("Savings:  $0"):setForeground(colors.black)
bankF:addLabel():setPosition(2,5)
      :setText("Interest: 0.30% / day (no loans active)")
      :setForeground(colors.gray)

function M.refreshBalances()
  if economyAPI and economyAPI.getBankBalances then
    local c, s = economyAPI.getBankBalances()
    chkLbl:setText(("Checking: $%d"):format(c or 0))
    savLbl:setText(("Savings:  $%d"):format(s or 0))
  end
end


-- Amount + account selectors
bankF:addLabel():setText("Amount:"):setPosition(2,7):setForeground(colors.black)
local amtTF  = bankF:addInput()
  :setInputType("number"):setPosition(10,7):setSize(8,1):setDefaultText("0")

bankF:addLabel():setText("Account:"):setPosition(20,7):setForeground(colors.black)
local acctDD = bankF:addDropdown():setPosition(29,7):setSize(12,1)
acctDD:addItem("Checking"); acctDD:addItem("Savings")

local function amt()  return math.max(0, math.floor(tonumber( (amtTF.getValue and amtTF:getValue()) or "0") or 0)) end
local function acct() local v = (acctDD.getValue and acctDD:getValue()) or "Checking"; return tostring(v):lower() end
local function loanActive() return (economyAPI and economyAPI.hasActiveLoan and economyAPI.hasActiveLoan()) or false end

local function selectedAccount()
  -- Try text first
  local v = (acctDD.getValue and acctDD:getValue()) or ""
  if type(v) == "string" and v ~= "" then
    v = v:lower()
    if v:find("sav", 1, true) then return "savings" end
    return "checking"
  end
  -- Fallback to index
  local idx = (acctDD.getItemIndex and acctDD:getItemIndex()) or 1
  return (idx == 2) and "savings" or "checking"
end

-- Buttons (we build them once)
local dBtn = bankF:addButton():setText("Deposit"):setPosition(2,9):setSize(8,1)
local wBtn = bankF:addButton():setText("Withdraw"):setPosition(12,9):setSize(9,1)

-- Updaters that re-apply visual enable/disable every time the tab is shown
function refreshButtons()
  if loanActive() and selectedAccount() == "savings" then
    -- savings deposit disabled while a loan is active
    dBtn:setBackground(colors.lightGray):setForeground(colors.white)
  else
    dBtn:setBackground(colors.green):setForeground(colors.white)
  end
  wBtn:setBackground(colors.red):setForeground(colors.white)
end

-- Safe handlers (no duplicate binds)
dBtn:onClick(function()
  local a = amt()
  if a <= 0 then return end
  if selectedAccount() == "savings" and loanActive() then
    M.toast(bankF, "Savings disabled while loan active", 5, 11, colors.red, 1.6)
    return
  end
  local ok, msg = economyAPI.deposit(a, selectedAccount())   -- checking -> selected acct
  if selectedAccount() == "savings" then dAct = "savings" else  dAct = "checkings" end
  M.toast(bankF, ok and ("Deposited $"..a.." to "..dAct) or (msg or "Failed"), ok and 9 or 8, 11, ok and colors.green or colors.red, 1.8)
  M.refreshBalances(); refreshButtons()
end)

wBtn:onClick(function()
  local a = amt()
  if a <= 0 then return end
  if selectedAccount() == "savings" then wAct = "savings" else  wAct = "checkings" end
  local ok, msg = economyAPI.withdraw(a, selectedAccount())  -- selected acct -> checking
  M.toast(bankF, ok and ("Withdrew $"..a.." from "..wAct) or (msg or "Failed"), ok and 9 or 8, 11, ok and colors.green or colors.red, 1.4)
  M.refreshBalances(); refreshButtons()
end)

if acctDD.onChange then acctDD:onChange(function() M.refreshBalances() refreshButtons() end) end
M.refreshBalances()
refreshButtons()
  ----------------------------------------------------------------
  -- STOCKS TAB (your code kept as-is)
  ----------------------------------------------------------------
  local stocksF = pages.stocks
  local curStage = (stageAPI and stageAPI.getStage and stageAPI.getStage()) or "base"
  if curStage ~= "tower" then
    stocksF:addLabel():setText("High-Rise stage required to unlock \n          stock market"):setPosition(5,2):setForeground(colors.gray)
  else
    stocksF:addLabel():setText("Ticker Price ^"):setPosition(2,1):setForeground(colors.gray)
    local listFrame = stocksF:addFrame():setPosition(2,2):setSize(14,10):setBackground(colors.white)
    local graphFrame = stocksF:addFrame():setPosition(17,1):setSize(21,7):setBackground(colors.white)
    local ctlFrame   = stocksF:addFrame():setPosition(17,8):setSize(21,4):setBackground(colors.white)

    local tickers = economyAPI.getStocks()
    local selected = 1
    local tickerBtns = {}

    function M.renderList()
      tickers = economyAPI.getStocks()
      for i,info in ipairs(tickers) do
        if not tickerBtns[i] then
          tickerBtns[i] = listFrame:addButton():setPosition(1, (i-1)*2+1):setSize(12,1)
            :onClick(function() selected = i; M.renderList(); M.renderChart(); M.renderControls() end)
        end
        local snap = economyAPI.getStock(info.sym)
        local h = snap.history or {}
        local prev = (#h >= 2) and h[#h-1] or info.price
        local delta = info.price - prev
        local s = string.format("%-3s %6.0f %s", info.sym, info.price, (delta>=0 and "^" or "v"))
        tickerBtns[i]:setText(s)
          :setBackground(i==selected and colors.blue or colors.lightGray)
          :setForeground(i==selected and colors.white or colors.gray)
      end
    end

    local chartDots = {}
    local function clearChart()
      for _,lbl in ipairs(chartDots) do if lbl and lbl.remove then pcall(function() lbl:remove() end) end end
      chartDots = {}
    end
    function M.renderChart()
      clearChart()
      local info = tickers[selected]; if not info then return end
      local snap = economyAPI.getStock(info.sym)
      local hist = snap.history or {}
      local n = #hist
      local take = 21
      local start = math.max(1, n - take + 1)
      local view = {}
      for i=start, n do table.insert(view, hist[i]) end
      if #view == 0 then return end
      local vmin, vmax = view[1], view[1]
      for _,v in ipairs(view) do if v < vmin then vmin = v end; if v > vmax then vmax = v end end
      local span = math.max(0.01, vmax - vmin)

      for x=1,#view do
        local v = view[x]
        local t = (v - vmin) / span
        local y = 1 + (6 - math.floor(t*7 + 0.5))
        chartDots[#chartDots+1] = graphFrame:addLabel():setPosition(x, y):setText("*")
      end
      chartDots[#chartDots+1] = graphFrame:addLabel():setPosition(1, 7):setText(("$%.0f"):format(vmin)):setForeground(colors.gray)
      chartDots[#chartDots+1] = graphFrame:addLabel():setPosition(1, 1):setText(("$%.0f"):format(vmax)):setForeground(colors.gray)
    end

    local qtyDD, buyBtn, sellBtn, maxBtn, allBtn, holdLbl, priceLbl
    local qty = qty or 1
    local qtyLbl = ctlFrame:addLabel():setPosition(5,2):setText(tostring(qty)):setForeground(colors.black)
    function M.renderControls()
      for _,c in ipairs({qtyDD,buyBtn,sellBtn,maxBtn,allBtn,holdLbl,priceLbl}) do
        if c and c.remove then pcall(function() c:remove() end) end
      end
      local info = tickers[selected]; if not info then return end
      local snap = economyAPI.getStock(info.sym)
      priceLbl = ctlFrame:addLabel():setPosition(1,1)
        :setText(string.format("%s @ $%.0f ", info.sym, info.price)):setForeground(colors.black)
      holdLbl = ctlFrame:addLabel():setPosition(13,1)
        :setText(string.format("Hold: %d", snap.qty or 0)):setForeground(colors.gray)

      local function clamp(n) if n > 1 then return n else n = 1 end return n end
      local function setQty(n) qty = clamp(n); if qtyLbl and qtyLbl.setText then qtyLbl:setText(string.format("%d", qty)):setPosition(5,2) end end

      ctlFrame:addButton():setText("<<"):setPosition(2,2):setSize(2,1)
        :setBackground(colors.lightGray):setForeground(colors.black)
        :onClick(function() setQty(qty - 1) end)
      ctlFrame:addButton():setText(">>"):setPosition(8,2):setSize(2,1)
        :setBackground(colors.lightGray):setForeground(colors.black)
        :onClick(function() setQty(qty + 1) end)

      buyBtn  = ctlFrame:addButton():setText("Buy"):setPosition(10,2):setSize(5,1)
        :setBackground(colors.green):setForeground(colors.white)
        :onClick(function()
          local q = qty
          local ok,msg = economyAPI.buyStock(info.sym, q)
          M.toast(ctlFrame, ok and ("Bought "..q.." "..info.sym) or msg, 3, 4, ok and colors.green or colors.red, 1.2)
          M.renderList(); M.renderChart(); M.renderControls()
        end)

      sellBtn = ctlFrame:addButton():setText("Sell"):setPosition(16,2):setSize(5,1)
        :setBackground(colors.red):setForeground(colors.white)
        :onClick(function()
          local q = qty
          local ok,msg = economyAPI.sellStock(info.sym, q)
          M.toast(ctlFrame, ok and ("Sold "..q.." "..info.sym) or msg, 3, 4, ok and colors.green or colors.red, 1.2)
          M.renderList(); M.renderChart(); M.renderControls()
        end)

      maxBtn = ctlFrame:addButton():setText("BuyMax"):setPosition(1,3):setSize(7,1)
        :setBackground(colors.blue):setForeground(colors.white)
        :onClick(function()
          local ok,msg = economyAPI.buyMax(info.sym)
          M.toast(ctlFrame, ok and ("Bought MAX "..info.sym) or msg, 3, 4, ok and colors.green or colors.red, 1.2)
          M.renderList(); M.renderChart(); M.renderControls()
        end)

      allBtn = ctlFrame:addButton():setText("SellAll"):setPosition(9,3):setSize(7,1)
        :setBackground(colors.gray):setForeground(colors.white)
        :onClick(function()
          local ok,msg = economyAPI.sellAll(info.sym)
          M.toast(ctlFrame, ok and ("Sold ALL "..info.sym) or msg, 3, 4, ok and colors.green or colors.red, 1.2)
          M.renderList(); M.renderChart(); M.renderControls()
        end)
    end

    M.renderList(); M.renderChart(); M.renderControls()
  end

  -- default shown tab
  show("bank")
  M.refreshBalances()
end


return M

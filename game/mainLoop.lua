
-- mainLoop.lua (Rewritten Core) — PixelCorp
-- Goals:
-- 1) Keep the same UI layout and interactions.
-- 2) Push logic into APIs where possible.
-- 3) Keep stage backgrounds stable & fast (no re-paint thrash).
-- 4) Be consistent and predictable; no hidden globals beyond those set by uiAPI.

-- =========
-- Bootstrap
-- =========
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

-- Core deps (APIs own the heavy logic)
local basalt       = require(root.."/API/basalt")
local uiAPI        = require(root.."/API/uiAPI")
local timeAPI      = require(root.."/API/timeAPI")
local saveAPI      = require(root.."/API/saveAPI")
local stageAPI     = require(root.."/API/stageAPI")
local backgroundAPI= require(root.."/API/backgroundAPI")
local licenseAPI   = require(root.."/API/licenseAPI")
local itemsAPI     = require(root.."/API/itemsAPI")
local inventoryAPI = require(root.."/API/inventoryAPI")
local economyAPI   = require(root.."/API/economyAPI")
local levelAPI     = require(root.."/API/levelAPI")
local upgradeAPI   = require(root.."/API/upgradeAPI")
local craftAPI     = require(root.."/API/craftAPI")
local tutorialAPI  = require(root.."/API/tutorialAPI")
local guideAPI     = require(root.."/API/guideAPI")
local guideData    = require(root.."/API/guideData")
local eventAPI = require(root.."/API/eventAPI") 

-- Seed RNG safely
pcall(function() math.randomseed(os.epoch("utc") % 2^31); for i=1,3 do math.random() end end)

-- Screen
local SCREEN_WIDTH, SCREEN_HEIGHT = term.getSize()

-- ==========================
-- Build the shared UI layout
-- ==========================
local UI = uiAPI.createBaseLayout()
local mainFrame        = UI.mainFrame
local topBar           = UI.topBar
local sidebar          = UI.sidebar
local displayFrame     = UI.displayFrame
local inventoryOverlay = UI.inventoryOverlay
local pauseMenu        = UI and UI.pauseMenu or pauseMenu

-- Stash references for convenience
local function Wipe(frame) if frame and frame.removeChildren then frame:removeChildren() end end

-- =========
-- Guide HUD
-- =========
guideAPI.init(mainFrame); guideAPI.setData(guideData)

-- ==============
-- Stage helpers
-- ==============
local function progressToArt(progress)
  if progress == "lemonade_stand" then return "lemonade"
  elseif progress == "warehouse"   then return "office"
  elseif progress == "factory"     then return "factory"
  elseif progress == "highrise"    then return "tower"
  else return "base" end
end

local function applyStageFromProgress()
  local s = saveAPI.get() or {}; s.player = s.player or {}
  local artKey = progressToArt(s.player.progress or "odd_jobs")
  if stageAPI.setStage then stageAPI.setStage(artKey) end
  pcall(function() if stageAPI.invalidateBackground then stageAPI.invalidateBackground() end end)
  pcall(function() if backgroundAPI and backgroundAPI.clear then backgroundAPI.clear(displayFrame) end end)
  stageAPI.refreshBackground(displayFrame)
end

uiAPI.onStageChanged(function(nextProgressKey)
  local artKey = uiAPI.progressToArt and uiAPI.progressToArt(nextProgressKey) or progressToArt(nextProgressKey)
  if stageAPI.setStage then stageAPI.setStage(artKey) end
  pcall(function() if stageAPI.invalidateBackground then stageAPI.invalidateBackground() end end)
  pcall(function() if backgroundAPI and backgroundAPI.clear then backgroundAPI.clear(displayFrame) end end)
  stageAPI.refreshBackground(displayFrame)
end)

-- ==================
-- Inventory Overlay
-- ==================
-- Tabs are owned here (we keep layout identical to previous UI).
local inventoryTabs = {}
local TAB_ORDER = { "Materials", "Products", "Crafting", "All" }

local tabBar = inventoryOverlay:addMenubar()
  :setPosition(2, 2):setSize(40,1):setScrollable(false)
  :addItem(" Materials"):addItem(" Products"):addItem(" Crafting"):addItem(" All ")

local function selectInventoryTab(name)
  for k, f in pairs(inventoryTabs) do if f and f.hide then f:hide() end end
  if inventoryTabs[name] then inventoryTabs[name]:show() end
end

local function menubarSelectedName(self)
  local idx = self.getItemIndex and self:getItemIndex() or 1
  return TAB_ORDER[idx] or "Materials"
end

tabBar:onChange(function(self) selectInventoryTab(menubarSelectedName(self)) end)

-- Tab shells (same positions/sizes/colors as before)
inventoryTabs["Materials"] = inventoryOverlay:addScrollableFrame()
  :setPosition(2,4):setSize(40,12):setBackground(colors.white):hide()
inventoryTabs["Products"]  = inventoryOverlay:addScrollableFrame()
  :setPosition(2,4):setSize(40,12):setBackground(colors.white):hide()
inventoryTabs["Crafting"]  = inventoryOverlay:addFrame()
  :setPosition(2,4):setSize(40,12):setBackground(colors.white):hide()
inventoryTabs["All"]       = inventoryOverlay:addScrollableFrame()
  :setPosition(2,4):setSize(40,12):setBackground(colors.white):hide()

-- ======
-- Stock
-- ======
-- The market logic lives in inventoryAPI; this page just renders it.
local STOCK_CATS  = { base="Cups", fruit="Fruit", sweet="Sweetener", topping="Toppings" }
local STOCK_ORDER = { "base","fruit","sweet","topping" }
local _stockCatIdx = 1
local pageElements = { stock = {}, upgrades = {}, main = {}, development = {} }
local function _rarityColor(it) return itemsAPI.itemRarityColor(it) end

local function _clearGroup(name)
  if pageElements[name] then
    for _, el in ipairs(pageElements[name]) do
      if el and el.remove then pcall(function() el:remove() end) end
      if el and el.destroy then pcall(function() el:destroy() end) end
    end
    pageElements[name] = {}
  end
end

-- =====================
-- Materials/Products UI
-- =====================
local function _mkHeader(tab) 
  tab:addLabel():setPosition(3,1):setText("Item"):setForeground(colors.yellow)
  tab:addLabel():setPosition(25,1):setText("+$"):setForeground(colors.yellow)
  tab:addLabel():setPosition(37,1):setText("Qty"):setForeground(colors.yellow)
end
local function _mkRow(tab, y, name, qty, value, color)
  tab:addLabel():setPosition(3,y):setSize(27,1):setText(name or ""):setForeground(color)
  tab:addLabel():setPosition(24,y):setSize(10,1):setText(("(+$%d ea)"):format(tonumber(value) or 0))
  tab:addLabel():setPosition(34,y):setSize(6,1):setText(tostring(qty or 0)):setTextAlign("right")
end
local function _mkHeaderProducts(tab)
  tab:addLabel():setPosition(3,1):setText("Item"):setForeground(colors.yellow)
  tab:addLabel():setPosition(31,1):setText("Qty"):setForeground(colors.yellow)
  tab:addLabel():setPosition(37,1):setText("$"):setForeground(colors.yellow)
end
local function _mkRowProduct(tab, y, name, qty, price)
  tab:addLabel():setPosition(3,y):setText(name or "")
  tab:addLabel():setPosition(30,y):setText("|")
  tab:addLabel():setPosition(30,y):setSize(4,1):setText(tostring(qty or 0)):setTextAlign("right")
  tab:addLabel():setPosition(35,y):setSize(5,1):setText(tostring(price or 0)):setTextAlign("right")
end

local function _safeText(str, maxLen)
  local t = tostring(str or "")
  t = t:gsub("[\0-\8\11\12\14-\31]", " ")
  t = t:gsub("\t", " ")
  t = t:gsub("\r?\n", " ")
  if maxLen and #t > maxLen then t = t:sub(1, maxLen) end
  return t
end

local function _inventoryMap()
  local s = saveAPI.get(); s.player = s.player or {}; s.player.inventory = s.player.inventory or {}
  return s.player.inventory
end

local rarityRank = { common=1, uncommon=2, rare=3, unique=4, legendary=5, mythical=6, relic=7, masterwork=8, divine=9 }
local function _rarityRank(it) local r=(it.rarity or "common"); if type(r)=="table" then r=r.name or "common" end; return rarityRank[tostring(r):lower()] or 1 end

local function safeGetMaterials()
  local have = _inventoryMap()
  local mats = {}
  local L = levelAPI.getLevel()
  for _, it in ipairs(itemsAPI.getAll()) do
    if itemsAPI.isUnlockedForLevel(it.id, L) then
      local qty = tonumber(have[it.id] or 0) or 0
      if qty > 0 then
        table.insert(mats, { key=it.id, label=it.name, qty=qty, base=tonumber(it.base_value or 0) or 0, type=it.type or "material", rarity=it.rarity or "common", color=itemsAPI.itemRarityColor(it) })
      end
    end
  end
  table.sort(mats, function(a,b)
    if a.type ~= b.type then return a.type < b.type end
    local ra, rb = _rarityRank(a), _rarityRank(b); if ra ~= rb then return ra > rb end
    return (a.label or a.key) < (b.label or b.key)
  end)
  return mats
end

local function safeGetProducts()
  local have = _inventoryMap()
  local known = {}; for _, it in ipairs(itemsAPI.getAll()) do known[it.id]=true end
  local out = {}
  for k,v in pairs(have) do
    if not known[k] then local q=tonumber(v) or 0; if q>0 then table.insert(out, { key=k, label=k, qty=q, type="product" }) end end
  end
  table.sort(out, function(a,b) return (a.label or a.key) < (b.label or b.key) end)
  return out
end

local function safeGetAll()
  local a = {}; for _,it in ipairs(safeGetMaterials()) do table.insert(a,it) end; for _,it in ipairs(safeGetProducts()) do table.insert(a,it) end; return a
end

local function getProductPrice(keyOrName)
  if economyAPI and economyAPI.getPrice then
    local p = economyAPI.getPrice(keyOrName); if type(p)=="number" then return p end
  end
  local s = saveAPI.get(); local ep = (s.economy and s.economy.prices) or {}
  return tonumber(ep[keyOrName] or 0) or 0
end

local function populateMaterials()
  local tab = inventoryTabs["Materials"]; Wipe(tab); _mkHeader(tab)
  local y=2; for _, it in ipairs(safeGetMaterials()) do _mkRow(tab,y,_safeText(it.label,29), it.qty, it.base, it.color); y=y+1 end
end
local function populateProducts()
  local tab = inventoryTabs["Products"]; Wipe(tab); _mkHeaderProducts(tab)
  local y=2; for _, it in ipairs(safeGetProducts()) do
    local shown = it.label
    if type(shown)=="string" and shown:find("^drink:") and craftAPI.prettyNameFromKey then shown = craftAPI.prettyNameFromKey(shown) end
    local price = getProductPrice(it.key)
    _mkRowProduct(tab,y,_safeText(shown,28), it.qty, price); y=y+1
  end
end
local function populateAll()
  local tab = inventoryTabs["All"]; Wipe(tab); _mkHeader(tab)
  local y=2; for _, it in ipairs(safeGetAll()) do
    local shown = it.label or it.key
    if type(shown)=="string" and shown:find("^drink:") and craftAPI.prettyNameFromKey then shown = craftAPI.prettyNameFromKey(shown) end
    local price = getProductPrice(it.label or it.key)
    local tag = (it.type=="material") and "M" or "P"
    _mkRow(tab,y,_safeText(("["..tag.."] "..shown),26), it.qty, it.base or price, it.color); y=y+1
  end
end

-- Map friendly names → actual item ids (fallbacks if not found)
local function _id(name) return (itemsAPI.idByName and itemsAPI.idByName(name)) or name end

local LOOT = {
  bush   = { pool = {"Cherry","Berry"},    qty = function() return math.random(1,8) end,  icon="*", color=colors.purple   },
  tree   = { pool = {"Lemon","Mango"},     qty = function() return math.random(1,4) end,  icon="*", color=colors.lime  },
  ground = { cash = true,                   amt = function() return math.random(5,50) end, icon="$", color=colors.yellow},
}

local function _safeGiveItems(names, count)
  for i,name in ipairs(names or {}) do
    local id = _id(name)
    if id then inventoryAPI.add(id, count) end  -- inventoryAPI.add exists and saves :contentReference[oaicite:2]{index=2}
  end
end

local function spawnBush(x, y)
  uiAPI._spawnPickup(displayFrame, x, y, LOOT.bush.icon, LOOT.bush.color, 8, function()
    local n = LOOT.bush.qty()
    -- choose one fruit from pool
    local which = LOOT.bush.pool[math.random(1, #LOOT.bush.pool)]
    _safeGiveItems({which}, n)
    uiAPI.toast("displayFrame", ("Picked +"..n.." "..which), 15, 17, colors.yellow, 1.6)
  end)
end

local function spawnTreeFruit(x, y)
  uiAPI._spawnPickup(displayFrame, x, y, LOOT.tree.icon, LOOT.tree.color, 8, function()
    local n = LOOT.tree.qty()
    local which = LOOT.tree.pool[math.random(1, #LOOT.tree.pool)]
    _safeGiveItems({which}, n)
    uiAPI.toast("displayFrame", ("Shook +"..n.." "..which), 15, 17, colors.yellow, 1.6)
  end)
end

local function spawnGroundCash(x, y)
  uiAPI._spawnPickup(displayFrame, x, y, LOOT.ground.icon, LOOT.ground.color, 6, function()
    local amt = LOOT.ground.amt()
    if economyAPI and economyAPI.addMoney then economyAPI.addMoney(amt, "Found cash") end
    uiAPI.toast("displayFrame", ("Found $"..amt), 20, 17, colors.yellow, 1.5)
    uiAPI.refreshBalances()
  end)
end
local SpawnCtrl = {
  max_active = 3,   -- never show more than 3 pickups on screen
  cooldown   = 60,   -- minutes remaining before another spawn is allowed
  charge     = 0,   -- increases each minute w/out a spawn (ramps probability)
}

local function trySpawnWorldPickup(t)
  local hour = t.hour or 0

  -- only daytime
  local daylight = (hour >= 7 and hour <= 20)
  if not daylight then return end

  -- enforce on-screen cap
  local active = (uiAPI.getActivePickups and uiAPI.getActivePickups()) or 0
  if active >= SpawnCtrl.max_active then
    return
  end

  -- hard cooldown (in in-game minutes) after any successful spawn
  if SpawnCtrl.cooldown > 0 then
    SpawnCtrl.cooldown = SpawnCtrl.cooldown - 1
    return
  end

  local base   = 0.002    -- 0.4% baseline per minute
  local chance = base * (1 + SpawnCtrl.charge * 0.2)

  if math.random() < chance then
    -- Choose a spawn type uniformly to keep it varied
    local r = math.random()
    if r < 0.34 then
      spawnBush(8 + math.random(0, 40), math.random(13, 17))
    elseif r < 0.67 then
      spawnTreeFruit(math.random(29, 33), math.random(9, 11))
    else
      spawnGroundCash(1 + math.random(1, 48), math.random(13, 17))
    end

    -- reset ramp and start a new cooldown window (8–16 in-game minutes)
    SpawnCtrl.charge   = 0
    SpawnCtrl.cooldown = math.random(8, 16)  -- space spawns further apart
  else
    -- no spawn this minute; slightly increase the ramp (soft "decay" to fewer spawns)
    SpawnCtrl.charge = math.min(20, SpawnCtrl.charge + 1)
  end
end

-- Fire this every minute via eventAPI’s global listeners
eventAPI.onGlobal(function(t) trySpawnWorldPickup(t) end)

-- ========
-- Crafting
-- ========
local _craftSel = _craftSel or { product="Lemonade", base=nil, fruit=nil, sweet=nil, topping=nil }

-- Compact stepper (keeps same look/feel)
local function mkStepper(parent, x, y, w, color)
  local f = parent:addFrame():setPosition(x,y):setSize(w,1):setBackground(colors.white):setForeground(color or colors.white)
  f._items, f._i, f._onChange = {}, 1, nil
  local lblW = w - 4
  local function updateLabel()
    local t = f._items[f._i] or ""
    if type(t)=="table" then t = t.text or t[1] or "" end
    if f._lbl then f._lbl:setText(t) end
  end
  f._lbl = f:addLabel():setPosition(1,1):setSize(lblW,1):setText("")
  local btnL=f:addButton():setPosition(lblW-3,1):setSize(3,1):setText(" <<"):setBackground(colors.white)
    :onClick(function() if #f._items==0 then return end; f._i=(f._i-2)%#f._items+1; updateLabel(); if f._onChange then f._onChange() end end)
  local btnR=f:addButton():setPosition(lblW,1):setSize(3,1):setText(">>"):setBackground(colors.white)
    :onClick(function() if #f._items==0 then return end; f._i=(f._i)%#f._items+1;   updateLabel(); if f._onChange then f._onChange() end end)
  function f:setItems(list) self._items=list or {}; self._i=(#self._items>0) and 1 or 1; updateLabel(); return self end
  function f:setIndex(i) if #self._items==0 then self._i=1; updateLabel(); return self end; if i<1 then i=1 elseif i>#self._items then i=#self._items end; self._i=i; updateLabel(); return self end
  function f:getText() local t=self._items[self._i]; if type(t)=="table" then t=t.text or t[1] end; return t end
  function f:onChange(fn) self._onChange=fn; return self end
  return f
end

local function cleanLabel(label)
  if type(label)~="string" then return label end
  local name = label:match("^(.-)%s*|%s*rq:") or label
  return (name:gsub("%s+$",""))
end

local function idByLabel(label) return itemsAPI.idByName(label) end
local function reqByLabel(label) return itemsAPI.craftReqByName(label) or 0 end

local function optionLabelsForType(typeName, haveMap, playerLevel, currentProduct)
  local list = {}
  currentProduct = currentProduct or (_craftSel.product or "Lemonade")
  local iceShaver = upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution()

  local function push(name, id, req, qtyKey)
    local qty = tonumber(haveMap[qtyKey or id] or 0) or 0
    if qty > 0 then table.insert(list, ("%s|rq:%d|S:%d"):format(name, req, qty)) end
  end

  if currentProduct == "Italian Ice" then
    if typeName == "base" then
      for _, it in ipairs(itemsAPI.listByType("base")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then push(it.name, it.id, tonumber(it.craft_req or 0) or 0) end
      end
    elseif typeName == "fruit" then
      if iceShaver then
        local shaved = itemsAPI.getByName("Shaved Ice"); if shaved then
          local iceId = itemsAPI.idByName("Ice Cubes"); local req=2
          if iceId then push(shaved.name, shaved.id, req, iceId) end
        end
      end
    elseif typeName == "sweet" then
      for _, it in ipairs(itemsAPI.listByType("sweet")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) and itemsAPI.isSyrup(it.id) then push(it.name, it.id, tonumber(it.craft_req or 0) or 0) end
      end
    elseif typeName == "topping" then
      for _, it in ipairs(itemsAPI.listByType("topping")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then
          local nameLower = (it.name or ""):lower()
          if nameLower ~= "ice" and nameLower ~= "ice cubes" and nameLower ~= "shaved ice" then
            push(it.name, it.id, tonumber(it.craft_req or 0) or 0)
          end
        end
      end
      for _, it in ipairs(itemsAPI.listByType("fruit")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then
          local qty = tonumber(haveMap[it.id] or 0) or 0
          if qty > 0 then table.insert(list, ("%s| rq:%d | S:%d"):format(it.name, 1, qty)) end
        end
      end
    end
  else
    for _, it in ipairs(itemsAPI.listByType(typeName)) do
      if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then
        local req = tonumber(it.craft_req or 0) or 0
        if typeName == "fruit" then
          local delta = upgradeAPI.fruitReqDelta and upgradeAPI.fruitReqDelta() or 0
          req = math.max(0, req + delta)
        end
        if typeName == "topping" then
          local nameLower = (it.name or ""):lower()
          if nameLower == "shaved ice" then goto continue end
        end
        push(it.name, it.id, req)
      end
      ::continue::
    end
  end
  table.sort(list)
  return list
end

local ddProduct -- forward

local function populateCrafting()
  local tab = inventoryTabs["Crafting"]; Wipe(tab)
  tab:addLabel():setPosition(1,1):setText("Select Items to craft x5 for:")
  ddProduct = tab:addDropdown():setPosition(30,1):setSize(12,1):setZIndex(40)

  local L = (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1
  ddProduct:addItem("Lemonade")
  if (upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution()) and L >= 10 then
    ddProduct:addItem("Italian Ice")
  end

  local function _selectProductByName(name)
    if not ddProduct or not ddProduct.getItemCount then return false end
    for i=1, ddProduct:getItemCount() do local it=ddProduct:getItem(i); local v=(type(it)=="table" and it.text) or it
      if v==name then ddProduct:selectItem(i); return true end end
    return false
  end

  if not _craftSel.product or not _selectProductByName(_craftSel.product) then
    ddProduct:selectItem(1); local it=ddProduct:getItem(1); _craftSel.product=(type(it)=="table" and it.text) or it or "Lemonade"
  end

  local have = _inventoryMap()
  local currentProduct = _craftSel.product or "Lemonade"
  local baseOpts    = optionLabelsForType("base",    have, L, currentProduct)
  local fruitOpts   = optionLabelsForType("fruit",   have, L, currentProduct)
  local sweetOpts   = optionLabelsForType("sweet",   have, L, currentProduct)
  local toppingOpts = optionLabelsForType("topping", have, L, currentProduct); if #toppingOpts==0 or toppingOpts[1]~="None" then table.insert(toppingOpts,1,"None") end
  if #baseOpts==0    then baseOpts    = { (itemsAPI.listByType("base")[1]    or {}).name or "Plastic Cup" } end
  if #fruitOpts==0   then fruitOpts   = { (itemsAPI.listByType("fruit")[1]   or {}).name or "Lemon" } end
  if #sweetOpts==0   then sweetOpts   = { (itemsAPI.listByType("sweet")[1]   or {}).name or "Sugar" } end
  if #toppingOpts==0 then toppingOpts = { "None" } end

  local function buildColorMap(opts)
    local map = {}; for _, name in ipairs(opts) do
      if name=="None" or name=="" then map[name]=colors.gray
      else
        local baseName = cleanLabel(name)
        local id = idByLabel(baseName)
        map[name] = (itemsAPI.itemRarityColor and itemsAPI.itemRarityColor(id or baseName)) or colors.white
      end
    end; return map
  end
  local baseColMap, fruitColMap, sweetColMap, toppingColMap = buildColorMap(baseOpts), buildColorMap(fruitOpts), buildColorMap(sweetOpts), buildColorMap(toppingOpts)

  local y=4
  local lblFruit = (currentProduct == "Italian Ice") and "Ice:" or "Fruit:"
  tab:addLabel():setPosition(2,y):setText("Cups:");     local ddBase    = mkStepper(tab,12,y,32); y=y+1; ddBase:setItems(baseOpts)
  tab:addLabel():setPosition(2,y):setText(lblFruit);    local ddFruit   = mkStepper(tab,12,y,32); y=y+1; ddFruit:setItems(fruitOpts)
  tab:addLabel():setPosition(2,y):setText("Sweetener:");local ddSweet   = mkStepper(tab,12,y,32); y=y+1; ddSweet:setItems(sweetOpts)
  tab:addLabel():setPosition(2,y):setText("Topping:");  local ddTopping = mkStepper(tab,12,y,32); y=y+1; ddTopping:setItems(toppingOpts)
  
  local function _applyPrevious(stepper, opts, prev)
    if not prev or prev=="" then return end
    local basePrev = cleanLabel(prev)
    local idx = 1
    for i,txt in ipairs(opts) do
      local nm = cleanLabel(txt)
      if nm == basePrev then idx = i; break end
    end
    if stepper.setIndex then stepper:setIndex(idx) end
  end
  _applyPrevious(ddBase,    baseOpts,    _craftSel.base)
  _applyPrevious(ddFruit,   fruitOpts,   _craftSel.fruit)
  _applyPrevious(ddSweet,   sweetOpts,   _craftSel.sweet)
  _applyPrevious(ddTopping, toppingOpts, _craftSel.topping)

  local function applyStepColor(stepper, list, cmap) local v=stepper:getText() or list[1]; local col=(cmap and cmap[v]) or colors.white; (stepper._lbl or stepper):setForeground(col) end
  applyStepColor(ddBase,baseOpts,baseColMap); applyStepColor(ddFruit,fruitOpts,fruitColMap); applyStepColor(ddSweet,sweetOpts,sweetColMap); applyStepColor(ddTopping,toppingOpts,toppingColMap)

  local status   = tab:addLabel():setPosition(2,12):setSize(28,1):setText("")
  local craftBtn = tab:addButton():setPosition(34,12):setSize(5,1):setText("Craft")

  local function pick(stepper, list) local v=stepper:getText(); if not v or v=="" then v=list[1] end; return v end

  local function computePossible()
    local base    = cleanLabel(pick(ddBase,baseOpts))
    local fruit   = cleanLabel(pick(ddFruit,fruitOpts))
    local sweet   = cleanLabel(pick(ddSweet,sweetOpts))
    local topping = cleanLabel(pick(ddTopping,toppingOpts))
    local needs = {}
    local bk, fk, sk = idByLabel(base), idByLabel(fruit), idByLabel(sweet)
    local tk         = (topping ~= "None") and idByLabel(topping) or nil

    local n
    local currentProduct = _craftSel.product or "Lemonade"
    local iceShaver = upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution()

    n = reqByLabel(base); if bk and n and n > 0 then needs[bk] = n end

    if currentProduct == "Italian Ice" then
      if iceShaver then
        local iceId = idByLabel("Ice Cubes"); if iceId then needs[iceId] = (needs[iceId] or 0) + 2 end
      else return 0, base, fruit, sweet, topping end
      local swId = idByLabel(sweet); if not (itemsAPI.isSyrup and (itemsAPI.isSyrup(swId) or itemsAPI.isSyrup(sweet))) then return 0, base, fruit, sweet, topping end
    else
      n = reqByLabel(fruit); if fk and n and n > 0 then local delta = upgradeAPI.fruitReqDelta and upgradeAPI.fruitReqDelta() or 0; n = math.max(0, n + delta); if n>0 then needs[fk] = n end end
    end

    n = reqByLabel(sweet); if sk and n and n>0 then needs[sk]=n end

    if tk then
      n = reqByLabel(topping); if n and n>0 then needs[tk]=n end
      if currentProduct ~= "Italian Ice" and iceShaver and topping=="Shaved Ice" then
        local iceId = idByLabel("Ice Cubes"); if iceId then needs[tk]=nil; needs[iceId]=(needs[iceId] or 0) + n end
      end
      if currentProduct == "Italian Ice" then
        local topId = idByLabel(topping); local it = itemsAPI.getById(topId) or itemsAPI.getByName(topping)
        if it and it.type=="fruit" then needs[topId] = 1 end
      end
    end

    local inv = _inventoryMap()
    local max = math.huge
    for k, need in pairs(needs) do if need > 0 then max = math.min(max, math.floor((inv[k] or 0) / need)) end end
    if max == math.huge then max = 0 end
    return max, base, fruit, sweet, topping
  end

  local function refreshStatus()
    local can = computePossible()
    local count = type(can)=="number" and can or 0
    status:setText("Can craft: "..tostring(count).."  (x5 per craft)")
    if craftBtn.setEnabled then craftBtn:setEnabled(count>0) end
    if craftBtn.setBackground then craftBtn:setBackground((count>0) and colors.green or colors.gray) end
  end

  ddBase:onChange(function()  applyStepColor(ddBase,baseOpts,baseColMap);   _craftSel.base=ddBase:getText();    refreshStatus() end)
  ddFruit:onChange(function() applyStepColor(ddFruit,fruitOpts,fruitColMap);_craftSel.fruit=ddFruit:getText();  refreshStatus() end)
  ddSweet:onChange(function() applyStepColor(ddSweet,sweetOpts,sweetColMap);_craftSel.sweet=ddSweet:getText();  refreshStatus() end)
  ddTopping:onChange(function()applyStepColor(ddTopping,toppingOpts,toppingColMap);_craftSel.topping=ddTopping:getText();refreshStatus() end)

  ddProduct:onChange(function()
    local v=ddProduct:getValue(); if type(v)=="table" and v.text then v=v.text end
    if type(v)=="string" and v~="" then _craftSel.product=v end
    populateCrafting()
  end)

  craftBtn:onClick(function()
    local can, base, fruit, sweet, topping = computePossible()
    local count = tonumber(can or 0) or 0
    if count <= 0 then return end

    _craftSel.base, _craftSel.fruit, _craftSel.sweet, _craftSel.topping =
      (cleanLabel(ddBase:getText())), (cleanLabel(ddFruit:getText())), (cleanLabel(ddSweet:getText())), (cleanLabel(ddTopping:getText()))

    local chosen = (_craftSel.product or "Lemonade"):match("^%s*(.-)%s*$")
    local ok, key, label = craftAPI.craftItem(chosen, base, fruit, sweet, topping)
    if ok then
      local computedPrice = craftAPI.computeCraftPrice(base, fruit, sweet, topping)
      if economyAPI and economyAPI.setPrice then economyAPI.setPrice(key, computedPrice) end
      refreshInventoryTabs()
      uiAPI.toast("overlay", ("Crafted: "..tostring(label).." x5"), 3, 13, colors.orange, 2.2)
    else
      status:setText(_safeText("Error: "..tostring(label), 28))
    end
  end)

  refreshStatus()
end

function refreshInventoryTabs()
  populateMaterials()
  populateProducts()
  populateCrafting()
  populateAll()
end

local function showInventoryOverlay()
  refreshInventoryTabs()
  inventoryOverlay:show()
  if tabBar.setItemIndex then tabBar:setItemIndex(1) end
  selectInventoryTab("Materials")
end

-- Hook the quick buttons in the top bar
uiAPI.onTopInv(function() showInventoryOverlay() end)
uiAPI.onTopCraft(function()
  showInventoryOverlay()
  if tabBar.setItemIndex then tabBar:setItemIndex(3) end
  selectInventoryTab("Crafting")
end)

-- ============
-- Upgrades UI
-- ============
local upgradeRowRefs, upgradeRowY = {}, {}
local LEFT_W, EFFECT_W, BTN_W, BTN_X = 26, 36, 15, 34
local function _pad(text, w) text=tostring(text or ""); local n=w-#text; return (n>0) and (text..string.rep(" ",n)) or text:sub(1,w) end
local function _canAfford(cost) return (economyAPI and economyAPI.canAfford and economyAPI.canAfford(cost)) or true end
local function _rowColor(state)  return (state=="locked" or state=="owned") and colors.gray or colors.black end
local function _effectColor(s)   return (s=="locked" or s=="owned") and colors.gray or colors.yellow end
local function _btnBg(en)        return en and colors.blue or colors.lightGray end
local function _btnFg(en)        return en and colors.white or colors.gray end
local function _prettyName(k) return ({seating="Seating",marketing="Marketing",awning="Awning",ice_shaver="Ice Shaver",juicer="Juicer",exp_boost="EXP Boost"})[k] or k end

local function _expMultNow() if upgradeAPI and upgradeAPI.expBoostFactor then return upgradeAPI.expBoostFactor() end; local s=saveAPI.get(); local u=s.upgrades or {}; local lvl=tonumber(u.exp_boost or 0) or 0; local M={1.0,1.5,2.25,3.5,4.25,5.0}; return M[math.min(lvl,5)+1] end
local function _expMultNext(lvl) local def = upgradeAPI.catalog and upgradeAPI.catalog.exp_boost; return def and def.multipliers and def.multipliers[(lvl or 0)+1] end
local function _effectText(key, lvl)
  if key=="seating"   then return ("Buy chance: %.0f%% -> %.0f%%"):format( 7*(lvl or 0), 7*((lvl or 0)+1) )
  elseif key=="marketing" then return ("Customers/hr: x%.2f -> x%.2f"):format(1+0.15*(lvl or 0), 1+0.15*((lvl or 0)+1))
  elseif key=="awning"    then return ("Price tolerance: x%.2f -> x%.2f"):format(1-0.12*(lvl or 0), 1-0.12*((lvl or 0)+1))
  elseif key=="exp_boost" then local cur=_expMultNow(); local nxt=_expMultNext(lvl); return nxt and ("XP boost: x%.2f -> x%.2f"):format(cur, nxt) or ("XP boost: x%.2f (Max)"):format(cur)
  elseif key=="ice_shaver" then return "Unlocks 'Italian Ice' product in Craft"
  elseif key=="juicer"     then return "Fruit requirement: -1 when crafting" end
  return ""
end

local function _destroyRow(key)
  local refs = upgradeRowRefs[key]
  if refs then for _,el in ipairs(refs) do if el and el.destroy then pcall(function() el:destroy() end) elseif el and el.remove then pcall(function() el:remove() end) end end end
  upgradeRowRefs[key] = nil
end

local function buildUpgradeRow(key, y)
  upgradeRowY[key] = y; _destroyRow(key)
  local def = upgradeAPI.catalog[key]
  local oneTime = def and def.one_time
  local lvl     = (upgradeAPI.level and upgradeAPI.level(key)) or 0
  local ownedOT = (upgradeAPI.has and upgradeAPI.has(key)) or false
  local cost    = (upgradeAPI.cost and upgradeAPI.cost(key)) or 0
  local canBuy, why = true, nil; if upgradeAPI.canPurchase then canBuy, why = upgradeAPI.canPurchase(key) end
  local atCap = (not oneTime) and def and def.level_cap and (lvl >= def.level_cap)

  local state = (oneTime and (ownedOT and "owned" or (canBuy and "buyable" or "locked"))) or ((atCap and "owned") or (canBuy and "buyable" or "locked"))
  local leftText = (oneTime and ("%s   $%d  (%s)"):format(_prettyName(key), cost, ownedOT and "Unlocked" or "Locked")) or ("%s   Lv %d"):format(_prettyName(key), lvl)

  local left = displayFrame:addLabel():setPosition(2,y):setSize(LEFT_W,1):setZIndex(50):setText(_pad(leftText, LEFT_W)):setForeground(_rowColor(state)):hide()
  local eff  = displayFrame:addLabel():setPosition(2,y+1):setSize(EFFECT_W,1):setZIndex(50):setText(_pad(_effectText(key,lvl), EFFECT_W)):setForeground(_effectColor(state)):hide()

  local btnText = (state=="locked" and "LOCKED") or (oneTime and (ownedOT and "Owned" or (key=="juicer" and "Upgrade req -1" or "Unlock Product"))) or ((atCap and "Maxed") or ("Lv "..(lvl+1).." - $"..tostring(cost)))
  local enabled = (state~="locked") and not (oneTime and ownedOT) and not (not oneTime and atCap) and _canAfford(cost) and canBuy
  local btn = displayFrame:addButton():setPosition(34,y):setSize(BTN_W,1):setText(btnText):setBackground(_btnBg(enabled)):setForeground(_btnFg(enabled)):setZIndex(20):hide()
    :onClick(function()
      local cBuy, whyNow = canBuy, why; if upgradeAPI.canPurchase then cBuy, whyNow = upgradeAPI.canPurchase(key) end
      local okEnabled = (state~="locked") and not (oneTime and ownedOT) and not (not oneTime and atCap) and _canAfford(cost) and cBuy
      if not okEnabled then uiAPI.toast("displayFrame", whyNow or "Locked", 17,4, colors.red,1.0); return end
      local ok, msg = upgradeAPI.purchase(key, function(c) return economyAPI.spendMoney(c) end)
      uiAPI.toast("displayFrame", msg or (ok and "Purchased!" or "Purchase failed"), 16,4, ok and colors.cyan or colors.red, 1.0)
      buildUpgradeRow(key, y); if currentPage=="upgrades" then for _,el in ipairs(upgradeRowRefs[key] or {}) do if el.show then el:show() end end end
    end)

  upgradeRowRefs[key] = { left, eff, btn }
  table.insert(pageElements.upgrades, left); table.insert(pageElements.upgrades, eff); table.insert(pageElements.upgrades, btn)
  if currentPage=="upgrades" then left:show(); eff:show(); btn:show() end
end

local function rebuildUpgradesPage()
  _clearGroup("upgrades")
  local y=3
  local hdr = displayFrame:addLabel():setText("Upgrades"):setPosition(2,y):setZIndex(10):hide()
  table.insert(pageElements.upgrades, hdr); y=y+1
  local Lvl = (levelAPI.getLevel and levelAPI.getLevel()) or 1
  if upgradeAPI.isVisibleAtLevel("seating",    Lvl) then buildUpgradeRow("seating",    y); y=y+2 end
  if upgradeAPI.isVisibleAtLevel("marketing",  Lvl) then buildUpgradeRow("marketing",  y); y=y+2 end
  if upgradeAPI.isVisibleAtLevel("awning",     Lvl) then buildUpgradeRow("awning",     y); y=y+2 end
  if upgradeAPI.isVisibleAtLevel("exp_boost",  Lvl) then buildUpgradeRow("exp_boost",  y); y=y+2 end
  if upgradeAPI.isVisibleAtLevel("ice_shaver", Lvl) then buildUpgradeRow("ice_shaver", y); y=y+2 end
  if upgradeAPI.isVisibleAtLevel("juicer",     Lvl) then buildUpgradeRow("juicer",     y); y=y+2 end
end

-- ==============
-- Main / Dev UI
-- ==============
local function buildMainPage()
  _clearGroup("main")

  local title = displayFrame:addLabel():setText("---------------| Main Screen |---------------"):setPosition(2,2):setZIndex(10):hide()
  local guideBtn = displayFrame:addButton():setText("[??]"):setPosition(2,3):setSize(4,1):setBackground(colors.blue):setForeground(colors.black):hide()
    :onClick(function()
       guideAPI.show()
    end)
  table.insert(pageElements.main, title); table.insert(pageElements.main, guideBtn)
end

-- ==================
-- Page switcher glue
-- ==================
local function hideAllPages()
  pcall(function() if uiAPI.hideStock then uiAPI.hideStock() end end)
  for name, group in pairs(pageElements or {}) do
    for _, el in ipairs(group) do
      if el then if el.disable then pcall(function() el:disable() end) end; if el.hide then pcall(function() el:hide() end) end end
    end
  end
  pcall(function() uiAPI.hideDevelopment() end)
  pcall(function() if uiAPI.disableDevelopment then uiAPI.disableDevelopment() end end)
end

currentPage = "main"
local function switchPage(name)
  hideAllPages()
  currentPage = name

  -- Keep background correct
  applyStageFromProgress()

  if name == "stock" then
  pcall(function() if uiAPI.showStock then uiAPI.buildStockPage() uiAPI.showStock()  end end); return
  elseif name == "upgrades" then
    rebuildUpgradesPage(); for _,el in ipairs(pageElements.upgrades) do if el.show then el:show() uiAPI.softRefreshStockLabels() end end; return
  elseif name == "development" then
    uiAPI.showDevelopment(); return
  else
  pcall(function() if uiAPI.killDevelopment then uiAPI.killDevelopment() end end)
    if #pageElements.main == 0 then buildMainPage() end
    for _,el in ipairs(pageElements.main) do if el.show then el:show() end end
  end
end

local function populateSidebar()
  local pages = {"Main","Development","Stock","Upgrades"}
  for i, page in ipairs(pages) do
    local pname = string.lower(page)
    sidebar:setBackground(colors.white)
  sBtn =  sidebar:addButton()
      :setText(page):setPosition(3, 2 + (i-1)*4):setSize(13,3)
      :setBackground(colors.lightBlue):setForeground(colors.black)
      :onClick(function() switchPage(pname) end)
  end
end

-- ==================
-- HUD / Level popup
-- ==================
local function renderLevelHUD()
  do
    local prog = levelAPI.getProgress and levelAPI.getProgress() or { level=1, xpInto=0, xpToNext=1 }
    local L = prog.level or (levelAPI.getLevel and levelAPI.getLevel()) or 1
    _G._lastLevelSeen = _G._lastLevelSeen or L
    if L > _G._lastLevelSeen then
      _G._lastLevelSeen = L
      -- Show unlocks popup (owned by this file for now to keep visuals same)
      local border = mainFrame:addFrame():setSize(34,14):setPosition(12,5):setBackground(colors.lightGray):setZIndex(220)
      local box    = border:addFrame():setSize(32,12):setPosition(2,2):setBackground(colors.white):setZIndex(221)
      box:addLabel():setText("Level Up!"):setPosition(12,1):setForeground(colors.green)
      local body   = box:addScrollableFrame():setPosition(3,5):setSize(26,6):setBackground(colors.white)
      local lpSub  = box:addLabel():setText(("You reached level %d!"):format(L)):setPosition(3,3):setForeground(colors.black)
      local items = {}
      local hasPrev = {}
      for _, it in ipairs(itemsAPI.getAll()) do if itemsAPI.isUnlockedForLevel(it.id, L-1) then hasPrev[it.id]=true end end
      for _, it in ipairs(itemsAPI.getAll()) do if itemsAPI.isUnlockedForLevel(it.id, L) and not hasPrev[it.id] then table.insert(items, it.name or it.id) end end
      table.sort(items)
      local y=1; if #items==0 then body:addLabel():setText("No new unlocks this level."):setPosition(1,y); y=y+1
      else for _,nm in ipairs(items) do body:addLabel():setText("- "..nm):setPosition(1,y); y=y+1 end end
      box:addButton():setText("Continue"):setPosition(10,11):setSize(12,1):setBackground(colors.green):setForeground(colors.black)
        :onClick(function() border:hide(); box:hide(); pcall(function() border:remove() end); pcall(function() box:remove() end) end)
    end
  end

  local prog = levelAPI.getProgress and levelAPI.getProgress() or { level=1, xpInto=0, xpToNext=1 }
  local lvl = prog.level or 1; local into = tonumber(prog.xpInto or 0) or 0; local need = tonumber(prog.xpToNext or 1) or 1; if need<=0 then need=1 end
  local pct = math.floor((into/need)*100 + 0.5); if pct<0 then pct=0 elseif pct>100 then pct=100 end
  local slots = 10; local filled = math.floor((into/need)*slots + 0.5); if filled<0 then filled=0 elseif filled>slots then filled=slots end
  local bar = string.rep("#", filled)..string.rep("-", slots-filled)
  uiAPI.setHUDLevel("lvl "..tostring(lvl)); uiAPI.setHUDLevelBar("|"..bar.."| "..tostring(pct).."%")
end

-- ==================
-- Pause menu wiring
-- ==================
uiAPI.onPauseOpen(function() timeAPI.setSpeed("pause"); uiAPI.updateSpeedButtons() end)
uiAPI.onPauseResume(function() timeAPI.setSpeed("normal"); uiAPI.updateSpeedButtons() end)
uiAPI.onPauseSave(function() saveAPI.save(); saveAPI.commit(); uiAPI.toast("pauseMenu","Game saved", 19,17, colors.green,1.7) end)
uiAPI.onPauseLoad(function() saveAPI.load(); refreshUI(); uiAPI.toast("pauseMenu","Game loaded", 19,17, colors.yellow,1.7) end)
uiAPI.onPauseSettings(function() uiAPI.toast("pauseMenu","Settings coming soon", 11,17, colors.gray,1.7) end)
uiAPI.onPauseQuitToMenu(function()
  saveAPI.save(); basalt.stop()
  local ok, err = pcall(function() shell.run(fs.combine(root, "PixelCorp.lua")) end)
  if not ok and err then print(err) end
end)


-- ================
-- Skip Night wiring (20:00 → 05:30)
-- ================
uiAPI.onSkipNight(function()
  local t = timeAPI.getTime()
  local h, m = t.hour or 0, t.minute or 0
  local allowed = (h >= 20) or (h < 5) or (h == 5 and m < 30)
  if not allowed then
    return
  end
  local prev = timeAPI.getSpeed()
  timeAPI.setSpeed("pause"); uiAPI.updateSpeedButtons()
  local ok = timeAPI.skipNight()
  timeAPI.setSpeed(prev or "normal"); uiAPI.updateSpeedButtons()
  refreshUI()
  if ok then uiAPI.toast("displayFrame", "New day!", 20,5, colors.cyan, 1.6) end
end)

-- =====================
-- Sales / Open Hours
-- =====================
local openLabel = topBar:addLabel():setPosition(25,3):setText("Closed"):setForeground(colors.red)
local function _isOpen()
  local t = timeAPI.getTime(); local h = t.hour or 0; return (h >= 7 and h < 19)
end

local function buyProbability(price)
  local SWEET_SPOT, BASE_WILL, PRICE_SLOPE = 9, 0.16, 0.04
  local priceDelta  = (price or 0) - SWEET_SPOT
  local priceFactor = 1.0 - (PRICE_SLOPE * priceDelta)
  local p = BASE_WILL * priceFactor
  if p < 0.02 then p = 0.02 end; if p > 0.95 then p = 0.95 end; return p
end

local function getSellableProducts()
  local out = {}; local inv = _inventoryMap()
  for k,q in pairs(inv) do if type(k)=="string" and k:sub(1,6)=="drink:" and tonumber(q or 0) > 0 then
    local label = (craftAPI.prettyNameFromKey and craftAPI.prettyNameFromKey(k)) or k
    table.insert(out, { key=k, label=label, qty=q })
  end end
  table.sort(out, function(a,b) return (a.label or a.key) < (b.label or b.key) end)
  return out
end

local function trySellOnce()
  local products = getSellableProducts(); if #products == 0 then return false end
  local pick = products[math.random(1,#products)]
  local price = getProductPrice(pick.key)
  if math.random() < buyProbability(price) then
    inventoryAPI.add(pick.key, -1)
    if economyAPI and economyAPI.addMoney then economyAPI.addMoney(price, "Product sale: "..pick.label) end
    local xpGrant = 0; pcall(function() local stageKey = (stageAPI and stageAPI.getStage and stageAPI.getStage()) or "lemonade"; local g = (levelAPI.onSale and select(1, levelAPI.onSale(pick.key, nil, stageKey))) or 0; xpGrant = g or 0 end)
    local tx, ty = uiAPI.getMoneyTail()
    uiAPI.toast("topbar", ("+$%d"):format(price), tx, 2, colors.green, 1.7)
    uiAPI.toast("topbar", ("+%d xp"):format(math.floor(xpGrant+0.5)), 10,3, colors.green,1.7)
    uiAPI.toast("displayFrame", ("Sold 1x %s"):format(pick.label), 9,18, colors.yellow,1.7)
    uiAPI.refreshBalances()
    if inventoryOverlay and inventoryOverlay.isVisible and inventoryOverlay:isVisible() then refreshInventoryTabs() end
    return true
  end
  return false
end

timeAPI.onTick(function(_)
  if not _isOpen() then openLabel:setText("Closed"):setForeground(colors.red); return end
  openLabel:setText("Open"):setForeground(colors.green)

  -- about 4 customers/hour baseline, paced per minute tick
  local CUSTOMERS_PER_HOUR = 4
  local lambdaPerMinute = (CUSTOMERS_PER_HOUR / 60.0)
  -- integer attempts
  for i=1, math.floor(lambdaPerMinute) do trySellOnce() end
  -- fractional attempt
  local rem = lambdaPerMinute - math.floor(lambdaPerMinute)
  if rem > 0 and math.random() < rem then trySellOnce() end
end)
  _didDailyStockRefresh = false
-- ==============
-- UI Refreshers
-- ==============
function refreshUI()
  local t = timeAPI.getTime()
  uiAPI.setHUDTime(string.format("Time: Y%d M%d D%d %02d:%02d", t.year, t.month, t.day, t.hour, t.minute))

  pcall(function() if uiAPI._refreshSkipOr4x then uiAPI._refreshSkipOr4x() end end)
  -- Daily market refresh & page repaint if needed (6:00)
  local s = saveAPI.get(); local day, hour, minute = s.time.day, s.time.hour, s.time.minute
  if hour == 6 then
    if not _didDailyStockRefresh then
      _didDailyStockRefresh = true
      -- 1) Trigger backend market recompute if available (safely no-op if not present)
      if inventoryAPI then
        pcall(function() if inventoryAPI.rollDailyMarket then inventoryAPI.rollDailyMarket() end end)
        pcall(function() if inventoryAPI.refreshMarket then inventoryAPI.refreshMarket() end end)
        pcall(function() if inventoryAPI.reseedDailyStock then inventoryAPI.reseedDailyStock() end end)
      end
      -- 2) Soft refresh labels immediately so visible numbers update
      if currentPage == "stock" then pcall(function() if uiAPI.softRefreshStockLabels then uiAPI.softRefreshStockLabels() end end) end
      -- 3) Do a second soft refresh shortly after in case backend rolls async
      uiAPI.softRefreshStockLabels()
      if uiAPI and uiAPI.runLater then
        uiAPI.runLater(1.0, function()
          if currentPage == "stock" then pcall(function() if uiAPI.softRefreshStockLabels then uiAPI.softRefreshStockLabels() end end) end
        end)
      end
    end
  else
    _didDailyStockRefresh = false
  end
  if hour == 7 then
    if not _didDailyLoanCharge then
      _didDailyLoanCharge = true
      pcall(function() if economyAPI and economyAPI.processDailyLoans then economyAPI.processDailyLoans() end end)
      pcall(function() if economyAPI and economyAPI.cleanupLoans then economyAPI.cleanupLoans() end end)
    end
  else
    _didDailyLoanCharge = false
  end

  do
    local t = timeAPI.getTime()
    local hour = t.hour
    if hour >= 20 then
      uiAPI.toast("displayFrame", "Skip available 20:00 -> 05:30", 10,4, colors.gray, 0.5)
      uiAPI._refreshSkipOr4x()
    end
    -- remember last hour we stepped on (persist outside 'do' via upvalue)
    _lastStockHour = _lastStockHour or hour

    if hour ~= _lastStockHour then
      -- Optional: if you might skip multiple hours at once, you can loop here.
      -- For now, we just step once per observed change.
      pcall(function()
        if economyAPI and economyAPI.stepStocks then
          economyAPI.stepStocks()
          uiAPI.renderList()
          uiAPI.renderChart()
          uiAPI.renderControls()
        end
      end)
      _lastStockHour = hour
    end
  end

  -- Money/Stage HUD
  local state = saveAPI.get()
  local currentStageName = ({ odd_jobs="Odd Jobs", lemonade_stand="Lemonade Stand", warehouse="Warehouse Services", factory="Factory", highrise="High-Rise Corporation" })[state.player.progress] or "Odd Jobs"
  uiAPI.setHUDMoney("Money:$" .. (state.player.money or 0))
  uiAPI.setHUDStage("Stage: " .. currentStageName)

  -- Keep background in sync with progress (also on Dev page)
  applyStageFromProgress()

  -- Level bar
  renderLevelHUD()
end

-- ============
-- Time thread
-- ============
local timeThread = mainFrame:addThread()
local function startTimeUpdates()
  timeThread:start(function()
    while true do
      timeAPI.tick()
      refreshUI()
      local sp = timeAPI.getSpeed and timeAPI.getSpeed() or "normal"
      local sleepTime = (sp == "pause") and 0.05 or (sp == "4x") and 0.15 or (sp == "2x") and 0.50 or 1
      os.sleep(sleepTime)
    end
  end)
end

-- ============
-- Initialization
-- ============
local function initialize()
  if not saveAPI.hasSave() then saveAPI.newGame() else saveAPI.load() end

  parallel.waitForAny(
    function() basalt.autoUpdate() end,
    function()
      uiAPI.setLoading("Loading backgrounds...", 10)
      -- Preload & paint initial stage
      applyStageFromProgress()
      os.sleep(0.7)
      uiAPI.setLoading("Building pages...", 40)
      buildMainPage()
      uiAPI.buildStockPage()
      rebuildUpgradesPage()
      populateSidebar()
      os.sleep(1.25)
      uiAPI.setLoading("Starting time...", 70)
      startTimeUpdates()
      os.sleep(0.8)
      uiAPI.setLoading("Ready", 100)
      os.sleep(0.7)
      uiAPI.showRoot()
      uiAPI.hideLoading()
      timeAPI.onTick(function(t) eventAPI.onTick(t) end)
      -- Kick off tutorial after UI is visible

      -- Default page
      switchPage("main")

      while true do os.sleep(0.5) end
    end
  )
end

initialize()

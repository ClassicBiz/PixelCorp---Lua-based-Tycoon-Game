-- version 0.1.7 [0.1-2.1-9 = lemon Stage, 0.2-4.1-9 = warehouse Stage, 0.4-6.1-9 = factory Stage, 0.6-8.1-9 = tower Stage, 0.8.9 - 1.0.0 = QoL, fixes, bugSmashing, touchUps, animations, additional features. 1.0.0 + = restructuring additional challenges, modding? ]


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
local saveAPI = require(root.."/API/saveAPI")
local eventAPI = require(root.."/API/eventAPI")
local licenseAPI = require(root.."/API/licenseAPI")
local economyAPI = require(root.."/API/economyAPI")
local levelAPI = require(root.."/API/levelAPI")
local inventoryAPI = require(root.."/API/inventoryAPI")
local jobsAPI = require(root.."/API/jobsAPI")
local backgroundAPI = require(root.."/API/backgroundAPI")
local stageAPI = require(root.."/API/stageAPI")
local craftAPI = require(root.."/API/craftAPI")
local itemsAPI   = require(root.."/API/itemsAPI")
local upgradeAPI = require(root.."/API/upgradeAPI")
local tutorialAPI = require(root.."/API/tutorialAPI")
local guideAPI = require(root.."/API/guideAPI")
local guideData = require(root.."/API/guideData")

-- seed RNG once (real UTC seconds)
pcall(function()
  math.randomseed(os.epoch("utc") % 2^31)
  -- throw away a few first draws for better entropy
  for i=1,3 do math.random() end
end)

local function safeText(str, maxLen)
  local t = tostring(str or "")
  t = t:gsub("[\0-\8\11\12\14-\31]", " ")
  t = t:gsub("\t", " ")
  t = t:gsub("\r?\n", " ")
  if maxLen and #t > maxLen then t = t:sub(1, maxLen) end
  return t
end




-- Constants
local SCREEN_WIDTH, SCREEN_HEIGHT = term.getSize()

-- Stage Definitions
local STAGES = {
    odd_jobs = { name = "Odd Jobs", next = "lemonade_stand", required_license = "lemonade", cost = 100, req_lvl = 0 },
    lemonade_stand = { name = "Lemonade Stand", next = "warehouse", required_license = "warehouse", cost = 1000, req_lvl = 50 },
    warehouse = { name = "Warehouse Services", next = "factory", required_license = "factory", cost = 5000, req_lvl = 125 },
    factory = { name = "Factory", next = "highrise", required_license = "highrise", cost = 15000, req_lvl = 200 },
    highrise = { name = "High-Rise Corporation" }
}

-- Page backgrounds removed (stage-driven bg only)

-- Main UI Setup
local mainFrame = basalt.createFrame():setSize(SCREEN_WIDTH, SCREEN_HEIGHT)
local timeThread = mainFrame:addThread() -- Background thread for time updates

guideAPI.init(mainFrame)
guideAPI.setData(guideData)

-- Map progress id to stage art key
local function progressToStage(progress)
    if progress == "lemonade_stand" then return "lemonade"
    elseif progress == "warehouse"   then return "office"
    elseif progress == "factory"     then return "factory"
    elseif progress == "highrise"    then return "tower"
    else return "base" end
end




-- Loading Screen
local loadingFrame = mainFrame:addFrame():show()
    :setSize(SCREEN_WIDTH, SCREEN_HEIGHT)
    :setPosition(1, 1)
    :setBackground(colors.lightGray)
    :setZIndex(100)

-- Pre-calculate positions for the loading label and progress bar
local labelWidth = 24 -- Approximate width of "Loading Backgrounds..."
local labelX = math.floor((SCREEN_WIDTH - labelWidth) / 2) -- Center the label
local labelY = math.floor(SCREEN_HEIGHT / 2) - 1 -- One line above the center

local progressBarWidth = 25
local progressBarX = math.floor((SCREEN_WIDTH - progressBarWidth) / 2) -- Center the progress bar
local progressBarY = math.floor(SCREEN_HEIGHT / 2) -- Center vertically

local loadingLabel = loadingFrame:addLabel()
    :setText("Loading Backgrounds...")
    :setPosition(labelX-8, labelY)
    :setForeground(colors.white)

local progressLabel = loadingFrame:addLabel()
    :setText("Loading 0%")
    :setPosition(20,labelY+4)
    :setForeground(colors.white)

local progressBar = loadingFrame:addProgressbar()
    :setDirection(0)
    :setPosition(progressBarX, progressBarY)
    :setSize(progressBarWidth, 1)
    :setProgressBar(colors.blue, " ") 
    :setBackground(colors.gray)
    :setProgress(0)

local function wipe(frame) frame:removeChildren() end
local function mkHeader(tab)
    tab:addLabel():setPosition(2,1):setText("Item"):setForeground(colors.yellow)
    tab:addLabel():setPosition(25,1):setText("+$"):setForeground(colors.yellow)
    tab:addLabel():setPosition(37,1):setText("Qty"):setForeground(colors.yellow)
end
local function mkRow(tab, y, name, qty, value, color)
    tab:addLabel():setPosition(2, y):setSize(26, 1):setText(name or ""):setForeground(color)
    tab:addLabel():setPosition(24, y):setSize(10, 1):setText(("(+$%d ea)"):format(tonumber(value)) or "(0 ea)")
    tab:addLabel():setPosition(34, y):setSize(6, 1):setText(tostring(qty or 0)):setTextAlign("right")
end

-- overlay container
local inventoryOverlay = mainFrame:addMovableFrame()
    :setSize(42, 16)
    :setPosition((SCREEN_WIDTH - 40) / 2, 3)
    :setBackground(colors.lightGray)
    :setZIndex(45)
    :hide()

inventoryOverlay:addLabel():setText("Inventory"):setPosition(2, 1)

-- close button (kept)
inventoryOverlay:addButton()
    :setText(" x ")
    :setPosition(40, 1)
    :setSize(3, 1)
    :setBackground(colors.red)
    :setForeground(colors.white)
    :onClick(function() inventoryOverlay:hide() end)

-- Menubar tabs (kept) + frames per tab
local inventoryTabs = {}

_lastProductChoice = _lastProductChoice or "Lemonade"

-- Robust tab selection helpers (handle index OR label from Menubar:onChange)
local TAB_ORDER = { "Materials", "Products", "Crafting", "All" }

local function selectInventoryTab(name)
    for _, f in pairs(inventoryTabs) do f:hide() end
    if inventoryTabs[name] then inventoryTabs[name]:show() end
end

    local function resolveTabKey(val)
    if type(val) == "number" then
        return TAB_ORDER[val] or "Materials"
    elseif type(val) == "string" then
        local v = val:gsub("^%s+", ""):gsub("%s+$", "")
        if inventoryTabs[v] then return v end
        local cap = v:sub(1,1):upper() .. v:sub(2):lower()
        if inventoryTabs[cap] then return cap end
        for name,_ in pairs(inventoryTabs) do
        if name:lower() == v:lower() then return name end
        end
    end
    return "Materials"
    end

    local rarityRank = {
        common    = 1,
        uncommon  = 2,
        rare      = 3,
        unique    = 4,
        legendary = 5,
        mythical  = 6,
        relic     = 7,
        masterwork= 8,
        divine    = 9
    }

    local function getRarityRank(it)
        if not it then return 999 end
        local r = (it.rarity or "")
        if type(r) == "table" then r = r.name or "" end
        r = tostring(r):lower()
        return rarityRank[r] or 999
    end


local tabBar = inventoryOverlay:addMenubar()
    :setPosition(2, 2)
    :setSize(40, 1)
    :setScrollable(false)
    :addItem(" Materials")
    :addItem(" Products")
    :addItem(" Crafting")
    :addItem(" All ")

-- === Top bar (kept) ===
local topBar = mainFrame:addFrame()
    :setSize(SCREEN_WIDTH, 3)
    :setPosition(1, 1)
    :setBackground(colors.gray)
    :hide()

topBar:addButton()
    :setText("[ INV ]")
    :setPosition( 35, 3)
    :setSize(6, 1)
    :onClick(function()
        showInventoryOverlay()
            --selectInventoryTab("Materials")
    end)

topBar:addButton()
    :setBackground(colors.orange)
    :setForeground(colors.black)
    :setText("[ CRAFT ]")
    :setPosition(42, 3)
    :setSize(9, 1)
    :onClick(function()
        refreshInventoryTabs()
        selectInventoryTab("Crafting")
        inventoryOverlay:show()
    end)



local timeLabel = topBar:addLabel()
    :setText("Time: Initializing...")
    :setPosition(2, 1)

local moneyLabel = topBar:addLabel()
    :setText("Money: $0")
    :setPosition(25, 2)

local stageLabel = topBar:addLabel()
    :setText("Stage: Unknown")
    :setPosition(25, 1)

    -- ===== Level HUD (below top bar) =====
local levelLabel = topBar:addLabel()
  :setText("lvl 1")
  :setPosition(1, 3)
  :setForeground(colors.lightGray)

local levelBarLabel = topBar:addLabel()
  :setText("|----------| 0%")
  :setPosition(7, 3)
  :setForeground(colors.blue)


-- Pause Button
local previousSpeed = "normal" -- Store the speed before pausing
topBar:addButton()
    :setText("Pause")
    :setPosition(SCREEN_WIDTH - 50, 2)
    :setSize(6, 1)
    :setBackground(colors.red)
    :setForeground(colors.white)
    :onClick(function()
        previousSpeed = timeAPI.getSpeed()
        timeAPI.setSpeed("pause")
        TICK_INTERVAL = nil
        updateSpeedButtonColors()
        showPauseMenu()
    end)

-- Time Control Buttons
local speedButtons = {}
function updateSpeedButtonColors()
    local currentSpeed = timeAPI.getSpeed()
    for mode, btn in pairs(speedButtons) do
        if mode == currentSpeed then
            if mode == "pause" then
                btn:setBackground(colors.red)
            elseif mode == "normal" then
                btn:setBackground(colors.green)
            elseif mode == "2x" then
                btn:setBackground(colors.blue)
            elseif mode == "4x" then
                btn:setBackground(colors.orange)
            end
            btn:setForeground(colors.white)
        else
            btn:setBackground(colors.lightGray)
            btn:setForeground(colors.gray)
        end
    end
end


    speedButtons["pause"] = topBar:addButton()
        :setText("II")
        :setPosition(SCREEN_WIDTH - 44, 2)
        :setSize(4, 1)
        :onClick(function()
            timeAPI.setSpeed("pause")
            TICK_INTERVAL = nil
            updateSpeedButtonColors()
        end)

    speedButtons["normal"] = topBar:addButton()
        :setText(">")
        :setPosition(SCREEN_WIDTH - 40, 2)
        :setSize(4, 1)
        :onClick(function()
            timeAPI.setSpeed("normal")
            TICK_INTERVAL = 1
            updateSpeedButtonColors()
        end)

    speedButtons["2x"] = topBar:addButton()
        :setText(">>")
        :setPosition(SCREEN_WIDTH - 36, 2)
        :setSize(4, 1)
        :onClick(function()
            timeAPI.setSpeed("2x")
            TICK_INTERVAL = 0.50
            updateSpeedButtonColors()
        end)

    speedButtons["4x"] = topBar:addButton()
        :setText(">>>")
        :setPosition(SCREEN_WIDTH - 32, 2)
        :setSize(4, 1)
        :onClick(function()
            timeAPI.setSpeed("4x")
            TICK_INTERVAL = 0.15
            updateSpeedButtonColors()
        end)


updateSpeedButtonColors()

-- Sidebar
    local SIDEBAR_W = 15
        local sidebar = mainFrame:addScrollableFrame()
        :setBackground(colors.lightGray)
        :setPosition(SCREEN_WIDTH, 4)   
        :setSize(SIDEBAR_W, SCREEN_HEIGHT - 3)
        :setZIndex(25)
        :setDirection("vertical")
        :hide()


local arrowTop    = sidebar:addLabel():setText("<"):setPosition(1, 5):setForeground(colors.black)
local arrowBottom = sidebar:addLabel():setText("<"):setPosition(1,15):setForeground(colors.black)


sidebar:onGetFocus(function(self)
  self:setPosition(SCREEN_WIDTH - (SIDEBAR_W - 1))  
  arrowTop:setText(">")
  arrowBottom:setText(">")
end)

sidebar:onLoseFocus(function(self)
  self:setPosition(SCREEN_WIDTH)                  
  arrowTop:setText("<")
  arrowBottom:setText("<")
end)

-- Display Frame (single parent for all pages)
local displayFrame = mainFrame:addFrame()
    :setSize(SCREEN_WIDTH, SCREEN_HEIGHT - 2)
    :setPosition(0, 3)
    :setZIndex(0)
    :hide()

-- Base stage backdrop for the display area (painted once)
if stageAPI and stageAPI.refreshBackground then
    stageAPI.refreshBackground(displayFrame)
end

-- Cached Page Backgrounds (each page gets its own painted frame)
local pageBackgrounds = {}
local activeBgKey     = nil

local function normalizeKey(s)
  s = (s or ""):lower()
  -- strip common suffixes/plurals/spaces/underscores
  s = s:gsub("%.nfp$", "") :gsub("[_%s%-]+","")
  s = s:gsub("stage","") :gsub("page","")
  s = s:gsub("background","") :gsub("backdrop","")
  -- unify obvious variants
  if s == "lemonade" then s = "lemon" end
  return s
end

-- if you have known canonical mappings, put them here
local STAGE_IMAGE_MAP = {
  -- stage/page name (any form) -> image key
  lemonade = "lemon",
  lemon    = "lemon",
  intro    = "title",
  default  = "lemon",     -- fallback choice
}

local function resolveImageKey(name)
  local n = normalizeKey(name)
  -- explicit table mapping wins
  if STAGE_IMAGE_MAP[n] then return STAGE_IMAGE_MAP[n] end
  -- otherwise use normalized directly
  return n
end

local function collectBackgroundItems()
  local items = {}
  local assetsDir = fs.combine(root, "assets")
  if fs.exists(assetsDir) and fs.isDir(assetsDir) then
    for _, p in ipairs(backgroundAPI.listImages(assetsDir)) do
      local base = fs.getName(p):gsub("%.nfp$", "")
      table.insert(items, { key = normalizeKey(base), path = p })
    end
  end
  table.sort(items, function(a,b) return a.key < b.key end)
  return items
end

local function showBackgroundKey(key)
  if activeBgKey and pageBackgrounds[activeBgKey] then
    pageBackgrounds[activeBgKey]:hide()
  end
  local f = pageBackgrounds[key]
  if f then
    f:show()
    activeBgKey = key
  end
end

local function showBackgroundFor(name)
  showBackgroundKey(resolveImageKey(name))
end

-- call this once during load
local function initStageBackgroundsCached()
  local items = collectBackgroundItems()
  local total = #items
  if total == 0 then
    progressBar:setProgress(100)
    progressLabel:setText("loading.. 100%")
    allBackgroundsLoaded = true
    return
  end

  for i, it in ipairs(items) do
    local key, path = it.key, it.path
    loadingLabel:setText(("Loading: %s (%d/%d)"):format(path, i, total))

    backgroundAPI.preload(path)

    local bgFrame = displayFrame:addFrame()
      :setSize(SCREEN_WIDTH, SCREEN_HEIGHT - 1)
      :setPosition(1, 1)
      :setZIndex(0)  -- keep under content, over base
      :hide()

    backgroundAPI.setCachedBackground(bgFrame, path)
    pageBackgrounds[key] = bgFrame

    local pct = math.floor((i / total) * 100)
    progressBar:setProgress(pct)
    progressLabel:setText("loading.. "..pct.."%")
    os.sleep(0)
  end

  allBackgroundsLoaded = true
  loadingLabel:setText("All stage backgrounds loaded!")
  loadingFrame:hide()
  topBar:show()
  displayFrame:show()
  sidebar:show()

  -- Pick initial bg based on your current stage/page:
  local initialName =
      (stageAPI and stageAPI.getStageName and stageAPI.getStageName())
      or currentPage
      or "default"

  showBackgroundFor(initialName)

end

local function _inventoryMap()
  local state = saveAPI.get()
  local p = state.player or {}
  p.inventory = p.inventory or {}
  return p.inventory
end

-- Label <-> id via itemsAPI
local function idByLabel(label)
  return itemsAPI.idByName(label)
end
local function labelById(id)
  return itemsAPI.nameById(id) or id
end

-- Requirements via items.json
local function reqByLabel(label)
  return itemsAPI.craftReqByName(label) or 0
end


local function optionLabelsForType(typeName, haveMap, playerLevel, currentProduct)
  local list = {}
  currentProduct = currentProduct or (ddProduct and ddProduct.getValue and ddProduct:getValue()) or "Lemonade"
  local iceShaver = upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution()

  -- Helper to push an entry if qty>0
  local function push(name, id, req, qtyKey)
    local qty = tonumber(haveMap[qtyKey or id] or 0) or 0
    if qty > 0 then table.insert(list, ("%s|rq:%d|S:%d"):format(name, req, qty)) end
  end

  if currentProduct == "Italian Ice" then
    if typeName == "base" then
      for _, it in ipairs(itemsAPI.listByType("base")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then
          push(it.name, it.id, tonumber(it.craft_req or 0) or 0)
        end
      end
    elseif typeName == "fruit" then
      -- Fruit slot is Shaved Ice -> 2 Ice Cubes
      if iceShaver then
        local shaved = itemsAPI.getByName("Shaved Ice")
        if shaved then
          local iceId = itemsAPI.idByName("Ice Cubes")
          local req = 2
          if iceId then push(shaved.name, shaved.id, req, iceId) end
        end
      end
    elseif typeName == "sweet" then
      for _, it in ipairs(itemsAPI.listByType("sweet")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) and itemsAPI.isSyrup(it.id) then
          push(it.name, it.id, tonumber(it.craft_req or 0) or 0)
        end
      end
    elseif typeName == "topping" then
      -- Allow fruits or toppings, excluding ice-based
      for _, it in ipairs(itemsAPI.listByType("topping")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then
          local nameLower = (it.name or ""):lower()
          if nameLower ~= "ice" and nameLower ~= "ice cubes" and nameLower ~= "shaved ice" then
            push(it.name, it.id, tonumber(it.craft_req or 0) or 0)
          end
        end
      end
      -- Also include fruits as toppers (fixed rq:1)
      for _, it in ipairs(itemsAPI.listByType("fruit")) do
        if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then
          local qty = tonumber(haveMap[it.id] or 0) or 0
          if qty > 0 then table.insert(list, ("%s| rq:%d | S:%d"):format(it.name, 1, qty)) end
        end
      end
    end
  else
    -- Lemonade (default): standard lists; apply Juicer to fruit; remove Shaved Ice from toppings
    for _, it in ipairs(itemsAPI.listByType(typeName)) do
      if itemsAPI.isUnlockedForLevel(it.id, playerLevel) then
        local req = tonumber(it.craft_req or 0) or 0
        local id  = it.id
        if typeName == "fruit" then
          local delta = upgradeAPI.fruitReqDelta and upgradeAPI.fruitReqDelta() or 0
          req = math.max(0, req + delta)
        end
        if typeName == "topping" then
          local nameLower = (it.name or ""):lower()
          if nameLower == "shaved ice" then
            -- skip in Lemonade mode
            goto continue
          end
        end
        push(it.name, id, req)
      end
      ::continue::
    end
  end

  table.sort(list)
  return list
end

local function cleanLabel(label)
  if type(label) ~= "string" then return label end
  -- try pipe style first
  local name = label:match("^(.-)%s*|%s*rq:") 
            or label:match("^(.-)%s+req:%s*x") 
            or label
  return (name:gsub("%s+$",""))
end


local function _playerInvMap()
  local state = saveAPI.get()
  local p = state.player or {}
  p.inventory = p.inventory or {}
  return p.inventory
end

local function safeGetMaterials()
    local have = _inventoryMap()
    local mats = {}
    local L = levelAPI.getLevel()

    for _, it in ipairs(itemsAPI.getAll()) do
        if itemsAPI.isUnlockedForLevel(it.id, L) then
            local qty = tonumber(have[it.id] or 0) or 0
            local base = tonumber(it.base_value or 0) or 0
            local label = ("%s"):format(it.name)
            local typ = it.type or "material"  -- fallback type
            local rarity = it.rarity or "common" -- fallback rarity
            local color = itemsAPI.itemRarityColor(it) -- 'it' is the item table in the loop
            if qty > 0 then
                table.insert(mats, {
                    key = it.id,
                    label = label,
                    base = base,
                    qty = qty,
                    type = typ,
                    rarity = rarity,
                    color = color
                })
            end
        end
    end

    table.sort(mats, function(a, b)
        -- sort by type first
        if a.type ~= b.type then
            return a.type < b.type
        end
        -- then sort by rarity rank (higher rarity first)
        local ra = getRarityRank(b)
        local rb = getRarityRank(a)
        if ra ~= rb then
            return ra > rb
        end
        -- then alphabetically by label
        return (a.label or a.key) < (b.label or b.key)
    end)

    return mats
end


local function safeGetProducts()
  -- If you track crafted products under their own ids (not in items.json),
  -- treat any inv entry that is NOT an items.json id as a product.
  local have = _inventoryMap()
  local known = {}
  for _, it in ipairs(itemsAPI.getAll()) do known[it.id] = true end
  local out = {}
  for k,v in pairs(have) do
    if not known[k] then
      local q = tonumber(v) or 0; if q > 0 then table.insert(out, { key=k, label=k, qty=q, type="product" }) end
    end
  end
  table.sort(out, function(a,b) return (a.label or a.key) < (b.label or b.key) end)
  return out
end

local function safeGetAll()
  local all = {}
  for _, it in ipairs(safeGetMaterials()) do table.insert(all, it) end
  for _, it in ipairs(safeGetProducts())  do table.insert(all, it) end
  return all
end

-- robust reader: ignore callback payloads, ask the widget what’s selected
local function menubarSelectedName(self)
  -- Prefer explicit index if available
  if self.getItemIndex then
    local idx = self:getItemIndex()
    if type(idx) == "number" and idx >= 1 and idx <= #TAB_ORDER then
      return TAB_ORDER[idx]
    end
  end
  -- Some builds expose a string via getValue()
  if self.getValue then
    local v = self:getValue()
    if type(v) == "string" then return resolveTabKey(v) end
    if type(v) == "number" then return TAB_ORDER[v] end
    if type(v) == "table" and type(v.text) == "string" then return resolveTabKey(v.text) end
  end
  -- Last resort: fall back to Materials
  return "Materials"
end

tabBar:onChange(function(self, _)
  selectInventoryTab(menubarSelectedName(self))
end)

-- Ensure the default selection is actually set in the menubar, too
if tabBar.setItemIndex then tabBar:setItemIndex(1) end

-- tab frames
inventoryTabs["Materials"] = inventoryOverlay:addScrollableFrame()
  :setPosition(2, 4):setSize(40, 12):setBackground(colors.white):hide()
inventoryTabs["Products"] = inventoryOverlay:addScrollableFrame()
  :setPosition(2, 4):setSize(40, 12):setBackground(colors.white):hide()
inventoryTabs["Crafting"] = inventoryOverlay:addFrame()
  :setPosition(2, 4):setSize(40, 12):setBackground(colors.white):hide()
inventoryTabs["All"] = inventoryOverlay:addScrollableFrame()
  :setPosition(2, 4):setSize(40, 12):setBackground(colors.white):hide()


  local function getProductPrice(name)
  if economyAPI and economyAPI.getPrice then
    local p = economyAPI.getPrice(name)
    if type(p) == "number" then return p end
  end
  local s = saveAPI.get()
  local ep = (s.economy and s.economy.prices) or {}
  return tonumber(ep[name] or 0) or 0
end

local function mkHeaderProducts(tab)
  tab:addLabel():setPosition(2,1):setText("Item"):setForeground(colors.yellow)
  tab:addLabel():setPosition(31,1):setText("Qty"):setForeground(colors.yellow)
  tab:addLabel():setPosition(37,1):setText("$"):setForeground(colors.yellow)
end

local function mkRowProduct(tab, y, name, qty, price)
  tab:addLabel():setPosition(2,  y):setText(name or "")
  tab:addLabel():setPosition(30,  y):setText("|")
  tab:addLabel():setPosition(30, y):setSize(4,  1):setText(tostring(qty or 0)):setTextAlign("right")
  tab:addLabel():setPosition(35, y):setSize(5,  1):setText(tostring(price or 0)):setTextAlign("right")
end

-- populate logic for each tab
local function populateMaterials()
  local tab = inventoryTabs["Materials"]; wipe(tab); mkHeader(tab)
  local items, y = safeGetMaterials(), 2
  for _,it in ipairs(items) do mkRow(tab, y, safeText(it.label, 29), it.qty, it.base, it.color); y = y + 1 end
end

local function populateProducts()
  local tab = inventoryTabs["Products"]; wipe(tab); mkHeaderProducts(tab)
  local items, y = safeGetProducts(), 2
    for _, it in ipairs(items) do
    local shown = it.label or it.key
    -- If it's a composition key, show the pretty name
    if type(shown)=="string" and shown:find("^drink:") and craftAPI.prettyNameFromKey then
        shown = craftAPI.prettyNameFromKey(shown)
    end
    local price = getProductPrice(it.key)  -- price by key
    mkRowProduct(tab, y, safeText(shown, 28), it.qty, price)
    y = y + 1
    end
end

local function populateAll()
  local tab = inventoryTabs["All"]; wipe(tab); mkHeader(tab)
  local items, y = safeGetAll(), 2
  for _,it in ipairs(items) do
        if type(shown)=="string" and shown:find("^drink:") and craftAPI.prettyNameFromKey then
        shown = craftAPI.prettyNameFromKey(shown)
    end
    local price = getProductPrice(it.label or it.key)
    local tag = (it.type == "material") and "M" or "P"
    mkRow(tab, y, safeText(("[%s] %s"):format(tag, it.label or it.key), 26), it.qty, it.base or price, it.color); y = y + 1
  end
end

local SWEET_SPOT        = 9     -- fair price customers expect
local BASE_WILL         = 0.16  -- baseline willingness to buy
local PRICE_SLOPE       = 0.04  -- demand sensitivity per $ delta

-- Build sellable list as { key=<inventory key>, label=<display name>, qty=<n> }
-- We prefer 'key' when consuming inventory; 'label' for display/price lookups.
local function getSellableProducts()
  local out = {}
  local inv = _inventoryMap()
  for k, q in pairs(inv) do
    if type(k) == "string" and k:sub(1,6) == "drink:" and tonumber(q or 0) > 0 then
      local label = k
      if craftAPI and craftAPI.prettyNameFromKey then
        label = craftAPI.prettyNameFromKey(k)
      end
      table.insert(out, { key = k, label = label, qty = q })
    end
  end
  table.sort(out, function(a,b) return (a.label or a.key) < (b.label or b.key) end)
  return out
end

local function buyProbability(price)
  local priceDelta  = (price or 0) - SWEET_SPOT
  local priceFactor = 1.0 - (PRICE_SLOPE * priceDelta)
  local p = BASE_WILL * priceFactor
  if p < 0.02 then p = 0.02 end
  if p > 0.95 then p = 0.95 end
  return p
end



-- =======================
-- Text Toast Manager (single thread, pooled)
-- (constant real-time toasts / floating text)
-- =======================
local TextToasts = { items = {}, runner = nil, root = nil, max_active = 24 }

local function _startToastRunner(rootFrame)
  if TextToasts.runner then return end
  TextToasts.root = rootFrame or mainFrame
  local th = TextToasts.root:addThread()
  TextToasts.runner = th
  th:start(function()
    while true do
      local now = os.clock()
      -- sweep expired labels
      for i = #TextToasts.items, 1, -1 do
        local it = TextToasts.items[i]
        if now >= (it.t1 or 0) then
          if it.lbl and it.lbl.remove then pcall(function() it.lbl:remove() end) end
          table.remove(TextToasts.items, i)
        end
      end
      os.sleep(0.05) -- constant wall-clock pacing, independent of game speed
    end
  end)
end

-- Creates a timed text label on an existing parent and auto-removes it.
-- parent: any basalt frame (e.g., topBar, displayFrame, mainFrame)
-- text:   string
-- x,y:    absolute coordinates within the parent
-- color:  cc.colors.* (defaults to white)
-- duration: seconds (real-time, independent of game speed)
function spawnToast(parent, text, x, y, color, duration)
  if not parent or not parent.addLabel then return end
  if not TextToasts or not TextToasts.runner then
    if _startToastRunner then _startToastRunner(mainFrame) end
  end

  -- Limit number of active toasts
  if TextToasts and #TextToasts.items >= (TextToasts.max_active or 24) then
    local it = table.remove(TextToasts.items, 1)
    if it and it.lbl and it.lbl.remove then pcall(function() it.lbl:remove() end) end
  end

  local px = tonumber(x) or 1
  local py = tonumber(y) or 1
  local pw = (parent.getSize and select(1, parent:getSize())) or SCREEN_WIDTH
  local avail = math.max(1, pw - (px - 1))

  local txt = safeText(tostring(text or ""), avail)

  local lbl = parent:addLabel()
      :setPosition(px, py)
      :setSize(#txt, 1)
      :setText(txt)
      :setForeground(color or colors.white)
      :setZIndex(200)

  if TextToasts then
    table.insert(TextToasts.items, { lbl = lbl, t1 = os.clock() + (tonumber(duration) or 2.0) })
  end
  return lbl
end

local function trySellOnce()
  local products = getSellableProducts()
  if #products == 0 then return false end

  local pick = products[math.random(1, #products)]
  local price = getProductPrice(pick.key)
  local pBuy  = buyProbability(price)

  if math.random() < pBuy then
    -- 1) consume stock
    inventoryAPI.add(pick.key, -1)

    -- 2) money
    if economyAPI and economyAPI.addMoney then
      economyAPI.addMoney(price, "Product sale: "..pick.label)
    end

    -- 3) XP: get the authoritative value from levelAPI (base defaults to 10 inside levelAPI)
    local xpGrant = 0
    do
      local ok, grant = pcall(function()
        local stageKey = (stageAPI and stageAPI.getCurrentStage and stageAPI.getCurrentStage()) or "lemonade"
        local g, _ = levelAPI.onSale(pick.key, nil, stageKey)  -- pass nil so levelAPI uses BASE_SALE_XP = 10
        return g
      end)
      if ok and type(grant) == "number" and grant > 0 then
        xpGrant = grant
      end
    end

    -- 4) UI toasts (show the total XP ONLY)
    pcall(function()
      local xpShown = math.floor(xpGrant + 0.5)
      spawnToast(topBar, ("+$%d"):format(price), 36, 2, colors.green, 1.7)
      spawnToast(topBar, ("+%d xp"):format(xpShown), 10, 3, colors.green, 1.7)
      spawnToast(displayFrame, ("Sold 1x %s"):format(pick.label), 9, 17, colors.yellow, 1.7)
    end)

    -- 5) refresh overlay if open
    pcall(function()
      if inventoryOverlay and inventoryOverlay.isVisible and inventoryOverlay:isVisible() then
        refreshInventoryTabs()
      end
    end)

    return true
  end

  return false
end

local CUSTOMERS_PER_HOUR = 4  -- tune me

local openLabel = topBar:addLabel()
  :setPosition(25,3)
  :setText("Closed")
  :setForeground(colors.red)

-- Minutes deliver fractional expected customers; accumulate and sample.
local _custCarry = 0.5

-- Only sell during open hours? Optional helper:
local function _isOpen()
  -- If you have timeAPI.getTime():
  local t = timeAPI.getTime()
  local h = t.hour or 0
  return (h >= 7 and h < 19)  -- 8:00–19:59 open; change or remove if you want always open
end

-- Run on every in-game minute (timeAPI.onTick fires once per minute advanced)
    timeAPI.onTick(function(_)
        -- Skip if closed (remove this guard if you want 24/7)
        if not _isOpen() then openLabel:setText("Closed"):setForeground(colors.red) return end
        openLabel:setText("Open"):setForeground(colors.green)

        local lambda = (CUSTOMERS_PER_HOUR / 60.0)
        _custCarry = _custCarry + lambda


        local n = math.floor(_custCarry)
        if n > 0 then
            for i = 1, n do trySellOnce() end
            _custCarry = _custCarry - n
        end

        if _custCarry > 0 and math.random() < _custCarry then
            trySellOnce()
            _custCarry = 0
        end
    end)

function mkStepper(parent, x, y, w, color)
  local f = parent:addFrame():setPosition(x, y):setSize(w, 1):setBackground(colors.white):setForeground(color)
  f._items, f._i, f._onChange = {}, 1, nil

  local function updateLabel()
    local t = f._items[f._i] or ""
    if type(t) == "table" then t = t.text or t[1] or "" end
    if f._lbl then f._lbl:setText(t) end
  end

  -- layout: [text] < >
  local lblW = w - 4
  f._lbl = f:addLabel():setPosition(1, 1):setSize(lblW, 1):setText("")
  local btnL = f:addButton():setPosition(lblW - 3, 1):setSize(3, 1):setText(" <<"):setBackground(colors.white)
  local btnR = f:addButton():setPosition(lblW, 1):setSize(3, 1):setText(">>"):setBackground(colors.white)

  local function fire()
    if f._onChange then f._onChange() end
  end

  btnL:onClick(function()
    if #f._items == 0 then return end
    f._i = (f._i - 2) % #f._items + 1  -- wrap left
    updateLabel(); fire()
  end)
  btnR:onClick(function()
    if #f._items == 0 then return end
    f._i = (f._i) % #f._items + 1       -- wrap right
    updateLabel(); fire()
  end)

  function f:setItems(list)
    self._items = list or {}
    self._i = (#self._items > 0) and 1 or 1
    updateLabel()
    return self
  end
  function f:setIndex(i)
    if #self._items == 0 then self._i = 1; updateLabel(); return self end
    if i < 1 then i = 1 elseif i > #self._items then i = #self._items end
    self._i = i; updateLabel(); return self
  end
  function f:getIndex() return self._i end
  function f:getText()
    local t = self._items[self._i]
    if type(t) == "table" then t = t.text or t[1] end
    return t
  end
  function f:onChange(fn) self._onChange = fn; return self end

  return f
end

local function buildColorMap(opts)
  local map = {}
  for _, name in ipairs(opts) do
    if name == "None" or name == "" then
      map[name] = colors.gray
    else
      local baseName = cleanLabel and cleanLabel(name) or name  -- strip “| rq:… | S:…”
      local id = idByLabel and idByLabel(baseName) or nil
      map[name] = (itemsAPI.itemRarityColor and itemsAPI.itemRarityColor(id or baseName)) or colors.white
    end
  end
  return map
end

local function applyStepColor(stepper, list, cmap)
  if not stepper or not stepper.getText then return end
  local v = stepper:getText()
  if not v or v == "" then v = list[1] end
  local col = (cmap and cmap[v]) or colors.white
  local lbl = stepper._lbl or stepper._label or stepper -- our mkStepper stores the text label as _lbl
  if lbl.setForeground then lbl:setForeground(col) end
end

_craftSel = _craftSel or { product = "Lemonade", base=nil, fruit=nil, sweet=nil, topping=nil }

local function _indexOf(list, value)
  if not value then return nil end
  for i, v in ipairs(list or {}) do
    local s = (type(v)=="table" and (v.text or v[1])) or v
    if s == value then return i end
    if cleanLabel and s and cleanLabel(s) == cleanLabel(value) then return i end
  end
  return nil
end

local function _selectStepperByLabel(stepper, list, label)
  if not stepper or not stepper.setIndex then return end
  local idx = _indexOf(list, label)
  if idx then stepper:setIndex(idx) end
end
-- === End Crafting UI helpers ===

function populateCrafting()
  local tab = inventoryTabs["Crafting"]; wipe(tab)
  tab:addLabel():setPosition(1,1):setText("Select Items to craft x5 for:")

  ddProduct = tab:addDropdown():setPosition(30,1):setSize(12,1):setZIndex(40)

  local L = (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1
  ddProduct:addItem("Lemonade")
  if (upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution()) and L >= 10 then
    ddProduct:addItem("Italian Ice")
  end

  -- select by visible name (Basalt needs selectItem(index) to show it)
  local function _selectProductByName(name)
    if not ddProduct or not ddProduct.getItemCount then return false end
    local n = ddProduct:getItemCount()
    for i=1,(n or 0) do
      local it = ddProduct:getItem(i)
      local v = type(it)=="table" and it.text or it
      if v == name then ddProduct:selectItem(i); return true end
    end
    return false
  end

  -- restore last chosen product if present; otherwise pick first
  if not _craftSel.product or not _selectProductByName(_craftSel.product) then
    ddProduct:selectItem(1)
    local it = ddProduct:getItem(1)
    _craftSel.product = (type(it)=="table" and it.text) or it or "Lemonade"
  end
  _lastProductChoice = _craftSel.product

  local have = _inventoryMap()
  local currentProduct = _craftSel.product or "Lemonade"
  local baseOpts    = optionLabelsForType("base",    have, L, currentProduct)
  local fruitOpts   = optionLabelsForType("fruit",   have, L, currentProduct)
  local sweetOpts   = optionLabelsForType("sweet",   have, L, currentProduct)
  local toppingOpts = optionLabelsForType("topping", have, L, currentProduct)
  if #toppingOpts == 0 or toppingOpts[1] ~= "None" then table.insert(toppingOpts, 1, "None") end

  -- Fallbacks if inventory empty
  if #baseOpts    == 0 then baseOpts    = { (itemsAPI.listByType("base")[1]    or {}).name or "Plastic Cup" } end
  if #fruitOpts   == 0 then fruitOpts   = { (itemsAPI.listByType("fruit")[1]   or {}).name or "Lemon" } end
  if #sweetOpts   == 0 then sweetOpts   = { (itemsAPI.listByType("sweet")[1]   or {}).name or "Sugar" } end
  if #toppingOpts == 0 then toppingOpts = { "None" } end

  local baseColMap    = buildColorMap(baseOpts)
  local fruitColMap   = buildColorMap(fruitOpts)
  local sweetColMap   = buildColorMap(sweetOpts)
  local toppingColMap = buildColorMap(toppingOpts)

  local y = 4
  local lblFruit = (currentProduct == "Italian Ice") and "Ice:" or "Fruit:"
  local lblSweet = "Sweetener:"

  tab:addLabel():setPosition(2, y):setText("Cups:")
  local ddBase = mkStepper(tab, 12, y, 32, col); y = y + 1
  ddBase:setItems(baseOpts)

  tab:addLabel():setPosition(2, y):setText(lblFruit)
  local ddFruit = mkStepper(tab, 12, y, 32, col); y = y + 1
  ddFruit:setItems(fruitOpts)

  tab:addLabel():setPosition(2, y):setText(lblSweet)
  local ddSweet = mkStepper(tab, 12, y, 32, col); y = y + 1
  ddSweet:setItems(sweetOpts)

  tab:addLabel():setPosition(2, y):setText("Topping:")
  local ddTopping = mkStepper(tab, 12, y, 32, col); y = y + 1
  ddTopping:setItems(toppingOpts)

  -- restore previous ingredient selections if they still exist
  _selectStepperByLabel(ddBase,    baseOpts,    _craftSel.base)
  _selectStepperByLabel(ddFruit,   fruitOpts,   _craftSel.fruit)
  _selectStepperByLabel(ddSweet,   sweetOpts,   _craftSel.sweet)
  _selectStepperByLabel(ddTopping, toppingOpts, _craftSel.topping)

  -- apply initial colors
  applyStepColor(ddBase,    baseOpts,    baseColMap)
  applyStepColor(ddFruit,   fruitOpts,   fruitColMap)
  applyStepColor(ddSweet,   sweetOpts,   sweetColMap)
  applyStepColor(ddTopping, toppingOpts, toppingColMap)

  local status   = tab:addLabel():setPosition(2, 12):setSize(28,1):setText("")
  local craftBtn = tab:addButton():setPosition(34, 12):setSize(5,1):setText("Craft")

  local function pickLabel(ctrl, list)
    if ctrl.getValue then
      local v = ctrl:getValue()
      if type(v) == "table" and v.text then v = v.text end
      if type(v) == "number" then v = list[v] or list[1] end
      if v == nil or v == "" then v = list[1] end
      return v
    end
    if ctrl.getText then
      local v = ctrl:getText()
      if not v or v == "" then v = list[1] end
      return v
    end
    return list[1]
  end

  local function setEnabledCompat(btn, enabled)
    if btn.setEnabled   then return btn:setEnabled(enabled) end
    if btn.setActive    then return btn:setActive(enabled) end
    if btn.setClickable then return btn:setClickable(enabled) end
    local btnColor = enabled and colors.green or colors.gray
    if enabled and btn.enable then btn:enable() elseif btn.disable then btn:disable() end
    if btn.setBackground then btn:setBackground(btnColor) end
  end

  local function computePossible()
    local base    = cleanLabel(pickLabel(ddBase,    baseOpts))
    local fruit   = cleanLabel(pickLabel(ddFruit,   fruitOpts))
    local sweet   = cleanLabel(pickLabel(ddSweet,   sweetOpts))
    local topping = cleanLabel(pickLabel(ddTopping, toppingOpts))

    local needs = {}
    local bk, fk, sk = idByLabel(base), idByLabel(fruit), idByLabel(sweet)
    local tk         = (topping ~= "None") and idByLabel(topping) or nil
    local n

    local currentProduct = _lastProductChoice or "Lemonade"
    local iceShaver = upgradeAPI and upgradeAPI.allowShavedIceSubstitution and upgradeAPI.allowShavedIceSubstitution()

    -- base
    n = reqByLabel(base)
    if bk and n and n > 0 then needs[bk] = n end

    if currentProduct == "Italian Ice" then
      if iceShaver then
        local iceId = idByLabel("Ice Cubes")
        if iceId then needs[iceId] = (needs[iceId] or 0) + 2 end
      else
        return 0, base, fruit, sweet, topping
      end
      local swId = idByLabel(sweet)
      if not (itemsAPI.isSyrup and (itemsAPI.isSyrup(swId) or itemsAPI.isSyrup(sweet))) then
        return 0, base, fruit, sweet, topping
      end
    else
      n = reqByLabel(fruit)
      if fk and n and n > 0 then
        local delta = upgradeAPI.fruitReqDelta() or 0
        n = math.max(0, n + delta)
        if n > 0 then needs[fk] = n end
      end
    end

    n = reqByLabel(sweet)
    if sk and n and n > 0 then needs[sk] = n end

    if tk then
      n = reqByLabel(topping); if n and n > 0 then needs[tk] = n end
      if currentProduct ~= "Italian Ice" and iceShaver and topping == "Shaved Ice" then
        local iceId = idByLabel("Ice Cubes")
        if iceId then
          needs[tk] = nil
          needs[iceId] = (needs[iceId] or 0) + n
          tk = iceId
        end
      end
      if currentProduct == "Italian Ice" then
        local topId = idByLabel(topping)
        local it = itemsAPI.getById(topId) or itemsAPI.getByName(topping)
        if it and it.type == "fruit" then
          needs[topId] = 1
        end
      end
    end

    local inv = _inventoryMap()
    local max = math.huge
    for k, need in pairs(needs) do
      if need > 0 then
        max = math.min(max, math.floor((inv[k] or 0) / need))
      end
    end
    if max == math.huge then max = 0 end
    return max, base, fruit, sweet, topping
  end

  local function pickStepperText(stepper, list)
    local v = stepper:getText()
    if v == nil or v == "" then v = list[1] end
    return v
  end

  local function refreshStatus()
    local base    = cleanLabel(pickStepperText(ddBase,  baseOpts))
    local fruit   = cleanLabel(pickStepperText(ddFruit, fruitOpts))
    local sweet   = cleanLabel(pickStepperText(ddSweet, sweetOpts))
    local topping = cleanLabel(pickStepperText(ddTopping,   toppingOpts))
    local can = computePossible(base, fruit, sweet, topping)
    local count = type(can)=="number" and can or 0
    status:setText(safeText("Can craft: "..tostring(count).."  (x5 per craft)", 28))
    setEnabledCompat(craftBtn, count > 0)
  end

  -- set explicit starting values so labels exist
  if ddBase.setValue    and baseOpts[1]    then ddBase:setValue(baseOpts[1]) end
  if ddFruit.setValue   and fruitOpts[1]   then ddFruit:setValue(fruitOpts[1]) end
  if ddSweet.setValue   and sweetOpts[1]   then ddSweet:setValue(sweetOpts[1]) end
  if ddTopping.setValue and toppingOpts[1] then ddTopping:setValue(toppingOpts[1]) end

  -- change listeners (also store the picks)
  ddBase:onChange(function()
    applyStepColor(ddBase, baseOpts, baseColMap)
    _craftSel.base = ddBase:getText()
    refreshStatus()
  end)
  ddFruit:onChange(function()
    applyStepColor(ddFruit, fruitOpts, fruitColMap)
    _craftSel.fruit = ddFruit:getText()
    refreshStatus()
  end)
  ddSweet:onChange(function()
    applyStepColor(ddSweet, sweetOpts, sweetColMap)
    _craftSel.sweet = ddSweet:getText()
    refreshStatus()
  end)
  ddTopping:onChange(function()
    applyStepColor(ddTopping, toppingOpts, toppingColMap)
    _craftSel.topping = ddTopping:getText()
    refreshStatus()
  end)

  if ddProduct and ddProduct.onChange then
    ddProduct:onChange(function()
      local v = ddProduct:getValue(); if type(v)=="table" and v.text then v=v.text end
      if type(v)=="string" and v~="" then
        _lastProductChoice = v
        _craftSel.product  = v
      end
      populateCrafting()
    end)
  end

  craftBtn:onClick(function()
    local can, base, fruit, sweet, topping = computePossible()
    local count = type(can)=="number" and can or (can and can[1]) or 0
    if count > 0 then
      -- persist exactly what the user used before any rebuild
      _craftSel.base    = ddBase:getText()
      _craftSel.fruit   = ddFruit:getText()
      _craftSel.sweet   = ddSweet:getText()
      _craftSel.topping = ddTopping:getText()

      local chosen = (_lastProductChoice and tostring(_lastProductChoice))
                  or (ddProduct and ddProduct.getValue and (function(v)
                        v = ddProduct:getValue()
                        if type(v)=="table" and v.text then v=v.text end
                        return tostring(v)
                      end)())
                  or "Lemonade"
      chosen = chosen:match("^%s*(.-)%s*$")

      local ok, key, label = craftAPI.craftItem(chosen, base, fruit, sweet, topping)
      if ok then
        local computedPrice = craftAPI.computeCraftPrice(base, fruit, sweet, topping)
        if economyAPI and economyAPI.setPrice then
          economyAPI.setPrice(key, computedPrice)
        end
        refreshInventoryTabs()
        refreshStatus()
        spawnToast(inventoryTabs["Crafting"], ("crafted: "..tostring(label).." x5"), 2, 9, colors.orange, 2.2)
      else
        status:setText(safeText("Error: "..tostring(label), 28))
      end
    end
  end)

  refreshStatus()
end

-- full refresh (call whenever inventory changes)
function refreshInventoryTabs()
  populateMaterials()
  populateProducts()
  populateCrafting()
  populateAll()
end

-- Default: show Materials
refreshInventoryTabs()
for _, f in pairs(inventoryTabs) do selectInventoryTab("Materials") f:hide() end


-- Overlay show function (combined)
function showInventoryOverlay()
  refreshInventoryTabs()
  inventoryOverlay:show()
end

-- Pause Menu
local borderMenu = mainFrame:addFrame()
    :setSize(30, 14)
    :setPosition((SCREEN_WIDTH - 30) / 2, 5)
    :setBackground(colors.lightGray)
    :hide()
local pauseMenu = borderMenu:addFrame()
    :setSize(28, 12)
    :setPosition(2, 2)
    :setBackground(colors.white)
    :setZIndex(50)
pauseMenu:addLabel():setText("[--------------------------]"):setPosition(1, 1):setForeground(colors.black)
pauseMenu:addLabel():setText("Pause Menu"):setPosition(10, 1):setForeground(colors.gray)
local pauseLabel = pauseMenu:addLabel():setForeground(colors.gray):setPosition(8, 14):hide()

local function hidePauseMenu()
    pauseMenu:hide()
    borderMenu:hide()
    timeAPI.setSpeed(previousSpeed)
    TICK_INTERVAL = previousSpeed == "normal" and 1 or previousSpeed == "2x" and 0.50 or previousSpeed == "4x" and 0.15 or nil
    updateSpeedButtonColors()
end

function showPauseMenu()
    pauseMenu:show()
    borderMenu:show()
    -- sleep handled dynamically
end

-- Pause Menu Buttons
pauseMenu:addButton()
    :setText("Resume")
    :setPosition(2, 3)
    :setSize(26, 1)
    :setBackground(colors.green)
    :setForeground(colors.black)
    :onClick(hidePauseMenu)

pauseMenu:addButton()
    :setText("Save Game")
    :setPosition(2, 5)
    :setSize(26, 1)
    :setBackground(colors.blue)
    :setForeground(colors.black)
    :onClick(function()
    saveAPI.save()     
    saveAPI.commit()
    spawnToast(pauseMenu, ("Game saved!"), 10, 12, colors.green, 1.0)
    --pauseLabel:setPosition(10, 12):setForeground(colors.green):setText("Game saved!"):show()
    end)

pauseMenu:addButton()
    :setText("Settings")
    :setPosition(2, 7)
    :setSize(26, 1)
    :setBackground(colors.blue)
    :setForeground(colors.black)
    :onClick(function()
        spawnToast(pauseMenu, ("Settings menu not implemented yet."), 1, 12, colors.gray, 2.2)
       -- pauseLabel:setPosition(1, 12):setForeground(colors.gray):setText("Settings menu not implemented yet."):show()
    end)

pauseMenu:addButton()
    :setText("Load Save")
    :setPosition(2, 9)
    :setSize(26, 1)
    :setBackground(colors.blue)
    :setForeground(colors.black)
    :onClick(function()
        saveAPI.load()
        refreshUI()
        spawnToast(pauseMenu, ("Game loaded!"), 9, 12, colors.orange, 1.0)
       -- pauseLabel:setPosition(9, 12):setForeground(colors.orange):setText("Game loaded!"):show()
    end)

pauseMenu:addButton()
    :setText("Quit to Main Menu")
    :setPosition(2, 11)
    :setSize(26, 1)
    :setBackground(colors.red)
    :setForeground(colors.black)
    :onClick(function()
        basalt.stop()
        shell.run(root.."/PixelCorp")
    end)


    local _isPopupActive = false
-- ===== Level Up Popup =====
local levelPopupBorder = mainFrame:addFrame()
    :setSize(34, 14)
    :setPosition(12, 5)
    :setBackground(colors.lightGray)
    :setZIndex(220)
    :hide()

local levelPopup = levelPopupBorder:addFrame()
    :setSize(32, 12)
    :setPosition(2, 2)
    :setBackground(colors.white)
    :setZIndex(221)
    :hide()

local lpTitle = levelPopup:addLabel()
    :setText("Level Up!")
    :setPosition(12, 1)
    :setForeground(colors.green)

local lpSub  = levelPopup:addLabel()
    :setText("")
    :setPosition(3, 3)
    :setForeground(colors.black)

local lpList = levelPopup:addScrollableFrame()
    :setPosition(3, 5)
    :setSize(26, 6)
    :setBackground(colors.white)
    :setDirection("vertical")

local _prevSpeedBeforePopup = "normal"

    local function _pauseForPopup()
    _prevSpeedBeforePopup = timeAPI.getSpeed and timeAPI.getSpeed() or "normal"
    if timeAPI.setSpeed then timeAPI.setSpeed("pause") end
    updateSpeedButtonColors()
    end

    local function _resumeFromPopup()
    if timeAPI.setSpeed then timeAPI.setSpeed(_prevSpeedBeforePopup or "normal") end
    updateSpeedButtonColors()
    end

    local function collectLevelUnlocks(levelNum)
    local items = {}
    local hasPrev = {}
    for _, it in ipairs(itemsAPI.getAll()) do
        if itemsAPI.isUnlockedForLevel(it.id, levelNum-1) then
        hasPrev[it.id] = true
        end
    end
    for _, it in ipairs(itemsAPI.getAll()) do
        if itemsAPI.isUnlockedForLevel(it.id, levelNum) and not hasPrev[it.id] then
        table.insert(items, it.name or it.id)
        end
    end
    table.sort(items)
    local stageNote = nil
    if stageAPI and stageAPI.unlocksAtLevel then
        local ok, note = pcall(stageAPI.unlocksAtLevel, levelNum)
        if ok and note and note ~= "" then stageNote = note end
    end
    return items, stageNote
    end

    local function showLevelUpPopup(newLevel)
    lpTitle:setText(("Level Up!")):setForeground(colors.green)
    lpSub:setText(("You reached level %d!"):format(newLevel))
    lpList:removeChildren()
        _isPopupActive = true
    local items, stageNote = collectLevelUnlocks(newLevel)
    if #items == 0 and not stageNote then
        lpList:addLabel():setText("No new unlocks this level."):setPosition(1,1)
    else
        local y = 1
        if stageNote then
        lpList:addLabel():setText("- "..stageNote):setPosition(1,y); y = y + 1
        end
        for _, name in ipairs(items) do
        lpList:addLabel():setText("- "..name):setPosition(1,y)
        y = y + 1
        end
    end

    _pauseForPopup()
    levelPopupBorder:show(); levelPopup:show()
    end

levelPopup:addButton()
  :setText("Continue")
  :setPosition(10, 11)
  :setSize(12, 1)
  :setBackground(colors.green)
  :setForeground(colors.black)
  :onClick(function()
    levelPopup:hide(); levelPopupBorder:hide()
    _resumeFromPopup()
    _isPopupActive = false
  end)

  local function _hideGroup(group)
  if not group then return end
  for _, el in ipairs(group) do
    if el then
      if el.disable then pcall(function() el:disable() end) end
      if el.hide    then pcall(function() el:hide()    end) end
    end
  end
end

local function _showGroup(group)
  if not group then return end
  for _, el in ipairs(group) do
    if el then
      if el.show   then pcall(function() el:show()   end) end
      if el.enable then pcall(function() el:enable() end) end
    end
  end
end



-- Page Management
local pageElements = {} -- Store elements for each page
local stageListLabel = nil -- Label for stage progress
local STOCK_CATS = { base = "Cups", fruit = "Fruit", sweet = "Sweetener", topping = "Toppings" }
local STOCK_ORDER = { "base", "fruit", "sweet", "topping" }
local _stockCatIdx = _stockCatIdx or 1

local stockFrames       = stockFrames       or {}   -- one frame per category inside the Stock page
local stockRendered     = stockRendered     or {}   -- [cat] -> set of ids already rendered
local stockNameRefs     = stockNameRefs     or {}   -- [cat][id] -> label
stockLabelRefs          = stockLabelRefs    or {}   -- [cat][id] -> stock label
priceLabelRefs          = priceLabelRefs    or {}
-- Track last day we refreshed/rebuilt Stock at 06:00
local _lastStockRefreshDay = nil

-- Rebuild the Stock page based on current level + market state

local function rebuildStockPage()
  -- Remove any existing Stock widgets from the page
  if pageElements.stock then
    for _, el in ipairs(pageElements.stock) do
      if el and el.remove then el:remove() end
    end
  end
  pageElements.stock = {}

  -- Which category are we showing?
  local catKey = STOCK_ORDER[_stockCatIdx] or "base"
  local catTitle = (STOCK_CATS[catKey] or catKey):upper()

  -- Header: show category name
  local header = displayFrame:addLabel()
      :setText("[ "..catTitle.." ]")
      :setPosition(3, 3)
      :setZIndex(10)
      :hide()
  table.insert(pageElements.stock, header)

  -- Pager controls (bottom)
  local bottomY = (SCREEN_HEIGHT - 2) - 1
  local pageLbl = displayFrame:addLabel()
      :setText(("< page: %d/%d >"):format(_stockCatIdx, #STOCK_ORDER))
      :setPosition(22, bottomY)
      :setZIndex(10)
      :hide()
  local leftBtn = displayFrame:addButton()
      :setText("<")
      :setPosition(22, bottomY)
      :setSize(1,1)
      :setZIndex(10)
      :onClick(function()
        _stockCatIdx = (_stockCatIdx - 2) % #STOCK_ORDER + 1
        rebuildStockPage()
        if currentPage == "stock" then for _,e in ipairs(pageElements.stock) do e:show() end end
      end)
      :hide()
  local rightBtn = displayFrame:addButton()
      :setText(">")
      :setPosition(34, bottomY)
      :setSize(1,1)
      :setZIndex(10)
      :onClick(function()
        _stockCatIdx = (_stockCatIdx) % #STOCK_ORDER + 1
        rebuildStockPage()
        if currentPage == "stock" then for _,e in ipairs(pageElements.stock) do e:show() end end
      end)
      :hide()
  table.insert(pageElements.stock, pageLbl)
  table.insert(pageElements.stock, leftBtn)
  table.insert(pageElements.stock, rightBtn)

  -- Eligible, purchasable items for this category only
  local L = (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1

  -- Build a list of item tables (not just ids) to allow sorting by rarity + name
  local items = {}
  for _, it in ipairs(itemsAPI.listByType(catKey)) do
    if it.purchasable and itemsAPI.isUnlockedForLevel(it.id, L) then
      table.insert(items, it)
    end
  end

  table.sort(items, function(a, b)
    local ra, rb = getRarityRank(a), getRarityRank(b)
    if ra == rb then
      local na = (a.name or itemsAPI.nameById and itemsAPI.nameById(a.id) or a.id) or ""
      local nb = (b.name or itemsAPI.nameById and itemsAPI.nameById(b.id) or b.id) or ""
      return string.lower(na) < string.lower(nb)
    end
    return ra < rb
  end)

  -- Market stock snapshot
  local marketStock = inventoryAPI.getAvailableStock()

  -- Render rows (uses the same layout you had)
  local i = 1
  for _, it in ipairs(items) do
    local id = it.id
    i = i + 1
    local y = 3 + i
    local qtyToBuy = 1
    local name  = it.name or itemsAPI.nameById(id) or id
    local price = inventoryAPI.getMarketPrice(id)
    local amt   = marketStock[id] or 0

    local nameLabel = displayFrame:addLabel()
      :setText(("| %s"):format(name))
      :setPosition(1, y)
      :setZIndex(10)
      :hide()

    -- color the name by rarity
    local col = itemsAPI.itemRarityColor(it) -- 'it' is the item table in the loop
    if nameLabel.setForeground then nameLabel:setForeground(col) end

    local eachLabel = displayFrame:addLabel()
      :setText(("(    ea)"):format(price))
      :setPosition(16, y)
      :setZIndex(10)
      :hide()

    local priceLabel = displayFrame:addLabel()
      :setText(("$%d"):format(price))
      :setPosition(18, y)
      :setZIndex(10)
      :hide()
    -- optionally tint price a lighter shade; use gray/white for contrast
    if priceLabel.setForeground then priceLabel:setForeground(colors.yellow) end

    local stockLabel = displayFrame:addLabel()
      :setText("|In Stock: "..amt)
      :setPosition(24, y)
      :setZIndex(10)
      :hide()

    -- keep quick references so the 6am refresh code still updates
    stockLabelRefs[id] = stockLabel
    priceLabelRefs[id] = priceLabel

    local buyBtn = displayFrame:addButton()
      :setText("Buy")
      :setPosition(38, y)
      :setBackground(colors.blue)
      :setSize(5, 1)
      :setZIndex(10)
      :onClick(function()
        local ok, msg = inventoryAPI.buyFromMarket(id, qtyToBuy)
        if ok then
            spawnToast(displayFrame, (qtyToBuy .. " " .. name .. " bought!"), 16, 3, colors.blue, 1.0)
        else
            spawnToast(displayFrame, (msg or "Purchase failed."), 17, 3, colors.red, 1.0)
        end
        local newStock = inventoryAPI.getAvailableStock()
        local newPrice = inventoryAPI.getMarketPrice(id)
        if stockLabel and stockLabel.setText then stockLabel:setText("|In Stock: "..(newStock[id] or 0)) end
        if priceLabel and priceLabel.setText then priceLabel:setPosition(18,y):setText(("$%d"):format(newPrice)) end
      end)
      :hide()

    local qtyLabel = displayFrame:addLabel()
      :setText(tostring(qtyToBuy))
      :setPosition(46, y)
      :setZIndex(10)
      :hide()

    local decBtn = displayFrame:addButton()
      :setText("<")
      :setPosition(44, y)
      :setBackground(colors.white)
      :setSize(1, 1)
      :setZIndex(10)
      :onClick(function()
        qtyToBuy = math.max(1, qtyToBuy - 1)
        if qtyLabel and qtyLabel.setText then qtyLabel:setText(tostring(qtyToBuy)) end
      end)
      :hide()

    local incBtn = displayFrame:addButton()
      :setText(">")
      :setPosition(48, y)
      :setBackground(colors.white)
      :setSize(1, 1)
      :setZIndex(10)
      :onClick(function()
        qtyToBuy = qtyToBuy + 1
        if qtyLabel and qtyLabel.setText then qtyLabel:setText(tostring(qtyToBuy)) end
      end)
      :hide()

    table.insert(pageElements.stock, nameLabel)
    table.insert(pageElements.stock, eachLabel)
    table.insert(pageElements.stock, priceLabel)
    table.insert(pageElements.stock, stockLabel)
    table.insert(pageElements.stock, buyBtn)
    table.insert(pageElements.stock, decBtn)
    table.insert(pageElements.stock, qtyLabel)
    table.insert(pageElements.stock, incBtn)
  end
end

pageElements.upgrades = pageElements.upgrades or {}
local upgradeRowRefs, upgradeRowY = {}, {}
local LEFT_W   = 26   -- width for the left label (e.g., "Seating   Lv 3")
local EFFECT_W = 36   -- width for the effect line  (e.g., "Buy chance: 14% -> 21%")
local BTN_W    = 15
local BTN_X    = 34

local function pad(text, w)
  text = tostring(text or "")
  local n = w - #text
  if n > 0 then return text .. string.rep(" ", n) end
  return text:sub(1, w)
end

local function _L() return (levelAPI and levelAPI.getLevel and levelAPI.getLevel()) or 1 end
local function _canAfford(cost) return (economyAPI and economyAPI.canAfford and economyAPI.canAfford(cost)) or true end

local function _expMultNow()
  if upgradeAPI and upgradeAPI.expBoostFactor then return upgradeAPI.expBoostFactor() end
  local s = saveAPI.get(); local u = s.upgrades or {}; local lvl = tonumber(u.exp_boost or 0) or 0
  local M = {1.0, 1.5, 2.25, 3.5, 4.25, 5.0}; return M[math.min(lvl,5)+1]
end

local function _expMultNext(lvl)
  local def = upgradeAPI.catalog and upgradeAPI.catalog.exp_boost
  return def and def.multipliers and def.multipliers[(lvl or 0)+1]
end

local function _prettyName(k)
  return ({seating="Seating",marketing="Marketing",awning="Awning",ice_shaver="Ice Shaver",juicer="Juicer",exp_boost="EXP Boost"})[k] or k
end

local function _effectText(key, lvl)
  if key=="seating"   then return ("Buy chance: %.0f%% -> %.0f%%"):format( 7*(lvl or 0), 7*((lvl or 0)+1) )
  elseif key=="marketing" then return ("Customers/hr: x%.2f -> x%.2f"):format(1+0.15*(lvl or 0), 1+0.15*((lvl or 0)+1))
  elseif key=="awning"    then return ("Price tolerance: x%.2f -> x%.2f"):format(1-0.12*(lvl or 0), 1-0.12*((lvl or 0)+1))
  elseif key=="exp_boost" then
    local cur = _expMultNow(); local nxt = _expMultNext(lvl)
    return nxt and ("XP boost: x%.2f -> x%.2f"):format(cur, nxt) or ("XP boost: x%.2f (Max)"):format(cur)
  elseif key=="ice_shaver" then return "Unlocks 'Italian Ice' product in Craft"
  elseif key=="juicer"     then return "Fruit requirement: -1 when crafting"
  end
  return ""
end

local function _rowColor(state)  return (state=="locked" or state=="owned") and colors.gray or colors.black end
local function _effectColor(s)   return (s=="locked" or s=="owned") and colors.gray or colors.yellow end
local function _btnBg(en)        return en and colors.blue or colors.lightGray end
local function _btnFg(en)        return en and colors.white or colors.gray end

local function _destroyRow(key)
  local refs = upgradeRowRefs[key]
  if refs then
    for _, el in ipairs(refs) do
      if el and el.destroy then pcall(function() el:destroy() end)
      elseif el and el.remove  then pcall(function() el:remove()  end) end
    end
  end
  upgradeRowRefs[key] = nil
end

-- Build (or rebuild) a single row in place — no page-wide rebuilds.
local function buildUpgradeRow(key, y)
  upgradeRowY[key] = y
  _destroyRow(key)

  -- fresh read of state
  local def      = upgradeAPI.catalog[key]
  local oneTime  = def and def.one_time
  local lvl      = (upgradeAPI.level  and upgradeAPI.level(key))  or 0
  local ownedOT  = (upgradeAPI.has    and upgradeAPI.has(key))    or false
  local cost     = (upgradeAPI.cost   and upgradeAPI.cost(key))   or 0
  local canBuy, why = true, nil
  if upgradeAPI.canPurchase then canBuy, why = upgradeAPI.canPurchase(key) end
  local atCap = (not oneTime) and def and def.level_cap and (lvl >= def.level_cap)

  local state
  if oneTime then
    state = ownedOT and "owned" or (canBuy and "buyable" or "locked")
  else
    state = (atCap and "owned") or (canBuy and "buyable" or "locked")
  end

  -- LEFT LINE (bounded + padded + high zIndex)
  local leftText = (oneTime
    and ("%s   $%d  (%s)"):format(_prettyName(key), cost, ownedOT and "Unlocked" or "Locked")
    or  ("%s   Lv %d"):format(_prettyName(key), lvl))

  local left = displayFrame:addLabel()
      :setPosition(2, y)
      :setSize(LEFT_W, 1)                 -- bound draw area
      :setZIndex(50)                      -- draw above buttons
      :setText(pad(leftText, LEFT_W))     -- overwrite any leftover chars
      :setForeground(_rowColor(state))
      :hide()
  -- no background on labels (keeps background visible; spaces erase within box)

  -- EFFECT LINE (bounded + padded + high zIndex)
  local effText = _effectText(key, lvl)
  local eff = displayFrame:addLabel()
      :setPosition(2, y + 1)
      :setSize(EFFECT_W, 1)
      :setZIndex(50)
      :setText(pad(effText, EFFECT_W))
      :setForeground(_effectColor(state))
      :hide()

  -- BUTTON (lower zIndex so labels always sit on top)
  local btnText
  if state == "locked" then
    btnText = "LOCKED"
  elseif oneTime then
    btnText = ownedOT and "Owned" or (key == "juicer" and "Upgrade req -1" or "Unlock Product")
  else
    btnText = atCap and "Maxed" or ("Lv " .. (lvl + 1) .. " - $" .. tostring(cost))
  end

  local enabled = (state ~= "locked") and not (oneTime and ownedOT) and not (not oneTime and atCap)
                  and _canAfford(cost) and canBuy

  local btn = displayFrame:addButton()
      :setPosition(BTN_X, y)
      :setSize(BTN_W, 1)
      :setText(btnText)
      :setBackground(_btnBg(enabled))
      :setForeground(_btnFg(enabled))
      :setZIndex(20)     -- below labels
      :hide()

  btn:onClick(function()
    local cBuy, whyNow = canBuy, why
    if upgradeAPI.canPurchase then cBuy, whyNow = upgradeAPI.canPurchase(key) end
    local okEnabled = (state ~= "locked")
      and not (oneTime and ownedOT)
      and not (not oneTime and atCap)
      and _canAfford(cost)
      and cBuy

    if not okEnabled then
      spawnToast(displayFrame, whyNow or "Locked", 17, 3, colors.red, 1.0)
      return
    end

    local ok, msg = upgradeAPI.purchase(key, function(c) return economyAPI.spendMoney(c) end)
    spawnToast(displayFrame, msg or (ok and "Purchased!" or "Purchase failed"), 16, 3, ok and colors.cyan or colors.red, 1.0)

    -- Row-only refresh
    local yy = upgradeRowY[key] or y
    buildUpgradeRow(key, yy)
    if currentPage == "upgrades" then
      local refs = upgradeRowRefs[key]
      if refs then for _, el in ipairs(refs) do if el.show then el:show() end end end
    end
  end)

  upgradeRowRefs[key] = {left, eff, btn}
  table.insert(pageElements.upgrades, left)
  table.insert(pageElements.upgrades, eff)
  table.insert(pageElements.upgrades, btn)

  if currentPage == "upgrades" then
    left:show(); eff:show(); btn:show()
  end
end

function rebuildUpgradesPage()
  -- nuke previous page elements (and unregister handlers)
  if pageElements.upgrades then
    for _, el in ipairs(pageElements.upgrades) do
      if el and el.destroy then pcall(function() el:destroy() end)
      elseif el and el.remove  then pcall(function() el:remove()  end) end
    end
  end
  pageElements.upgrades = {}
  upgradeRowRefs, upgradeRowY = {}, {}

  local y = 3
  local hdr = displayFrame:addLabel()
      :setText("Upgrades")
      :setPosition(2, y)
      :setZIndex(10)
      :hide()
  table.insert(pageElements.upgrades, hdr)
  y = y + 1

  -- Instead of a for-loop, explicitly build each visible row:
  local Lvl = _L()
  if upgradeAPI.isVisibleAtLevel("seating",    Lvl) then buildUpgradeRow("seating",    y); y = y + 2 end
  if upgradeAPI.isVisibleAtLevel("marketing",  Lvl) then buildUpgradeRow("marketing",  y); y = y + 2 end
  if upgradeAPI.isVisibleAtLevel("awning",     Lvl) then buildUpgradeRow("awning",     y); y = y + 2 end
  if upgradeAPI.isVisibleAtLevel("exp_boost",  Lvl) then buildUpgradeRow("exp_boost",  y); y = y + 2 end
  if upgradeAPI.isVisibleAtLevel("ice_shaver", Lvl) then buildUpgradeRow("ice_shaver", y); y = y + 2 end
  if upgradeAPI.isVisibleAtLevel("juicer",     Lvl) then buildUpgradeRow("juicer",     y); y = y + 2 end
end


-- Initialize Page Elements
local function initPageElements()
      -- Main Page
  pageElements.main = pageElements.main or {}
  table.insert(pageElements.main,
    displayFrame:addLabel()
      :setText("---------------| Main Screen |---------------")
      :setPosition(2, 2)
      :setZIndex(10)
      :hide()
  )

  -- Add the Guide button (place wherever your main-page controls live)
  local guideBtn = displayFrame:addButton()
    :setText("[??]")
    :setPosition(2, 3)
    :setSize(4, 1)
    :setBackground(colors.blue)
    :setForeground(colors.black)
    :hide()
    :onClick(function()
      guideAPI.show()
    end)

  table.insert(pageElements.main, guideBtn)

    -- Licenses Page
    pageElements.licenses = {}
    table.insert(pageElements.licenses, displayFrame:addLabel():setText("Licenses"):setPosition(2, 2):setZIndex(10):hide())
    local function addLicenseButton(id, y)
        local license = licenseAPI.licenses[id]
        local btn = displayFrame:addButton()
            :setText(license.name .. " ($" .. license.cost .. ")")
            :setPosition(2, y)
            :setSize(25, 3)
            :setZIndex(10)
            :onClick(function()
                local success, msg = licenseAPI.purchase(id)
                print(msg)
                refreshUI()
            end)
            :hide()
        table.insert(pageElements.licenses, btn)
    end
    addLicenseButton("lemonade", 5)
    addLicenseButton("warehouse", 9)
    addLicenseButton("factory", 13)
    addLicenseButton("highrise", 17)

    -- Dynamic Stock Page
    pageElements.stock = {}
    rebuildStockPage()

    -- Stages Page
    pageElements.stages = {}
    table.insert(pageElements.stages, displayFrame:addLabel():setText("Stages"):setPosition(2, 2):setZIndex(10):hide())
    stageListLabel = displayFrame:addLabel():setText("Progress:\n"):setPosition(2, 5):setZIndex(10):hide()
    table.insert(pageElements.stages, stageListLabel)

    -- Upgrades Page
    pageElements.upgrades = {}
    rebuildUpgradesPage()

end



-- Page Switching (elements only; background handled by stageAPI)
local function switchPage(pageName)
  if currentPage and pageElements[currentPage] then
  _hideGroup(pageElements[currentPage])
  end
  if currentPage and pageBackgrounds[currentPage] then
  pageBackgrounds[currentPage]:hide()
  end
  if pageName == "Licenses" then 
  end

  if pageName == "stock" then rebuildStockPage() end
  if pageName == "upgrades" then rebuildUpgradesPage() end

  -- show + enable new page’s elements
  if pageElements[pageName] then
    currentPage = pageName
    _showGroup(pageElements[pageName])
    if pageBackgrounds[pageName] then pageBackgrounds[pageName]:show() end
  end

  -- refresh stage backdrop unless a popup is active
  if not _isPopupActive and stageAPI and stageAPI.refreshBackground then
    stageAPI.refreshBackground(displayFrame)
  end
end


-- Sidebar Population
local function populateSidebar()
  local pages = {"Main", "Licenses", "Stock", "Stages", "Upgrades"}
  for i, page in ipairs(pages) do
    local pname = string.lower(page)   -- capture a fresh value each loop
    sidebar:addButton()
      :setText(page)
      :setPosition(2, 1 + (i-1)*4)
      :setSize(12, 3)
      :setBackground(colors.blue)
      :setForeground(colors.white)
      :onClick(function()
        switchPage(pname)
      end)
  end
end

local function renderLevelHUD()
    do
      local prog = levelAPI.getProgress()
      local L = (prog and prog.level) or (levelAPI.getLevel and levelAPI.getLevel()) or 1
      if not _lastLevelSeen then _lastLevelSeen = L end
      if L > _lastLevelSeen then
        _lastLevelSeen = L
        showLevelUpPopup(L)
      end
    end

  local prog = levelAPI.getProgress()
  local lvl = prog.level or 1
  local into = tonumber(prog.xpInto or 0) or 0
  local need = tonumber(prog.xpToNext or 1) or 1
  if need <= 0 then need = 1 end
  local pct = math.floor((into / need) * 100 + 0.5)
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  local slots = 10
  local filled = math.floor((into / need) * slots + 0.5)
  if filled < 0 then filled = 0 end
  if filled > slots then filled = slots end
  local bar = string.rep("#", filled) .. string.rep("-", slots - filled)
  if levelLabel then levelLabel:setText("lvl " .. tostring(lvl)):setForeground(colors.yellow) end
  if levelBarLabel then levelBarLabel:setText("|" .. bar .. "| " .. tostring(pct) .. "%"):setForeground(colors.blue) end
end





-- Refresh UI
local _lastStageKey = nil
local _lastLevelSeen = _lastLevelSeen or nil
function refreshUI()
     local t = timeAPI.getTime()
    -- Check for daily 6AM stock refresh
    do
        local day = saveAPI.get().time.day
        local hour = saveAPI.get().time.hour

        if hour == 6 then
            pcall(function()
                local stock = inventoryAPI.getAvailableStock()
                    for id, lbl in pairs(stockLabelRefs) do
                        lbl:setText("|In Stock: " .. (stock[id] or 0))
                    end
                    for id, plbl in pairs(priceLabelRefs) do
                        plbl:setText(("$%d"):format(inventoryAPI.getMarketPrice(id)))
                    end

        -- Rebuild Stock page once per day at 06:00 so newly-unlocked items appear
        if hour == 6 and _lastStockRefreshDay ~= day then
            _lastStockRefreshDay = day
            rebuildStockPage()
            if currentPage == "stock" then
                for _, el in ipairs(pageElements.stock) do el:show() end
            end
        end
            end)
        end
    end
    renderLevelHUD()
    -- keep save time in sync if helper exists
    if timeAPI and timeAPI.bindToSave then timeAPI.bindToSave() end
    local state = saveAPI.get()

    local currentStage = STAGES[state.player.progress] or STAGES.odd_jobs

    -- Set stage/background only if changed
        local stageKey = progressToStage(state.player.progress)
        if stageKey ~= _lastStageKey then
            if stageAPI and stageAPI.setStage then stageAPI.setStage(stageKey) end
            if stageAPI and stageAPI.refreshBackground then stageAPI.refreshBackground(displayFrame) end
            _lastStageKey = stageKey
        end

        timeLabel:setText(string.format("Time: Y%d M%d D%d %02d:%02d", t.year, t.month, t.day, t.hour, t.minute))
            moneyLabel:setText("Money: $" .. state.player.money)
            stageLabel:setText("Stage: " .. currentStage.name)

            -- Update Stages page
            if currentPage == "stages" and stageListLabel then
                local stageText = "Progress:\n"
                for id, stage in pairs(STAGES) do
                    stageText = stageText .. (id == state.player.progress and "> " or "  ") .. stage.name .. "\n"
                end
                stageListLabel:setText(stageText)
            end

    -- Dynamically update Buy page for stage upgrade
    if currentPage == "stages" then
        local existing = displayFrame:getChild("upgradeButton")
        if existing then existing:remove() end
        if currentStage.next then
            local nextStage = STAGES[currentStage.next]
            local lvl = (upgradeAPI.level and upgradeAPI.level(key)) or 0
            local btn = displayFrame:addButton("upgradeButton")
                :setText("Unlock " .. nextStage.name .. " ($" .. currentStage.cost .. ")")
                :setPosition(4, 13)
                :setSize(25, 3)
                :setZIndex(10)
                :onClick(function()
                if lvl >= currentStage.req_lvl then
                    if licenseAPI.has(currentStage.required_license) and economyAPI.spendMoney(currentStage.cost, "Stage Upgrade") then
                        state.player.progress = currentStage.next
                        stageAPI.unlock(progressToStage(currentStage.next))
                        saveAPI.setState(state)
                        refreshUI()
                    elseif not licenseAPI.has(currentStage.required_license) then
                        spawnToast(displayFrame, ("License "..currentStage.required_license.." required!"), 15, 2, colors.red, 1.7)
                    end
                else
                    spawnToast(displayFrame, ("level "..currentStage.req_lvl.." required!"), 15, 2, colors.red, 1.7)
                end
                end)
            table.insert(pageElements.stages, btn)
        end
    end

    -- Save the current time to the state
    saveAPI.updateTime(t)
end

-- Background Time Update
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


-- Initialization

local function initialize()
    if not saveAPI.hasSave() then
        saveAPI.newGame()
    else
        saveAPI.load()
    end

    -- Kick the UI loop immediately so loading screen paints.
    -- IMPORTANT: The loader thread never returns (it idles after setup),
    -- so parallel.waitForAny will keep basalt.autoUpdate() alive.
    parallel.waitForAny(
        function()
            basalt.autoUpdate()
        end,
        function()
            -- Preload & paint backgrounds with progress
            initStageBackgroundsCached()
            -- Once backgrounds are ready, build pages & show default
            initPageElements()
            populateSidebar()
            switchPage("main")
            -- start the time tick thread AFTER UI exists
            startTimeUpdates()
            -- never return; idle to keep parallel.waitForAny alive
            while true do os.sleep(0.5) end
        end
    )
end

-- Main Execution
initialize()

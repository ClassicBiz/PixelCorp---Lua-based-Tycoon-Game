-- TycoonGame Main Loader - CC:Tweaked + Basalt
-- Adds Main Menu Settings with tabs: General, Save/Load, Game Version.
local function getRoot()
    local dir = fs.getDir(shell.getRunningProgram())
    if dir == "" then return "/" end
    return "/"..dir
end
local root = getRoot()
local basalt = require("/PixelCorp/API/basalt")

-- APIs
local timeAPI = require(root.."/API/timeAPI")
local saveAPI = require(root.."/API/saveAPI")
local economyAPI = require(root.."/API/economyAPI")
local backgroundAPI = require(root.."/API/backgroundAPI")
local settingsAPI = require(root.."/API/settingsAPI")
local updaterAPI  = require(root.."/API/updaterAPI")
local uiAPI = require(root.."/API/uiAPI")
local SCREEN_WIDTH, SCREEN_HEIGHT = term.getSize()
local GAME_TITLE = "Pixel Corp"
local GROUND_Y = 12  -- ground row for walking dots

-- Ensure save folders
if not fs.exists(root.."/saves/") then fs.makeDir(root.."/saves/") end
if not fs.exists(root.."/saves/profiles") then fs.makeDir(root.."/saves/profiles") end
if not fs.exists(root.."/config") then fs.makeDir(root.."/config") end

local function _archiveProfileAndClearActive(profileName)
  local slot   = profileName or "profile1"
  saveAPI.setProfile(slot)
  saveAPI.archiveCurrentCommitted(slot)
end

-- 3x5 glyphs used for the title
local BIG = {
  P = {"111","101","111","100","100"},
  I = {"111","010","010","010","111"},
  X = {"101","010","010","010","101"},
  E = {"111","100","110","100","111"},
  L = {"100","100","100","100","111"},
  C = {"011","100","100","100","011"},
  O = {"111","101","101","101","111"},
  R = {"111","101","111","110","101"},
  [" "] = {"000","000","000","000","000"},
}

local function _drawGlyph(frame, glyph, x, y, scale, color)
  scale = scale or 1
  for row = 1, #glyph do
    local line, col = glyph[row], 1
    while col <= #line do
      if line:sub(col,col) == "1" then
        local startCol = col
        while col <= #line and line:sub(col,col) == "1" do col = col + 1 end
        local w = (col - startCol)
        frame:addPane()
          :setPosition(x + (startCol-1)*scale, y + (row-1)*scale)
          :setSize(w*scale, scale)
          :setBackground(color)
      else
        col = col + 1
      end
    end
  end
end

local function drawBigText(frame, text, x, y, opts)
  opts = opts or {}
  local scale   = opts.scale or 1
  local color   = opts.color or colors.blue
  local shadow  = opts.shadow or false
  local spacing = opts.spacing or 1
  local dx = (shadow and (type(shadow)=="table" and (shadow.dx or 1) or 1)) or 0
  local dy = (shadow and (type(shadow)=="table" and (type(shadow)=="table" and (shadow.dy or 1) or 1)) or 0)
  local shColor = (shadow and (type(shadow)=="table" and (shadow.color or colors.gray) or colors.gray)) or nil

  local cursor = x
  if shadow then
    local c2 = cursor + dx*scale
    for i = 1, #text do
      local g = BIG[text:sub(i,i):upper()]
      if g then
        _drawGlyph(frame, g, c2, y + dy*scale, scale, shColor)
        c2 = c2 + ((#g[1] + spacing) * scale)
      else
        c2 = c2 + ((5 + spacing) * scale)
      end
    end
  end

  for i = 1, #text do
    local g = BIG[text:sub(i,i):upper()]
    if g then
      _drawGlyph(frame, g, cursor, y, scale, color)
      cursor = cursor + ((#g[1] + spacing) * scale)
    else
      cursor = cursor + ((5 + spacing) * scale)
    end
  end
end

-- Backgrounds
local BG_LIST = {
  root.."/assets/screen.nfp",   -- title scene (no customers)
  root.."/assets/lemon.nfp",    -- lemonade stand
  root.."/assets/office.nfp",   -- office
  root.."/assets/factory.nfp",  -- factory
}

-- Per-background animation config
local BG_CFG = {
  [root.."/assets/screen.nfp"]  = { spawn = "none",  targetX = nil, targetY = nil },
  [root.."/assets/lemon.nfp"]   = { spawn = "right", targetX = 14,  targetY = GROUND_Y },
  [root.."/assets/office.nfp"]  = { spawn = "right", targetX = 17,  targetY = GROUND_Y },
  [root.."/assets/factory.nfp"] = { spawn = "right", targetX = 23,  targetY = GROUND_Y },
}

local function stopUIAndRun(fn)
  basalt.stop()
  os.queueEvent("pc_next_tick")
  while true do
    local e = { os.pullEvent() }
    if e[1] == "pc_next_tick" then
      fn()
      break
    end
  end
end

-- =======================
-- Settings Modal (Main)
-- =======================
local function openSettingsModal(parent)
  local W,H = term.getSize()
  local border = parent:addFrame():setSize(49,17):setPosition(2,2)
      :setBackground(colors.lightGray):setZIndex(40)
  local f = border:addFrame():setSize(47,15):setPosition(2,2):setBackground(colors.white)

  f:addLabel():setText("Settings"):setPosition(20,1):setForeground(colors.gray)
  border:addButton():setText(" X "):setPosition(47,1):setBackground(colors.red):setForeground(colors.black):setSize(3,1)
  :onClick(function() border:hide(); border:remove() end)
  -- Tabs
  local tabs = f:addMenubar():setPosition(7,2):setSize(34,1):setScrollable(false)
      :addItem("General"):addItem("Save/Load"):addItem("Game Version")

  local pages = {
    general = f:addFrame():setPosition(2,4):setSize(44,12):setBackground(colors.white):hide(),
    saveload = f:addFrame():setPosition(2,4):setSize(44,12):setBackground(colors.white):hide(),
    version = f:addFrame():setPosition(2,4):setSize(44,12):setBackground(colors.white):hide(),
  }

  local function showPage(key)
    for k,frame in pairs(pages) do if frame.hide then frame:hide() end end
    pages[key]:show()
  end

  -- ---------- General Tab ----------
  local gen = pages.general
  gen:addLabel():setText("Difficulty:"):setPosition(2,2)
  local ddDiff = gen:addDropdown():setPosition(14,2):setSize(14,1)
  ddDiff:addItem("easy"); ddDiff:addItem("medium"); ddDiff:addItem("hard")

  gen:addLabel():setText("Navigation:"):setPosition(2,4)
  local ddNav = gen:addDropdown():setPosition(14,4):setSize(14,1)
  ddNav:addItem("dropdown"); ddNav:addItem("sidebar")

  gen:addLabel():setText("Tutorial:"):setPosition(2,6)
  local ddTut = gen:addDropdown():setPosition(14,6):setSize(10,1)
  ddTut:addItem("on"); ddTut:addItem("off")

  gen:addLabel():setText("Autosave:"):setPosition(2,8)
  local ddAuto = gen:addDropdown():setPosition(14,8):setSize(10,1)
  ddAuto:addItem("on"); ddAuto:addItem("off")

  local s = settingsAPI.load()
  local function _applyDD(dd, val, def)
    local v = tostring(val or def or "")
    for i=1, dd:getItemCount() do local it = dd:getItem(i); local t = (type(it)=="table" and it.text) or it
      if t == v then dd:selectItem(i) break end
    end
  end
  _applyDD(ddDiff, s.general.difficulty, "medium")
  _applyDD(ddNav,  s.general.navigation, "sidebar")
  _applyDD(ddTut,  s.general.tutorial and "on" or "off", "on")
  _applyDD(ddAuto, s.general.autosave and "on" or "off", "off")

  gen:addButton():setText("Save")
    :setPosition(34,11):setSize(12,1):setBackground(colors.green):setForeground(colors.white)
    :onClick(function()
      -- robust text extractor (works if dropdown returns text, table, or index)
      local function _read(dd)
        if not dd or not dd.getValue then return nil end
        local v = dd:getValue()
        if type(v) == "table" and v.text then return v.text end    -- some Basalt builds
        if type(v) == "number" and dd.getItem then                 -- index → text
          local it = dd:getItem(v); if type(it)=="table" then return it.text end
        end
        return v                                                   -- already a string
      end

      -- load, mutate, save the entire settings object
      local s = settingsAPI.load()
      s.general = s.general or {}
      s.general.difficulty = _read(ddDiff) or "medium"
      s.general.navigation = _read(ddNav)  or "sidebar"
      s.general.tutorial   = ((_read(ddTut)  or "on")  == "on")
      s.general.autosave   = ((_read(ddAuto) or "off") == "on")
      uiAPI.toast(f,"Settings Saved",15,14,colors.green,1.2)
      settingsAPI.save(s)  -- <- writes /config/.settings
    end)

  -- ---------- Save/Load Tab ----------
  local sl = pages.saveload
  sl:addLabel():setText("Active Profile:"):setPosition(2,2)
  local ddProf = sl:addDropdown():setPosition(18,2):setSize(18,1)
  local list = saveAPI.listProfiles()
  if #list == 0 then list = {"profile1"} end
  for _,p in ipairs(list) do ddProf:addItem(p) end
  -- pre-select current
  local cur = saveAPI.getActiveProfile()
  for i=1, ddProf:getItemCount() do local it=ddProf:getItem(i); local t=(type(it)=="table" and it.text) or it
    if t==cur then ddProf:selectItem(i) break end
  end

  sl:addLabel():setText("Rename to:"):setPosition(2,4)
  local tfName = sl:addInput():setPosition(18,4):setSize(18,1)

  sl:addButton():setText("Apply Rename"):setPosition(2,6):setSize(16,1):setBackground(colors.blue):setForeground(colors.white)
    :onClick(function()
      local src = (type(ddProf:getValue())=="table" and ddProf:getValue().text) or ddProf:getValue()
      local dst = tfName:getValue()
      local ok, msg = saveAPI.renameProfile(src, dst)
      if ok then
        ddProf:clear()
        for _,p in ipairs(saveAPI.listProfiles()) do ddProf:addItem(p) end
      end
    end)

  sl:addButton():setText("Load on Next Start"):setPosition(20,6):setSize(20,1):setBackground(colors.orange):setForeground(colors.black)
    :onClick(function()
      local v = (type(ddProf:getValue())=="table" and ddProf:getValue().text) or ddProf:getValue()
      if v and v ~= "" then settingsAPI.set({"profile","last_loaded"}, v) end
    end)

  sl:addButton():setText("Recover Previous Save"):setPosition(2,8):setSize(18,1):setBackground(colors.yellow):setForeground(colors.black)
    :onClick(function()
      local v = (type(ddProf:getValue())=="table" and ddProf:getValue().text) or ddProf:getValue()
      local ok, msg = saveAPI.recoverLast(v)
    end)

  sl:addButton():setText("Reset All Saves"):setPosition(22,8):setSize(18,1):setBackground(colors.red):setForeground(colors.white)
    :onClick(function()
      saveAPI.resetAllSaves()
      ddProf:clear(); ddProf:addItem("profile1")
    end)

  -- ---------- Game Version Tab ----------
  local gv = pages.version
  gv:addLabel():setText("Version:"):setPosition(2,2)
  local ddVer = gv:addDropdown():setPosition(12,2):setSize(18,1)
  local vers, latest = updaterAPI.getVersionList()
  for _,v in ipairs(vers) do ddVer:addItem(v) end
  -- Try to select current from settings
  local curV = settingsAPI.get({"version","current"}, latest or "dev")
  for i=1, ddVer:getItemCount() do local it=ddVer:getItem(i); local t=(type(it)=="table" and it.text) or it
    if t==curV then ddVer:selectItem(i) break end
  end

  gv:addButton():setText("Update to Latest"):setPosition(2,5):setSize(18,1):setBackground(colors.green):setForeground(colors.white)
    :onClick(function()
      local ok, msg = updaterAPI.updateLatest()
    end)

  gv:addButton():setText("Repair Current"):setPosition(22,5):setSize(18,1):setBackground(colors.blue):setForeground(colors.white)
    :onClick(function()
      local ok, msg = updaterAPI.repairCurrent()
    end)

  gv:addButton():setText("Switch Version"):setPosition(2,7):setSize(18,1):setBackground(colors.orange):setForeground(colors.black)
    :onClick(function()
      local v = (type(ddVer:getValue())=="table" and ddVer:getValue().text) or ddVer:getValue()
      settingsAPI.set({"version","current"}, v or "dev")
      updaterAPI.switchTo(v or "dev")
    end)

  tabs:onChange(function(self)
    local idx = self:getItemIndex() or 1
    if idx == 1 then showPage("general")
    elseif idx == 2 then showPage("saveload")
    else showPage("version") end
  end)
  -- default to General
  showPage("general")
end

local function loadMainMenu()
  local main = basalt.createFrame():setSize(SCREEN_WIDTH, SCREEN_HEIGHT):setPosition(1, 1)

  local bgFrame = main:addFrame()
    :setSize(SCREEN_WIDTH, SCREEN_HEIGHT)
    :setPosition(1, 1)
    :setZIndex(5)
    :setBackground(colors.lightBlue)

  local function addMenuButton(label, yOffset, bkColor, txColor, onClick)
    main:addButton()
      :setText(label)
      :setPosition(35, yOffset)
      :setBackground(bkColor)
      :setForeground(txColor)
      :setSize(12, 1)
      :setZIndex(9)
      :onClick(onClick)
  end

  local running = true

  local function bootGame()
    running = false
    stopUIAndRun(function()
      shell.run(root.."/game/mainLoop.lua")
    end)
  end

  addMenuButton("[ New Game ]", 10, colors.gray, colors.green, function()
    local slot = settingsAPI.get({"profile","last_loaded"}, "profile1")
    _archiveProfileAndClearActive(slot)
    saveAPI.setProfile(slot)
    saveAPI.newGame()
    economyAPI.addMoney(350, "fresh start")
    saveAPI.commit(slot)
    if timeAPI and timeAPI.loadFromSave then timeAPI.loadFromSave() end
    bootGame()
  end)

  addMenuButton("[ Continue ]", 12, colors.gray, colors.orange, function()
    local slot = settingsAPI.get({"profile","last_loaded"}, "profile1")
    saveAPI.setProfile(slot)
    if saveAPI.hasSave(slot) then
      saveAPI.loadCommitted(slot)
      if timeAPI.loadFromSave then timeAPI.loadFromSave() end
      bootGame()
    else
      print("No save file found!")
    end
  end)

  addMenuButton("[ Settings ]", 14, colors.gray, colors.white, function()
    openSettingsModal(main)
  end)

  addMenuButton("[   Quit   ]", 16, colors.gray, colors.red, function()
    running = false
    stopUIAndRun(function()
      term.setBackgroundColor(colors.black)
      term.clear()
      term.setCursorPos(1, 1)
    end)
  end)

  for _, path in ipairs(BG_LIST) do
    pcall(function() backgroundAPI.preload(path) end)
  end
  pcall(function() backgroundAPI.prewarm(bgFrame, BG_LIST) end)

  local BG_SECONDS = 10
  local bgIndex = 1
  local currentPath = BG_LIST[bgIndex]

  local customers = {}
  local function cfgFor(path) return BG_CFG[path] or { spawn = "none" } end

  local function setBG(path)
    backgroundAPI.setCachedBackground(bgFrame, path)
  end

  local function drawTitle()
    drawBigText(bgFrame, GAME_TITLE, 7, 1, {
      scale = 1,
      color = colors.blue,
      shadow = { dx = 1, dy = 1, color = colors.gray }
    })
  end

  local function clearCustomers()
    for i = #customers, 1, -1 do
      local c = customers[i]
      if c.pane then c.pane:remove() end
      customers[i] = nil
    end
  end

  local function spawnCustomerFor(path)
    local cfg = cfgFor(path)
    if cfg.spawn == "none" then return end
    local targetX = cfg.targetX or math.floor(SCREEN_WIDTH/2)
    local x, y, vx = 1, GROUND_Y, 0
    if cfg.spawn == "right" then
      x = SCREEN_WIDTH-2; vx = -(0.6 + math.random()*0.5)
    elseif cfg.spawn == "left" then
      x = 2;             vx =  (0.6 + math.random()*0.5)
    elseif cfg.spawn == "bottom" then
      x = math.random(3, SCREEN_WIDTH-3); y = SCREEN_HEIGHT-2; vx = 0
    else
      return
    end
    local color = (math.random() < 0.5) and colors.yellow or colors.brown
    local p = bgFrame:addPane():setSize(1,2):setPosition(x,y):setBackground(color)
    customers[#customers+1] = { pane=p, x=x, y=y, vx=vx, targetX=targetX, path=path }
  end

  local function tickCustomers(path)
    local cfg = cfgFor(path)
    for i = #customers, 1, -1 do
      local c = customers[i]
      if not running or cfg.spawn == "none" or c.path ~= path then
        if c.pane then c.pane:remove() end
        table.remove(customers, i)
      else
        c.y = GROUND_Y
        c.x = c.x + c.vx
        local reachedX = (c.vx <= 0 and c.x <= c.targetX) or (c.vx > 0 and c.x >= c.targetX)
        if reachedX then
          if c.pane then c.pane:remove() end
          table.remove(customers, i)
        else
          c.pane:setPosition(math.floor(c.x), GROUND_Y)
        end
      end
    end
  end

  local ok, now = pcall(os.epoch, "utc")
  math.randomseed(ok and now or math.floor(os.clock()*1e6))

  setBG(currentPath)
  drawTitle()
  if cfgFor(currentPath).spawn ~= "none" then for _=1,3 do spawnCustomerFor(currentPath) end end

  main:addThread():start(function()
    while running do
      os.sleep(BG_SECONDS)
      if not running then break end
      bgIndex      = (bgIndex % #BG_LIST) + 1
      currentPath  = BG_LIST[bgIndex]
      clearCustomers()
      setBG(currentPath)
      drawTitle()
      local cfg = cfgFor(currentPath)
      if cfg.spawn ~= "none" then
        for _=1, math.random(1,3) do spawnCustomerFor(currentPath) end
      end
    end
  end)

  main:addThread():start(function()
    local spawnTimer, dt, gcTimer = 0, 0.12, 0
    while running do
      local cfg = cfgFor(currentPath)
      spawnTimer = spawnTimer + dt
      gcTimer    = gcTimer + dt
      if cfg.spawn ~= "none" and #customers < 4 and spawnTimer >= 0.8 then
        spawnTimer = 0
        spawnCustomerFor(currentPath)
      end
      tickCustomers(currentPath)
      if gcTimer >= 5 then gcTimer = 0; pcall(collectgarbage, "collect") end
      os.sleep(dt)
    end
  end)

  basalt.autoUpdate()
end

loadMainMenu()

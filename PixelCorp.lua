-- TycoonGame Main Loader - CC:Tweaked + Basalt
-- Single bgFrame for background + title + dots
-- Uses Basalt frame threads (addThread():start(function() ... end))
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
local backgroundAPI = require(root.."/API/backgroundAPI")

local SCREEN_WIDTH, SCREEN_HEIGHT = term.getSize()
local GAME_TITLE = "Pixel Corp"
local GROUND_Y = 12  -- ground row for walking dots

-- Ensure save folders
if not fs.exists(root.."/saves/") then fs.makeDir(root.."/saves/") end
if not fs.exists(root.."/saves/profiles") then fs.makeDir(root.."/saves/profiles") end

local function _archiveProfileAndClearActive(profileName)
  local slot   = profileName or "profile1"
  if saveAPI and saveAPI.setProfile then saveAPI.setProfile(slot) end

  local base   = root.."/saves/profiles"
  if not fs.exists(base) then fs.makeDir(base) end

  local committed = fs.combine(base, slot .. ".json")
  local archived  = fs.combine(base, slot .. "_old.json")
  if fs.exists(archived) then fs.delete(archived) end
  if fs.exists(committed) then fs.move(committed, archived) end
  if fs.exists(root.."/saves/active.json") then fs.delete(root.."/saves/active.json") end
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

-- Draw one glyph onto a frame using run-length spans
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
  local dy = (shadow and (type(shadow)=="table" and (shadow.dy or 1) or 1)) or 0
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

-- Defer helper so button clicks are single-tap
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

local function loadMainMenu()
  local main = basalt.createFrame():setSize(SCREEN_WIDTH, SCREEN_HEIGHT):setPosition(1, 1)

  -- Single visual frame
  local bgFrame = main:addFrame()
    :setSize(SCREEN_WIDTH, SCREEN_HEIGHT)
    :setPosition(1, 1)
    :setZIndex(5)
    :setBackground(colors.lightBlue) -- fallback color in case of any single-frame gaps

  -- Buttons live on main (above bgFrame)
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
    local slot = "profile1"
    _archiveProfileAndClearActive(slot)
    if saveAPI and saveAPI.setProfile then saveAPI.setProfile(slot) end
    saveAPI.newGame()
    saveAPI.commit(slot)
    if timeAPI and timeAPI.loadFromSave then timeAPI.loadFromSave() end
    bootGame()
end)

  addMenuButton("[ Continue ]", 12, colors.gray, colors.orange, function()
    saveAPI.setProfile("profile1")
    if saveAPI.hasSave() then
      saveAPI.load()
      if timeAPI.loadFromSave then timeAPI.loadFromSave() end
      bootGame()
    else
      print("No save file found!")
    end
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

  -- NEW: Pre-warm the background pool once using all cached images
  pcall(function() backgroundAPI.prewarm(bgFrame, BG_LIST) end)

  -- Scene state
  local BG_SECONDS = 10
  local bgIndex = 1
  local currentPath = BG_LIST[bgIndex]

  local customers = {} -- { pane, x, y, vx, targetX, path }
  local function cfgFor(path) return BG_CFG[path] or { spawn = "none" } end

  local function setBG(path)
    -- IMPORTANT: do NOT clear bgFrame here—avoids gray flash
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

  -- RNG
  local ok, now = pcall(os.epoch, "utc")
  math.randomseed(ok and now or math.floor(os.clock()*1e6))

  -- Initial paint
  setBG(currentPath)
  drawTitle()
  if cfgFor(currentPath).spawn ~= "none" then for _=1,3 do spawnCustomerFor(currentPath) end end

  -- Threads on the frame
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

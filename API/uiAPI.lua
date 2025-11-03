-- uiAPI.lua
-- Centralized UI placement & helpers for PixelCorp (Basalt)
-- This API builds the root frames (mainFrame, topBar, sidebar, displayFrame, inventory overlay),
-- owns speed buttons & pause menu, and exposes convenience helpers (spawnToast, setHUD, etc.).

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

-- --- State container ---
M.refs = {
  mainFrame = nil,
  displayFrame = nil,
  topBar = nil,
  sidebar = nil,
  inventoryOverlay = nil,
  tabBar = nil,
  loading = nil,       -- {frame,label,progressLabel,bar}
  speedButtons = {},
  timeThread = nil,
}

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
      :setZIndex(200)

  table.insert(TextToasts.items, { lbl = lbl, t1 = os.clock() + (tonumber(duration) or 2.0) })
  return lbl
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
      :setPosition(math.floor(W/2)-20, math.floor(H/2)-1)
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
      :setSize(W, H - 2)
      :setPosition(0, 3)
      :setZIndex(0)
      :hide()

  local SIDEBAR_W = 15
  local sidebar = mainFrame:addScrollableFrame()
      :setBackground(colors.lightGray)
      :setPosition(W, 4)
      :setSize(SIDEBAR_W, H - 3)
      :setZIndex(25)
      :setDirection("vertical")
      :hide()

  local arrowTop    = sidebar:addLabel():setText("<"):setPosition(1, 5):setForeground(colors.black)
  local arrowBottom = sidebar:addLabel():setText("<"):setPosition(1,15):setForeground(colors.black)

  sidebar:onGetFocus(function(self)
    self:setPosition(W - (SIDEBAR_W - 1))
    arrowTop:setText(">")
    arrowBottom:setText(">")
  end)
  sidebar:onLoseFocus(function(self)
    self:setPosition(W)
    arrowTop:setText("<")
    arrowBottom:setText("<")
  end)

  -- Inventory overlay shell (tabs created by caller)
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

  -- HUD labels (user can fill/update later)
  local timeLabel  = topBar:addLabel():setText("Time: --"):setPosition(2, 1)
  local moneyLabel = topBar:addLabel():setText("Money: $0"):setPosition(25, 2)
  local stageLabel = topBar:addLabel():setText("Stage: --"):setPosition(25, 1)
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
  speedButtons["4x"] = topBar:addButton():setText(">>>"):setPosition(W - 32, 2):setSize(4,1)
      :onClick(function() timeAPI.setSpeed("4x"); updateSpeedButtonColors(speedButtons) end)

  updateSpeedButtonColors(speedButtons)
  M.updateSpeedButtons()

  -- Pause button + menu shell (caller wires callbacks)
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
  -- Top bar quick access buttons
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

-- Convenience HUD updaters (caller may call these each tick)
function M.setHUDTime(text)      if M.refs.labels and M.refs.labels.timeLabel then M.refs.labels.timeLabel:setText(text) end end
function M.setHUDMoney(text)     if M.refs.labels and M.refs.labels.moneyLabel then M.refs.labels.moneyLabel:setText(text) end end
function M.setHUDStage(text)     if M.refs.labels and M.refs.labels.stageLabel then M.refs.labels.stageLabel:setText(text) end end
function M.setHUDLevel(text)     if M.refs.labels and M.refs.labels.levelLabel then M.refs.labels.levelLabel:setText(text) end end
function M.setHUDLevelBar(text)  if M.refs.labels and M.refs.labels.levelBarLabel then M.refs.labels.levelBarLabel:setText(text) end end

-- Background helper

-- Frame accessors / toast routing
function M.getFrame(name)
  if not name then return M.refs.mainFrame end
  if M.refs.frames and M.refs.frames[name] then return M.refs.frames[name] end
  return M.refs.mainFrame
end

-- route to topbar by default when target is pause to avoid covering menu content
function M.toast(where, text, x, y, color, duration)
  local target = M.getFrame(where)
  if where == "pause" then target = M.refs.topBar or target end
  return M.spawnToast(target, text, x, y, color, duration)
end
function M.refreshStageBackground()
  if stageAPI and stageAPI.refreshBackground and M.refs.displayFrame then
    stageAPI.refreshBackground(M.refs.displayFrame)
  end
end



function M.onPauseResume(fn) M._onPauseResume = fn end
function M.onPauseOpen(fn) M._onPauseOpen = fn end
function M.onPauseSave(fn) M._onPauseSave = fn end
function M.onPauseLoad(fn) M._onPauseLoad = fn end
function M.onPauseSettings(fn) M._onPauseSettings = fn end
function M.onPauseQuitToMenu(fn) M._onPauseQuitToMenu = fn end

function M.onTopInv(fn) M._onTopInv = fn end
function M.onTopCraft(fn) M._onTopCraft = fn end

-- Lightweight page manager (groups children into named frames)
local _pages = _pages or {}

-- Pages that should NOT create a container (paint directly on displayFrame)
local NO_CONTAINER = { stock = true }  -- add more names here if needed

function M.ensurePage(name)
  if not name or name == "" then return M.refs.displayFrame end
  if NO_CONTAINER[name] then
    -- Draw directly on the stage-backed displayFrame
    return M.refs.displayFrame
  end

  -- For normal pages, create (or reuse) an isolated container
  if _pages[name] and _pages[name].frame then return _pages[name].frame end

  local W, H = term.getSize()
  local f = M.refs.displayFrame:addFrame()
      :setSize(W, H - 2)
      :setPosition(1, 1)    -- matches your content coordinates
      :setZIndex(10)        -- above stage bg, below overlays
      :hide()

  _pages[name] = { frame = f, built = false }
  return f
end

function M.showPage(name)
  if NO_CONTAINER[name] then return end      -- never show/hide displayFrame
  local p = _pages[name]; if p and p.frame then p.frame:show() end
end

function M.hidePage(name)
  if NO_CONTAINER[name] then return end      -- never show/hide displayFrame
  local p = _pages[name]; if p and p.frame then p.frame:hide() end
end

function M.teardownPage(name)
  -- For isolated pages, clear their container; for background pages,
  -- caller should remove its own widgets as usual.
  local p = _pages[name]
  if p and p.frame then pcall(function() p.frame:removeChildren() end); p.built = false end
end

function M.pageBuilt(name)        return _pages[name] and _pages[name].built end
function M.setPageBuilt(name, v)  if _pages[name] then _pages[name].built = not not v end end
function M.getPageFrame(name)     return (NO_CONTAINER[name] and M.refs.displayFrame) or (_pages[name] and _pages[name].frame) end
return M
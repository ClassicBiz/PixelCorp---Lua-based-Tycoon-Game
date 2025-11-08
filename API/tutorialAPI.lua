local tutorialAPI = {}


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
local economyAPI = require(root.."/API/economyAPI")

-- Internal state
tutorialAPI._state   = { ran = false, step = 1 }
tutorialAPI._waiting = nil
tutorialAPI._root    = nil        -- Basalt parent frame for UI
tutorialAPI._ui      = nil        -- { gate, panel, title, body, next }

-- ----- Save helpers -----
local function _load()
  local s = saveAPI.get()
  s.tutorial = s.tutorial or { ran = false, step = 1 }
  tutorialAPI._state = s.tutorial
end

local function _save()
  local s = saveAPI.get()
  s.tutorial = s.tutorial or {}
  s.tutorial.ran  = tutorialAPI._state.ran
  s.tutorial.step = tutorialAPI._state.step
  if saveAPI.save   then saveAPI.save()   end
  if saveAPI.commit then saveAPI.commit() end
end

-- ----- UI helpers -----
local function _mkGate()
  local g = tutorialAPI._root:addFrame()
    :setPosition(1,1)
    :setSize(tutorialAPI._root:getSize())
    :setBackground(colors.black)
    :setZIndex(240)
  if g.setOpacity then pcall(function() g:setOpacity(0.35) end) end
  g:onClick(function() end); g:onKey(function() end)
  return g
end

local function _mkPanel()
  local W,H = tutorialAPI._root:getSize()
  local PW  = math.min(38, W-4)
  local wrap = tutorialAPI._root:addFrame()
      :setSize(PW, 10)
      :setPosition(math.floor((W-PW)/2), math.max(2, math.floor(H/2)-4))
      :setBackground(colors.lightGray)
      :setZIndex(241)

  local box = wrap:addFrame()
      :setSize(PW-2, 8)
      :setPosition(1, 1)
      :setBackground(colors.white)

  local title = box:addLabel()
      :setPosition(2,1)
      :setForeground(colors.black)
      :setText("Tutorial")

  local body  = box:addScrollableFrame()
      :setPosition(2,2)
      :setSize(PW-6, 5)
      :setBackground(colors.white)

  local nextX = math.max(1, math.floor((PW-2-14)/2))
  local next  = box:addButton()
      :setText("Continue")
      :setPosition(nextX,7)
      :setSize(14,1)
      :setBackground(colors.green)
      :setForeground(colors.black)

  return wrap, title, body, next
end

function tutorialAPI.show(title, lines, onNext)
  tutorialAPI.hide()
  tutorialAPI._ui = {}
  tutorialAPI._ui.gate = _mkGate()

  local p, t, b, n = _mkPanel()
  tutorialAPI._ui.panel, tutorialAPI._ui.title, tutorialAPI._ui.body, tutorialAPI._ui.next = p,t,b,n
  t:setText(title or "Tutorial")
  b:removeChildren()
  local y=1
  for _,ln in ipairs(lines or {}) do
    b:addLabel():setText(ln):setPosition(1,y); y=y+1
  end
  n:onClick(function()
    if onNext then onNext() end
    tutorialAPI.hide()
  end)
end

function tutorialAPI.hide()
  local ui = tutorialAPI._ui
  if not ui then return end
  if ui.panel then pcall(function() ui.panel:remove() end) end
  if ui.gate  then pcall(function() ui.gate:remove()  end) end
  tutorialAPI._ui = nil
end

function tutorialAPI.waitFor(checkpoint, title, lines, nextStep)
  tutorialAPI._state.step = nextStep or (tutorialAPI._state.step + 1)
  tutorialAPI._waiting    = checkpoint
  _save()
  tutorialAPI.show(title, lines, function() end)
end

function tutorialAPI.hit(checkpoint)
  if tutorialAPI._waiting == checkpoint then
    tutorialAPI._waiting = nil
    tutorialAPI.startIfNeeded(tutorialAPI._root)
  end
end

function tutorialAPI.startIfNeeded(rootFrame)
  tutorialAPI._root = rootFrame or tutorialAPI._root
  if not tutorialAPI._root then return end
  _load()
  if tutorialAPI._state.ran then return end

  local step = tutorialAPI._state.step or 1

  if step == 1 then
    if economyAPI and economyAPI.addMoney then economyAPI.addMoney(350, "Tutorial seed") end
    tutorialAPI.waitFor("nav:licenses", "Welcome!", {
      "Here's $350 to kickstart your company.",
      "Head to the Licenses page to begin."
    }, 2)

  elseif step == 2 then
    tutorialAPI.waitFor("buy:first_license", "Licenses", {
      "Buy permits for bigger builds & processes here.",
      "Purchase your first license."
    }, 3)

  elseif step == 3 then
    tutorialAPI.waitFor("nav:stages", "Great!", {
      "Now let’s set up your first stand.",
      "Go to the Stages page."
    }, 4)

  elseif step == 4 then
    tutorialAPI.waitFor("buy:first_stage", "Your First Building", {
      "It’s humble, but it’ll work.",
      "Buy your first building."
    }, 5)

  elseif step == 5 then
    tutorialAPI.waitFor("nav:stock", "Time to Stock Up", {
      "Grab materials from each aisle.",
      "Tip: you’ll use up to x4 fruit per craft.",
      "Buy 1 cup, 1 sugar, 3 lemons, 1 ice cube."
    }, 6)

  elseif step == 6 then
    tutorialAPI.waitFor("stock:starter_kit_bought", "Nice haul!", {
      "You’ve got enough for your first batch.",
      "Open inventory and click the CRAFT tab."
    }, 7)

  elseif step == 7 then
    tutorialAPI.waitFor("nav:craft", "Crafting", {
      "Use << and >> to pick items you own.",
      "Select Cups, Lemons, Sugar, Ice Cubes then press Craft."
    }, 8)

  elseif step == 8 then
    tutorialAPI.waitFor("craft:first_batch", "You did it!", {
      "Explore upgrades, better ingredients, and marketing.",
      "Tutorial complete — don’t go broke ;)"
    }, 9)

  else
    tutorialAPI._state.ran = true
    _save()
    tutorialAPI.hide()
  end
end

return tutorialAPI

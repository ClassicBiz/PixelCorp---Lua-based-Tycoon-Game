-- API/stageAPI.lua
-- Manages stage unlocks and background switching (works with your backgroundAPI).
-- Stages: "base","lemonade","office","factory","tower" (rename as needed).

local saveAPI = require("/API/saveAPI")
local backgroundAPI = require("/API/backgroundAPI")

local stageAPI = {}

-- Map stages to NFP assets
local STAGE_BG = {
  base     = "assets/screen.nfp",
  lemonade = "assets/lemon.nfp",
  office   = "assets/office.nfp",
  factory  = "assets/factory.nfp",
  tower    = "assets/tower.nfp",
}

-- Ensure unlocks table
local function _ensure()
  local s = saveAPI.get()
  s.unlocks = s.unlocks or { base = true }
  s.stage = s.stage or "base"
  return s
end

function stageAPI.getStage()
  return (_ensure()).stage
end

function stageAPI.isUnlocked(name)
  local s = _ensure()
  return s.unlocks[name] == true
end

function stageAPI.unlock(name)
  local s = _ensure()
  s.unlocks[name] = true
  -- Promote current stage only if this is "higher" than current
  s.stage = name
  saveAPI.save()
end

-- Explicitly set current stage (assumes it's unlocked)
function stageAPI.setStage(name)
  local s = _ensure()
  if s.unlocks[name] then
    s.stage = name
    saveAPI.save()
  end
end

-- Call this whenever stage changes or on page load
-- frame: the Basalt frame to draw background into
function stageAPI.refreshBackground(frame)
  local s = _ensure()
  local path = STAGE_BG[s.stage] or STAGE_BG.base
  local ok, err = pcall(function()
    -- ensure cached
    backgroundAPI.preload(path)
    backgroundAPI.setCachedBackground(frame, path, 1, 1)
  end)
  if not ok then
    print("stageAPI: failed to set background: "..tostring(err))
  end
end
-- Return a shallow copy of stage->path map
function stageAPI.getAllStagePaths()
  local out = {}
  for k,v in pairs(STAGE_BG) do out[k] = v end
  return out
end

-- Preload all stage backgrounds once at load
local ok_pre, err_pre = pcall(function()
  for _, p in pairs(STAGE_BG) do
    backgroundAPI.preload(p)
  end
end)
if not ok_pre then print("stageAPI: preload error: "..tostring(err_pre)) end

return stageAPI

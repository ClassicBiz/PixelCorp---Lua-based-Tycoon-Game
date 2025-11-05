
local stageAPI = {}

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
local backgroundAPI = require(root.."/API/backgroundAPI")



-- Map stages to NFP assets
local STAGE_BG = {
  base     = root.."/assets/screen.nfp",
  lemonade_stand = root.."/assets/lemon.nfp",
  lemonade = root.."/assets/lemon.nfp",  -- alias for art key
  office   = root.."/assets/office.nfp",
  factory  = root.."/assets/factory.nfp",
  tower    = root.."/assets/tower.nfp",
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
  -- Accept either "progress keys" or "art keys" that exist in STAGE_BG
  if not STAGE_BG[name] then
    -- map common progress key -> art key where needed
    if name == "lemonade_stand" and STAGE_BG["lemonade"] then name = "lemonade" end
  end
  -- auto-unlock if needed
  s.unlocks[name] = true
  s.stage = name
  saveAPI.save()
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
    os.sleep(5)
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




-- Set stage from a progress key (e.g., "warehouse") by mapping to an art key if needed
function stageAPI.setStageFromProgress(progressKey)
  local map = {
    odd_jobs = "base",
    lemonade_stand = STAGE_BG["lemonade"] and "lemonade" or "lemonade_stand",
    warehouse = "office",
    factory = "factory",
    highrise = "tower",
  }
  local key = map[progressKey] or progressKey
  stageAPI.setStage(key)
end
return stageAPI

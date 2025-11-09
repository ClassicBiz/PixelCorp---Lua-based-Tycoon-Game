
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
  lemonade = root.."/assets/lemon.nfp",
  office   = root.."/assets/office.nfp",
  factory  = root.."/assets/factory.nfp",
  tower    = root.."/assets/tower.nfp",
}


 stageAPI.STAGES = {
  lemonade = {
    key="lemonade",
    stock_order = {"base","fruit","sweet","topping"},
    stock_labels = { base="Cups", fruit="Fruit", sweet="Sweetener", topping="Toppings" },
    crafting = { productType="drink", slots={"base","fruit","sweet","topping"} },
    interact = { pickups = {"bush","tree","ground"} }
  },
  warehouse = {
    key="warehouse",
    stock_order = {"container","cushion","accessory","product"},
    stock_labels = { container="Container", cushion="Cushion", accessory="Accessory", product = "product" },
    crafting = { productType="pack", slots={"container","cushion","accessory","product"} },
    interact = { pickups = {"crate","pallet"} }
  }
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
  s.stage = name
  saveAPI.save()
end

function stageAPI.setStage(name)
  local s = _ensure()
  if not STAGE_BG[name] then
    if name == "lemonade_stand" and STAGE_BG["lemonade"] then name = "lemonade" end
  end
  s.unlocks[name] = true
  s.stage = name
  saveAPI.save()
end

function stageAPI.refreshBackground(frame)
  local s = _ensure()
  local path = STAGE_BG[s.stage] or STAGE_BG.base
  local ok, err = pcall(function()
    backgroundAPI.preload(path)

    local fw, fh = 1, 1
    if frame and frame.getSize then fw, fh = frame:getSize() end
    local iw, ih = backgroundAPI.measure(path)
    iw, ih = iw or 0, ih or 0

    -- center the image inside the frame (fall back to 1,1)
    local ox = math.max(1, math.floor((fw - iw) / 2) + 1)
    local oy = math.max(1, math.floor((fh - ih) / 2) + 1)

    backgroundAPI.setCachedBackground(frame, path, ox, oy)
  end)
  if not ok then
    print("stageAPI: failed to set background: "..tostring(err))
  end
end

function stageAPI.getAllStagePaths()
  local out = {}
  for k,v in pairs(STAGE_BG) do out[k] = v end
  return out
end

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

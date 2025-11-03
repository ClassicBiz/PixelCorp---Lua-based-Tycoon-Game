-- backgroundAPI.lua (RLE renderer)
-- Efficient background drawing using run-length encoding (RLE) segments per row.
-- This avoids creating a pane for every pixel and prevents "too long without yielding".
-- Drop-in replacement for previous backgroundAPI.* calls used in your project.

local backgroundAPI = {}

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

-- CC color map for NFP chars
local colorMap = {
    ["f"] = colors.black,   ["0"] = colors.white,   ["e"] = colors.red,
    ["d"] = colors.green,   ["b"] = colors.blue,    ["7"] = colors.gray,
    ["8"] = colors.lightGray, ["9"] = colors.cyan,  ["2"] = colors.purple,
    ["c"] = colors.brown,   ["1"] = colors.orange,  ["3"] = colors.lightBlue,
    ["4"] = colors.yellow,  ["5"] = colors.lime,    ["6"] = colors.pink,
    ["a"] = colors.magenta
}

-- Cooperative yield helper (tunable)
local function cyield()
    os.sleep(0.01)
end

-- Cache format:
-- cache_by_path[path] = {
--    w=width, h=height,
--    segments = { {x,y,w,color}, ... }  -- run-length segments
-- }
local cache_by_path = {}
local frameSegments = {} -- [frame] = { panes = {pane1,...}, count = N }

-- Read NFP file (array of strings)
local function readRows(path)
    local fh = fs.open(path, "r")
    if not fh then error("Failed to open NFP: " .. tostring(path)) end
    local rows, w = {}, 0
    local n = 0
    while true do
        local line = fh.readLine()
        if not line then break end
        rows[#rows+1] = line
        if #line > w then w = #line end
        n = n + 1
        if n % 32 == 0 then cyield() end
    end
    fh.close()
    return rows, w, #rows
end

-- Convert rows to run-length segments (hugely fewer items than per-pixel)
local function rowsToSegments(rows, startX, startY)
    startX, startY = startX or 1, startY or 1
    local segments = {}
    for y, row in ipairs(rows) do
        local i = 1
        while i <= #row do
            local ch = row:sub(i,i)
            local col = colorMap[ch] or colors.black
            local j = i + 1
            while j <= #row and (colorMap[row:sub(j,j)] or colors.black) == col do
                j = j + 1
            end
            -- segment from i..(j-1)
            local seg = { x = startX + i - 1, y = startY + y - 1, w = (j - i), color = col }
            segments[#segments+1] = seg
            i = j
        end
        if y % 6 == 0 then cyield() end
    end
    return segments
end

-- Preload: compute RLE and cache
function backgroundAPI.preload(path, startX, startY)
    if cache_by_path[path] then return end
    local rows, w, h = readRows(path)
    local segs = rowsToSegments(rows, startX, startY)
    cache_by_path[path] = { w = w, h = h, segments = segs }
end

local function fastYield()
  os.queueEvent("__bg_y"); os.pullEvent("__bg_y")
end

-- keep your colorMap / cache tables...

-- expose a helper so we can inspect cache
function backgroundAPI.getCachedInfo(path)
  return cache_by_path[path]  -- { w, h, segments = {...} } or nil
end

local framePools = {}  -- keeps pools keyed by frame
local function getOrCreatePool(frame)
  if not framePools[frame] then
    framePools[frame] = { panes = {} }
  end
  return framePools[frame]
end

-- Ensure the pool on a frame is at least 'needed' panes (off-screen by default)
local function ensurePool(frame, needed)
  local pool = getOrCreatePool(frame)   -- your existing pool getter
  while #pool.panes < needed do
    local p = frame:addPane()
      :setSize(1, 1)
      :setPosition(9999, 9999)          -- park off-screen to prevent (1,1) flash
      :setBackground(colors.lightBlue)   -- or any neutral fallback
    table.insert(pool.panes, p)
    if (#pool.panes % 200) == 0 then fastYield() end
  end
  return pool
end

function backgroundAPI.prewarm(frame, paths)
  local maxSegs = 0
  for _, path in ipairs(paths) do
    local info = backgroundAPI.getCachedInfo(path)
    if info and info.segments and #info.segments > maxSegs then
      maxSegs = #info.segments
    end
  end
  if maxSegs > 0 then ensurePool(frame, maxSegs) end
end

-- In your painter, keep tiny yields during the heavy loops:
function backgroundAPI.setCachedBackground(frame, path, ox, oy)
  local info = cache_by_path[path]
  if not info then return false, "not preloaded: "..tostring(path) end
  local segs = info.segments
  local pool = ensurePool(frame, #segs)
  local panes = pool.panes

  for i = 1, #segs do
    local s = segs[i]
    local p = panes[i]
    p:setPosition((ox or 0) + s.x, (oy or 0) + s.y)
     :setSize(s.w, 1)
     :setBackground(s.color)
    if (i % 250) == 0 then fastYield() end
  end

  -- hide extras if pool is larger
  for j = #segs + 1, #panes do
    panes[j]:setPosition(9999, 9999)
    if (j % 500) == 0 then fastYield() end
  end
  return true
end

-- Compatibility path: draw non-cached NFP immediately
function backgroundAPI.setBackground(frame, filePath, startX, startY)
    local rows = select(1, readRows(filePath))
    local segs = rowsToSegments(rows, startX, startY)
    local tmp = { w = 0, h = 0, segments = segs }
    cache_by_path["__tmp__"] = tmp
    local ok = backgroundAPI.setCachedBackground(frame, "__tmp__", startX, startY)
    cache_by_path["__tmp__"] = nil
    return ok
end

-- List images
function backgroundAPI.listImages(folder)
    local out = {}
    for _, file in ipairs(fs.list(folder)) do
        if file:match("%.nfp$") then
            table.insert(out, fs.combine(folder, file))
        end
    end
    table.sort(out)
    return out
end

return backgroundAPI

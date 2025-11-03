local timeAPI = {}

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

-- =========================
-- Defaults / internal state
-- =========================
timeAPI.time = {
    year   = 2005,
    month  = 1,
    week   = 1,
    day    = 1,
    hour   = 6,
    minute = 0,
}

-- Speed settings (how many in‑game minutes per main-loop tick)
local speedModes = {
    pause  = 0,
    normal = 1,
    ["2x"] = 2,
    ["4x"] = 4,
}
local currentSpeed = "normal"

-- Subscribers called after each minute advance
timeAPI.listeners = {}

-- ==================
-- Public API: Speed
-- ==================
function timeAPI.setSpeed(mode)
    if speedModes[mode] ~= nil then
        currentSpeed = mode
    end
end

function timeAPI.getSpeed()
    return currentSpeed
end

-- ===================
-- Public API: Time IO
-- ===================
function timeAPI.getTime()
    -- return a shallow copy (avoid outside mutation)
    local t = timeAPI.time
    return { year=t.year, month=t.month, week=t.week, day=t.day, hour=t.hour, minute=t.minute }
end

-- Rehydrate from save (call on boot; also auto-wired via onLoad below)
function timeAPI.loadFromSave()
    local s = saveAPI.get()
    if s and s.time then
        timeAPI.time = {
            year   = s.time.year   or 2005,
            month  = s.time.month  or 1,
            week   = s.time.week   or 1,
            day    = s.time.day    or 1,
            hour   = s.time.hour   or 6,
            minute = s.time.minute or 0,
        }
    end
end

-- Persist into save (used once per tick)
function timeAPI.bindToSave()
    local s = saveAPI.get()
    s.time.year   = timeAPI.time.year
    s.time.month  = timeAPI.time.month
    s.time.week   = timeAPI.time.week
    s.time.day    = timeAPI.time.day
    s.time.hour   = timeAPI.time.hour
    s.time.minute = timeAPI.time.minute
    saveAPI.setState(s)
end

-- ====================
-- Public API: Ticking
-- ====================
function timeAPI.onTick(callback)
    table.insert(timeAPI.listeners, callback)
end

local function notifyListeners()
    for _, fn in ipairs(timeAPI.listeners) do
        pcall(fn, timeAPI.time)
    end
end

local function advanceMinute()
    local t = timeAPI.time
    t.minute = t.minute + 1
    if t.minute >= 60 then
        t.minute = 0
        t.hour = t.hour + 1
        if t.hour >= 24 then
            t.hour = 0
            t.day = t.day + 1
            -- 7-day weeks based on day-of-month
            t.week = math.floor((t.day - 1) / 7) + 1
            if t.day > 30 then
                t.day = 1
                t.month = t.month + 1
                t.week = 1
                if t.month > 12 then
                    t.month = 1
                    t.year = t.year + 1
                end
            end
        end
    end
    notifyListeners()
end

-- Advance time by the number of minutes for the currentSpeed.
-- Your main loop should call timeAPI.tick() once per UI frame;
-- real-time delay is controlled outside (sleep per speed).
function timeAPI.tick()
    local mult = speedModes[currentSpeed] or 1
    if mult <= 0 then return end
    for _ = 1, mult do
        advanceMinute()
    end
    -- persist once per frame after all minute advances
    if timeAPI.bindToSave then timeAPI.bindToSave() end
end

-- =======================
-- Auto-wire save hydration
-- =======================
if saveAPI and saveAPI.onLoad then
    saveAPI.onLoad(function(_)
        timeAPI.loadFromSave()
    end)
end

return timeAPI

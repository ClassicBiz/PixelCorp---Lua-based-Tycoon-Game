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
local eventAPI = require(root.."/API/eventAPI")

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
    ["2x"] = 5,
    ["4x"] = 10,
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
    local t = timeAPI.time
    return { year=t.year, month=t.month, week=t.week, day=t.day, hour=t.hour, minute=t.minute }
end

-- Rehydrate from save
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

function timeAPI.tick()
    local mult = speedModes[currentSpeed] or 1
    if mult <= 0 then return end
    for _ = 1, mult do
        advanceMinute()
    end

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

-- ====================
-- Public API: Fast-forward / Skip
-- ====================
function timeAPI.fastForwardMinutes(n)
    n = tonumber(n) or 0
    if n <= 0 then return end
    for _ = 1, n do
        local ok, err = pcall(function() advanceMinute() end)
        if not ok then break end
    end
    if timeAPI.bindToSave then timeAPI.bindToSave() end
end

function timeAPI.fastForwardTo(hh, mm, nextDay)
    hh = tonumber(hh) or 0
    mm = tonumber(mm) or 0
    if hh < 0 then hh = 0 end
    if hh > 23 then hh = 23 end
    if mm < 0 then mm = 0 end
    if mm > 59 then mm = 59 end

    local t = timeAPI.time
    if nextDay and (t.hour > hh or (t.hour == hh and t.minute >= mm)) then
        local minsToMid = (60 - t.minute) + (23 - t.hour) * 60
        if minsToMid > 0 then timeAPI.fastForwardMinutes(minsToMid) end
    end

    local cur = timeAPI.time
    local delta = (hh - cur.hour) * 60 + (mm - cur.minute)
    if delta < 0 then delta = 0 end
    if delta > 0 then timeAPI.fastForwardMinutes(delta) end
end

function timeAPI.skipNight()
    local t = timeAPI.time or {hour=0, minute=0}
    local h = tonumber(t.hour or 0) or 0
    local m = tonumber(t.minute or 0) or 0
    if h >= 20 then
        timeAPI.fastForwardTo(5, 30, true)
        return true
    elseif (h < 5) or (h == 5 and m < 30) then
        timeAPI.fastForwardTo(5, 30, false)
        return true
    end
    return false
end

return timeAPI

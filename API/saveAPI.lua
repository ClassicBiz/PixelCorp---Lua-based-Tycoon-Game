-- saveAPI.lua - Robust saving with active runtime file + committed profiles (multi-slot)
-- Backward-compatible: keeps your existing functions and adds slots.
-- Uses ComputerCraft's textutils.serialize/unserialize for JSON-ish persistence.

local saveAPI = {}
saveAPI._listeners = {}  -- onLoad/onSet listeners

local json = textutils

-- Paths
local ACTIVE_PATH   = "/saves/active.json"         -- runtime, autosave scratch
local PROFILE_DIR   = "/saves/profiles"            -- committed saves live here
local DEFAULT_SLOT  = "profile1"                   -- default profile name
local currentProfile = DEFAULT_SLOT

-- Default state template
local defaultState = {
    time = { year = 1, month = 1, week = 1, day = 1, hour = 6, minute = 0 },
    player = { money = 0, licenses = {}, inventory = {}, progress = "odd_jobs" },
    jobState = { inProgress = false, currentJob = nil, ticksRemaining = 0, earnings = 0 },
    meta = {}
}

-- Runtime in-memory state
local currentState = nil

-- ---------- Utilities ----------
local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k,v in pairs(t) do r[k] = deepcopy(v) end
    return r
end

local function ensureDirs()
    if not fs.exists("/saves") then fs.makeDir("/saves") end
    if not fs.exists(PROFILE_DIR) then fs.makeDir(PROFILE_DIR) end
end

local function profilePath(slot)
    slot = slot or currentProfile or DEFAULT_SLOT
    return fs.combine(PROFILE_DIR, slot .. ".json")
end

local function notify()
    for _, fn in ipairs(saveAPI._listeners) do
        pcall(fn, saveAPI.get())
    end
end

-- ---------- Core getters/setters ----------
function saveAPI.get()
    if not currentState then
        currentState = deepcopy(defaultState)
    end
    return currentState
end

function saveAPI.setState(s)
    currentState = s
    saveAPI.save()
    notify()
end

-- Convenience for modules that only update time
function saveAPI.updateTime(t)
    local s = saveAPI.get()
    s.time.year   = t.year
    s.time.month  = t.month
    s.time.week   = t.week
    s.time.day    = t.day
    s.time.hour   = t.hour
    s.time.minute = t.minute
    saveAPI.setState(s)
end

-- Legacy job state accessors kept for compatibility
function saveAPI.getJobState()
    local s = saveAPI.get()
    s.jobState = s.jobState or deepcopy(defaultState.jobState)
    return s.jobState
end

function saveAPI.setJobState(js)
    local s = saveAPI.get()
    s.jobState = js or deepcopy(defaultState.jobState)
    saveAPI.setState(s)
end

-- ---------- Slot control ----------
function saveAPI.setProfile(slotName)
    if slotName and slotName ~= "" then
        currentProfile = slotName
    else
        currentProfile = DEFAULT_SLOT
    end
end

function saveAPI.getActiveProfile()
    return currentProfile or DEFAULT_SLOT
end

function saveAPI.listProfiles()
    ensureDirs()
    local out = {}
    for _, f in ipairs(fs.list(PROFILE_DIR)) do
        if f:match("%.json$") then
            table.insert(out, (f:gsub("%.json$", "")))
        end
    end
    table.sort(out)
    return out
end

function saveAPI.deleteProfile(slotName)
    ensureDirs()
    local p = profilePath(slotName)
    if fs.exists(p) then fs.delete(p) end
end

-- ---------- Save/Load (Active & Committed) ----------
function saveAPI.save()
    ensureDirs()
    if not currentState then currentState = deepcopy(defaultState) end
    currentState.meta = currentState.meta or {}
    currentState.meta.last_saved = os.epoch("utc")
    local fh = fs.open(ACTIVE_PATH, "w")
    fh.write(json.serialize(currentState))
    fh.close()
    return true
end

function saveAPI.loadActive()
    if not fs.exists(ACTIVE_PATH) then return false end
    local fh = fs.open(ACTIVE_PATH, "r")
    local data = fh.readAll()
    fh.close()
    local parsed = json.unserialize(data)
    if not parsed then return false end
    currentState = parsed
    notify()
    return true
end

-- Create/overwrite the committed profile file with current active state
function saveAPI.commit(slotName)
    ensureDirs()
    local p = profilePath(slotName)
    local fh = fs.open(p, "w")
    fh.write(json.serialize(saveAPI.get()))
    fh.close()
    return true
end

-- Load a committed profile INTO current active state (and also write active)
function saveAPI.loadCommitted(slotName)
    ensureDirs()
    local p = profilePath(slotName)
    if not fs.exists(p) then return false end
    local fh = fs.open(p, "r")
    local data = fh.readAll()
    fh.close()
    local parsed = json.unserialize(data)
    if not parsed then return false end
    currentState = parsed
    saveAPI.save()   -- reflect into ACTIVE_PATH so autosaves keep working
    notify()
    return true
end

-- Preferred load sequence:
-- 1) If a committed profile for currentProfile exists, load it.
-- 2) Else, try the active file.
-- 3) Else, start a new game.
function saveAPI.load()
    if saveAPI.loadCommitted(currentProfile) then return true end
    if saveAPI.loadActive() then return true end
    saveAPI.newGame()
    return true
end

function saveAPI.hasSave(slotName)
    ensureDirs()
    local p = profilePath(slotName or currentProfile)
    return fs.exists(p) or fs.exists(ACTIVE_PATH)
end

-- ---------- New Game ----------
function saveAPI.newGame()
    currentState = deepcopy(defaultState)
    saveAPI.save()
    notify()
end

-- ---------- Observers ----------
function saveAPI.onLoad(fn)
    table.insert(saveAPI._listeners, fn)
end


-- ---------- Money Getters/Setters ----------
function saveAPI.getPlayerMoney()
    local s = saveAPI.get()
    s.player = s.player or {}
    return s.player.money or 0
end

function saveAPI.setPlayerMoney(amount)
    local s = saveAPI.get()
    s.player = s.player or {}
    s.player.money = tonumber(amount) or 0
    saveAPI.setState(s)
end


return saveAPI

-- saveAPI.lua - robust saving + slots

local saveAPI = {}

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

local settingsOK, settingsAPI = pcall(require, root.."/API/settingsAPI")  -- optional

saveAPI._listeners = {}
local json = textutils

local ACTIVE_PATH   = root.."/saves/active.json"
local PROFILE_DIR   = root.."/saves/profiles"
local DEFAULT_SLOT  = "profile1"
local currentProfile = DEFAULT_SLOT

local defaultState = {
    time = { year = 1, month = 1, week = 1, day = 1, hour = 6, minute = 0 },
    player = { money = 0, licenses = {}, inventory = {}, progress = "odd_jobs" },
    jobState = { inProgress = false, currentJob = nil, ticksRemaining = 0, earnings = 0 },
    meta = {}
}

local currentState = nil

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k,v in pairs(t) do r[k] = deepcopy(v) end
    return r
end

local function ensureDirs()
    if not fs.exists(root.."/saves") then fs.makeDir(root.."/saves") end
    if not fs.exists(PROFILE_DIR) then fs.makeDir(PROFILE_DIR) end
end

local function profilePath(slot)
    slot = slot or currentProfile or DEFAULT_SLOT
    return fs.combine(PROFILE_DIR, slot .. ".json")
end
local function archivedPath(slot)
    slot = slot or currentProfile or DEFAULT_SLOT
    return fs.combine(PROFILE_DIR, slot .. "_old.json")
end

local function notify()
    for _, fn in ipairs(saveAPI._listeners) do pcall(fn, saveAPI.get()) end
end

function saveAPI.get()
    if not currentState then currentState = deepcopy(defaultState) end
    return currentState
end

function saveAPI.setState(s)
    currentState = s
    saveAPI.save()
    notify()
end

function saveAPI.updateTime(t)
    local s = saveAPI.get()
    s.time.year, s.time.month, s.time.week, s.time.day, s.time.hour, s.time.minute =
      t.year, t.month, t.week, t.day, t.hour, t.minute
    saveAPI.setState(s)
end

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

function saveAPI.setProfile(slotName)
    currentProfile = (slotName and slotName ~= "") and slotName or DEFAULT_SLOT
end
function saveAPI.getActiveProfile() return currentProfile or DEFAULT_SLOT end

function saveAPI.listProfiles()
    ensureDirs()
    local out = {}
    for _, f in ipairs(fs.list(PROFILE_DIR)) do
        if f:match("%.json$") then table.insert(out, (f:gsub("%.json$", ""))) end
    end
    table.sort(out); return out
end

function saveAPI.deleteProfile(slotName)
    ensureDirs()
    local p = profilePath(slotName)
    if fs.exists(p) then fs.delete(p) end
end

function saveAPI.save()
    ensureDirs()
    currentState = currentState or deepcopy(defaultState)
    currentState.meta = currentState.meta or {}
    currentState.meta.last_saved = os.epoch("utc")
    local fh = fs.open(ACTIVE_PATH, "w")
    fh.write(json.serialize(currentState))
    fh.close()
    return true
end

function saveAPI.loadActive()
    if not fs.exists(ACTIVE_PATH) then return false end
    local fh = fs.open(ACTIVE_PATH, "r"); local data = fh.readAll(); fh.close()
    local parsed = textutils.unserialize(data); if not parsed then return false end
    currentState = parsed; notify(); return true
end

function saveAPI.commit(slotName)
    ensureDirs()
    local p = profilePath(slotName)
    local fh = fs.open(p, "w"); fh.write(json.serialize(saveAPI.get())); fh.close()
    return true
end

function saveAPI.loadCommitted(slotName)
    ensureDirs()
    local p = profilePath(slotName)
    if not fs.exists(p) then return false end
    local fh = fs.open(p, "r"); local data = fh.readAll(); fh.close()
    local parsed = textutils.unserialize(data); if not parsed then return false end
    currentState = parsed; saveAPI.save(); notify(); return true
end

function saveAPI.load()
    if saveAPI.loadCommitted(currentProfile) then return true end
    if saveAPI.loadActive() then return true end
    saveAPI.newGame(); return true
end

function saveAPI.hasSave(slotName)
    ensureDirs()
    local p = profilePath(slotName or currentProfile)
    return fs.exists(p) or fs.exists(ACTIVE_PATH)
end

-- NEW GAME respects difficulty starting cash
function saveAPI.newGame()
    currentState = deepcopy(defaultState)
    saveAPI.save()
    notify()
end

function saveAPI.onLoad(fn) table.insert(saveAPI._listeners, fn) end

function saveAPI.getPlayerMoney()
    local s = saveAPI.get(); s.player = s.player or {}; return s.player.money or 0
end
function saveAPI.setPlayerMoney(amount)
    local s = saveAPI.get(); s.player = s.player or {}; s.player.money = tonumber(amount) or 0; saveAPI.setState(s)
end

function saveAPI.renameProfile(oldName, newName)
    ensureDirs()
    if not oldName or oldName == "" then return false, "Old name missing" end
    if not newName or newName == "" then return false, "New name missing" end
    local src = profilePath(oldName); local dst = profilePath(newName)
    if not fs.exists(src) then return false, "Source profile not found" end
    if fs.exists(dst) then return false, "Target already exists" end
    fs.move(src, dst)
    local srcA, dstA = archivedPath(oldName), archivedPath(newName)
    if fs.exists(srcA) then if fs.exists(dstA) then fs.delete(dstA) end; fs.move(srcA, dstA) end
    if currentProfile == oldName then currentProfile = newName end
    return true, "Renamed"
end

function saveAPI.archiveCurrentCommitted(slotName)
    ensureDirs()
    local slot = slotName or currentProfile or DEFAULT_SLOT
    local committed = profilePath(slot); local archived  = archivedPath(slot)
    if fs.exists(archived) then fs.delete(archived) end
    if fs.exists(committed) then fs.move(committed, archived) end
    if fs.exists(ACTIVE_PATH) then fs.delete(ACTIVE_PATH) end
end

function saveAPI.recoverLast(slotName)
    ensureDirs()
    local slot = slotName or currentProfile or DEFAULT_SLOT
    local committed = profilePath(slot); local archived  = archivedPath(slot)
    if not fs.exists(archived) then return false, "No archived save found" end
    if fs.exists(committed) then fs.delete(committed) end
    fs.move(archived, committed)
    return saveAPI.loadCommitted(slot), "Recovered"
end

function saveAPI.resetAllSaves()
    if fs.exists(PROFILE_DIR) then fs.delete(PROFILE_DIR) end
    if fs.exists(ACTIVE_PATH) then fs.delete(ACTIVE_PATH) end
    fs.makeDir(PROFILE_DIR)
    currentState = deepcopy(defaultState); saveAPI.save(); return true, "All saves reset"
end

return saveAPI

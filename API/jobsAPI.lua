-- jobsAPI.lua (fast revert) — delta-minute timer, minimal disk writes
local jobsAPI = {}

local saveAPI = require("/API/saveAPI")
local timeAPI = require("/API/timeAPI")
local economyAPI = require("/API/economyAPI")

-- Internal helper: get mutable save + ensure schema
local function _state()
  local s = saveAPI.get()
  s.jobState = s.jobState or {
    inProgress = false,
    currentJob = nil,
    ticksRemaining = 0,
    earnings = 0,
    lastHM = nil,   -- last seen (hour*60 + minute)
  }
  return s
end

function jobsAPI.getState()
  return _state().jobState
end

-- Start a job for N in‑game minutes
function jobsAPI.start(jobName, minutes, earnings)
  local s = _state()
  local js = s.jobState
  if js.inProgress then return false, "Already working" end
  js.inProgress = true
  js.currentJob = jobName
  js.ticksRemaining = math.max(0, math.floor(tonumber(minutes) or 0))
  js.earnings = tonumber(earnings) or 0
  local t = timeAPI.getTime()
  js.lastHM = (t.hour * 60) + t.minute
  saveAPI.setState(s) -- state changed
  return true
end

local function completeIfDone(js)
  if (js.ticksRemaining or 0) <= 0 then
    if (js.earnings or 0) > 0 then
      economyAPI.addMoney(js.earnings, js.currentJob or "Job Completed")
    end
    js.inProgress = false
    js.currentJob = nil
    js.ticksRemaining = 0
    js.earnings = 0
    js.lastHM = nil
    return true
  end
  return false
end

-- Tick once per frame; returns true if a job completed this call
function jobsAPI.tick()
  local s = _state()
  local js = s.jobState

  if not js.inProgress then
    js.lastHM = nil
    return false
  end

  -- If already at/below zero (e.g., exact boundary), finalize without needing another minute
  if completeIfDone(js) then
    saveAPI.setState(s) -- state changed
    return true
  end

  -- Compute delta minutes from game clock
  local t = timeAPI.getTime()
  local nowHM = (t.hour * 60) + t.minute
  local last = js.lastHM or nowHM
  local delta = (nowHM - last) % (24 * 60)

  if delta > 0 then
    js.ticksRemaining = math.max(0, (js.ticksRemaining or 0) - delta)
    js.lastHM = nowHM
    if completeIfDone(js) then
      saveAPI.setState(s) -- state changed
      return true
    end
    saveAPI.setState(s) -- state changed (remaining/lastHM updated)
  end

  -- No change → no disk write
  return false
end

function jobsAPI.cancel()
  local s = _state()
  local js = s.jobState
  js.inProgress = false
  js.currentJob = nil
  js.ticksRemaining = 0
  js.earnings = 0
  js.lastHM = nil
  saveAPI.setState(s)
end

function jobsAPI.isWorking()
  return _state().jobState.inProgress
end

return jobsAPI

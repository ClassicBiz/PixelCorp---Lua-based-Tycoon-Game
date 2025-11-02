-- eventAPI.lua - Manages scheduled and triggered events in-game

local eventAPI = {}

-- List of events
local events = {}
local listeners = {}

-- Adds an event to be triggered at a specific in-game time
function eventAPI.schedule(timeTable, callback, description)
    table.insert(events, {
        triggerTime = timeTable,
        callback = callback,
        description = description or ""
    })
end

-- Compare two time tables
local function isTimeEqualOrPassed(current, target)
    local function toValue(t)
        return ((((t.year * 12 + t.month) * 30 + t.day) * 24 + t.hour) * 60 + t.minute)
    end
    return toValue(current) >= toValue(target)
end

-- Trigger events that are due
function eventAPI.check(currentTime)
    local remaining = {}
    for _, event in ipairs(events) do
        if isTimeEqualOrPassed(currentTime, event.triggerTime) then
            if event.callback then
                event.callback(currentTime)
            end
        else
            table.insert(remaining, event)
        end
    end
    events = remaining
end

-- Register global listeners for all time ticks
function eventAPI.onGlobal(callback)
    table.insert(listeners, callback)
end

-- Called every minute by timeAPI
function eventAPI.onTick(currentTime)
    -- Fire global listeners
    for _, fn in ipairs(listeners) do
        fn(currentTime)
    end
    -- Check scheduled events
    eventAPI.check(currentTime)
end

return eventAPI
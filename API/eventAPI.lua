local eventAPI = {}
local events = {}
local listeners = {}

function eventAPI.schedule(timeTable, callback, description)
    table.insert(events, {
        triggerTime = timeTable,
        callback = callback,
        description = description or ""
    })
end

local function isTimeEqualOrPassed(current, target)
    local function toValue(t)
        return ((((t.year * 12 + t.month) * 30 + t.day) * 24 + t.hour) * 60 + t.minute)
    end
    return toValue(current) >= toValue(target)
end

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

function eventAPI.onGlobal(callback)
    table.insert(listeners, callback)
end

function eventAPI.onTick(currentTime)
    for _, fn in ipairs(listeners) do
        fn(currentTime)
    end
    eventAPI.check(currentTime)
end

return eventAPI

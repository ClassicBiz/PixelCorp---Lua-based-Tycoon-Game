-- API/orderAPI.lua
-- Customer order helper for lemonade stand.


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
local economyAPI = require(root.."/API/economyAPI")
local inventoryAPI = require(root.."/API/inventoryAPI")
local saveAPI = require(root.."/API/saveAPI")

local orderAPI = {}

-- Create an order request from a customer
function orderAPI.process(request)
    local state = saveAPI.get()
    local unlocked = state.player and state.player.unlocks and state.player.unlocks.lemonade or false
    if not unlocked then
        return false, "Lemonade stand not unlocked"
    end
    local cups = math.max(1, math.floor(request.cups or 1))
    local price = tonumber(request.maxPrice or 0.5) or 0.5
    local useIce = request.useIce and true or false
    local ok, maxPossible = inventoryAPI.canMake(cups, useIce)
    if not ok then
        if maxPossible <= 0 then
            return false, "Out of stock"
        else
            cups = maxPossible
        end
    end

    local consumed, n = inventoryAPI.consumeForLemonade(cups, useIce)
    if not consumed then
        return false, "Failed to consume stock"
    end

    local unitPrice = (state.player and state.player.pricing and state.player.pricing.lemonade) or price
    local total = math.floor(n * unitPrice * 100 + 0.5) / 100
    economyAPI.addMoney(total, ("Sold %d cup(s) of lemonade @ $%.2f"):format(n, unitPrice))

    state.jobState = state.jobState or {}
    state.jobState.lemonade = state.jobState.lemonade or { served = 0, revenue = 0 }
    local js = state.jobState.lemonade
    js.served = js.served + n
    js.revenue = js.revenue + total
    saveAPI.save()

    return true, { cups = n, total = total }
end

return orderAPI

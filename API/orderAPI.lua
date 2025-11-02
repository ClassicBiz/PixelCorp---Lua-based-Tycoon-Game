-- API/orderAPI.lua
-- Customer order helper for lemonade stand.

local economyAPI = require("/API/economyAPI")
local inventoryAPI = require("/API/inventoryAPI")
local saveAPI = require("/API/saveAPI")

local orderAPI = {}

-- Create an order request from a customer
-- request = { cups = int, maxPrice = number, useIce = bool }
function orderAPI.process(request)
    local state = saveAPI.get()
    -- verify unlocked
    local unlocked = state.player and state.player.unlocks and state.player.unlocks.lemonade or false
    if not unlocked then
        return false, "Lemonade stand not unlocked"
    end

    local cups = math.max(1, math.floor(request.cups or 1))
    local price = tonumber(request.maxPrice or 0.5) or 0.5
    local useIce = request.useIce and true or false

    -- check inventory
    local ok, maxPossible = inventoryAPI.canMake(cups, useIce)
    if not ok then
        if maxPossible <= 0 then
            return false, "Out of stock"
        else
            cups = maxPossible -- partial fill
        end
    end

    -- use inventory
    local consumed, n = inventoryAPI.consumeForLemonade(cups, useIce)
    if not consumed then
        return false, "Failed to consume stock"
    end

    -- revenue: player sets price (saved somewhere); fallback to request.maxPrice
    local unitPrice = (state.player and state.player.pricing and state.player.pricing.lemonade) or price
    local total = math.floor(n * unitPrice * 100 + 0.5) / 100
    economyAPI.addMoney(total, ("Sold %d cup(s) of lemonade @ $%.2f"):format(n, unitPrice))

    -- analytics
    state.jobState = state.jobState or {}
    state.jobState.lemonade = state.jobState.lemonade or { served = 0, revenue = 0 }
    local js = state.jobState.lemonade
    js.served = js.served + n
    js.revenue = js.revenue + total
    saveAPI.save()

    return true, { cups = n, total = total }
end

return orderAPI

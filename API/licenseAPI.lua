-- licenseAPI.lua - Manages business licenses and progression gates

local licenseAPI = {}
local saveAPI = require("/API/saveAPI")

-- All licenses in the game
licenseAPI.licenses = {
    lemonade = { name = "Business License", cost = 100 },
    warehouse = { name = "Commercial License", cost = 1000 },
    cdl = { name = "CDL License", cost = 1500 },
    factory = { name = "Manufacturing License", cost = 5000 },
    osha = { name = "OSHA Permit", cost = 3500 },
    highrise = { name = "High-Rise Construction Permit", cost = 15000 },
    skyscraper = { name = "Multi-Story Safety Permit", cost = 10000 },
}

function licenseAPI.has(id)
    local state = saveAPI.get().player
    return state.licenses[id] == true
end

function licenseAPI.purchase(id)
    local license = licenseAPI.licenses[id]
    local state = saveAPI.get() -- Get the full state
    if not license then return false, "License does not exist." end
    if state.player.money < license.cost then return false, "Not enough money." end
    if licenseAPI.has(id) then return false, "Already purchased." end

    state.player.money = state.player.money - license.cost
    state.player.licenses[id] = true
    saveAPI.setState(state) -- Save the full state
    return true, "License purchased."
end

function licenseAPI.getAll()
    return licenseAPI.licenses
end

function licenseAPI.getOwned()
    local owned = {}
    for id, _ in pairs(saveAPI.get().player.licenses) do
        table.insert(owned, id)
    end
    return owned
end

return licenseAPI
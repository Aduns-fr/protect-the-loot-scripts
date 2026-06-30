local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Systems = ServerScriptService:WaitForChild("Systems")
local PlayerDataService = require(Systems:WaitForChild("DataSystem"):WaitForChild("Modules"):WaitForChild("PlayerDataService"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local UnitsConfig = require(Configs:WaitForChild("UnitsConfig"))
local WeaponsConfig = require(Configs:WaitForChild("WeaponsConfig"))

local adminPack = ServerScriptService:WaitForChild("UltimateAdminAbusePack")
local bindables = adminPack:WaitForChild("Bindables")

workspace:SetAttribute("ActiveAdminWeather", workspace:GetAttribute("ActiveAdminWeather") or "")
workspace:SetAttribute("ActiveAdminLuck", workspace:GetAttribute("ActiveAdminLuck") or "")
workspace:SetAttribute("AdminLuckMultiplier", workspace:GetAttribute("AdminLuckMultiplier") or 1)

local function getPlayer(userId)
    return Players:GetPlayerByUserId(tonumber(userId) or 0)
end

local function unitDisplayName(id, cfg)
    return tostring((type(cfg) == "table" and (cfg.DisplayName or cfg.Name)) or id)
end

local function addUnit(player, name, amount)
    local units = UnitsConfig.Units or UnitsConfig
    if type(units) ~= "table" then return false end
    if units[name] then PlayerDataService.AddUnit(player, name, amount); return true end
    local lowered = string.lower(name)
    for id, cfg in pairs(units) do
        if string.lower(tostring(id)) == lowered or string.lower(unitDisplayName(id, cfg)) == lowered then
            PlayerDataService.AddUnit(player, id, amount)
            return true
        end
    end
    return false
end

local function addWeapon(player, name, amount)
    local swords = WeaponsConfig.Swords or WeaponsConfig.Weapons or {}
    if type(swords) ~= "table" then return false end
    if swords[name] then PlayerDataService.AddWeapon(player, name, amount); return true end
    local lowered = string.lower(name)
    for id, cfg in pairs(swords) do
        if string.lower(tostring(id)) == lowered or (type(cfg) == "table" and string.lower(tostring(cfg.DisplayName or cfg.Name or "")) == lowered) then
            PlayerDataService.AddWeapon(player, id, amount)
            return true
        end
    end
    return false
end

local function giveNamed(player, name, amount)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    name = tostring(name or "")
    local lowered = string.lower(name)
    if lowered == "cash" or lowered == "money" or lowered == "coins" then
        PlayerDataService.AddCash(player, amount)
        return
    end
    if addUnit(player, name, amount) then return end
    if addWeapon(player, name, amount) then return end
    warn("[AdminGameBridge] Unknown item:", name)
end

bindables.GiveItem.Event:Connect(function(userId, items, customItem)
    local player = getPlayer(userId)
    if not player then return end
    if type(items) == "table" then
        local amount = tonumber(items.Amount) or 1
        for _, itemName in ipairs(type(items.List) == "table" and items.List or {}) do
            giveNamed(player, itemName, amount)
        end
    end
    if type(customItem) == "table" and customItem.Name and customItem.Name ~= "" then
        giveNamed(player, customItem.Name, tonumber(customItem.Amount) or 1)
    end
end)

bindables.WeatherStart.Event:Connect(function(weatherName)
    workspace:SetAttribute("ActiveAdminWeather", tostring(weatherName or ""))
end)

bindables.WeatherEnd.Event:Connect(function(weatherName)
    if workspace:GetAttribute("ActiveAdminWeather") == tostring(weatherName or "") then
        workspace:SetAttribute("ActiveAdminWeather", "")
    end
end)

bindables.LuckStart.Event:Connect(function(luckName)
    local multiplier = tonumber(tostring(luckName):match("%d+")) or 2
    workspace:SetAttribute("ActiveAdminLuck", tostring(luckName or ""))
    workspace:SetAttribute("AdminLuckMultiplier", multiplier)
end)

bindables.LuckEnd.Event:Connect(function(luckName)
    if workspace:GetAttribute("ActiveAdminLuck") == tostring(luckName or "") then
        workspace:SetAttribute("ActiveAdminLuck", "")
        workspace:SetAttribute("AdminLuckMultiplier", 1)
    end
end)
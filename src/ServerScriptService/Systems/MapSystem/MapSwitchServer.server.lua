local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local PlotService = require(ServerScriptService.Systems.PlotSystem.Modules.PlotService)

local mapSwitchRemote = ReplicatedStorage.Remotes:WaitForChild("MapSwitch")

-- bindables let us call into PlacementServer (a Script, not a module)
local bindables = ServerScriptService:WaitForChild("Bindables")
local savePlacedBF = bindables:WaitForChild("SavePlacedUnits")
local loadPlacedBF = bindables:WaitForChild("LoadPlacedUnits")

local function setPartColor(plot, color)
    for _, c in ipairs(plot:GetChildren()) do
        if c:IsA("BasePart") and c.Name == "Part" then
            c.Color = color
            break
        end
    end
end

local function applyMapLook(plot, targetMapId)
    local mapCfg = MapConfig.Maps[targetMapId]
    setPartColor(plot, mapCfg.PartColor)
end

mapSwitchRemote.OnServerInvoke = function(player, targetMapId)
    targetMapId = math.clamp(math.floor(tonumber(targetMapId) or 1), 1, 2)

    if player:GetAttribute("RaidActive") == true then
        return false, "Stop your raid before switching maps"
    end

    local currentMap = PlayerDataService.GetActiveMap(player)
    if currentMap == targetMapId then
        return false, "Already on that map"
    end

    -- save current map's placed units into data before switching
    -- (PlacementServer's serializePlaced writes to PlayerDataService.SetPlacedUnits)
    pcall(function() savePlacedBF:Invoke(player) end)

    -- switch data (cash, highestwave, units, etc.) to the target map
    local ok, err = PlayerDataService.SwitchMap(player, targetMapId)
    if not ok then return false, err end

    local plot = PlotService.GetPlayerPlot(player)
    if plot then applyMapLook(plot, targetMapId) end

    -- now restore the target map's placed units into the world
    task.delay(0.1, function()
        if player.Parent then
            pcall(function() loadPlacedBF:Invoke(player) end)
        end
    end)

    return true
end

-- on join, restore the map the player was last on
Players.PlayerAdded:Connect(function(player)
    task.wait(2) -- wait for PlotService assignment + data load
    local currentMap = PlayerDataService.GetActiveMap(player)
    if currentMap == 1 then return end -- map1 is default, no swap needed

    local plot = PlotService.GetPlayerPlot(player)
    if not plot then return end

    applyMapLook(plot, currentMap)
    -- PlacementServer's own PlayerAdded already calls loadPlaced, so no need to do it here
end)

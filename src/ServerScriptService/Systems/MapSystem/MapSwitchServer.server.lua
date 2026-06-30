local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local PlotService = require(ServerScriptService.Systems.PlotSystem.Modules.PlotService)

local mapSwitchRemote = ReplicatedStorage.Remotes:WaitForChild("MapSwitch")
local plots = Workspace:WaitForChild("Plots")

-- bindables let us call into PlacementServer (a Script, not a module)
local bindables = ServerScriptService:WaitForChild("Bindables")
local savePlacedBF = bindables:WaitForChild("SavePlacedUnits")
local loadPlacedBF = bindables:WaitForChild("LoadPlacedUnits")

local PLOT_NAMES = {"Plot1","Plot2","Plot3","Plot4","Plot5","Plot6"}
local ROTATED_PLOTS = {Plot4=true, Plot5=true, Plot6=true}

local function getPlotPart(plot)
    for _, c in ipairs(plot:GetChildren()) do
        if c:IsA("BasePart") and c.Name == "Part" then return c end
    end
    return nil
end

local map1Assets = {}
local function cacheMap1Assets()
    for _, plotName in ipairs(PLOT_NAMES) do
        local plot = plots:FindFirstChild(plotName)
        if not plot then continue end
        local pts = plot:FindFirstChild("Points")
        local path = plot:FindFirstChild("Path")
        map1Assets[plotName] = {
            points = pts and pts:Clone() or nil,
            path = path and path:Clone() or nil,
        }
    end
end

local function placeAssets(plot, sourcePoints, sourcePath)
    local plotPart = getPlotPart(plot)
    if not plotPart then warn("[MapSwitch] no Part in", plot.Name); return end

    local plot1Part = getPlotPart(plots:FindFirstChild("Plot1"))
    local worldOffset = plotPart.Position - plot1Part.Position
    local rotated = ROTATED_PLOTS[plot.Name]
    local pivotCf = plotPart.CFrame

    if sourcePoints then
        local newPts = sourcePoints:Clone()
        newPts.Name = "Points"
        for _, pt in ipairs(newPts:GetChildren()) do
            if pt:IsA("BasePart") then
                local worldPos = pt.Position + worldOffset
                if rotated then
                    local localPos = pivotCf:PointToObjectSpace(worldPos)
                    localPos = Vector3.new(-localPos.X, localPos.Y, -localPos.Z)
                    worldPos = pivotCf:PointToWorldSpace(localPos)
                end
                pt.CFrame = CFrame.new(worldPos)
            end
        end
        newPts.Parent = plot
    end

    if sourcePath then
        local newPath = sourcePath:Clone()
        newPath.Name = "Path"
        local worldCf = newPath.CFrame * CFrame.new(worldOffset)
        if rotated then
            local localCf = pivotCf:ToObjectSpace(worldCf)
            local newWorldPos = pivotCf:PointToWorldSpace(Vector3.new(-localCf.Position.X, localCf.Position.Y, -localCf.Position.Z))
            local newWorldCf = CFrame.new(newWorldPos) * (CFrame.Angles(0, math.pi, 0) * CFrame.fromMatrix(Vector3.new(), localCf.XVector, localCf.YVector, localCf.ZVector))
            newPath.CFrame = newWorldCf
        else
            newPath.CFrame = worldCf
        end
        newPath.Parent = plot
    end
end

local function removeCurrentAssets(plot)
    local pts = plot:FindFirstChild("Points")
    local path = plot:FindFirstChild("Path")
    if pts then pts:Destroy() end
    if path then path:Destroy() end
end

local function setPartColor(plot, color)
    for _, c in ipairs(plot:GetChildren()) do
        if c:IsA("BasePart") and c.Name == "Part" then
            c.Color = color
            break
        end
    end
end

local function swapPlotAssets(plot, targetMapId)
    removeCurrentAssets(plot)
    local mapCfg = MapConfig.Maps[targetMapId]
    setPartColor(plot, mapCfg.PartColor)

    if targetMapId == 1 then
        local cached = map1Assets[plot.Name]
        if cached then placeAssets(plot, cached.points, cached.path) end
    else
        local assetFolder = ReplicatedStorage:FindFirstChild(mapCfg.AssetFolder)
        if assetFolder then
            local srcPoints = assetFolder:FindFirstChild("Points") or assetFolder:FindFirstChild("Points2")
            local srcPath = assetFolder:FindFirstChild("Path")
            placeAssets(plot, srcPoints, srcPath)
        end
    end
end

task.defer(cacheMap1Assets)

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

    -- swap path/points in just this player's plot
    local plot = PlotService.GetPlayerPlot(player)
    if plot then swapPlotAssets(plot, targetMapId) end

    -- now restore the target map's placed units into the world
    -- small delay to let the path swap settle before units are positioned
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

    swapPlotAssets(plot, currentMap)
    -- PlacementServer's own PlayerAdded already calls loadPlaced, so no need to do it here
end)

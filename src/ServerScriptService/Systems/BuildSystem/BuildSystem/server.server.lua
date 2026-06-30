local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UnitsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitsConfig"))
local PlotService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PlotSystem"):WaitForChild("Modules"):WaitForChild("PlotService"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("DataSystem"):WaitForChild("Modules"):WaitForChild("PlayerDataService"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuildAction")
local unitModels = ReplicatedStorage:WaitForChild("UnitModels")
local activeFolder = Workspace:FindFirstChild("PlacedUnits") or Instance.new("Folder")
activeFolder.Name = "PlacedUnits"
activeFolder.Parent = Workspace
local function getPlotPart(plot) return plot and plot:FindFirstChild("Part") end
local function ensurePlotFolder(plot)
    local folder = activeFolder:FindFirstChild(plot.Name) or Instance.new("Folder")
    folder.Name = plot.Name
    folder.Parent = activeFolder
    return folder
end
local function insidePlot(part, worldPos, footprint)
    local localPos = part.CFrame:PointToObjectSpace(worldPos)
    local half = part.Size * 0.5
    local sx = footprint.X * 0.5
    local sz = footprint.Y * 0.5
    return math.abs(localPos.X) + sx <= half.X and math.abs(localPos.Z) + sz <= half.Z
end
local function surfaceCFrame(part, worldPos, rotation, footprint)
    local localPos = part.CFrame:PointToObjectSpace(worldPos)
    local half = part.Size * 0.5
    local x = math.clamp(localPos.X, -half.X + footprint.X * 0.5, half.X - footprint.X * 0.5)
    local z = math.clamp(localPos.Z, -half.Z + footprint.Y * 0.5, half.Z - footprint.Y * 0.5)
    local y = part.Size.Y * 0.5 + 0.5
    return part.CFrame * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rotation or 0), 0)
end
local function pathParts(plot)
    local path = plot and plot:FindFirstChild("Path")
    local parts = {}
    if not path then return parts end
    if path:IsA("BasePart") then table.insert(parts, path) end
    for _, desc in ipairs(path:GetDescendants()) do if desc:IsA("BasePart") then table.insert(parts, desc) end end
    return parts
end
local function intersects(cframe, size, include)
    if #include == 0 then return false end
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = include
    return #Workspace:GetPartBoundsInBox(cframe, size, params) > 0
end
local function overlapsPath(plot, cframe, size)
    return intersects(cframe, size, pathParts(plot))
end
local function overlapsPlaced(plot, cframe, size)
    local folder = activeFolder:FindFirstChild(plot.Name)
    if not folder then return false end
    local include = {}
    for _, desc in ipairs(folder:GetDescendants()) do if desc:IsA("BasePart") then table.insert(include, desc) end end
    return intersects(cframe, size, include)
end
local function createModel(unitId, cframe, player, plot)
    local template = unitModels:FindFirstChild(unitId)
    if not template then return nil end
    local model = template:Clone()
    model.Name = unitId
    model:SetAttribute("OwnerUserId", player.UserId)
    model:SetAttribute("UnitId", unitId)
    model:SetAttribute("PlotName", plot.Name)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then part.Anchored = true; part.CanCollide = true end
    end
    model:PivotTo(cframe)
    model.Parent = ensurePlotFolder(plot)
    return model
end
local function cframeToArray(cf)
    return { cf:GetComponents() }
end

local function arrayToCFrame(values)
    if type(values) ~= "table" or #values < 12 then return CFrame.new() end
    return CFrame.new(table.unpack(values, 1, 12))
end

local attackLoop
local function serializePlot(player, plot)
    local folder = activeFolder:FindFirstChild(plot.Name)
    local plotPart = getPlotPart(plot)
    local saved = {}
    if not folder or not plotPart then PlayerDataService.SetPlacedUnits(player, saved); return end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
            local rel = plotPart.CFrame:ToObjectSpace(model:GetPivot())
            table.insert(saved, { UnitId = model:GetAttribute("UnitId"), CFrame = cframeToArray(rel) })
        end
    end
    PlayerDataService.SetPlacedUnits(player, saved)
end

local function loadPlacedUnits(player)
    task.wait(2)
    local plot = PlotService.GetPlayerPlot(player) or PlotService.AssignPlayer(player)
    local plotPart = getPlotPart(plot)
    if not plot or not plotPart then return end
    local saved = PlayerDataService.GetPlacedUnits(player)
    if type(saved) ~= "table" then return end
    for _, entry in ipairs(saved) do
        local unitId = entry.UnitId
        local cfg = unitId and UnitsConfig.Units[unitId]
        if cfg and type(entry.CFrame) == "table" then
            local world = plotPart.CFrame * arrayToCFrame(entry.CFrame)
            local model = createModel(unitId, world, player, plot)
            if model then attackLoop(model) end
        end
    end
end

local function targetFor(model)
    local cfg = UnitsConfig.Units[model:GetAttribute("UnitId")]
    local root = model.PrimaryPart or model:FindFirstChild("Base")
    if not cfg or not root then return nil end
    local heroes = Workspace:FindFirstChild("ActiveHeroes")
    if not heroes then return nil end
    local best, bestDistance = nil, cfg.Range or 35
    for _, hero in ipairs(heroes:GetChildren()) do
        if hero:GetAttribute("OwnerUserId") == model:GetAttribute("OwnerUserId") then
            local hrp = hero:FindFirstChild("HumanoidRootPart")
            local hum = hero:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local dist = (hrp.Position - root.Position).Magnitude
                if dist < bestDistance then best = hero; bestDistance = dist end
            end
        end
    end
    return best
end
function attackLoop(model)
    task.spawn(function()
        while model.Parent do
            local cfg = UnitsConfig.Units[model:GetAttribute("UnitId")]
            local target = cfg and targetFor(model)
            if target then
                local hum = target:FindFirstChildOfClass("Humanoid")
                local hrp = target:FindFirstChild("HumanoidRootPart")
                local head = model:FindFirstChild("Head")
                if hum and hrp then
                    if head then TweenService:Create(head, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { CFrame = CFrame.lookAt(head.Position, Vector3.new(hrp.Position.X, head.Position.Y, hrp.Position.Z)) }):Play() end
                    hum:TakeDamage(cfg.Damage or 1)
                end
                task.wait(1 / math.max(0.1, cfg.FireRate or 1))
            else
                task.wait(0.12)
            end
        end
    end)
end
local function place(player, unitId, worldPos, rotation, hitPart, hitNormal)
    local cfg = UnitsConfig.Units[unitId]
    if not cfg then return false, "Bad unit" end
    local plot = PlotService.GetPlayerPlot(player)
    local plotPart = getPlotPart(plot)
    if not plot or not plotPart then return false, "No plot" end
    if plotPart.Name ~= "Part" then return false, "Bad plot part" end
    if typeof(worldPos) ~= "Vector3" then return false, "No position" end
    if hitPart ~= plotPart then return false, "Place on plot Part" end
    if typeof(hitNormal) ~= "Vector3" or hitNormal:Dot(plotPart.CFrame.UpVector) < 0.97 then return false, "Use top face" end
    if PlayerDataService.GetUnitCount(player, unitId) <= 0 then return false, "None owned" end

    local footprint = cfg.Footprint or Vector2.new(4, 4)
    if not insidePlot(plotPart, worldPos, footprint) then return false, "Outside plot" end
    local cframe = surfaceCFrame(plotPart, worldPos, math.floor((tonumber(rotation) or 0) / 90 + 0.5) * 90, footprint)
    local size = Vector3.new(footprint.X - 0.05, 5, footprint.Y - 0.05)
    if overlapsPath(plot, cframe, size) then return false, "Path blocked" end
    if overlapsPlaced(plot, cframe, size) then return false, "Occupied" end
    if not PlayerDataService.RemoveUnit(player, unitId, 1) then return false, "Inventory failed" end
    local model = createModel(unitId, cframe, player, plot)
    if not model then PlayerDataService.AddUnit(player, unitId, 1); return false, "Missing model" end
    attackLoop(model)
    serializePlot(player, plot)
    return true
end
local function delete(player, model)
    if typeof(model) ~= "Instance" or not model:IsDescendantOf(activeFolder) then return false, "Bad target" end
    if model:GetAttribute("OwnerUserId") ~= player.UserId then return false, "Not yours" end
    local unitId = model:GetAttribute("UnitId")
    model:Destroy()
    if unitId then PlayerDataService.AddUnit(player, unitId, 1) end
    local plot = PlotService.GetPlayerPlot(player)
    if plot then serializePlot(player, plot) end
    return true
end
game:GetService("Players").PlayerAdded:Connect(loadPlacedUnits)
for _, existingPlayer in ipairs(game:GetService("Players"):GetPlayers()) do task.spawn(loadPlacedUnits, existingPlayer) end

remote.OnServerInvoke = function(player, action, ...)
    if action == "Place" then return place(player, ...) end
    if action == "Delete" then return delete(player, ...) end
    return false, "Bad action"
end

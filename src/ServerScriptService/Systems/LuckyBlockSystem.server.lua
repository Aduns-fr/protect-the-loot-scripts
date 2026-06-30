local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local PlotService = require(ServerScriptService.Systems.PlotSystem.Modules.PlotService)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local cashPopupRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CashPopup")


local FIRST_SHOWER_MIN = 45
local FIRST_SHOWER_MAX = 90
local SHOWER_INTERVAL_MIN = 120
local SHOWER_INTERVAL_MAX = 240
local BLOCK_LIFETIME = 150
local MAX_BLOCKS_PER_PLOT = 2
local DROP_HEIGHT = 55
local BLOCK_SIZE = Vector3.new(4, 4, 4)

local rng = Random.new()
local activeByPlayer = {}
local opening = {}

local folder = workspace:FindFirstChild("LuckyBlocks") or Instance.new("Folder")
folder.Name = "LuckyBlocks"
folder.Parent = workspace

local function countActive(player)
    local count = 0
    local set = activeByPlayer[player]
    if set then
        for block in pairs(set) do
            if block.Parent then count += 1 else set[block] = nil end
        end
    end
    return count
end

local function isBlockedSurface(part, plotPart)
    if part == plotPart then return false end
    if not part then return true end
    local name = string.lower(part.Name)
    if name == "path" then return false end
    if name == "base" or name == "spawn" or name == "floor" then return true end
    local parentName = part.Parent and string.lower(part.Parent.Name) or ""
    if parentName == "path" or parentName == "points" then return false end
    return parentName == "crateslots" or parentName == "group" or parentName == "sign"
end

local function distanceToSegment2D(point, a, b)
    local ab = b - a
    local denominator = ab.X * ab.X + ab.Z * ab.Z
    if denominator <= 0.001 then
        return Vector2.new(point.X - a.X, point.Z - a.Z).Magnitude
    end
    local t = math.clamp(((point.X - a.X) * ab.X + (point.Z - a.Z) * ab.Z) / denominator, 0, 1)
    local closest = a + ab * t
    return Vector2.new(point.X - closest.X, point.Z - closest.Z).Magnitude
end

local function isNearRoute(plot, position)
    local pointsFolder = plot:FindFirstChild("Points")
    if not pointsFolder then return false end
    local points = {}
    for _, point in ipairs(pointsFolder:GetChildren()) do
        local index = tonumber(point.Name)
        if index and point:IsA("BasePart") then table.insert(points, { index = index, position = point.Position }) end
    end
    table.sort(points, function(a, b) return a.index < b.index end)
    for i = 1, #points - 1 do
        if distanceToSegment2D(position, points[i].position, points[i + 1].position) < 8 then return true end
    end
    return false
end

local function findDropPosition(plot)
    local plotPart = PlotService.GetPlotPart(plot)
    if not plotPart then return nil end
    local half = plotPart.Size * 0.5

    for _ = 1, 28 do
        local localX = rng:NextNumber(-half.X + 7, half.X - 7)
        local localZ = rng:NextNumber(-half.Z + 7, half.Z - 7)
        local top = plotPart.CFrame:PointToWorldSpace(Vector3.new(localX, half.Y, localZ))
        local target = top + plotPart.CFrame.UpVector * (BLOCK_SIZE.Y * 0.5)
        if isNearRoute(plot, target) then continue end

        local overlap = OverlapParams.new()
        overlap.FilterType = Enum.RaycastFilterType.Exclude
        overlap.FilterDescendantsInstances = { folder }
        local clear = true
        for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(target), BLOCK_SIZE + Vector3.new(4, 3, 4), overlap)) do
            if isBlockedSurface(part, plotPart) then
                clear = false
                break
            end
            local unitModel = part:FindFirstAncestorOfClass("Model")
            if unitModel and (unitModel:GetAttribute("OwnerUserId") or unitModel:GetAttribute("PlacedUnit")) then
                clear = false
                break
            end
        end
        if clear then return target end
    end

    return plotPart.CFrame:PointToWorldSpace(Vector3.new(0, half.Y + BLOCK_SIZE.Y * 0.5, 0))
end

local function rewardAmount(player)
    local leaderstats = player:FindFirstChild("leaderstats")
    local highestWave = leaderstats and leaderstats:FindFirstChild("Highest Wave")
    local wave = highestWave and highestWave.Value or 0
    local minimum = 150 + math.floor(wave / 5) * 25
    local maximum = 450 + math.floor(wave / 5) * 75
    local amount = rng:NextInteger(minimum, maximum)
    return math.floor(amount / 10 + 0.5) * 10
end

local function makeBurst(position)
    for x = -1, 1 do
        for y = -1, 1 do
            for z = -1, 1 do
                local voxel = Instance.new("Part")
                voxel.Name = "LuckyVoxel"
                voxel.Size = Vector3.new(0.92, 0.92, 0.92)
                voxel.Material = Enum.Material.Plastic
                voxel.Color = ((x + y + z) % 2 == 0) and Color3.fromRGB(255, 214, 35) or Color3.fromRGB(255, 232, 92)
                voxel.Anchored = false
                voxel.CanCollide = false
                voxel.CanTouch = false
                voxel.CanQuery = false
                voxel.Massless = true
                voxel.CastShadow = true
                voxel.CFrame = CFrame.new(position + Vector3.new(x, y, z) * 0.72) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.25, 0.25))
                voxel.Parent = folder
                local outward = Vector3.new(x + rng:NextNumber(-0.35, 0.35), y + 1.2, z + rng:NextNumber(-0.35, 0.35))
                voxel.AssemblyLinearVelocity = outward.Unit * rng:NextNumber(14, 25)
                voxel.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
                task.delay(0.45, function()
                    if voxel.Parent then
                        TweenService:Create(voxel, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.18, 0.18, 0.18) }):Play()
                    end
                end)
                Debris:AddItem(voxel, 0.9)
            end
        end
    end
end

local function openBlock(player, block)
    if opening[block] or not block.Parent or block:GetAttribute("OwnerUserId") ~= player.UserId then return end
    opening[block] = true
    local prompt = block:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then prompt.Enabled = false end

    local amount = rewardAmount(player)
    local awarded = PlayerDataService.AddCash(player, amount)
    if not awarded then
        opening[block] = nil
        if prompt then prompt.Enabled = true end
        return
    end

    block:SetAttribute("Opened", true)
    local startSize = block.Size
    local startCFrame = block.CFrame
    local grow = TweenService:Create(block, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = startSize * 2.1,
        CFrame = startCFrame * CFrame.Angles(0, math.rad(180), 0),
        Color = Color3.fromRGB(255, 255, 165),
    })
    grow:Play()
    grow.Completed:Wait()

    local position = block.Position
    makeBurst(position)
    cashPopupRemote:FireClient(player, amount)
    local set = activeByPlayer[player]
    if set then set[block] = nil end
    block:Destroy()
    opening[block] = nil
end

local function createBlock(player)
    if not player.Parent or countActive(player) >= MAX_BLOCKS_PER_PLOT then return nil end
    local plot = PlotService.GetPlayerPlot(player)
    local target = plot and findDropPosition(plot)
    if not plot or not target then return nil end

    local block = Instance.new("Part")
    block.Name = "LuckyBlock"
    block.Size = BLOCK_SIZE
    block.Material = Enum.Material.Plastic
    block.Color = Color3.fromRGB(255, 221, 25)
    block.Anchored = true
    block.CanCollide = false
    block.CanTouch = false
    block.CanQuery = true
    block.CastShadow = true
    block.CFrame = CFrame.new(target + Vector3.new(0, DROP_HEIGHT, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
    block:SetAttribute("OwnerUserId", player.UserId)
    block:SetAttribute("PlotName", plot.Name)
    block.Parent = folder

    local attachment = Instance.new("Attachment")
    attachment.Name = "LuckyAttachment"
    attachment.Parent = block

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "OpenPrompt"
    prompt.ActionText = "Open Lucky Block"
    prompt.ObjectText = "Lucky Block"
    prompt.KeyboardKeyCode = Enum.KeyCode.F
    prompt.HoldDuration = 0.35
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    prompt.Enabled = false
    prompt.Parent = attachment

    activeByPlayer[player] = activeByPlayer[player] or {}
    activeByPlayer[player][block] = true

    local landing = CFrame.new(target) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
    local fall = TweenService:Create(block, TweenInfo.new(1.05, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { CFrame = landing })
    fall:Play()
    fall.Completed:Once(function()
        if not block.Parent then return end
        local squash = TweenService:Create(block, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(4.7, 3.3, 4.7) })
        squash:Play()
        squash.Completed:Once(function()
            if not block.Parent then return end
            TweenService:Create(block, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = BLOCK_SIZE }):Play()
            prompt.Enabled = true
        end)
    end)

    prompt.Triggered:Connect(function(triggeringPlayer)
        if triggeringPlayer == player then task.spawn(openBlock, player, block) end
    end)

    task.delay(BLOCK_LIFETIME, function()
        if block.Parent and not opening[block] then
            local fade = TweenService:Create(block, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) })
            fade:Play()
            fade.Completed:Once(function()
                local set = activeByPlayer[player]
                if set then set[block] = nil end
                if block.Parent then block:Destroy() end
            end)
        end
    end)
    return block
end

local function shower()
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(createBlock, player)
    end
end

Players.PlayerRemoving:Connect(function(player)
    local set = activeByPlayer[player]
    if set then
        for block in pairs(set) do if block.Parent then block:Destroy() end end
    end
    activeByPlayer[player] = nil
end)

task.spawn(function()
    task.wait(rng:NextNumber(FIRST_SHOWER_MIN, FIRST_SHOWER_MAX))
    while true do
        shower()
        task.wait(rng:NextNumber(SHOWER_INTERVAL_MIN, SHOWER_INTERVAL_MAX))
    end
end)

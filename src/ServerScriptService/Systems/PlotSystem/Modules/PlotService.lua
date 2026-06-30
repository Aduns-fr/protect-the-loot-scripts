local Players = game:GetService("Players")

local PlotService = {}

local plotsFolder = workspace:WaitForChild("Plots")
local playerPlots = {}

local function getPlotPart(plot)
    local part = plot:FindFirstChild("Part")
    if part and part:IsA("BasePart") then
        return part
    end

    return nil
end

local function getSpawn(plot)
    local spawn = plot:FindFirstChild("Spawn")
    if spawn and spawn:IsA("BasePart") then
        return spawn
    end

    return nil
end

local function getSignUi(plot)
    local sign = plot and plot:FindFirstChild("Sign")
    local part = sign and sign:FindFirstChildWhichIsA("BasePart", true)
    local surfaceGui = part and part:FindFirstChildWhichIsA("SurfaceGui", true)
    local frame = surfaceGui and surfaceGui:FindFirstChildWhichIsA("Frame", true)
    local textLabel = frame and frame:FindFirstChildWhichIsA("TextLabel", true)
    local imageLabel = frame and frame:FindFirstChildWhichIsA("ImageLabel", true)
    return textLabel, imageLabel
end

local function updateSign(plot, player)
    local textLabel, imageLabel = getSignUi(plot)
    if textLabel then
        textLabel.Text = player and (player.Name .. "\nBase") or "Available\nBase"
    end
    if imageLabel then
        if player then
            local ok, image = pcall(function()
                return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
            end)
            imageLabel.Image = ok and image or ""
        else
            imageLabel.Image = ""
        end
    end
end

local function getSortedPlots()
    local plots = {}

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot:IsA("Folder") and getPlotPart(plot) and getSpawn(plot) then
            table.insert(plots, plot)
        end
    end

    table.sort(plots, function(a, b)
        local aNumber = tonumber(string.match(a.Name, "%d+")) or math.huge
        local bNumber = tonumber(string.match(b.Name, "%d+")) or math.huge
        return aNumber < bNumber
    end)

    return plots
end

function PlotService.GetPlayerPlot(player)
    return playerPlots[player]
end

function PlotService.GetPlotPart(plot)
    return getPlotPart(plot)
end

function PlotService.AssignPlayer(player)
    if playerPlots[player] then
        return playerPlots[player]
    end

    for _, plot in ipairs(getSortedPlots()) do
        if plot:GetAttribute("OwnerUserId") == player.UserId then
            playerPlots[player] = plot
            plot:SetAttribute("OwnerName", player.Name)
            player:SetAttribute("PlotName", plot.Name)
            updateSign(plot, player)
            return plot
        end
    end

    for _, plot in ipairs(getSortedPlots()) do
        local ownerUserId = plot:GetAttribute("OwnerUserId")
        if ownerUserId == nil or ownerUserId == 0 then
            plot:SetAttribute("OwnerUserId", player.UserId)
            plot:SetAttribute("OwnerName", player.Name)
            playerPlots[player] = plot
            player:SetAttribute("PlotName", plot.Name)
            updateSign(plot, player)
            return plot
        end
    end

    warn(("No available plot for %s"):format(player.Name))
    return nil
end

function PlotService.TeleportToPlotSpawn(player, character)
    local plot = PlotService.AssignPlayer(player)
    if not plot then
        return
    end

    local spawn = getSpawn(plot)
    if not spawn then
        warn(("%s is missing a Spawn part"):format(plot:GetFullName()))
        return
    end

    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
    if not humanoidRootPart then
        return
    end

    local function moveToSpawn()
        if not character.Parent or not spawn.Parent then return end
        humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
        humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
        character:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
    end

    moveToSpawn()
    task.delay(0.25, moveToSpawn)
    task.delay(1, moveToSpawn)
end

function PlotService.ReleasePlayer(player)
    local plot = playerPlots[player]
    if plot then
        plot:SetAttribute("OwnerUserId", nil)
        plot:SetAttribute("OwnerName", nil)
        updateSign(plot, nil)
    end

    playerPlots[player] = nil
end

local function bindPlayer(player)
    PlotService.AssignPlayer(player)

    player.CharacterAdded:Connect(function(character)
        PlotService.TeleportToPlotSpawn(player, character)
    end)

    if not player.Character then
        task.defer(function()
            if player.Parent and not player.Character then
                player:LoadCharacter()
            end
        end)
    else
        PlotService.TeleportToPlotSpawn(player, player.Character)
    end
end

function PlotService.Start()
    Players.CharacterAutoLoads = false

    for _, plot in ipairs(getSortedPlots()) do
        updateSign(plot, nil)
    end

    Players.PlayerAdded:Connect(bindPlayer)

    Players.PlayerRemoving:Connect(function(player)
        PlotService.ReleasePlayer(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        bindPlayer(player)
    end
end

return PlotService

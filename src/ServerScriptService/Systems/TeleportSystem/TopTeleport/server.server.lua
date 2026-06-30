local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(game:GetService("ServerScriptService"):WaitForChild("Systems"):WaitForChild("PlotSystem"):WaitForChild("Modules"):WaitForChild("PlotService"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TopTeleport")
local lastTeleport = {}
local COOLDOWN = 0.35

local function getRoot(player)
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function teleportToPart(player, part)
    local root = getRoot(player)
    if not root or not part or not part:IsA("BasePart") then return end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = part.CFrame + Vector3.new(0, 4, 0)
end

local function teleportToBase(player)
    local plot = PlotService.GetPlayerPlot(player) or PlotService.AssignPlayer(player)
    local spawn = plot and plot:FindFirstChild("Spawn")
    teleportToPart(player, spawn)
end

local function teleportToShops(player)
    local shops = workspace:FindFirstChild("Shops")
    local teleporter = shops and shops:FindFirstChild("Teleporter")
    teleportToPart(player, teleporter)
end

remote.OnServerEvent:Connect(function(player, destination)
    if typeof(destination) ~= "string" then return end
    local now = os.clock()
    if lastTeleport[player] and now - lastTeleport[player] < COOLDOWN then return end
    lastTeleport[player] = now

    if destination == "Base" then
        teleportToBase(player)
    elseif destination == "Shops" then
        teleportToShops(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    lastTeleport[player] = nil
end)

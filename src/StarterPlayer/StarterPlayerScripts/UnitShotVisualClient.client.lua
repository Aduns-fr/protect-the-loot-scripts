local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UnitShotVisual")
local effects = workspace:FindFirstChild("LocalEffects") or Instance.new("Folder")
effects.Name = "LocalEffects"
effects.Parent = workspace

remote.OnClientEvent:Connect(function(from, to)
    if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then return end
    local distance = (to - from).Magnitude
    if distance <= 0.05 then return end

    local beamPart = Instance.new("Part")
    beamPart.Name = "UnitShot"
    beamPart.Anchored = true
    beamPart.CanCollide = false
    beamPart.CanTouch = false
    beamPart.CanQuery = false
    beamPart.CastShadow = false
    beamPart.Material = Enum.Material.SmoothPlastic
    beamPart.Color = Color3.fromRGB(255, 224, 105)
    beamPart.Size = Vector3.new(0.08, 0.08, distance)
    beamPart.CFrame = CFrame.lookAt((from + to) * 0.5, to)
    beamPart.Parent = effects
    Debris:AddItem(beamPart, 0.045)
end)

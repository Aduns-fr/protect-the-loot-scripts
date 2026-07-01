local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local WATER_Y_LEVEL = 0.525
local ENTER_DEPTH = 1.35
local EXIT_HEIGHT = 2.4
local MAX_SWIM_DEPTH = 16

local activeForce
local activeAttachment

local function cleanupForce()
    if activeForce then activeForce:Destroy() end
    if activeAttachment then activeAttachment:Destroy() end
    activeForce = nil
    activeAttachment = nil
end

local function ensureForce(root)
    if activeForce and activeForce.Parent == root then return activeForce end
    cleanupForce()
    activeAttachment = Instance.new("Attachment")
    activeAttachment.Name = "InfiniteWaterSwimAttachment"
    activeAttachment.Parent = root
    activeForce = Instance.new("VectorForce")
    activeForce.Name = "InfiniteWaterSwimBuoyancy"
    activeForce.Attachment0 = activeAttachment
    activeForce.RelativeTo = Enum.ActuatorRelativeTo.World
    activeForce.ApplyAtCenterOfMass = true
    activeForce.Parent = root
    return activeForce
end

local function isInGeneratedWater(root, humanoid)
    if not root or not humanoid or humanoid.Health <= 0 then return false end
    if humanoid.Sit then return false end
    local y = root.Position.Y
    return y <= WATER_Y_LEVEL + ENTER_DEPTH and y >= WATER_Y_LEVEL - MAX_SWIM_DEPTH
end

RunService.Heartbeat:Connect(function()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid then
        cleanupForce()
        return
    end

    local inWater = isInGeneratedWater(root, humanoid)
    if not inWater and root.Position.Y < WATER_Y_LEVEL + EXIT_HEIGHT then
        inWater = root:GetAttribute("InfiniteWaterSwimming") == true and root.Position.Y <= WATER_Y_LEVEL + EXIT_HEIGHT
    end

    if not inWater then
        root:SetAttribute("InfiniteWaterSwimming", false)
        cleanupForce()
        return
    end

    root:SetAttribute("InfiniteWaterSwimming", true)
    humanoid:ChangeState(Enum.HumanoidStateType.Swimming)

    local force = ensureForce(root)
    local mass = root.AssemblyMass
    local targetY = WATER_Y_LEVEL + 1.05
    local depthError = targetY - root.Position.Y
    local damping = -root.AssemblyLinearVelocity.Y * 7
    local correction = math.clamp(depthError * 42 + damping, -Workspace.Gravity * 0.45, Workspace.Gravity * 0.75)
    force.Force = Vector3.new(0, mass * (Workspace.Gravity + correction), 0)
end)

player.CharacterRemoving:Connect(cleanupForce)

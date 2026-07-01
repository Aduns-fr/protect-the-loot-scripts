local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WATER_Y_LEVEL = 0.525
local FLOAT_CENTER_OFFSET = 1.35
local MAX_FORWARD_SPEED = 42
local REVERSE_SPEED = 18
local ACCELERATION = 7.5
local TURN_RATE = math.rad(76)
local IDLE_DRAG = 0.965

local BOAT_MODEL_NAME = "Boat Model"
local LEGACY_BOAT_NAME = "Boat"

local controlledBoats = {}

local function ensureBackupFolder()
    local backups = ServerStorage:FindFirstChild("Backups")
    if not backups then
        backups = Instance.new("Folder")
        backups.Name = "Backups"
        backups.Parent = ServerStorage
    end
    return backups
end

local function archiveLegacyBoat()
    local legacy = Workspace:FindFirstChild(LEGACY_BOAT_NAME)
    if not legacy then return end
    local backups = ensureBackupFolder()
    if backups:FindFirstChild("Boat_ScriptReference") then
        legacy:Destroy()
        return
    end
    legacy.Name = "Boat_ScriptReference"
    legacy.Parent = backups
end

local function getOrCreate(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing.ClassName == className then
        return existing
    end
    if existing then existing:Destroy() end
    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

local function setVisualPart(part)
    part.Anchored = false
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = true
    part.Massless = true
end

local function weldTo(root, part)
    if part == root then return end
    local weld = part:FindFirstChild("BoatVisualWeld")
    if not weld then
        weld = Instance.new("WeldConstraint")
        weld.Name = "BoatVisualWeld"
        weld.Parent = part
    end
    weld.Part0 = root
    weld.Part1 = part
end

local function prepareBoatModel(model)
    local readyHull = model:FindFirstChild("BoatHitbox")
    local readySeat = model:FindFirstChild("DriverSeat")
    if model:GetAttribute("BoatReady") == true and readyHull and readyHull:IsA("BasePart") and readySeat and readySeat:IsA("VehicleSeat") then
        local float = getOrCreate(readyHull, "BodyPosition", "BoatFloat")
        float.MaxForce = Vector3.new(0, 120000, 0)
        float.P = 9000
        float.D = 1300

        local gyro = getOrCreate(readyHull, "BodyGyro", "BoatGyro")
        gyro.MaxTorque = Vector3.new(180000, 180000, 180000)
        gyro.P = 8500
        gyro.D = 850

        return {
            model = model,
            hull = readyHull,
            seat = readySeat,
            float = float,
            gyro = gyro,
            yaw = select(2, readyHull.CFrame:ToOrientation()),
            speed = 0,
            bobSeed = os.clock(),
        }
    end

    local boxCf, boxSize = model:GetBoundingBox()
    local targetCenter = Vector3.new(boxCf.Position.X, WATER_Y_LEVEL + FLOAT_CENTER_OFFSET, boxCf.Position.Z)

    local hull = model:FindFirstChild("BoatHitbox")
    if not hull then
        hull = Instance.new("Part")
        hull.Name = "BoatHitbox"
        hull.Parent = model
    end

    hull.Size = Vector3.new(math.max(4, boxSize.X * 0.92), 1.1, math.max(7, boxSize.Z * 0.84))
    hull.CFrame = CFrame.new(targetCenter)
    hull.Transparency = 1
    hull.Anchored = false
    hull.CanCollide = true
    hull.CanTouch = true
    hull.CanQuery = true
    hull.CustomPhysicalProperties = PhysicalProperties.new(0.18, 0.35, 0, 1, 1)
    model.PrimaryPart = hull

    local transform = CFrame.new(targetCenter) * boxCf:Inverse()
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant ~= hull then
            descendant.CFrame = transform * descendant.CFrame
            setVisualPart(descendant)
            weldTo(hull, descendant)
        end
    end

    local seat = model:FindFirstChild("DriverSeat")
    if not seat then
        seat = Instance.new("VehicleSeat")
        seat.Name = "DriverSeat"
        seat.Parent = model
    end
    seat.Size = Vector3.new(2.25, 0.8, 2)
    seat.CFrame = hull.CFrame * CFrame.new(0, 1.0, 1.25)
    seat.Transparency = 0.18
    seat.Color = Color3.fromRGB(76, 52, 32)
    seat.Material = Enum.Material.Wood
    seat.Anchored = false
    seat.CanCollide = false
    seat.CanTouch = true
    seat.CanQuery = true
    pcall(function() seat.MaxSpeed = 0 end)
    pcall(function() seat.Torque = 0 end)
    pcall(function() seat.TurnSpeed = 0 end)
    pcall(function() seat.HeadsUpDisplay = false end)
    weldTo(hull, seat)

    local float = getOrCreate(hull, "BodyPosition", "BoatFloat")
    float.MaxForce = Vector3.new(0, 120000, 0)
    float.P = 9000
    float.D = 1300

    local gyro = getOrCreate(hull, "BodyGyro", "BoatGyro")
    gyro.MaxTorque = Vector3.new(180000, 180000, 180000)
    gyro.P = 8500
    gyro.D = 850

    model:SetAttribute("BoatReady", true)
    model:SetAttribute("WaterYLevel", WATER_Y_LEVEL)
    model:SetAttribute("FloatCenterOffset", FLOAT_CENTER_OFFSET)

    return {
        model = model,
        hull = hull,
        seat = seat,
        float = float,
        gyro = gyro,
        yaw = select(2, hull.CFrame:ToOrientation()),
        speed = 0,
        bobSeed = os.clock(),
    }
end

local function setupBoats()
    archiveLegacyBoat()
    local model = Workspace:FindFirstChild(BOAT_MODEL_NAME)
    if model and model:IsA("Model") and not controlledBoats[model] then
        controlledBoats[model] = prepareBoatModel(model)
    end
end

local function stepBoat(state, dt)
    local hull = state.hull
    local seat = state.seat
    if not hull.Parent or not seat.Parent then return false end

    local throttle = seat.ThrottleFloat
    local steer = seat.SteerFloat
    local occupied = seat.Occupant ~= nil
    local targetSpeed = 0
    if throttle > 0 then
        targetSpeed = throttle * MAX_FORWARD_SPEED
    elseif throttle < 0 then
        targetSpeed = throttle * REVERSE_SPEED
    end

    if not occupied then
        targetSpeed = 0
    end

    local alpha = math.clamp(dt * ACCELERATION, 0, 1)
    state.speed += (targetSpeed - state.speed) * alpha
    if math.abs(state.speed) < 0.05 then state.speed = 0 end

    local turnScale = math.clamp(math.abs(state.speed) / MAX_FORWARD_SPEED + 0.28, 0, 1)
    state.yaw -= steer * TURN_RATE * turnScale * dt

    local waterTarget = WATER_Y_LEVEL + FLOAT_CENTER_OFFSET + math.sin(os.clock() * 1.6 + state.bobSeed) * 0.08
    state.float.Position = Vector3.new(hull.Position.X, waterTarget, hull.Position.Z)

    local desiredCf = CFrame.new(hull.Position) * CFrame.Angles(0, state.yaw, 0)
    state.gyro.CFrame = desiredCf

    local forward = desiredCf.LookVector
    local current = hull.AssemblyLinearVelocity
    local desiredHorizontal = forward * state.speed
    if not occupied then desiredHorizontal = desiredHorizontal * IDLE_DRAG end
    hull.AssemblyLinearVelocity = Vector3.new(desiredHorizontal.X, current.Y, desiredHorizontal.Z)
    hull.AssemblyAngularVelocity = hull.AssemblyAngularVelocity * 0.35

    local occupant = seat.Occupant
    local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
    if player then
        pcall(function()
            hull:SetNetworkOwner(player)
        end)
    else
        pcall(function()
            hull:SetNetworkOwnershipAuto()
        end)
    end

    return true
end

setupBoats()
Workspace.ChildAdded:Connect(function(child)
    if child.Name == BOAT_MODEL_NAME then
        task.defer(setupBoats)
    end
end)

RunService.Heartbeat:Connect(function(dt)
    for model, state in pairs(controlledBoats) do
        if not stepBoat(state, dt) then
            controlledBoats[model] = nil
        end
    end
end)

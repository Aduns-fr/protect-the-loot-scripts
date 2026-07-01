--!strict
-- BoatController
-- Spawns one rideable boat floating at every Plot's BoatSpawn marker.
-- Players sit in the DriverSeat and steer with WASD. Buoyancy + heading are
-- driven by BodyPosition/BodyGyro on the hidden hull (BoatHitbox).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterConfig = require(ReplicatedStorage:WaitForChild("WaterSystem"):WaitForChild("WaterConfig"))

local MAX_FORWARD_SPEED = 42
local REVERSE_SPEED = 18
local ACCELERATION = 7.5
local TURN_RATE = math.rad(76)
local IDLE_DRAG = 0.965
local RETURN_SPEED = 4
local FLOAT_DRAFT = 0.8
local BOB_AMP = 0.08
local BOB_SPEED = 1.6

local BOAT_MODEL_NAME = "Boat Model"
local TEMPLATE_NAME = "BoatTemplate"
local HULL_NAME = "BoatHitbox"
local SEAT_NAME = "DriverSeat"

local boats = {}

local function getTemplate()
	local existing = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	if existing then return existing end

	local live = Workspace:FindFirstChild(BOAT_MODEL_NAME)
	if live then
		live.Name = TEMPLATE_NAME
		live.Parent = ServerStorage
		return live
	end
	return nil
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

local function weldTo(root, part)
	if part == root then return end
	local weld = part:FindFirstChild("BoatVisualWeld")
	if not weld or not weld:IsA("WeldConstraint") then
		if weld then weld:Destroy() end
		weld = Instance.new("WeldConstraint")
		weld.Name = "BoatVisualWeld"
		weld.Parent = part
	end
	weld.Part0 = root
	weld.Part1 = part
end

local function spawnBoat(spawnPart, parentFolder)
	local template = getTemplate()
	if not template then return nil end

	local model = template:Clone()
	local hull = model:FindFirstChild(HULL_NAME)
	local seat = model:FindFirstChild(SEAT_NAME)
	if not (hull and hull:IsA("BasePart")) then
		model:Destroy()
		return nil
	end

	local _, yaw = spawnPart.CFrame:ToOrientation()
	local floatY = WaterConfig.SurfaceY + FLOAT_DRAFT
	local target = CFrame.new(spawnPart.Position.X, floatY, spawnPart.Position.Z) * CFrame.Angles(0, yaw, 0)

	local transform = target * hull.CFrame:Inverse()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = transform * descendant.CFrame
		end
	end

	model.PrimaryPart = hull
	hull.Anchored = false
	hull.CanCollide = true
	hull.CanTouch = true
	hull.CanQuery = true
	hull.Massless = false
	hull.Transparency = 1
	hull.CustomPhysicalProperties = PhysicalProperties.new(0.18, 0.35, 0, 1, 1)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= hull and descendant ~= seat then
			descendant.Anchored = false
			descendant.CanCollide = true
			descendant.Massless = true
			weldTo(hull, descendant)
		end
	end

	if seat and seat:IsA("VehicleSeat") then
		seat.Anchored = false
		seat.CanCollide = false
		seat.CanTouch = true
		seat.Massless = true
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.TurnSpeed = 0
		seat.HeadsUpDisplay = false
		weldTo(hull, seat)
	end

	local float = getOrCreate(hull, "BodyPosition", "BoatFloat")
	float.MaxForce = Vector3.new(0, 120000, 0)
	float.P = 9000
	float.D = 1300
	float.Position = Vector3.new(hull.Position.X, floatY, hull.Position.Z)

	local gyro = getOrCreate(hull, "BodyGyro", "BoatGyro")
	gyro.MaxTorque = Vector3.new(180000, 180000, 180000)
	gyro.P = 8500
	gyro.D = 850
	gyro.CFrame = target

	model.Parent = parentFolder

	return {
		model = model,
		hull = hull,
		seat = seat,
		float = float,
		gyro = gyro,
		home = spawnPart.Position,
		floatY = floatY,
		yaw = yaw,
		speed = 0,
		bobSeed = spawnPart.Position.X + spawnPart.Position.Z,
	}
end

local function stepBoat(state, dt)
	local hull = state.hull
	local seat = state.seat
	if not hull.Parent then return false end

	local occupant = seat and seat.Occupant
	local occupied = occupant ~= nil

	local throttle = seat and seat.ThrottleFloat or 0
	local steer = seat and seat.SteerFloat or 0
	local targetSpeed = 0
	if occupied then
		if throttle > 0 then
			targetSpeed = throttle * MAX_FORWARD_SPEED
		elseif throttle < 0 then
			targetSpeed = throttle * REVERSE_SPEED
		end
	end

	local alpha = math.clamp(dt * ACCELERATION, 0, 1)
	state.speed += (targetSpeed - state.speed) * alpha
	if math.abs(state.speed) < 0.05 then state.speed = 0 end

	local turnScale = math.clamp(math.abs(state.speed) / MAX_FORWARD_SPEED + 0.28, 0, 1)
	if occupied then
		state.yaw -= steer * TURN_RATE * turnScale * dt
	end

	local bob = math.sin(os.clock() * BOB_SPEED + state.bobSeed) * BOB_AMP
	state.float.Position = Vector3.new(hull.Position.X, state.floatY + bob, hull.Position.Z)

	local desiredCf = CFrame.new(hull.Position) * CFrame.Angles(0, state.yaw, 0)
	state.gyro.CFrame = desiredCf

	local current = hull.AssemblyLinearVelocity
	local horizontal
	if occupied then
		horizontal = desiredCf.LookVector * state.speed
	else
		local toHome = state.home - hull.Position
		toHome = Vector3.new(toHome.X, 0, toHome.Z)
		local dist = toHome.Magnitude
		if dist > 2 then
			horizontal = toHome.Unit * math.min(dist, RETURN_SPEED)
		else
			horizontal = Vector3.new(current.X, 0, current.Z) * IDLE_DRAG
		end
	end
	hull.AssemblyLinearVelocity = Vector3.new(horizontal.X, current.Y, horizontal.Z)
	hull.AssemblyAngularVelocity = hull.AssemblyAngularVelocity * 0.35

	local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
	pcall(function()
		if player then
			hull:SetNetworkOwner(player)
		else
			hull:SetNetworkOwnershipAuto()
		end
	end)

	return true
end

local function setup()
	if not getTemplate() then
		warn("[BoatController] No 'Boat Model' template found in Workspace or ServerStorage.")
		return
	end

	local folder = Workspace:FindFirstChild("Boats")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "Boats"
	folder.Parent = Workspace

	local plots = Workspace:FindFirstChild("Plots")
	if not plots then return end

	for _, plot in ipairs(plots:GetChildren()) do
		local marker = plot:FindFirstChild("BoatSpawn")
		if marker and marker:IsA("BasePart") then
			local state = spawnBoat(marker, folder)
			if state then
				state.model.Name = plot.Name .. "_Boat"
				table.insert(boats, state)
			end
		end
	end
end

setup()

RunService.Heartbeat:Connect(function(dt)
	for i = #boats, 1, -1 do
		if not stepBoat(boats[i], dt) then
			table.remove(boats, i)
		end
	end
end)

--[[
    AnimalController (LocalScript module - client)
    Client-side mount locomotion, collision response, and ability movement.
]]

local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local RemoteEvents      = ReplicatedStorage:WaitForChild("RemoteEvents")
local EliminationRemote = RemoteEvents:WaitForChild("EliminationRemote")
local CombatRemote      = RemoteEvents:WaitForChild("CombatRemote")

local VoxelRemote = RemoteEvents:FindFirstChild("VoxelRemote")
if not VoxelRemote then
	task.spawn(function()
		VoxelRemote = RemoteEvents:WaitForChild("VoxelRemote", 10)
	end)
end

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- DEBUG FLAGS

local DEBUG_GROUND    = false  -- keep false for release builds
local DEBUG_INTERVAL  = 3      -- seconds between ground debug prints
local lastDebugPrint  = 0
local debugScanPrinted = false -- only print union scan result once per round

-- CONSTANTS

local MOUNT = { topSpeed = 40, acceleration = 60, friction = 12 }
local GRAVITY            = 150
local TERMINAL_VELOCITY  = 250
local OOB_BELOW_MARGIN   = 25
local OOB_ABOVE_MARGIN   = 300

local KNOCKBACK_PHYSICS_DURATION = 1.4
local KNOCKBACK_OOB_GRACE        = 1.0
local POST_DASH_IMMUNITY         = 1.0

local CONTACT_RADIUS           = 6
local CONTACT_PUSH_FORCE       = 25
local CONTACT_SPEED_MULTIPLIER = 0.8
local CONTACT_MIN_SEPARATION   = 4
local OOB_ENABLE_DELAY         = 3.5
local SIT_ANIM_ID              = "rbxassetid://119560872496377"
local MOBILE_DEAD_ZONE         = 0.15
local CHARGE_HIT_RADIUS        = 11.5
local CHARGE_DURATION          = 0.7

local KB_VERTICAL_POP = 48
local KB_HORIZ_MULT   = 1.75

local CHARGE_VOXEL_REACH    = 10
local KNOCKBACK_VOXEL_REACH = 10

local RAY_START_ABOVE = 200
local RAY_LENGTH      = 600
local MIN_NORMAL_Y    = 0.2

local SAMPLE_OFFSETS = {
	Vector3.new( 0,   0,  0  ),
	Vector3.new( 0.5, 0,  0  ),
	Vector3.new(-0.5, 0,  0  ),
	Vector3.new( 0,   0,  0.5),
	Vector3.new( 0,   0, -0.5),
}

local AnimationEngine

local currentMode    = nil
local animalModel    = nil
local animalHumanoid = nil
local animalRoot     = nil
local loopConnection = nil
local animData       = nil
local sitAnimTrack   = nil

local mountVelocity      = Vector3.zero
local mountGroundY       = 0
local verticalVelocity   = 0
-- ability movement state
local speedBoostMult     = 1
local speedBoostToken    = 0
local abilityMoveMult     = 1
local abilityMoveToken    = 0
local burrowUntil        = 0
local burrowMoveMult     = 1
local slideUntil         = 0
local leapAirborne       = false
local leapLandingPose    = nil
local leapLandingPoseDur = 0.4
local extraRecoveryUntil = 0
local extraRecoveryUsed  = false
local impulseVelocity    = Vector3.zero
local impulseDuration    = 0
local impulseElapsed     = 0
local impulseActive      = false

local inPhysicsKnockback    = false
local physicsKnockbackTimer = 0
local knockbackGraceTimer   = 0
local postDashImmunityTimer = 0
local knockbackVoxelFired   = false

local floorPart        = nil
local inRound          = false
local hasReportedOOB   = false
local oobEnableTimer   = 0
local contactPush      = Vector3.zero
local isCharging           = false
local chargeKnockbackFired = false

local lastMobileDir = Vector3.new(0, 0, -1)

-- nil = needs scan, {} = scanned
local mapUnions = nil

local mountRayParams = RaycastParams.new()
mountRayParams.FilterType = Enum.RaycastFilterType.Exclude

local AnimalController = {}

-- Union cache (lazy)

local function getMapUnions()
	if mapUnions then return mapUnions end

	mapUnions = {}
	local mf      = workspace:FindFirstChild("Map")
	local mainF   = mf and mf:FindFirstChild("Main")
	local gameMap = mainF and mainF:FindFirstChild("GameMap")

	if DEBUG_GROUND and not debugScanPrinted then
		debugScanPrinted = true
		if not mf    then warn("[DBG] workspace.Map not found!") end
		if not mainF then warn("[DBG] Map.Main not found!") end
		if not gameMap then warn("[DBG] Map.Main.GameMap not found!") end
	end

	if gameMap then
		local allDescendants = gameMap:GetDescendants()

		if DEBUG_GROUND and not debugScanPrinted then
			-- just set it false to avoid double-print from gameMap nil branch
		end

		for _, desc in allDescendants do
			if desc:IsA("UnionOperation") then
				table.insert(mapUnions, desc)
			end
		end

		if DEBUG_GROUND then
			print(string.format("[DBG] Union scan: found %d unions in GameMap", #mapUnions))
			for _, u in mapUnions do
				print(string.format("  union: %s (class: %s)", u:GetFullName(), u.ClassName))
			end
			-- also print ALL descendants so we can see what CrateredCore actually is
			print("[DBG] All GameMap descendants (first 40):")
			local count = 0
			for _, desc in allDescendants do
				count += 1
				if count <= 40 then
					print(string.format("  [%s] %s", desc.ClassName, desc:GetFullName()))
				end
			end
			if count > 40 then print(string.format("  ... and %d more", count - 40)) end
		end
	end

	return mapUnions
end

-- Direction helpers

function AnimalController.getPlayerForwardDirection()
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0, 0, -1)
end

function AnimalController.getPlayerRightDirection()
	local right = camera.CFrame.RightVector
	local flat  = Vector3.new(right.X, 0, right.Z)
	return flat.Magnitude > 0.001 and flat.Unit or Vector3.new(1, 0, 0)
end

local function getCameraYaw()
	local look = camera.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function getCameraRelativeDirection()
	local raw = Vector3.zero

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then raw += Vector3.new(0, 0, -1) end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then raw += Vector3.new(0, 0,  1) end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then raw += Vector3.new(-1, 0, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then raw += Vector3.new( 1, 0, 0) end

	if raw.Magnitude > 0.01 then
		if raw.Magnitude > 1 then raw = raw.Unit end
		local dir = (AnimalController.getPlayerForwardDirection() * -raw.Z
			+ AnimalController.getPlayerRightDirection()          *  raw.X)
		if dir.Magnitude > 0.01 then lastMobileDir = dir.Unit; return dir.Unit end
	end

	pcall(function()
		local gs = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
		for _, inp in ipairs(gs) do
			if inp.KeyCode == Enum.KeyCode.Thumbstick1 then
				local p = inp.Position
				if math.abs(p.X) > MOBILE_DEAD_ZONE or math.abs(p.Y) > MOBILE_DEAD_ZONE then
					raw = Vector3.new(p.X, 0, -p.Y)
					if raw.Magnitude > 1 then raw = raw.Unit end
					local dir = (AnimalController.getPlayerForwardDirection() * -raw.Z
						+ AnimalController.getPlayerRightDirection()          *  raw.X)
					if dir.Magnitude > 0.01 then lastMobileDir = dir.Unit; return dir.Unit end
				end
			end
		end
	end)
	if raw.Magnitude > 0.01 then return raw.Unit end

	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local md = hum.MoveDirection
		if md.Magnitude > MOBILE_DEAD_ZONE then
			local flat = Vector3.new(md.X, 0, md.Z)
			if flat.Magnitude > 0.01 then lastMobileDir = flat.Unit; return flat.Unit end
		end
	end

	return Vector3.zero
end

-- Ground detection

local function findGroundY(position)
	if not animData then return nil end

	local shouldPrint = DEBUG_GROUND and (tick() - lastDebugPrint) >= DEBUG_INTERVAL
	if shouldPrint then lastDebugPrint = tick() end

	local ch = player.Character
	local baseExclude = { animalModel }
	if ch then table.insert(baseExclude, ch) end

	local expectedFloorY = position.Y - animData.hrpToGround

	if shouldPrint then
		print(string.format("[DBG:findGroundY] pos=(%.1f, %.1f, %.1f)  hrpToGround=%.2f  expectedFloorY=%.2f",
			position.X, position.Y, position.Z, animData.hrpToGround, expectedFloorY))
		print(string.format("  mapUnions count: %d", #getMapUnions()))
	end

	-- Pass 1: exclude unions
	local unions = getMapUnions()
	local excludePass1 = { table.unpack(baseExclude) }
	for _, u in unions do table.insert(excludePass1, u) end
	mountRayParams.FilterDescendantsInstances = excludePass1

	local bestHitY    = nil
	local bestHitDist = math.huge
	local bestHitInfo = nil  -- for debug

	for i, off in SAMPLE_OFFSETS do
		local origin = Vector3.new(
			position.X + off.X,
			position.Y + RAY_START_ABOVE,
			position.Z + off.Z
		)
		local res = workspace:Raycast(origin, Vector3.new(0, -RAY_LENGTH, 0), mountRayParams)

		if shouldPrint then
			if res then
				print(string.format("  Pass1 sample[%d]: HIT %s (%s)  normalY=%.3f  hitY=%.2f",
					i, res.Instance.Name, res.Instance.ClassName, res.Normal.Y, res.Position.Y))
			else
				print(string.format("  Pass1 sample[%d]: MISS (no geometry hit)", i))
			end
		end

		if res and res.Normal.Y >= MIN_NORMAL_Y then
			local dist = math.abs(res.Position.Y - expectedFloorY)
			if dist < bestHitDist then
				bestHitDist = dist
				bestHitY    = res.Position.Y
				bestHitInfo = res
			end
		elseif res and shouldPrint then
			print(string.format("    ^ REJECTED: normalY %.3f < threshold %.2f", res.Normal.Y, MIN_NORMAL_Y))
		end
	end

	if bestHitY then
		local finalY = bestHitY + animData.hrpToGround
		if shouldPrint then
			print(string.format("  Pass1 WINNER: hitY=%.2f  finalY=%.2f (instance: %s)",
				bestHitY, finalY, bestHitInfo and bestHitInfo.Instance.Name or "?"))
			print(string.format("  Animal is %.2f studs above final ground", position.Y - finalY))
		end
		return finalY
	end

	if shouldPrint then
		print("  Pass1 found nothing valid, falling through to Pass2 (includes unions)")
	end

	-- Pass 2: include unions
	mountRayParams.FilterDescendantsInstances = baseExclude
	local res = workspace:Raycast(
		Vector3.new(position.X, position.Y + RAY_START_ABOVE, position.Z),
		Vector3.new(0, -RAY_LENGTH, 0),
		mountRayParams
	)

	if shouldPrint then
		if res then
			print(string.format("  Pass2: HIT %s (%s)  normalY=%.3f  hitY=%.2f → finalY=%.2f",
				res.Instance.Name, res.Instance.ClassName, res.Normal.Y,
				res.Position.Y, res.Position.Y + animData.hrpToGround))
		else
			print("  Pass2: MISS — returning nil")
		end
	end

	if res then return res.Position.Y + animData.hrpToGround end
	return nil
end

local function isPositionInFloorBounds(pos)
	if not floorPart or not floorPart.Parent then return true end
	local fp = floorPart.Position; local fs = floorPart.Size
	if math.abs(pos.X - fp.X) > fs.X * 0.5 + 3 then return false end
	if math.abs(pos.Z - fp.Z) > fs.Z * 0.5 + 3 then return false end
	local topY = fp.Y + fs.Y * 0.5
	if pos.Y < topY - OOB_BELOW_MARGIN then return false end
	if pos.Y > topY + OOB_ABOVE_MARGIN  then return false end
	return true
end

-- Voxel detection

local function isDestroyable(part)
	return part and part:IsA("BasePart") and part:GetAttribute("Destroyable") == true
end

local function requestVoxelBreak(position)
	local remote = VoxelRemote or RemoteEvents:FindFirstChild("VoxelRemote")
	if remote then remote:FireServer(position) end
end

-- Spherecast instead of a thin centerline ray: a 3-stud sphere catches
-- off-center hits, corner clips, and walls whose surface sits above/below
-- HRP height - the cases where the old ray silently missed.
local VOXEL_SPHERE_RADIUS = 3
local VOXEL_BREAK_COOLDOWN = 0.3  -- time-based, so one launch can smash through multiple walls
local lastVoxelBreak = 0

local function voxelSweep(dir, reach)
	if not animalRoot or not animalRoot.Parent then return end
	if os.clock() - lastVoxelBreak < VOXEL_BREAK_COOLDOWN then return end
	if dir.Magnitude < 0.01 then return end

	local exclude = { animalModel }
	if player.Character then table.insert(exclude, player.Character) end

	-- Catch geometry already touching the mount. Spherecast does not guarantee a
	-- hit when it begins overlapped, which made direct wall impacts feel random.
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	local probeCenter = animalRoot.Position + dir.Unit * 2
	local nearest, nearestDist = nil, math.huge
	for _, part in ipairs(workspace:GetPartBoundsInRadius(probeCenter, VOXEL_SPHERE_RADIUS + 2, overlap)) do
		if isDestroyable(part) and part.Name ~= "Floor" then
			local distance = (part.Position - probeCenter).Magnitude
			if distance < nearestDist then nearest, nearestDist = part, distance end
		end
	end
	if nearest then
		lastVoxelBreak = os.clock()
		requestVoxelBreak(nearest:GetClosestPointOnSurface(probeCenter))
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = workspace:Spherecast(animalRoot.Position, VOXEL_SPHERE_RADIUS, dir.Unit * reach, params)
	if result and isDestroyable(result.Instance) and result.Instance.Name ~= "Floor" then
		lastVoxelBreak = os.clock()
		requestVoxelBreak(result.Position)
	end
end

local function checkVoxelCharge()
	voxelSweep(animalRoot and animalRoot.CFrame.LookVector or Vector3.zero, CHARGE_VOXEL_REACH)
end

local function checkVoxelKnockback()
	if not animalRoot or not animalRoot.Parent then return end
	local vel = animalRoot.AssemblyLinearVelocity
	if vel.Magnitude < 8 then return end
	-- knockback launches you in an upward arc; walls are vertical, so sweep
	-- along the FLAT velocity when there's meaningful horizontal speed -
	-- the old code swept along full velocity and aimed the ray at the sky
	local flat = Vector3.new(vel.X, 0, vel.Z)
	if flat.Magnitude >= 8 then
		voxelSweep(flat, KNOCKBACK_VOXEL_REACH)
	else
		voxelSweep(vel, KNOCKBACK_VOXEL_REACH)
	end
end

-- Other-animal detection

local function getOtherAnimals()
	local results = {}
	for _, child in ipairs(workspace:GetChildren()) do
		if not child:IsA("Model") or child == animalModel then continue end
		for _, p in ipairs(Players:GetPlayers()) do
			if p == player then continue end
			local pfx = p.Name .. "_"
			if child.Name:sub(1, #pfx) == pfx then
				local root = child:FindFirstChild("HumanoidRootPart")
				if root then table.insert(results, { root = root, owner = p, model = child }); break end
			end
		end
	end
	-- enemy bot mounts: tagged AIMount, hit through the same path as players
	for _, mount in ipairs(CollectionService:GetTagged("AIMount")) do
		if mount ~= animalModel and mount.Parent then
			local root  = mount:FindFirstChild("HumanoidRootPart")
			local botId = mount:GetAttribute("BotId")
			if root and botId then
				table.insert(results, { root = root, owner = nil, model = mount, botId = botId })
			end
		end
	end
	return results
end

local function calculateContactPhysics(dt)
	contactPush = Vector3.zero
	if not animalRoot or not animalRoot.Parent then return end
	local myPos = animalRoot.Position
	for _, entry in ipairs(getOtherAnimals()) do
		local diff = Vector3.new(myPos.X - entry.root.Position.X, 0, myPos.Z - entry.root.Position.Z)
		local dist = diff.Magnitude
		if dist < CONTACT_RADIUS and dist > 0.01 then
			local pushDir  = diff.Unit
			local overlap  = CONTACT_RADIUS - dist
			local basePush = overlap * CONTACT_PUSH_FORCE
			local approach = -mountVelocity:Dot(pushDir)
			if approach > 0 then basePush += approach * CONTACT_SPEED_MULTIPLIER end
			contactPush += pushDir * basePush * dt
			if dist < CONTACT_MIN_SEPARATION then
				contactPush += pushDir * (CONTACT_MIN_SEPARATION - dist) * 0.5
			end
		end
	end
end

local function checkChargeCollisions()
	if not animalRoot or not animalRoot.Parent then return end
	checkVoxelCharge()
	local myPos = animalRoot.Position
	local forward = Vector3.new(animalRoot.CFrame.LookVector.X, 0, animalRoot.CFrame.LookVector.Z)
	if forward.Magnitude > 0.01 then forward = forward.Unit end

	local bestEntry, bestDistance = nil, math.huge
	for _, entry in ipairs(getOtherAnimals()) do
		local toTarget = Vector3.new(entry.root.Position.X - myPos.X, 0, entry.root.Position.Z - myPos.Z)
		local distance = toTarget.Magnitude
		if distance > 0.01 and distance < CHARGE_HIT_RADIUS then
			local inPath = distance <= 6 or (forward.Magnitude > 0.01 and forward:Dot(toTarget.Unit) > 0.05)
			if inPath and distance < bestDistance then
				bestEntry, bestDistance = entry, distance
			end
		end
	end

	if bestEntry then
		chargeKnockbackFired = true
		isCharging = false
		CombatRemote:FireServer("knockback", bestEntry.owner or bestEntry.botId)
	end
end

-- Sit animation

local function stopSitAnim()
	if sitAnimTrack then
		pcall(function() sitAnimTrack:Stop(); sitAnimTrack:Destroy() end)
		sitAnimTrack = nil
	end
end

local function playSitAnim()
	stopSitAnim()
	local ch = player.Character; if not ch then return end
	local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator"); if not animator then return end
	local a = Instance.new("Animation"); a.AnimationId = SIT_ANIM_ID
	sitAnimTrack = animator:LoadAnimation(a)
	sitAnimTrack.Priority = Enum.AnimationPriority.Action
	sitAnimTrack.Looped = true; sitAnimTrack:Play(); a:Destroy()
end

-- Public API

function AnimalController.init(animEngine)
	AnimationEngine = animEngine
end

function AnimalController.setInRound(value)
	inRound               = value
	hasReportedOOB        = false
	inPhysicsKnockback    = false
	physicsKnockbackTimer = 0
	knockbackGraceTimer   = 0
	postDashImmunityTimer = 0
	knockbackVoxelFired   = false
	isCharging            = false
	chargeKnockbackFired  = false

	-- invalidate union cache - lazy rescan on next findGroundY call
	mapUnions          = nil
	debugScanPrinted   = false

	if value then
		oobEnableTimer = OOB_ENABLE_DELAY
		local mf = workspace:FindFirstChild("Map")
		if mf then
			local mainF   = mf:FindFirstChild("Main")
			local gameMap = mainF and mainF:FindFirstChild("GameMap")
			floorPart = gameMap and gameMap:FindFirstChild("Floor")
		end
		if DEBUG_GROUND then
			print("[DBG] setInRound(true) — union cache cleared, will lazy-scan on first findGroundY")
		end
	else
		oobEnableTimer = 0; floorPart = nil
	end
end

function AnimalController.isInRound()        return inRound               end
function AnimalController.isMounted()        return currentMode == "mount" end

function AnimalController.getDashDirection()
	local dir = getCameraRelativeDirection()
	if dir.Magnitude > 0.01 then return dir end
	return lastMobileDir
end

function AnimalController.startCharge()
	if currentMode ~= "mount" then return end
	AnimalController.addImpulse(AnimalController.getPlayerForwardDirection(), 60, 0.65)
	isCharging = true; chargeKnockbackFired = false
	task.delay(CHARGE_DURATION, function() isCharging = false end)
end

function AnimalController.startDash(dir, force, duration, immunity)
	if currentMode ~= "mount" then return false end
	if not dir or dir.Magnitude < 0.01 then dir = lastMobileDir end
	AnimalController.addImpulse(dir.Unit, force or 80, duration or 0.55)
	postDashImmunityTimer = math.max(postDashImmunityTimer, immunity or 0.35)
	return true
end

function AnimalController.clearAll()
	if loopConnection then loopConnection:Disconnect(); loopConnection = nil end
	stopSitAnim()
	if animData and currentMode == "mount" then AnimationEngine.reset(animData, animalHumanoid) end
	currentMode = nil; animalModel = nil; animalHumanoid = nil; animalRoot = nil
	animData = nil; impulseActive = false; impulseVelocity = Vector3.zero
	mountVelocity = Vector3.zero; verticalVelocity = 0; contactPush = Vector3.zero
	inPhysicsKnockback = false; physicsKnockbackTimer = 0
	knockbackGraceTimer = 0; postDashImmunityTimer = 0; knockbackVoxelFired = false
	isCharging = false; chargeKnockbackFired = false
	speedBoostMult = 1; speedBoostToken += 1
	abilityMoveMult = 1; abilityMoveToken += 1
	burrowUntil = 0; burrowMoveMult = 1; slideUntil = 0
	leapAirborne = false; leapLandingPose = nil; leapLandingPoseDur = 0.4
	extraRecoveryUntil = 0; extraRecoveryUsed = false
end

function AnimalController.addImpulse(direction, force, duration)
	if not animalRoot or not animalRoot.Parent then return end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then return end
	impulseVelocity = direction.Unit * force; impulseDuration = duration
	impulseElapsed = 0; impulseActive = true
end

-- one recovery dash allowed per knockback, re-armed each time we get launched
local recoveryDashUsed = false

function AnimalController.receivePhysicsKnockback(direction, force, verticalPop)
	if currentMode ~= "mount" then return end
	if postDashImmunityTimer > 0 then return end
	inPhysicsKnockback = true; physicsKnockbackTimer = KNOCKBACK_PHYSICS_DURATION
	knockbackGraceTimer = KNOCKBACK_PHYSICS_DURATION + KNOCKBACK_OOB_GRACE
	knockbackVoxelFired = false; impulseActive = false; impulseVelocity = Vector3.zero
	mountVelocity = Vector3.zero; isCharging = false
	recoveryDashUsed = false
	extraRecoveryUsed = false
	if not direction or not force then return end
	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	if flatDir.Magnitude > 0.01 then flatDir = flatDir.Unit end
	local pop = math.clamp(tonumber(verticalPop) or KB_VERTICAL_POP, 0, 120)
	local vel = Vector3.new(flatDir.X * force * KB_HORIZ_MULT, pop, flatDir.Z * force * KB_HORIZ_MULT)
	if animalRoot and animalRoot.Parent then
		pcall(function()
			animalRoot.AssemblyLinearVelocity  = vel
			animalRoot.AssemblyAngularVelocity = Vector3.new(
				(math.random()-0.5)*10, math.random(12,24)*(math.random()>0.5 and 1 or -1), (math.random()-0.5)*10)
		end)
	end
end

-- RECOVERY DASH: one dash usable mid-knockback. Kills the launch momentum,
-- hands control back to the kinematic drive at the current air height, and
-- dashes toward the input direction. Timed right it saves you from the rim.
function AnimalController.tryRecoveryDash(dir)
	if not inPhysicsKnockback then return false end
	if recoveryDashUsed then
		-- axolotl regenerate grants one extra recovery inside its window
		if os.clock() <= extraRecoveryUntil and not extraRecoveryUsed then
			extraRecoveryUsed = true
		else
			return false
		end
	end
	if currentMode ~= "mount" then return false end
	if not animalRoot or not animalRoot.Parent then return false end
	recoveryDashUsed = true

	-- end the physics phase early and kill the launch momentum
	inPhysicsKnockback = false; physicsKnockbackTimer = 0
	pcall(function()
		animalRoot.AssemblyLinearVelocity  = Vector3.zero
		animalRoot.AssemblyAngularVelocity = Vector3.zero
	end)

	-- resume kinematic control from the current air position - gravity in the
	-- drive loop takes over the fall, the dash impulse carries us sideways.
	-- knockbackGraceTimer keeps ticking, so the OOB grace window still applies
	-- while we try to make it back over the floor
	mountGroundY = animalRoot.Position.Y
	verticalVelocity = 0
	mountVelocity = Vector3.zero

	if not dir or dir.Magnitude < 0.01 then dir = AnimalController.getPlayerForwardDirection() end
	AnimalController.addImpulse(dir, 85, 0.5)
	postDashImmunityTimer = POST_DASH_IMMUNITY
	return true
end

function AnimalController.getModel()         return animalModel        end
function AnimalController.getRoot()          return animalRoot         end
function AnimalController.getHumanoid()      return animalHumanoid     end
function AnimalController.getAnimData()      return animData           end
function AnimalController.getMode()          return currentMode        end
function AnimalController.isImpulseActive()  return impulseActive      end
function AnimalController.getMountVelocity() return mountVelocity      end
function AnimalController.isInKnockback()    return inPhysicsKnockback end

function AnimalController.startFollow(model)
	AnimalController.clearAll()
	animalModel = model; animalHumanoid = model:FindFirstChildOfClass("Humanoid")
	animalRoot  = model:FindFirstChild("HumanoidRootPart"); currentMode = "follow"
	animData = nil; contactPush = Vector3.zero
end

function AnimalController.startMount(model)
	AnimalController.clearAll()
	if not model or not model.Parent then
		task.spawn(function()
			local deadline = tick() + 12
			while tick() < deadline do
				task.wait(0.1)
				if model and model.Parent then AnimalController.startMount(model); return end
			end
			warn("[AnimalController] startMount: model never replicated after 12s")
		end)
		return
	end

	animalModel = model; animalHumanoid = model:FindFirstChildOfClass("Humanoid")
	animalRoot  = model:FindFirstChild("HumanoidRootPart")
	if not animalHumanoid or not animalRoot then return end

	currentMode = "mount"; inPhysicsKnockback = false; physicsKnockbackTimer = 0
	knockbackGraceTimer = 0; postDashImmunityTimer = 0; knockbackVoxelFired = false
	mountVelocity = Vector3.zero; verticalVelocity = 0; contactPush = Vector3.zero
	isCharging = false; chargeKnockbackFired = false

	if DEBUG_GROUND then
		print("[DBG] startMount called — animData will be set up, then findGroundY fires")
	end

	playSitAnim(); task.wait(0.1)
	if animalModel ~= model or not model.Parent then return end

	animData = AnimationEngine.setup(model, animalHumanoid, animalRoot)
	if animData and #animData.joints == 0 then
		warn("[AnimalController] No joints — retrying after 0.3s")
		task.wait(0.3)
		if animalModel ~= model or not model.Parent then return end
		animData = AnimationEngine.setup(model, animalHumanoid, animalRoot)
	end

	if DEBUG_GROUND and animData then
		print(string.format("[DBG] animData.hrpToGround = %.3f", animData.hrpToGround))
	end

	local ig = findGroundY(animalRoot.Position)
	mountGroundY = ig or animalRoot.Position.Y

	if DEBUG_GROUND then
		print(string.format("[DBG] Initial mountGroundY=%.2f  animalRoot.Y=%.2f  (gap=%.2f)",
			mountGroundY, animalRoot.Position.Y, animalRoot.Position.Y - mountGroundY))
	end

	loopConnection = RunService.Heartbeat:Connect(function(dt)
		if not animalRoot or not animalRoot.Parent or not animalHumanoid or not animalHumanoid.Parent then
			AnimalController.clearAll(); return
		end

		if oobEnableTimer      > 0 then oobEnableTimer      = math.max(0, oobEnableTimer - dt)      end
		if knockbackGraceTimer > 0 then knockbackGraceTimer = math.max(0, knockbackGraceTimer - dt) end
		if postDashImmunityTimer > 0 then postDashImmunityTimer = math.max(0, postDashImmunityTimer - dt) end

		if inRound and not hasReportedOOB and oobEnableTimer <= 0
			and knockbackGraceTimer <= 0 and not inPhysicsKnockback then
			if not isPositionInFloorBounds(animalRoot.Position) then
				hasReportedOOB = true; EliminationRemote:FireServer("outOfBounds")
			end
		end

		if inPhysicsKnockback then
			physicsKnockbackTimer -= dt; checkVoxelKnockback()
			if physicsKnockbackTimer <= 0 then
				inPhysicsKnockback = false; knockbackVoxelFired = false
				local gy = findGroundY(animalRoot.Position)
				mountGroundY = gy or animalRoot.Position.Y; verticalVelocity = 0; mountVelocity = Vector3.zero
			end
			AnimationEngine.update(animData, animalHumanoid, dt, false, 0, MOUNT.topSpeed); return
		end

		if isCharging and not chargeKnockbackFired then checkChargeCollisions() end

		local impulseThisFrame = Vector3.zero
		if impulseActive then
			impulseElapsed += dt
			if impulseElapsed >= impulseDuration then
				impulseActive = false; impulseVelocity = Vector3.zero
			else
				impulseThisFrame = impulseVelocity * (1 - impulseElapsed / impulseDuration) * dt
			end
		end

		calculateContactPhysics(dt)

		local inputDir   = getCameraRelativeDirection()
		local controlMul = impulseActive and 0.2 or 1
		-- belly slide keeps momentum with weak steering
		if os.clock() < slideUntil then controlMul = math.min(controlMul, 0.35) end

		-- gallop boosts, burrow crawls
		local effectiveTop = MOUNT.topSpeed * speedBoostMult * abilityMoveMult
		if os.clock() < burrowUntil then effectiveTop = effectiveTop * burrowMoveMult end

		if inputDir.Magnitude > 0.01 then
			mountVelocity = mountVelocity:Lerp(inputDir * effectiveTop * controlMul,
				math.min(dt * MOUNT.acceleration / MOUNT.topSpeed, 1))
		else
			mountVelocity = mountVelocity:Lerp(Vector3.zero, math.min(dt * MOUNT.friction, 1))
		end

		local yaw = getCameraYaw()
		local hm  = mountVelocity * dt + impulseThisFrame + contactPush
		local cp  = animalRoot.Position
		local nxz = Vector3.new(cp.X + hm.X, cp.Y, cp.Z + hm.Z)
		local gy  = findGroundY(nxz)

		if gy then
			local heightAboveGround = cp.Y - gy
			if verticalVelocity > 0 then
				-- ascending from a leap: never snap to ground mid-jump
				verticalVelocity = verticalVelocity - GRAVITY * dt
				mountGroundY     = mountGroundY + verticalVelocity * dt
				if verticalVelocity <= 0 and mountGroundY <= gy then
					mountGroundY = gy; verticalVelocity = 0
				end
			elseif heightAboveGround <= 0.5 or (verticalVelocity <= 0 and heightAboveGround < 2) then
				mountGroundY = gy; verticalVelocity = 0
			else
				verticalVelocity = math.max(verticalVelocity - GRAVITY * dt, -TERMINAL_VELOCITY)
				mountGroundY     = mountGroundY + verticalVelocity * dt
				if mountGroundY <= gy then mountGroundY = gy; verticalVelocity = 0 end
			end
		else
			verticalVelocity = math.max(verticalVelocity - GRAVITY * dt, -TERMINAL_VELOCITY)
			mountGroundY     = mountGroundY + verticalVelocity * dt
		end

		-- leap landing: tell the server so splash abilities resolve there
		if leapAirborne and verticalVelocity == 0 and gy and (mountGroundY - gy) < 0.6 then
			leapAirborne = false
			if leapLandingPose and animData and AnimationEngine.setPose then
				AnimationEngine.setPose(animData, leapLandingPose, leapLandingPoseDur)
			end
			leapLandingPose = nil
			CombatRemote:FireServer("abilityLand")
		end

		-- burrow sinks the mount visually while active
		local visualY = mountGroundY
		if os.clock() < burrowUntil then visualY = visualY - 2.2 end

		local newCF = CFrame.new(Vector3.new(nxz.X, visualY, nxz.Z)) * CFrame.Angles(0, yaw, 0)
		pcall(function()
			animalRoot.AssemblyLinearVelocity = Vector3.zero
			animalRoot.AssemblyAngularVelocity = Vector3.zero
		end)
		animalRoot.CFrame = newCF

		local spd = mountVelocity.Magnitude
		if impulseActive then
			spd = math.max(spd, impulseVelocity.Magnitude * (1 - impulseElapsed / impulseDuration))
		end

		AnimationEngine.update(animData, animalHumanoid, dt, spd > 0.5, spd, MOUNT.topSpeed)
	end)
end

-- ability movement api, called by AbilityController per the equipped animal

function AnimalController.getAnimalName()
	if not animalModel then return nil end
	local attributed = animalModel:GetAttribute("AnimalName")
	if typeof(attributed) == "string" and attributed ~= "" then return attributed end
	local configured = require(ReplicatedStorage.Modules.AbilityConfig).resolveAnimalName(animalModel.Name)
	return configured or animalModel.Name
end

function AnimalController.performLeap(vert, horiz, landingPose, landingPoseDuration)
	if currentMode ~= "mount" or inPhysicsKnockback then return false end
	if not animalRoot or not animalRoot.Parent then return false end
	verticalVelocity = vert or 60
	leapAirborne = true
	leapLandingPose = landingPose
	leapLandingPoseDur = landingPoseDuration or 0.4
	if horiz and horiz > 4 then
		local dir = AnimalController.getDashDirection()
		if not dir or dir.Magnitude < 0.01 then dir = AnimalController.getPlayerForwardDirection() end
		AnimalController.addImpulse(dir, horiz, 0.5)
	end
	return true
end

function AnimalController.performBlink(dist)
	if currentMode ~= "mount" or inPhysicsKnockback then return false end
	if not animalRoot or not animalRoot.Parent then return false end
	local look = animalRoot.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then return false end
	flat = flat.Unit
	-- step back if the full distance would put us outside the floor
	local cp = animalRoot.Position
	for _, frac in ipairs({ 1, 0.7, 0.45, 0.25 }) do
		local target = cp + flat * (dist * frac)
		if isPositionInFloorBounds(target) then
			local gy = findGroundY(target)
			local y = gy or cp.Y
			mountGroundY = y
			verticalVelocity = 0
			animalRoot.CFrame = CFrame.new(Vector3.new(target.X, y, target.Z)) * CFrame.Angles(0, getCameraYaw(), 0)
			return true
		end
	end
	return false
end

function AnimalController.performSpeedBoost(mult, dur)
	if currentMode ~= "mount" then return false end
	speedBoostMult = mult or 1.4
	speedBoostToken += 1
	local token = speedBoostToken
	task.delay(dur or 3, function()
		if speedBoostToken == token then speedBoostMult = 1 end
	end)
	return true
end

function AnimalController.performSlide(force, dur)
	if currentMode ~= "mount" or inPhysicsKnockback then return false end
	local dir = AnimalController.getDashDirection()
	if not dir or dir.Magnitude < 0.01 then dir = AnimalController.getPlayerForwardDirection() end
	AnimalController.addImpulse(dir, force or 70, dur or 1.1)
	slideUntil = os.clock() + (dur or 1.1)
	postDashImmunityTimer = math.max(postDashImmunityTimer, 0.3)
	return true
end

function AnimalController.performGuard(dur, canMove, moveMult)
	if currentMode ~= "mount" or inPhysicsKnockback then return false end
	abilityMoveToken += 1
	local token = abilityMoveToken
	abilityMoveMult = canMove == false and 0 or (moveMult or 1)
	if abilityMoveMult <= 0 then mountVelocity = Vector3.zero end
	task.delay(dur or 1, function()
		if abilityMoveToken == token then abilityMoveMult = 1 end
	end)
	return true
end

function AnimalController.performBurrow(dur, moveMult)
	if currentMode ~= "mount" or inPhysicsKnockback then return false end
	burrowUntil = os.clock() + (dur or 1.2)
	burrowMoveMult = moveMult or 0.4
	return true
end

function AnimalController.grantExtraRecovery(window)
	extraRecoveryUntil = os.clock() + (window or 5)
	extraRecoveryUsed = false
	return true
end

return AnimalController

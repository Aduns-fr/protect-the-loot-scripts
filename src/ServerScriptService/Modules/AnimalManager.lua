--[[
    AnimalManager (ModuleScript - ServerScriptService.Modules)

    RAYCAST FIX v2: Two-pass ground detection in the follow loop.
      Pass 1 - excludes all UnionOperation parts. Unions with Box collision
               fidelity have bounding boxes that extend beyond the visual mesh,
               causing the ray to hit above the actual geometry (floating).
               Excluding them lets the ray fall through to the wedge plates.
      Pass 2 - fallback including unions, for areas where a union is the only
               floor geometry.
      Pick logic: closest-to-expected-floor-Y instead of highest, so an offset
      sample hitting a neighboring higher plate doesn't cause incorrect snapping.
]]

local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local RemoteEvents  = ReplicatedStorage:WaitForChild("RemoteEvents")
local MountRemote   = RemoteEvents:WaitForChild("MountRemote")
local CombatRemote  = RemoteEvents:WaitForChild("CombatRemote")
local Animals       = ServerStorage:WaitForChild("Animals")

local AnimalConfig    = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimalConfig"))
local AnimationEngine = require(script.Parent:WaitForChild("AnimationEngine"))

local AnimalManager = {}

local playerAnimals    = {}
local lastSpawnTime    = {}
local SPAWN_RATE_LIMIT = 0.5

local FOLLOW_POS_LERP     = 12
local FOLLOW_ROT_LERP     = 10
local FOLLOW_GROUND_LERP  = 9
local FOLLOW_TELEPORT     = 40
local FOLLOW_OFFSET_BACK  = 5
local FOLLOW_OFFSET_RIGHT = 2.5
local FOLLOW_MIN_MOVE     = 0.08

local WRITE_POS_THRESH = 0.06
local WRITE_ROT_THRESH = 0.015

local KB_VERTICAL_POP   = 45
local KB_HORIZ_MULT     = 1.4
local KB_OWNERSHIP_HOLD = 1.2

local lastCollisionEffect       = {}
local COLLISION_EFFECT_COOLDOWN = 0.4

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

-- MapVotingManager reuses the GameMap folder and replaces its contents, so the
-- floor instance is the reliable generation marker for this cache.
local cachedUnionList   = nil
local cachedGameMapRef  = nil
local cachedFloorRef    = nil

local function getGameMapFolder()
	local mf   = workspace:FindFirstChild("Map")
	local main = mf and mf:FindFirstChild("Main")
	return main and main:FindFirstChild("GameMap")
end

local function getCurrentFloor()
	local gm = getGameMapFolder()
	return gm and gm:FindFirstChild("Floor")
end

-- Returns a list of all UnionOperation parts in the current GameMap, cached
-- until either the map folder or its floor instance changes.
local function getMapUnions()
	local gameMap = getGameMapFolder()
	if not gameMap then
		cachedUnionList  = {}
		cachedGameMapRef = nil
		cachedFloorRef   = nil
		return {}
	end

	local floor = gameMap:FindFirstChild("Floor")
	if gameMap == cachedGameMapRef and floor == cachedFloorRef and cachedUnionList then
		return cachedUnionList
	end

	cachedGameMapRef = gameMap
	cachedFloorRef   = floor
	cachedUnionList  = {}
	for _, desc in gameMap:GetDescendants() do
		if desc:IsA("UnionOperation") then
			table.insert(cachedUnionList, desc)
		end
	end
	return cachedUnionList
end

-- Two-pass raycast returning raw hit Y (caller adds hrpToGround).
-- Pass 1 excludes unions so the ray can reach the actual wedge-plate geometry.
-- Pass 2 falls back to including unions for union-only floor areas.
local function sampleGroundHitY(targetXZ, currentY, baseExclude)
	local expectedFloorY = currentY  -- caller has already subtracted hrpToGround if needed

	-- Build pass-1 exclude list: base (model + character) + all map unions
	local unions = getMapUnions()
	local excludePass1 = { table.unpack(baseExclude) }
	for _, u in unions do
		table.insert(excludePass1, u)
	end

	local pass1Params = RaycastParams.new()
	pass1Params.FilterType = Enum.RaycastFilterType.Exclude
	pass1Params.FilterDescendantsInstances = excludePass1

	local bestHitY    = nil
	local bestHitDist = math.huge

	for _, off in SAMPLE_OFFSETS do
		local origin = Vector3.new(
			targetXZ.X + off.X,
			currentY + RAY_START_ABOVE,
			targetXZ.Z + off.Z
		)
		local res = workspace:Raycast(origin, Vector3.new(0, -RAY_LENGTH, 0), pass1Params)
		if res and res.Normal.Y >= MIN_NORMAL_Y then
			local dist = math.abs(res.Position.Y - expectedFloorY)
			if dist < bestHitDist then
				bestHitDist = dist
				bestHitY    = res.Position.Y
			end
		end
	end

	if bestHitY then return bestHitY end

	-- Pass 2: include unions as last resort
	local pass2Params = RaycastParams.new()
	pass2Params.FilterType = Enum.RaycastFilterType.Exclude
	pass2Params.FilterDescendantsInstances = baseExclude

	local res = workspace:Raycast(
		Vector3.new(targetXZ.X, currentY + RAY_START_ABOVE, targetXZ.Z),
		Vector3.new(0, -RAY_LENGTH, 0),
		pass2Params
	)
	return res and res.Position.Y or nil
end

local function newSessionToken()
	return tostring(math.random(1, 2147483647))
end

local function prepareJoints(model)
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local toConvert = {}
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then
			table.insert(toConvert, d)
		end
	end
	for _, joint in toConvert do
		local partA, partB, offsetA, offsetB
		if joint:IsA("WeldConstraint") then
			partA, partB = joint.Part0, joint.Part1
			if not partA or not partB then joint:Destroy(); continue end
			if partB == rootPart then partA, partB = partB, partA end
			offsetA = partA.CFrame:ToObjectSpace(partB.CFrame)
			offsetB = CFrame.new()
		else
			partA, partB = joint.Part0, joint.Part1
			if not partA or not partB then joint:Destroy(); continue end
			offsetA, offsetB = joint.C0, joint.C1
		end
		local m   = Instance.new("Motor6D")
		m.Name    = partB.Name .. "_Joint"
		m.Part0   = partA; m.Part1   = partB
		m.C0      = offsetA; m.C1   = offsetB
		m.Parent  = partA
		joint:Destroy()
	end
end

local function assignNetworkOwnership(model, targetPlayer)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(function() part:SetNetworkOwner(targetPlayer) end)
		end
	end
end

local function zeroVelocities(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			pcall(function()
				part.AssemblyLinearVelocity  = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end
end

local function lerpAngle(a, b, t)
	local diff = math.atan2(math.sin(b - a), math.cos(b - a))
	return a + diff * t
end

local function startFollowLoop(player, data)
	local animalHumanoid = data.animalHumanoid
	local animalRoot     = data.model:FindFirstChild("HumanoidRootPart")
	if not animalRoot then return end

	animalRoot.Anchored = true

	local currentCF     = animalRoot.CFrame
	local currentYaw    = select(2, currentCF:ToEulerAnglesYXZ())
	local smoothGroundY = currentCF.Position.Y
	local lastTick      = tick()

	local lastWritePos = currentCF.Position
	local lastWriteYaw = currentYaw

	data.stopFollow = false

	data.followThread = task.spawn(function()
		while not data.stopFollow
			and data.mode == "follow"
			and data.model
			and data.model.Parent do

			local now = tick()
			local dt  = math.min(now - lastTick, 0.1)
			lastTick  = now

			local character = player.Character
			if not character then task.wait(); continue end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then task.wait(); continue end

			animalRoot = data.model:FindFirstChild("HumanoidRootPart")
			if not animalRoot then break end

			local look  = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
			local right = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z)
			if look.Magnitude  > 0.01 then look  = look.Unit  end
			if right.Magnitude > 0.01 then right = right.Unit end

			local flatTarget = hrp.Position
			- look  * FOLLOW_OFFSET_BACK
				+ right * FOLLOW_OFFSET_RIGHT

			local hrpToGround = (data.animData and data.animData.hrpToGround) or 3

			local baseExclude = { data.model, character }
			-- Pass expected floor Y so sampleGroundHitY can pick closest-to-expected
			local expectedY = currentCF.Position.Y - hrpToGround
			local hitY      = sampleGroundHitY(flatTarget, expectedY, baseExclude)
			local rawGroundY = hitY and (hitY + hrpToGround) or smoothGroundY
			smoothGroundY    = smoothGroundY + (rawGroundY - smoothGroundY) * math.min(dt * FOLLOW_GROUND_LERP, 1)

			local targetPos = Vector3.new(flatTarget.X, smoothGroundY, flatTarget.Z)

			if (currentCF.Position - targetPos).Magnitude > FOLLOW_TELEPORT then
				currentYaw    = select(2, hrp.CFrame:ToEulerAnglesYXZ())
				smoothGroundY = rawGroundY
				currentCF     = CFrame.new(targetPos) * CFrame.Angles(0, currentYaw, 0)
				animalRoot.CFrame = currentCF
				lastWritePos  = currentCF.Position
				lastWriteYaw  = currentYaw
				if data.animData and animalHumanoid and animalHumanoid.Parent then
					AnimationEngine.update(data.animData, animalHumanoid, dt, false, 0, 40)
				end
				task.wait()
				continue
			end

			local newPos    = currentCF.Position:Lerp(targetPos, math.min(dt * FOLLOW_POS_LERP, 1))
			local moveVec   = Vector3.new(targetPos.X - currentCF.Position.X, 0, targetPos.Z - currentCF.Position.Z)
			local isMoving  = moveVec.Magnitude > FOLLOW_MIN_MOVE
			local moveSpeed = moveVec.Magnitude / math.max(dt, 0.001)

			local targetAngle = isMoving
				and math.atan2(-moveVec.X, -moveVec.Z)
				or select(2, hrp.CFrame:ToEulerAnglesYXZ())

			currentYaw = lerpAngle(currentYaw, targetAngle, math.min(dt * FOLLOW_ROT_LERP, 1))
			currentCF  = CFrame.new(newPos) * CFrame.Angles(0, currentYaw, 0)

			local posDelta = (currentCF.Position - lastWritePos).Magnitude
			local rotDelta = math.abs(currentYaw - lastWriteYaw)
			if posDelta >= WRITE_POS_THRESH or rotDelta >= WRITE_ROT_THRESH then
				animalRoot.CFrame = currentCF
				lastWritePos      = currentCF.Position
				lastWriteYaw      = currentYaw
			end

			if data.animData and animalHumanoid and animalHumanoid.Parent then
				AnimationEngine.update(data.animData, animalHumanoid, dt, isMoving, math.clamp(moveSpeed, 0, 40), 40)
			end

			task.wait()
		end
	end)
end

local function stopFollowLoop(data)
	if not data then return end
	data.stopFollow   = true
	data.followThread = nil
end

local function playCollisionSound()
	local sfx = SoundService:FindFirstChild("SFX")
	if not sfx then return end
	local bonkFolder = sfx:FindFirstChild("Bonk")
	if not bonkFolder then return end
	local sounds = {}
	for _, s in ipairs(bonkFolder:GetChildren()) do
		if s:IsA("Sound") then table.insert(sounds, s) end
	end
	if #sounds == 0 then return end
	local clone = sounds[math.random(#sounds)]:Clone()
	clone.Parent = workspace
	clone:Play()
	Debris:AddItem(clone, 3)
end

local function spawnCollisionVFX(victimAnimal)
	local vfxFolder = ServerStorage:FindFirstChild("VFX")
	if not vfxFolder then return end
	local collideFolder = vfxFolder:FindFirstChild("Collide")
	if not collideFolder then return end
	local attachments = {}
	for _, att in ipairs(collideFolder:GetChildren()) do
		if att:IsA("Attachment") and att.Name:match("^Bonk%d+$") then
			table.insert(attachments, att)
		end
	end
	if #attachments == 0 then return end
	local head = victimAnimal:FindFirstChild("Head")
	if not head then return end
	local clone = attachments[math.random(#attachments)]:Clone()
	clone.Parent = head
	Debris:AddItem(clone, 1.5)
end

function AnimalManager.playCollisionFeedback(victimAnimal, cooldownKey)
	if not victimAnimal or not victimAnimal.Parent then return end
	local key = cooldownKey or victimAnimal
	local now = tick()
	if lastCollisionEffect[key] and (now - lastCollisionEffect[key]) < COLLISION_EFFECT_COOLDOWN then return end
	lastCollisionEffect[key] = now
	playCollisionSound()
	spawnCollisionVFX(victimAnimal)
end

-- CombatManager supplies a 0..1 knockback multiplier for active guards.
local defenseProvider = nil
function AnimalManager.setDefenseProvider(fn)
	defenseProvider = fn
end

function AnimalManager.applyPhysicsKnockback(victimPlayer, direction, force, verticalPop)
	local data = playerAnimals[victimPlayer]
	if not data or data.mode ~= "mount" then return end
	local model      = data.model
	local animalRoot = model:FindFirstChild("HumanoidRootPart")
	if not animalRoot then return end

	-- ability guards reduce or fully block the hit
	if defenseProvider then
		local ok, scale = pcall(defenseProvider, victimPlayer)
		if ok and type(scale) == "number" then
			if scale <= 0.05 then return end
			force = force * scale
		end
	end

	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	if flatDir.Magnitude < 0.01 then return end
	flatDir = flatDir.Unit

	local floor = getCurrentFloor()
	if floor then
		local fromCenter = Vector3.new(
			animalRoot.Position.X - floor.Position.X,
			0,
			animalRoot.Position.Z - floor.Position.Z
		)
		local halfWidth      = floor.Size.X * 0.5
		local distFromCenter = fromCenter.Magnitude
		if distFromCenter > 2 then
			local awayDir  = fromCenter.Unit
			local edgeFrac = math.clamp(distFromCenter / halfWidth, 0, 1)
			local nudge    = edgeFrac * 0.25
			flatDir = (flatDir * (1 - nudge) + awayDir * nudge).Unit
		end
	end

	assignNetworkOwnership(model, victimPlayer)
	CombatRemote:FireClient(victimPlayer, "physicsKnockback", flatDir, force, verticalPop)

	AnimalManager.playCollisionFeedback(model, victimPlayer)

	local modelAtKnockback = model
	task.delay(KB_OWNERSHIP_HOLD, function()
		local stillData = playerAnimals[victimPlayer]
		if stillData and stillData.mode == "mount" and stillData.model == modelAtKnockback then
			assignNetworkOwnership(model, victimPlayer)
		end
	end)
end

function AnimalManager.cleanup(player)
	local data = playerAnimals[player]
	if not data then return end
	local token = data.sessionToken
	playerAnimals[player]         = nil
	lastCollisionEffect[player]   = nil
	lastSpawnTime[player]         = nil

	stopFollowLoop(data)
	for _, conn in data.connections do conn:Disconnect() end

	if data.riderWeld and data.riderWeld.Parent then data.riderWeld:Destroy() end
	if data.animData and data.animalHumanoid and data.animalHumanoid.Parent then
		AnimationEngine.reset(data.animData, data.animalHumanoid)
	end
	if data.model and data.model.Parent then data.model:Destroy() end

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local hrp      = character:FindFirstChild("HumanoidRootPart")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid.AutoRotate    = true
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
		if hrp then hrp.Anchored = false end
	end

	MountRemote:FireClient(player, "clear", nil, token)
end

function AnimalManager.getAnimalData(player)   return playerAnimals[player]        end
function AnimalManager.hasAnimal(player)        return playerAnimals[player] ~= nil end
function AnimalManager.getAnimalName(player)
	local data = playerAnimals[player]
	return data and data.name or nil
end

function AnimalManager.getDefaultAnimalName()
	local defaults = AnimalConfig.getDefaultAnimals()
	return defaults[1] or "Snail"
end

function AnimalManager.spawnAnimal(player, animalName, requestedMode)
	local now = tick()
	if lastSpawnTime[player] and (now - lastSpawnTime[player]) < SPAWN_RATE_LIMIT then return end
	lastSpawnTime[player] = now

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp      = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or humanoid.Health <= 0 then return end

	if not AnimalConfig.exists(animalName) then
		warn("[AnimalManager] Unknown animal:", animalName); return
	end

	if playerAnimals[player] then
		local prev = playerAnimals[player]
		if prev.name == animalName and prev.mode == requestedMode then return end
		AnimalManager.cleanup(player)
	end

	local cfg      = AnimalConfig.getConfig(animalName)
	local template = cfg and cfg.ModelName and Animals:FindFirstChild(cfg.ModelName)
		or Animals:FindFirstChild(animalName)
	if not template then
		warn("[AnimalManager] No model for:", animalName); return
	end

	local model          = template:Clone()
	model.Name           = player.Name .. "_" .. animalName
	model:SetAttribute("AnimalName", animalName)
	local animalRoot     = model:FindFirstChild("HumanoidRootPart")
	local animalHumanoid = model:FindFirstChildOfClass("Humanoid")
	if not animalRoot or not animalHumanoid then model:Destroy(); return end

	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then seat:Destroy() end
	end

	model.PrimaryPart                         = animalRoot
	animalHumanoid.DisplayDistanceType        = Enum.HumanoidDisplayDistanceType.None
	animalHumanoid.RequiresNeck               = false
	animalHumanoid.BreakJointsOnDeath         = false
	animalHumanoid.MaxHealth                  = 1e9
	animalHumanoid.Health                     = 1e9
	animalHumanoid.PlatformStand              = true
	animalRoot.Anchored                       = requestedMode ~= "mount"

	if requestedMode == "mount" then
		local sh = animalRoot.Size.Y * 0.5 + hrp.Size.Y * 0.5 + 0.1
		model:PivotTo(hrp.CFrame * CFrame.new(0, -sh, 0))
	else
		model:PivotTo(hrp.CFrame * CFrame.new(4, 0, 4))
	end

	model.Parent = workspace
	prepareJoints(model)

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then part.CollisionGroup = "Animals" end
	end
	zeroVelocities(model)

	local animData = nil
	if requestedMode == "follow" then
		animData = AnimationEngine.setup(model, animalHumanoid, animalRoot)
		if animData and cfg then animData.hrpToGround = cfg.HRPToGround end
	end

	local connections = {}
	local riderWeld   = nil

	if requestedMode == "mount" then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		riderWeld = AnimalManager._createRiderWeld(animalRoot, hrp)
		assignNetworkOwnership(model, player)
	else
		humanoid.PlatformStand = false
		humanoid.AutoRotate    = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	local token = newSessionToken()
	playerAnimals[player] = {
		name           = animalName,
		mode           = requestedMode,
		model          = model,
		animalHumanoid = animalHumanoid,
		connections    = connections,
		riderWeld      = riderWeld,
		animData       = animData,
		followThread   = nil,
		stopFollow     = false,
		sessionToken   = token,
	}

	if requestedMode == "follow" then
		startFollowLoop(player, playerAnimals[player])
	end

	MountRemote:FireClient(player, requestedMode, model, token)
end

function AnimalManager.switchMode(player, newMode)
	local data = playerAnimals[player]
	if not data or data.mode == newMode then return end

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp      = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then return end

	local animalRoot = data.model:FindFirstChild("HumanoidRootPart")
	if not animalRoot then return end

	data.mode = newMode
	stopFollowLoop(data)

	if data.riderWeld and data.riderWeld.Parent then
		data.riderWeld:Destroy(); data.riderWeld = nil
	end
	if data.animData then
		AnimationEngine.reset(data.animData, data.animalHumanoid)
	end

	local newToken    = newSessionToken()
	data.sessionToken = newToken

	if newMode == "mount" then
		animalRoot.Anchored = false
		zeroVelocities(data.model)
		pcall(function()
			hrp.AssemblyLinearVelocity  = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end)
		local sh = animalRoot.Size.Y * 0.5 + hrp.Size.Y * 0.5 + 0.1
		animalRoot.CFrame = hrp.CFrame * CFrame.new(0, -sh, 0)
		assignNetworkOwnership(data.model, player)
		data.animData  = nil
		data.riderWeld = AnimalManager._createRiderWeld(animalRoot, hrp)
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		data.animalHumanoid.PlatformStand = true
	else
		assignNetworkOwnership(data.model, nil)
		zeroVelocities(data.model)
		if not data.animData then
			data.animData = AnimationEngine.setup(data.model, data.animalHumanoid, animalRoot)
			local config  = AnimalConfig.getConfig(data.name)
			if data.animData and config then
				data.animData.hrpToGround = config.HRPToGround
			end
		end
		humanoid.PlatformStand = false
		humanoid.AutoRotate    = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		data.animalHumanoid.PlatformStand = true
		animalRoot.Anchored = true
		zeroVelocities(data.model)
		startFollowLoop(player, data)
	end

	MountRemote:FireClient(player, newMode, data.model, newToken)
end

function AnimalManager._createRiderWeld(animalRoot, playerRoot)
	local sh = animalRoot.Size.Y * 0.5 + playerRoot.Size.Y * 0.5 + 0.1
	local w  = Instance.new("Weld")
	w.Name   = "RiderWeld"
	w.Part0  = animalRoot
	w.Part1  = playerRoot
	w.C0     = CFrame.new(0, sh, 0)
	w.Parent = animalRoot
	return w
end

return AnimalManager

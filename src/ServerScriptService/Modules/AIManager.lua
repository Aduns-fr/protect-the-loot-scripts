--[[
	AIManager v2 (ModuleScript - ServerScriptService.Modules)

	Server-driven enemy bots built like real mounted players: random animal mount,
	rider rig welded on top, posed by AnimationEngine, driven kinematically.

	WHY v2 EXISTS — design goals:
	1. POPULATION SCALING. Bots exist to fill thin servers, not to crowd full ones.
	   1 real fighter  -> 3 bots
	   2 real fighters -> 2 bots
	   3 real fighters -> 1 bot
	   4+ real fighters -> 0 bots (pure PvP)
	   Recomputed live every couple seconds. When humans join mid-round, the bot
	   farthest from the action quietly leaves. When humans leave, bots refill.
	   Empty arena + people in lobby -> bots brawl each other as a draw-in.
	2. HUMAN FEEL. Per-bot personality (Brawler / Slick / Stalker), per-bot skill
	   scalar, reaction delays, aim error on charges, occasional whiffs, retreat
	   after attacking, dodges that feel earned. No laser-aim, no instant reactions.
	3. CLEAN CREDIT. Bot->player and player->bot kill credit both flow through
	   RoundManager with timestamps and windows, so the elim feed is accurate.

	Wiring (GameServer): AIManager.init(PlayerManager, AnimalManager, RoundManager)
	then RoundManager.setAIManager + CombatManager.setAIManager.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")

local Modules         = script.Parent
local AnimationEngine = require(Modules:WaitForChild("AnimationEngine"))
local VoxelManager    = require(Modules:WaitForChild("VoxelManager"))
local AnimalConfig    = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AnimalConfig"))
local AbilityConfig   = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AbilityConfig"))
local AbilityRemote   = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("AbilityRemote")

local RIG_TEMPLATE = ReplicatedStorage:FindFirstChild("Rig")
local ANIMALS      = ServerStorage:FindFirstChild("Animals")
local HEAD_TAG     = ServerStorage:FindFirstChild("Head")  -- name billboard
local ELIM_TAG     = ServerStorage:FindFirstChild("Elim")  -- elim count billboard

local BOT_TAG = "AIMount"
local rng = Random.new()

-- Mount physics, mirrors AnimalController so bots move/feel like players
local MOUNT_TOP_SPEED   = 40
local MOUNT_ACCEL       = 60
local MOUNT_FRICTION    = 12
local GRAVITY           = 150
local TERMINAL_VELOCITY = 250
local SIT_ANIM_ID       = "rbxassetid://119560872496377"

local CHARGE_HIT_RADIUS    = 8
local CHARGE_DURATION      = 0.62
local CHARGE_WINDUP_MIN    = 0.32
local CHARGE_WINDUP_MAX    = 0.48
local CHARGE_IMPULSE       = 48
local CHARGE_IMPULSE_TIME  = 0.52
local DASH_IMPULSE         = 64
local DASH_IMPULSE_TIME    = 0.45
local POST_DASH_IMMUNITY   = 0.55
local BOT_KNOCKBACK_FORCE  = 82     -- slightly under the player's 105 — bots hit a touch softer

local KB_HORIZ_MULT              = 1.6
local KB_VERTICAL_POP            = 42
local KNOCKBACK_PHYSICS_DURATION = 1.15
local KNOCK_GUARD                = 0.4
local HIT_FORWARD_DOT            = 0.48
local HIT_LATERAL_RADIUS         = 5.5

-- Ground sampling
local RAY_START_ABOVE = 200
local RAY_LENGTH      = 600
local MIN_NORMAL_Y    = 0.2
local SAMPLE_OFFSETS  = {
	Vector3.new( 0,   0,  0  ),
	Vector3.new( 0.5, 0,  0  ),
	Vector3.new(-0.5, 0,  0  ),
	Vector3.new( 0,   0,  0.5),
	Vector3.new( 0,   0, -0.5),
}

-- Population scaling
local TARGET_FILL     = 4     -- total combatants the arena should feel like it has
local MAX_AI          = 3     -- hard cap on bots
local POP_INTERVAL    = 1.5   -- how often we recompute the desired bot count
local RESPAWN_DELAY   = 4
local SPAWN_GRACE     = 2.5
local MIN_SPAWN_DIST  = 25    -- never spawn a bot on top of a player

-- Brain timing
local BEHAVIOR_TICK          = 0.15
local RETARGET_INTERVAL      = 1.1
local GROUND_SAMPLE_INTERVAL = 0.05
local KILL_CREDIT_WINDOW = 5
local STUCK_DIST         = 2.0
local STUCK_TIME         = 1.05
local EDGE_MARGIN        = 18
local RAM_SPEED          = 32
local RAM_COOLDOWN       = 0.8

-- Personality definitions. Each bot rolls one at spawn, plus a skill scalar
-- (0.75..1.1) that scales reaction speed, aim, and dodge ability. Two bots with
-- the same personality still play differently because of skill variance.
local PERSONALITIES = {
	Brawler = {
		-- gets in your face, charges often, doesn't retreat
		awareness     = 90,
		chargeCooldown = 4.2,
		chargeTrigger  = 14,
		chargeChance   = 0.68,
		dodgeChance    = 0.18,
		spacing        = 7,
		retreatAfterHit = false,
		reaction       = 0.65,
		aimErrorDeg    = 9,
	},
	Slick = {
		-- cautious counter-puncher: keeps distance, dodges a lot, picks moments
		awareness     = 80,
		chargeCooldown = 5.5,
		chargeTrigger  = 12,
		chargeChance   = 0.52,
		dodgeChance    = 0.45,
		spacing        = 12,
		retreatAfterHit = true,
		reaction       = 0.55,
		aimErrorDeg    = 7,
	},
	Stalker = {
		-- opportunist: prefers targets near the edge or freshly knocked back
		awareness     = 100,
		chargeCooldown = 5.0,
		chargeTrigger  = 13,
		chargeChance   = 0.58,
		dodgeChance    = 0.30,
		spacing        = 10,
		retreatAfterHit = false,
		reaction       = 0.70,
		aimErrorDeg    = 8,
	},
}
local PERSONALITY_NAMES = { "Brawler", "Slick", "Stalker" }

-- Display names so bots read like real players in the feed and on nametags.
-- Generic gamer-tag style, no real-username impersonation.
local NAME_POOL = {
	"xXRiderXx", "MooMaster", "HoofHavoc", "SaddleKing", "RamItUp",
	"ChargeLord", "PiggyBacker", "YeehawYT", "BuckWild", "TrotsALot",
	"KnockKnock", "RodeoRex", "StampedeSam", "GallopGuy", "BroncoBoi",
	"HayDude", "WranglerW", "MountUpMike", "CowpokeCal", "LassoLuke", "No1Larper", "TUFF", "Drake", "LOL this game is fire", "67676767", "Not a bot"
}

local AIManager = {}

local PlayerManager, AnimalManager, RoundManager

local bots       = {}
local botsById   = {}
local idInUse    = {}
local nameInUse  = {}
local heartbeat  = nil
local active     = false
local unionCache = nil
local floorPart  = nil
local descCache  = {}
local recentAnimals = {}

local nextPopCheck = 0

-- Environment helpers

local function getFloor()
	if floorPart and floorPart.Parent then return floorPart end
	local mf      = workspace:FindFirstChild("Map")
	local mainF   = mf and mf:FindFirstChild("Main")
	local gameMap = mainF and mainF:FindFirstChild("GameMap")
	floorPart = gameMap and gameMap:FindFirstChild("Floor") or nil
	return floorPart
end

local function refreshEnv()
	floorPart = nil
	getFloor()
	unionCache = {}
	local mf      = workspace:FindFirstChild("Map")
	local mainF   = mf and mf:FindFirstChild("Main")
	local gameMap = mainF and mainF:FindFirstChild("GameMap")
	if gameMap then
		for _, d in ipairs(gameMap:GetDescendants()) do
			if d:IsA("UnionOperation") then table.insert(unionCache, d) end
		end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function sampleGroundY(xz, expectedY, exclude)
	local pass1 = { table.unpack(exclude) }
	if unionCache then for _, u in ipairs(unionCache) do table.insert(pass1, u) end end
	rayParams.FilterDescendantsInstances = pass1

	local bestY, bestDist = nil, math.huge
	for _, off in ipairs(SAMPLE_OFFSETS) do
		local origin = Vector3.new(xz.X + off.X, xz.Y + RAY_START_ABOVE, xz.Z + off.Z)
		local res = workspace:Raycast(origin, Vector3.new(0, -RAY_LENGTH, 0), rayParams)
		if res and res.Normal.Y >= MIN_NORMAL_Y then
			local dist = math.abs(res.Position.Y - expectedY)
			if dist < bestDist then bestDist = dist; bestY = res.Position.Y end
		end
	end
	if bestY then return bestY end

	rayParams.FilterDescendantsInstances = exclude
	local res = workspace:Raycast(Vector3.new(xz.X, xz.Y + RAY_START_ABOVE, xz.Z), Vector3.new(0, -RAY_LENGTH, 0), rayParams)
	return res and res.Position.Y or nil
end

-- Joint prep: convert welds to Motor6D and weld orphan parts to the root so
-- the whole mount moves as one body when we drive the root CFrame

local function prepareJoints(model)
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local toConvert = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then
			table.insert(toConvert, d)
		end
	end
	for _, joint in ipairs(toConvert) do
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
		local m  = Instance.new("Motor6D")
		m.Name   = partB.Name .. "_Joint"
		m.Part0  = partA; m.Part1 = partB
		m.C0     = offsetA; m.C1  = offsetB
		m.Parent = partA
		joint:Destroy()
	end
end

local function weldOrphansToRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local connected = { [root] = true }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			if d.Part0 then connected[d.Part0] = true end
			if d.Part1 then connected[d.Part1] = true end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root and not connected[d] then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root; w.Part1 = d; w.Parent = root
		end
	end
end

-- Avatars: dress riders in real outfits so they don't look like grey dummies

local FAMOUS_IDS = { 1, 156, 261, 30857, 80254, 51580, 13268, 23383, 16563, 27817 }

local function fetchDesc(uid)
	if descCache[uid] ~= nil then return descCache[uid] or nil end
	local ok, d = pcall(function() return Players:GetHumanoidDescriptionFromUserId(uid) end)
	descCache[uid] = (ok and d) or false
	return (ok and d) or nil
end

local function applyRandomAvatar(riderHum)
	local candidates = {}
	for _, p in ipairs(Players:GetPlayers()) do table.insert(candidates, p.UserId) end
	for _, id in ipairs(FAMOUS_IDS) do table.insert(candidates, id) end
	for _ = 1, 6 do
		if not riderHum or not riderHum.Parent then return nil end
		local uid
		if #candidates > 0 then
			uid = table.remove(candidates, rng:NextInteger(1, #candidates))
		else
			uid = rng:NextInteger(1, 90000000)
		end
		local desc = fetchDesc(uid)
		if desc then
			local ok = pcall(function() riderHum:ApplyDescription(desc:Clone()) end)
			if ok then return uid end
		end
	end
	return nil
end

-- Id + name pools

local function takeId()
	for i = 1, MAX_AI do
		if not idInUse[i] then idInUse[i] = true; return i end
	end
	return nil
end
local function freeId(n) idInUse[n] = nil end

local function takeName()
	local free = {}
	for _, n in ipairs(NAME_POOL) do
		if not nameInUse[n] then table.insert(free, n) end
	end
	if #free == 0 then return "Rider" .. rng:NextInteger(100, 999) end
	local pick = free[rng:NextInteger(1, #free)]
	nameInUse[pick] = true
	return pick
end
local function freeName(n) nameInUse[n] = nil end

-- Animal selection with no immediate repeats

local function pickAnimalTemplate()
	local valid = {}
	for _, m in ipairs(ANIMALS:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") and m:FindFirstChildOfClass("Humanoid") then
			if not recentAnimals[m.Name] then table.insert(valid, m) end
		end
	end
	if #valid == 0 then
		for _, m in ipairs(ANIMALS:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") and m:FindFirstChildOfClass("Humanoid") then
				table.insert(valid, m)
			end
		end
	end
	if #valid == 0 then return nil end
	local pick = valid[rng:NextInteger(1, #valid)]
	recentAnimals[pick.Name] = true
	local order = {}
	for name in pairs(recentAnimals) do table.insert(order, name) end
	if #order > 4 then recentAnimals[order[1]] = nil end
	return pick
end

-- Spawn position: ring around center, rejected if too close to a real player

local function pickSpawnPos(floor, hrpToGround)
	local topY = floor.Position.Y + floor.Size.Y * 0.5
	local maxR = math.min(floor.Size.X, floor.Size.Z) * 0.34

	local playerRoots = {}
	for _, p in ipairs(PlayerManager.getAlivePlayers()) do
		local data = AnimalManager.getAnimalData(p)
		local model = data and data.model
		local r = model and model:FindFirstChild("HumanoidRootPart")
		if r then table.insert(playerRoots, r.Position) end
	end

	local best = nil
	for _ = 1, 8 do
		local ang = rng:NextNumber(0, 2 * math.pi)
		local rad = maxR * rng:NextNumber(0.3, 0.95)
		local pos = Vector3.new(
			floor.Position.X + math.cos(ang) * rad,
			topY + hrpToGround,
			floor.Position.Z + math.sin(ang) * rad)
		best = best or pos
		local tooClose = false
		for _, pr in ipairs(playerRoots) do
			if (Vector3.new(pos.X - pr.X, 0, pos.Z - pr.Z)).Magnitude < MIN_SPAWN_DIST then
				tooClose = true; break
			end
		end
		if not tooClose then return pos, ang end
	end
	return best, rng:NextNumber(0, 2 * math.pi)  -- crowded arena, accept best effort
end

-- Bot nametag + elim tag on the rider's head so they read as players

local function attachHeadTags(state)
	local head = state.rig and state.rig:FindFirstChild("Head")
	if not head then return end
	if HEAD_TAG then
		local tag = HEAD_TAG:Clone()
		tag.Name = "NameTag"
		local label = tag:FindFirstChildWhichIsA("TextLabel", true)
		if label then label.Text = state.displayName end
		tag.Parent = head
	end
	if ELIM_TAG then
		local tag = ELIM_TAG:Clone()
		tag.Name = "ElimTag"
		local label = tag:FindFirstChildWhichIsA("TextLabel", true)
		if label then label.Text = "0" end
		tag.Parent = head
		state.elimTag = tag
	end
end

local function refreshElimTag(state)
	if not state.elimTag or not state.elimTag.Parent then return end
	local label = state.elimTag:FindFirstChildWhichIsA("TextLabel", true)
	if label then label.Text = tostring(state.elims or 0) end
end

-- Bot construction. Atomic: if anything errors mid-build the partial models
-- get destroyed and the id/name return to the pool. A bad animal model can
-- never leak parts onto the map.

function AIManager._spawnOne()
	if not RIG_TEMPLATE or not ANIMALS then return end
	local floor = getFloor()
	if not floor then return end

	local idNum = takeId()
	if not idNum then return end
	local botId = "bot_" .. idNum
	local displayName = takeName()

	local mount, rig
	local ok, err = pcall(function()
		local template = pickAnimalTemplate()
		if not template then error("no animal template") end
		local animalName = template.Name
		local cfg = AnimalConfig.getConfig(animalName)
		local hrpToGround = (cfg and cfg.HRPToGround) or 1.5

		mount = template:Clone()
		local animalRoot = mount:FindFirstChild("HumanoidRootPart")
		local animalHum  = mount:FindFirstChildOfClass("Humanoid")
		if not animalRoot or not animalHum then error("animal missing root/humanoid") end

		mount.Name = "Bot_" .. animalName .. "_" .. idNum
		mount:SetAttribute("AnimalName", animalName)
		for _, s in ipairs(mount:GetDescendants()) do
			if s:IsA("Seat") or s:IsA("VehicleSeat") then s:Destroy() end
		end
		mount.PrimaryPart             = animalRoot
		animalHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		animalHum.RequiresNeck        = false
		animalHum.BreakJointsOnDeath  = false
		animalHum.MaxHealth, animalHum.Health = 1e9, 1e9
		animalHum.PlatformStand       = true

		local spawnPos, ang = pickSpawnPos(floor, hrpToGround)
		mount:PivotTo(CFrame.new(spawnPos))
		mount.Parent = workspace

		prepareJoints(mount)
		weldOrphansToRoot(mount)
		for _, part in ipairs(mount:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CollisionGroup = "Animals"
			end
		end

		rig = RIG_TEMPLATE:Clone()
		local riderHum = rig:FindFirstChildOfClass("Humanoid")
		local riderHrp = rig:FindFirstChild("HumanoidRootPart")
		if not riderHum or not riderHrp then error("rig missing humanoid/root") end
		rig.Name = "BotRider_" .. idNum
		local animate = rig:FindFirstChild("Animate")
		if animate then animate:Destroy() end
		riderHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		riderHum.BreakJointsOnDeath  = false
		riderHum.PlatformStand       = true
		riderHum.MaxHealth, riderHum.Health = 1e9, 1e9
		for _, part in ipairs(rig:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Players"
				part.CanCollide     = false
				part.Massless       = true
			end
		end

		local sh = animalRoot.Size.Y * 0.5 + riderHrp.Size.Y * 0.5 + 0.1
		riderHrp.CFrame = animalRoot.CFrame * CFrame.new(0, sh, 0)
		rig.Parent = workspace
		local riderWeld = AnimalManager._createRiderWeld(animalRoot, riderHrp)

		for _, part in ipairs(mount:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then pcall(function() part:SetNetworkOwner(nil) end) end
		end
		for _, part in ipairs(rig:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then pcall(function() part:SetNetworkOwner(nil) end) end
		end

		local animData = AnimationEngine.setup(mount, animalHum, animalRoot)
		if animData then animData.hrpToGround = hrpToGround end

		local sitTrack
		local animator = riderHum:FindFirstChildOfClass("Animator")
		if animator then
			local a = Instance.new("Animation"); a.AnimationId = SIT_ANIM_ID
			local okT, track = pcall(function() return animator:LoadAnimation(a) end)
			if okT and track then
				track.Priority = Enum.AnimationPriority.Action
				track.Looped = true; track:Play()
				sitTrack = track
			end
			a:Destroy()
		end

		mount:SetAttribute("BotId", botId)
		CollectionService:AddTag(mount, BOT_TAG)

		-- roll the bot's character: personality + skill
		local personality = PERSONALITIES[PERSONALITY_NAMES[rng:NextInteger(1, #PERSONALITY_NAMES)]]
		local skill = rng:NextNumber(0.75, 1.1)

		local now = os.clock()
		local state = {
			botId = botId, idNum = idNum, animalName = animalName,
			displayName = displayName,
			mount = mount, animalRoot = animalRoot, animalHum = animalHum,
			rig = rig, riderHum = riderHum, riderWeld = riderWeld,
			animData = animData, sitTrack = sitTrack, hrpToGround = hrpToGround,

			personality = personality,
			skill = skill,
			-- slight speed variance so two bots never move in perfect lockstep
			speedMult = rng:NextNumber(0.92, 1.04),

			mountVelocity = Vector3.zero, verticalVelocity = 0, groundY = spawnPos.Y,
			cachedGroundHitY = spawnPos.Y - hrpToGround,
			nextGroundSample = now + rng:NextNumber(0, GROUND_SAMPLE_INTERVAL),
			yaw = ang + math.pi, orbitSign = (rng:NextNumber() > 0.5) and 1 or -1,
			impulseVel = Vector3.zero, impulseDur = 0, impulseElapsed = 0, impulseActive = false,

			inKnockback = false, knockbackTimer = 0, postDashImmunity = 0, lastKnockedAt = 0,
			isCharging = false, chargeFired = false, chargeTimer = 0,
			isWindingCharge = false, chargeWindupUntil = 0, pendingChargeDir = nil,
			retreatUntil = 0, closeSince = 0,

			target = nil, moveDir = Vector3.zero, faceTarget = false, faceDir = nil,
			nextRetarget = 0, nextCharge = now + rng:NextNumber(1, 3), nextDash = 0,
			nextAbility = now + rng:NextNumber(2.5, 5.5), guardUntil = 0, guardResist = 0,
			abilitySpeedMult = 1, abilitySpeedUntil = 0, empoweredForce = 1, rebirthReady = false,
			reactReadyAt = now + personality.reaction, nextRam = 0,
			wanderDir = Vector3.new(math.cos(ang), 0, math.sin(ang)), wanderUntil = 0,
			stuckPos = spawnPos, stuckCheckAt = now + STUCK_TIME, unstickUntil = 0,
			spawnGraceUntil = now + SPAWN_GRACE,

			elims = 0,
			avatarUserId = 0,
			elimTag = nil,
			lastHitBy = nil, lastHitTime = 0,
			lastBotHitBy = nil, lastBotHitTime = 0,
			alive = true, dead = false,
		}

		attachHeadTags(state)

		bots[#bots + 1] = state
		botsById[botId] = state
		task.spawn(function()
			local avatarUserId = applyRandomAvatar(riderHum)
			if avatarUserId and not state.dead and mount and mount.Parent then
				state.avatarUserId = avatarUserId
				mount:SetAttribute("AvatarUserId", avatarUserId)
			end
		end)
	end)

	if not ok then
		warn("[AIManager] spawn failed: " .. tostring(err))
		if mount then pcall(function() CollectionService:RemoveTag(mount, BOT_TAG) end); if mount.Parent then mount:Destroy() end end
		if rig and rig.Parent then rig:Destroy() end
		freeId(idNum)
		freeName(displayName)
	end
end

-- Bots smash Destroyable walls just like players: spherecast along their
-- movement, break server-side (no remote round-trip needed). Cooldown is
-- per-bot and time-based so one launch can punch through multiple walls.
local VOXEL_SPHERE_RADIUS  = 3
local VOXEL_SMASH_COOLDOWN = 0.3
local VOXEL_SMASH_REACH    = 10

local function tryBotVoxelSmash(state, dir)
	local now = os.clock()
	if (state.lastVoxelSmash or 0) + VOXEL_SMASH_COOLDOWN > now then return end
	if not dir or dir.Magnitude < 0.01 then return end
	local root = state.animalRoot
	if not root or not root.Parent then return end
	local exclude = { state.mount, state.rig }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	local probeCenter = root.Position + dir.Unit * 2
	for _, part in ipairs(workspace:GetPartBoundsInRadius(probeCenter, VOXEL_SPHERE_RADIUS + 2, overlap)) do
		if part:IsA("BasePart") and part.Name ~= "Floor" and part:GetAttribute("Destroyable") == true then
			state.lastVoxelSmash = now
			pcall(VoxelManager.breakAt, part:GetClosestPointOnSurface(probeCenter))
			return
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = workspace:Spherecast(root.Position, VOXEL_SPHERE_RADIUS, dir.Unit * VOXEL_SMASH_REACH, params)
	if result and result.Instance and result.Instance.Name ~= "Floor" and result.Instance:GetAttribute("Destroyable") == true then
		state.lastVoxelSmash = now
		pcall(VoxelManager.breakAt, result.Position)
	end
end

-- Impulses (charge / dash)

local function addImpulse(state, dir, force, dur)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then return end
	state.impulseVel = dir.Unit * force
	state.impulseDur = dur; state.impulseElapsed = 0; state.impulseActive = true
end

-- Charges have aim error scaled by skill — high skill bots barely miss,
-- low skill bots can whiff past you. This is the single biggest "feels
-- human" lever: perfect aim reads as robotic instantly.
local function botStartCharge(state, towardDir)
	local errDeg = state.personality.aimErrorDeg * (2 - state.skill)
	local errRad = math.rad(rng:NextNumber(-errDeg, errDeg))
	local cosE, sinE = math.cos(errRad), math.sin(errRad)
	local dir = Vector3.new(
		towardDir.X * cosE - towardDir.Z * sinE,
		0,
		towardDir.X * sinE + towardDir.Z * cosE
	)
	state.yaw = math.atan2(-dir.X, -dir.Z)
	addImpulse(state, dir, CHARGE_IMPULSE, CHARGE_IMPULSE_TIME)
	state.isCharging = true; state.chargeFired = false; state.chargeTimer = CHARGE_DURATION
	if state.mount and state.mount.Parent then state.mount:SetAttribute("ChargeActive", true) end
	if state.personality.retreatAfterHit then
		state.retreatUntil = os.clock() + CHARGE_DURATION + rng:NextNumber(0.8, 1.6)
	end
end

local function botQueueCharge(state, towardDir)
	local flat = Vector3.new(towardDir.X, 0, towardDir.Z)
	if flat.Magnitude < 0.01 then flat = state.wanderDir end
	state.isWindingCharge = true
	state.pendingChargeDir = flat.Unit
	state.chargeWindupUntil = os.clock() + rng:NextNumber(CHARGE_WINDUP_MIN, CHARGE_WINDUP_MAX)
	state.moveDir = Vector3.zero
	state.faceTarget = true
	state.faceDir = state.pendingChargeDir
	if state.mount and state.mount.Parent then state.mount:SetAttribute("ChargeActive", true) end
end

local function botStartDash(state, dir, force, duration, immunity)
	addImpulse(state, dir, force or DASH_IMPULSE, duration or DASH_IMPULSE_TIME)
	state.postDashImmunity = math.max(state.postDashImmunity, immunity or POST_DASH_IMMUNITY)
end

-- Knockback received by a bot

function AIManager.applyKnockbackToBot(botId, attacker, direction, force)
	local state = botsById[botId]
	if not state or state.dead then return false end
	if state.postDashImmunity > 0 then return false end
	local now = os.clock()
	if now - state.lastKnockedAt < KNOCK_GUARD then return false end
	state.lastKnockedAt = now
	force = force or BOT_KNOCKBACK_FORCE
	if now < (state.guardUntil or 0) then
		local scale = 1 - math.clamp(state.guardResist or 0, 0, 1)
		if scale <= 0.05 then return false end
		force *= scale
	end

	state.inKnockback = true
	state.knockbackTimer = KNOCKBACK_PHYSICS_DURATION
	state.impulseActive = false; state.impulseVel = Vector3.zero
	state.mountVelocity = Vector3.zero; state.isCharging = false; state.isWindingCharge = false
	if state.mount and state.mount.Parent then state.mount:SetAttribute("ChargeActive", false) end

	if attacker and typeof(attacker) == "Instance" and attacker:IsA("Player") then
		state.lastHitBy = attacker; state.lastHitTime = now
	elseif typeof(attacker) == "string" then
		state.lastBotHitBy = attacker; state.lastBotHitTime = now
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0.01 then flat = flat.Unit end
	local root = state.animalRoot
	if root and root.Parent then
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.new(flat.X * force * KB_HORIZ_MULT, KB_VERTICAL_POP, flat.Z * force * KB_HORIZ_MULT)
			root.AssemblyAngularVelocity = Vector3.new((rng:NextNumber()-0.5)*10, rng:NextInteger(12,24)*(rng:NextNumber()>0.5 and 1 or -1), (rng:NextNumber()-0.5)*10)
		end)
		if AnimalManager.playCollisionFeedback then
			AnimalManager.playCollisionFeedback(state.mount, state.botId)
		end
	end
	return true
end

function AIManager.getBotRoot(botId)
	local state = botsById[botId]
	if state and not state.dead and state.animalRoot and state.animalRoot.Parent then return state.animalRoot end
	return nil
end

function AIManager.isBotId(id) return botsById[id] ~= nil end

function AIManager.getDisplayName(botId)
	local state = botsById[botId]
	return state and state.displayName or botId
end

function AIManager.getStandings()
	local standings = {}
	for _, state in ipairs(bots) do
		if state and not state.dead then
			table.insert(standings, {
				id = state.botId,
				name = state.displayName,
				userId = tonumber(state.avatarUserId) or 0,
				elims = tonumber(state.elims) or 0,
			})
		end
	end
	return standings
end

-- Best bot for the leader highlight: returns name, elims, mount model
function AIManager.getLeader()
	local bestName, bestElims, bestMount = nil, 0, nil
	for _, state in ipairs(bots) do
		if not state.dead and (state.elims or 0) > bestElims and state.mount and state.mount.Parent then
			bestName  = state.displayName
			bestElims = state.elims
			bestMount = state.mount
		end
	end
	return bestName, bestElims, bestMount
end

function AIManager.creditBotElim(botId)
	local state = botsById[botId]
	if state then
		state.elims = (state.elims or 0) + 1
		refreshElimTag(state)
	end
end

-- Player started a charge near us: nearby bots get a chance to read it and
-- sidestep, gated by reaction delay + skill. CombatManager calls this.
function AIManager.onPlayerCharge(player)
	if not active then return end
	local data = AnimalManager.getAnimalData(player)
	local model = data and data.model
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local origin = root.Position
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then return end
	flatLook = flatLook.Unit

	local now = os.clock()
	for _, state in ipairs(bots) do
		if not state.dead and not state.inKnockback and state.animalRoot and state.animalRoot.Parent then
			local toMe = Vector3.new(state.animalRoot.Position.X - origin.X, 0, state.animalRoot.Position.Z - origin.Z)
			local dist = toMe.Magnitude
			-- only react if roughly in the charge path and in range
			if dist > 2 and dist < 22 and flatLook:Dot(toMe.Unit) > 0.5 then
				local dodgeChance = state.personality.dodgeChance * state.skill
				if now >= state.nextDash and state.postDashImmunity <= 0 and rng:NextNumber() < dodgeChance then
					-- delayed sidestep: human reaction time, scaled by skill
					local delay = state.personality.reaction * (2 - state.skill) * rng:NextNumber(0.5, 0.9)
					local capturedState = state
					task.delay(delay, function()
						if capturedState.dead or capturedState.inKnockback then return end
						local side = Vector3.new(-toMe.Z, 0, toMe.X)
						if rng:NextNumber() > 0.5 then side = -side end
						if side.Magnitude > 0.01 then
							capturedState.nextDash = os.clock() + 2.4
							botStartDash(capturedState, side.Unit)
						end
					end)
				end
			end
		end
	end
end

-- Precise charge hit check (same cone math as the player path)

local function isPreciseChargeHit(attackerRoot, targetRoot)
	local forward = Vector3.new(attackerRoot.CFrame.LookVector.X, 0, attackerRoot.CFrame.LookVector.Z)
	if forward.Magnitude < 0.01 then return false end
	forward = forward.Unit

	local offset = Vector3.new(targetRoot.Position.X - attackerRoot.Position.X, 0, targetRoot.Position.Z - attackerRoot.Position.Z)
	local distance = offset.Magnitude
	if distance <= 0.1 or distance > CHARGE_HIT_RADIUS then return false end

	local toward = offset.Unit
	if forward:Dot(toward) < HIT_FORWARD_DOT then return false end

	local forwardDistance = offset:Dot(forward)
	if forwardDistance <= 0 or forwardDistance > CHARGE_HIT_RADIUS then return false end

	local lateral = (offset - forward * forwardDistance).Magnitude
	return lateral <= HIT_LATERAL_RADIUS
end

local function botCheckChargeHit(state)
	local root = state.animalRoot
	if not root or not root.Parent then return end
	local dir = root.CFrame.LookVector

	-- momentum damage, mirrored from the player side: a hit early in the
	-- charge (full speed) knocks harder than one at the tail end
	local momentum = 1
	if state.impulseActive and state.impulseDur > 0 then
		local remaining = 1 - math.clamp(state.impulseElapsed / state.impulseDur, 0, 1)
		momentum = 0.85 + 0.45 * remaining
	end
	local hitForce = BOT_KNOCKBACK_FORCE * momentum * (state.empoweredForce or 1)

	for _, p in ipairs(PlayerManager.getAlivePlayers()) do
		local data = AnimalManager.getAnimalData(p)
		if data and data.mode == "mount" and data.model and data.model.Parent then
			local r = data.model:FindFirstChild("HumanoidRootPart")
			if r and isPreciseChargeHit(root, r) then
				state.chargeFired = true; state.isCharging = false
				if state.mount and state.mount.Parent then state.mount:SetAttribute("ChargeActive", false) end
				if RoundManager then
					if RoundManager.registerKnockback then RoundManager.registerKnockback(p) end
					if RoundManager.registerBotAttacker then
						RoundManager.registerBotAttacker(p, state.botId, state.displayName, state.avatarUserId)
					end
				end
				AnimalManager.applyPhysicsKnockback(p, dir, hitForce)
				return
			end
		end
	end

	for _, other in ipairs(bots) do
		if other ~= state and not other.dead and other.animalRoot and other.animalRoot.Parent then
			if isPreciseChargeHit(root, other.animalRoot) then
				state.chargeFired = true; state.isCharging = false
				if state.mount and state.mount.Parent then state.mount:SetAttribute("ChargeActive", false) end
				AIManager.applyKnockbackToBot(other.botId, state.botId, dir, hitForce)
				return
			end
		end
	end
end

-- AI brain

local function flatDist(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end

local function safeUnit(v, fallback)
	if not v or v.Magnitude < 0.01 then
		return fallback or Vector3.zero
	end
	return v.Unit
end

local function botsTargeting(player)
	local n = 0
	for _, b in ipairs(bots) do
		if not b.dead and b.target and b.target.kind == "player" and b.target.player == player then n += 1 end
	end
	return n
end

-- how close a position is to the floor edge, 0 = center, 1 = at the edge
local function edgeFraction(pos)
	local floor = getFloor()
	if not floor then return 0 end
	local dx = math.abs(pos.X - floor.Position.X) / (floor.Size.X * 0.5)
	local dz = math.abs(pos.Z - floor.Position.Z) / (floor.Size.Z * 0.5)
	return math.clamp(math.max(dx, dz), 0, 1)
end

local function acquireTarget(state)
	if not state.animalRoot or not state.animalRoot.Parent then return nil end
	local myPos = state.animalRoot.Position
	local bestPlayer, bestPlayerScore = nil, state.personality.awareness + 15

	-- Real arena players are the primary opponents. A small crowding cost spreads
	-- bots between players without making a nearby bot more attractive than a human.
	for _, p in ipairs(PlayerManager.getAlivePlayers()) do
		local data = AnimalManager.getAnimalData(p)
		if data and data.mode == "mount" and data.model and data.model.Parent then
			local r = data.model:FindFirstChild("HumanoidRootPart")
			if r then
				local score = flatDist(myPos, r.Position) + botsTargeting(p) * 8
				score -= edgeFraction(r.Position) * 15
				if score < bestPlayerScore then
					bestPlayer = { kind = "player", player = p, root = r }
					bestPlayerScore = score
				end
			end
		end
	end
	if bestPlayer then return bestPlayer end

	local bestBot, bestBotScore = nil, state.personality.awareness
	for _, other in ipairs(bots) do
		if other ~= state and not other.dead and other.animalRoot and other.animalRoot.Parent then
			local score = flatDist(myPos, other.animalRoot.Position)
			if score < bestBotScore then
				bestBot = { kind = "ai", state = other, root = other.animalRoot }
				bestBotScore = score
			end
		end
	end
	return bestBot
end

local function targetRoot(target)
	if not target then return nil end
	if target.kind == "player" then
		local data = AnimalManager.getAnimalData(target.player)
		if data and data.mode == "mount" and data.model and data.model.Parent then
			return data.model:FindFirstChild("HumanoidRootPart")
		end
		return nil
	else
		local s = target.state
		if s and not s.dead and s.animalRoot and s.animalRoot.Parent then return s.animalRoot end
		return nil
	end
end

local function botHitTarget(state, target, direction, force, verticalPop)
	if not target or not direction or direction.Magnitude < 0.01 then return false end
	if target.kind == "player" then
		local player = target.player
		if not player or not player.Parent then return false end
		if RoundManager and RoundManager.registerKnockback then RoundManager.registerKnockback(player) end
		if RoundManager and RoundManager.registerBotAttacker then
			RoundManager.registerBotAttacker(player, state.botId, state.displayName, state.avatarUserId)
		end
		AnimalManager.applyPhysicsKnockback(player, direction.Unit, force, verticalPop)
		return true
	end
	local other = target.state
	if other and not other.dead then
		return AIManager.applyKnockbackToBot(other.botId, state.botId, direction.Unit, force)
	end
	return false
end

local function spawnBotWall(state, cfg)
	local root = state.animalRoot
	if not root or not root.Parent then return end
	local back = -Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if back.Magnitude < 0.01 then return end
	back = back.Unit
	local wall = Instance.new("Part")
	wall.Name = "BotTrashWall"
	wall.Size = Vector3.new(cfg.width or 8, cfg.height or 5, 2)
	wall.CFrame = CFrame.lookAt(root.Position + back * 5, root.Position + back * 6)
		* CFrame.new(0, (cfg.height or 5) * 0.5 - root.Size.Y, 0)
	wall.Anchored = true
	wall.Material = Enum.Material.Plastic
	wall.MaterialVariant = "Universal"
	wall.Color = Color3.fromRGB(115, 86, 53)
	wall:SetAttribute("Destroyable", true)
	wall.Parent = workspace
	local touched = {}
	wall.Touched:Connect(function(hit)
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model or model == state.mount or touched[model] then return end
		touched[model] = true
		task.delay(0.6, function() touched[model] = nil end)
		local otherId = model:GetAttribute("BotId")
		local otherRoot = model:FindFirstChild("HumanoidRootPart")
		if otherId and otherRoot then
			local away = Vector3.new(otherRoot.Position.X - wall.Position.X, 0, otherRoot.Position.Z - wall.Position.Z)
			if away.Magnitude > 0.01 then AIManager.applyKnockbackToBot(otherId, state.botId, away.Unit, 55) end
			return
		end
		for _, player in ipairs(PlayerManager.getAlivePlayers()) do
			local data = AnimalManager.getAnimalData(player)
			if data and data.model == model and otherRoot then
				local away = Vector3.new(otherRoot.Position.X - wall.Position.X, 0, otherRoot.Position.Z - wall.Position.Z)
				if away.Magnitude > 0.01 then
					botHitTarget(state, { kind = "player", player = player }, away.Unit, 55)
				end
				return
			end
		end
	end)
	Debris:AddItem(wall, cfg.life or 6)
end

local function botAbilityFxPower(state, cfg)
	local geometryScale = 1
	if state.mount and state.mount.Parent then
		local ok, _, size = pcall(state.mount.GetBoundingBox, state.mount)
		if ok and size then geometryScale = math.clamp(size.Magnitude / 7, 0.72, 1.42) end
	end
	local reach = cfg.radius or cfg.range or cfg.landRadius or cfg.dist or 8
	local reachScale = math.clamp(reach / 10, 0.72, 1.35)
	return math.clamp(0.68 + geometryScale * 0.22 + reachScale * 0.10, 0.55, 1.55)
end

local function scheduleBotBurst(state, target, delayTime, radius, force, pop, effect)
	if not radius or not force then return end
	task.delay(math.max(delayTime or 0, 0), function()
		local root = state.animalRoot
		if state.dead or not root or not root.Parent then return end
		local tRoot = targetRoot(target)
		if tRoot then
			local offset = Vector3.new(tRoot.Position.X - root.Position.X, 0, tRoot.Position.Z - root.Position.Z)
			if offset.Magnitude <= radius then
				local direction = offset.Magnitude > 0.01 and offset.Unit or Vector3.new(0, 0, -1)
				botHitTarget(state, target, direction, force, pop)
			end
		end
		AbilityRemote:FireAllClients("fx", {
			effect = effect or "slam",
			animal = state.animalName,
			position = root.Position,
			source = root,
			power = botAbilityFxPower(state, { radius = radius }) * 0.9,
			radius = radius,
		})
	end)
end

local function useBotAbility(state, target, now)
	local cfg = AbilityConfig.Abilities[state.animalName]
	local root = state.animalRoot
	local tRoot = targetRoot(target)
	if not cfg or not root or not tRoot then return false end
	local offset = Vector3.new(tRoot.Position.X - root.Position.X, 0, tRoot.Position.Z - root.Position.Z)
	local dist = offset.Magnitude
	local toward = dist > 0.01 and offset.Unit or Vector3.new(-math.sin(state.yaw), 0, -math.cos(state.yaw))
	local kind = cfg.kind
	local used = false

	if kind == "dash" then
		botStartDash(state, toward, cfg.force, cfg.dur, cfg.immunity)
		scheduleBotBurst(state, target, cfg.endDelay or cfg.dur or 0, cfg.endRadius, cfg.endForce, cfg.endPop, cfg.endEffect)
		used = true
	elseif kind == "leap" then
		state.verticalVelocity = cfg.vert or 60
		state.pendingLandPose = cfg.landPose
		state.pendingLandPoseDur = cfg.landPoseDur or 0.4
		state.pendingLandCfg = cfg.landForce and cfg or nil
		state.pendingLandTarget = cfg.landForce and target or nil
		if (cfg.horiz or 0) > 0 then addImpulse(state, toward, cfg.horiz, 0.5) end
		used = true
	elseif kind == "blink" then
		local floor = getFloor()
		local step = math.min(cfg.dist or 14, math.max(4, dist - 3))
		local targetPos = root.Position + toward * step
		if floor and math.abs(targetPos.X - floor.Position.X) < floor.Size.X * 0.45
			and math.abs(targetPos.Z - floor.Position.Z) < floor.Size.Z * 0.45 then
			root.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, math.atan2(-toward.X, -toward.Z), 0)
			state.groundY = targetPos.Y
			scheduleBotBurst(state, target, cfg.endDelay or 0, cfg.endRadius, cfg.endForce, cfg.endPop, cfg.endEffect)
			used = true
		end
	elseif kind == "speed" then
		state.abilitySpeedMult = cfg.mult or 1.4
		state.abilitySpeedUntil = now + (cfg.dur or 3)
		if (cfg.resist or 0) > 0 then
			state.guardUntil = now + (cfg.dur or 3)
			state.guardResist = cfg.resist
		end
		scheduleBotBurst(state, target, cfg.dur or 3, cfg.endRadius, cfg.endForce, cfg.endPop, cfg.endEffect)
		used = true
	elseif kind == "cone" then
		if dist <= (cfg.range or 10) then used = botHitTarget(state, target, toward, cfg.force or 65, cfg.pop) end
	elseif kind == "radial" then
		if dist <= (cfg.radius or 10) then used = botHitTarget(state, target, toward, cfg.force or 65, cfg.pop) end
	elseif kind == "guard" or kind == "burrow" then
		state.guardUntil = now + (cfg.dur or 1.2)
		state.guardResist = cfg.resist or 1
		if kind == "burrow" then
			scheduleBotBurst(state, target, cfg.dur or 1.2, cfg.emergeRadius, cfg.emergeForce, cfg.emergePop, cfg.emergeEffect)
		end
		used = true
	elseif kind == "empower" then
		state.empoweredForce = cfg.forceMult or 1.25
		used = true
	elseif kind == "rebirth" then
		state.rebirthReady = true
		used = true
	elseif kind == "refresh" then
		botStartDash(state, -toward, 72, 0.45, 0.45)
		if (cfg.resist or 0) > 0 then
			state.guardUntil = now + (cfg.resistDur or 0.5)
			state.guardResist = cfg.resist
		end
		used = true
	elseif kind == "wall" then
		spawnBotWall(state, cfg)
		used = true
	end

	if used then
		if cfg.moveBoostMult then
			state.abilitySpeedMult = cfg.moveBoostMult
			state.abilitySpeedUntil = now + (cfg.moveBoostDur or 2)
		end
		state.nextAbility = now + cfg.cd * rng:NextNumber(0.9, 1.15)
		local presentation = AbilityConfig.getPresentation(state.animalName, cfg)
		if presentation.windupPose then
			AnimationEngine.setPose(state.animData, presentation.windupPose, (presentation.windup or 0.1) + 0.08)
		end
		task.delay(presentation.windup or 0, function()
			if not state.dead and state.animData then
				AnimationEngine.setPose(
					state.animData,
					presentation.actionPose or cfg.pose or "charge",
					presentation.actionDur or AbilityConfig.getPoseDuration(cfg)
				)
			end
		end)
		if cfg.airPose then
			task.delay((presentation.windup or 0) + (cfg.poseDur or 0.16), function()
				if not state.dead and state.animData then
					AnimationEngine.setPose(state.animData, cfg.airPose, cfg.airPoseDur or 0.65)
				end
			end)
		end
		local look = root.CFrame.LookVector
		local direction = Vector3.new(look.X, 0, look.Z)
		if direction.Magnitude > 0.01 then direction = direction.Unit end
		AbilityRemote:FireAllClients("fx", {
			effect = presentation.effect,
			animal = state.animalName,
			position = root.Position,
			source = root,
			direction = direction,
			power = botAbilityFxPower(state, cfg) * 0.85,
			radius = cfg.radius or cfg.landRadius,
			range = cfg.range or cfg.dist,
			angle = cfg.angle,
			duration = cfg.dur or cfg.window or cfg.armDur or cfg.extraWindow,
			sound = cfg.sound,
		})
	end
	return used
end

local function sameTarget(a, b)
	if not a or not b or a.kind ~= b.kind then return false end
	if a.kind == "player" then return a.player == b.player end
	return a.state == b.state
end

local function edgeCorrection(pos)
	local floor = getFloor()
	if not floor then return nil end
	local dx = pos.X - floor.Position.X
	local dz = pos.Z - floor.Position.Z
	if math.abs(dx) > floor.Size.X * 0.5 - EDGE_MARGIN or math.abs(dz) > floor.Size.Z * 0.5 - EDGE_MARGIN then
		local toCenter = Vector3.new(-dx, 0, -dz)
		if toCenter.Magnitude > 0.01 then return toCenter.Unit end
	end
	return nil
end

local function incomingThreat(state)
	local myPos = state.animalRoot.Position
	for _, p in ipairs(PlayerManager.getAlivePlayers()) do
		local data = AnimalManager.getAnimalData(p)
		if data and data.mode == "mount" and data.model and data.model.Parent then
			local r = data.model:FindFirstChild("HumanoidRootPart")
			if r then
				local toMe = Vector3.new(myPos.X - r.Position.X, 0, myPos.Z - r.Position.Z)
				if toMe.Magnitude <= 16 then
					local charging = data.model:GetAttribute("ChargeActive") == true
					local look = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z)
					if charging and look.Magnitude > 0.01 and toMe.Magnitude > 0.01
						and look.Unit:Dot(toMe.Unit) > 0.4 then
						return r.Position
					end
				end
			end
		end
	end
	return nil
end

-- Server-side ram detection: a player charging through a bot knocks it back
-- without depending on the client's tag round-trip
local function checkRammedByPlayer(state, now)
	if now < state.nextRam then return end
	local myPos = state.animalRoot.Position
	for _, p in ipairs(PlayerManager.getAlivePlayers()) do
		local data = AnimalManager.getAnimalData(p)
		if data and data.mode == "mount" and data.model and data.model.Parent then
			local r = data.model:FindFirstChild("HumanoidRootPart")
			if r and flatDist(myPos, r.Position) <= CHARGE_HIT_RADIUS then
				local charging = data.model:GetAttribute("ChargeActive") == true
				local look = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z)
				local toBot = Vector3.new(myPos.X - r.Position.X, 0, myPos.Z - r.Position.Z)
				local facingContact = toBot.Magnitude < 6.5 or (look.Magnitude > 0.01 and toBot.Magnitude > 0.01 and look.Unit:Dot(toBot.Unit) > 0.05)
				if charging and facingContact then
					local away = toBot.Magnitude > 0.01 and toBot.Unit or look
					if AIManager.applyKnockbackToBot(state.botId, p, away, BOT_KNOCKBACK_FORCE) then
						state.nextRam = now + RAM_COOLDOWN
					end
					return
				end
			end
		end
	end
end

local function think(state, now)
	local myPos = state.animalRoot.Position
	local pers  = state.personality

	if state.isWindingCharge then
		if now < state.chargeWindupUntil then
			state.moveDir = Vector3.zero
			state.faceTarget = true
			state.faceDir = state.pendingChargeDir
			return
		end
		local committedDir = state.pendingChargeDir or state.wanderDir
		state.isWindingCharge = false
		state.pendingChargeDir = nil
		botStartCharge(state, committedDir)
		return
	end

	-- velocity-based dodge (reads any fast approach, not just charges)
	if now >= state.reactReadyAt and now >= state.nextDash and state.postDashImmunity <= 0 then
		local threat = incomingThreat(state)
		if threat and rng:NextNumber() < pers.dodgeChance * state.skill then
			local away = Vector3.new(myPos.X - threat.X, 0, myPos.Z - threat.Z)
			local side = Vector3.new(-away.Z, 0, away.X)
			if rng:NextNumber() > 0.5 then side = -side end
			local edge = edgeCorrection(myPos)
			local dodgeDir = safeUnit(side, safeUnit(away, state.wanderDir))
			if edge then dodgeDir = safeUnit(dodgeDir + edge, edge) end
			state.nextDash = now + 2.4
			botStartDash(state, dodgeDir)
			return
		end
	end

	if now >= state.nextRetarget or not targetRoot(state.target)
		or (state.target and state.target.kind == "ai" and #PlayerManager.getAlivePlayers() > 0) then
		local newT = acquireTarget(state)
		if newT and not sameTarget(newT, state.target) then
			-- reaction delay on a NEW target: the bot "notices" you, then acts
			state.reactReadyAt = now + pers.reaction * (2 - state.skill)
		end
		state.target = newT
		state.nextRetarget = now + RETARGET_INTERVAL * rng:NextNumber(0.8, 1.3)
	end

	local tRoot = targetRoot(state.target)
	local edge  = edgeCorrection(myPos)

	if not tRoot then
		-- nobody around: wander with natural meander
		if now >= state.wanderUntil then
			local a = rng:NextNumber(0, 2 * math.pi)
			state.wanderDir = Vector3.new(math.cos(a), 0, math.sin(a))
			state.wanderUntil = now + rng:NextNumber(1, 2.5)
		end
		state.moveDir = edge or state.wanderDir
		state.faceTarget = false
		return
	end

	if now >= (state.nextAbility or 0) and not state.isCharging and not state.isWindingCharge then
		if rng:NextNumber() <= 0.7 and useBotAbility(state, state.target, now) then return end
		state.nextAbility = now + rng:NextNumber(0.8, 1.6)
	end

	local toTarget = Vector3.new(tRoot.Position.X - myPos.X, 0, tRoot.Position.Z - myPos.Z)
	local dist = toTarget.Magnitude
	local approach = dist > 0.01 and toTarget.Unit or state.wanderDir
	if dist < pers.spacing then
		if state.closeSince == 0 then state.closeSince = now end
	else
		state.closeSince = 0
	end

	local retreating = now < state.retreatUntil

	if edge then
		state.moveDir = safeUnit(approach + edge * 1.5, edge)
	elseif now < state.unstickUntil then
		state.moveDir = state.wanderDir
	elseif retreating and dist < pers.spacing * 2 then
		-- back off after an attack (Slick behavior): kite away with a side drift
		local back = -approach
		local tangent = Vector3.new(-approach.Z, 0, approach.X) * state.orbitSign
		state.moveDir = safeUnit(back * 0.7 + tangent * 0.3, back)
	elseif dist < pers.spacing and not state.isCharging then
		-- orbit at preferred spacing instead of body-blocking
		local tangent = Vector3.new(-approach.Z, 0, approach.X) * state.orbitSign
		state.moveDir = safeUnit(tangent * 0.55 + approach * 0.45, approach)
	else
		state.moveDir = approach
	end
	state.faceTarget = true
	state.faceDir = approach

	-- charge decision
	if now >= state.nextCharge and now >= state.reactReadyAt and not state.isCharging
		and not retreating and dist <= pers.chargeTrigger and not edge then
		local chance = pers.chargeChance
		if state.closeSince > 0 and now - state.closeSince > 0.55 then chance += 0.45 end
		if state.closeSince > 0 and now - state.closeSince > 1.4 then chance = 1 end
		-- target near the edge? everyone gets greedier — easy ring-out
		chance += edgeFraction(tRoot.Position) * 0.25
		-- target mid-knockback? free hit, take it more often
		if state.target.kind == "ai" and state.target.state.inKnockback then chance += 0.3 end
		if rng:NextNumber() < chance then
			local facing = Vector3.new(-math.sin(state.yaw), 0, -math.cos(state.yaw))
			if facing:Dot(approach) > 0.6 or dist < 9 then
				state.nextCharge = now + pers.chargeCooldown * rng:NextNumber(0.85, 1.25)
				botQueueCharge(state, approach)
			end
		else
			-- decided not to charge this window — short re-check delay so it
			-- doesn't re-roll every brain tick (would converge to 100% chance)
			state.nextCharge = now + rng:NextNumber(0.6, 1.4)
		end
	end
end

-- Per-frame kinematic drive

local function lerpAngle(a, b, t)
	local diff = math.atan2(math.sin(b - a), math.cos(b - a))
	return a + diff * t
end

local function driveBot(state, dt)
	local root = state.animalRoot
	if not root or not root.Parent or not state.animalHum or not state.animalHum.Parent then
		AIManager._eliminate(state, nil); return
	end

	if os.clock() >= (state.abilitySpeedUntil or 0) then state.abilitySpeedMult = 1 end
	local topSpeed = MOUNT_TOP_SPEED * state.speedMult * (state.abilitySpeedMult or 1)

	if state.postDashImmunity > 0 then state.postDashImmunity = math.max(0, state.postDashImmunity - dt) end
	if state.chargeTimer > 0 then
		state.chargeTimer = math.max(0, state.chargeTimer - dt)
		if state.chargeTimer <= 0 then
			state.isCharging = false
			if state.mount and state.mount.Parent then state.mount:SetAttribute("ChargeActive", false) end
		end
	end

	if state.inKnockback then
		state.knockbackTimer -= dt
		-- flying through the air: smash any Destroyable wall in the path.
		-- sweep along FLAT velocity — walls are vertical and the launch arc
		-- points upward, so the full-velocity direction would miss them
		local kv = root.AssemblyLinearVelocity
		local kFlat = Vector3.new(kv.X, 0, kv.Z)
		if kFlat.Magnitude >= 8 then
			tryBotVoxelSmash(state, kFlat)
		elseif kv.Magnitude >= 8 then
			tryBotVoxelSmash(state, kv)
		end
		if state.knockbackTimer <= 0 then
			state.inKnockback = false
			local gy = sampleGroundY(root.Position, root.Position.Y - state.hrpToGround, { state.mount, state.rig })
			state.cachedGroundHitY = gy
			state.nextGroundSample = os.clock() + GROUND_SAMPLE_INTERVAL
			state.groundY = (gy and gy + state.hrpToGround) or root.Position.Y
			state.verticalVelocity = 0; state.mountVelocity = Vector3.zero
		end
		if state.animData then AnimationEngine.update(state.animData, state.animalHum, dt, false, 0, topSpeed) end
		return
	end

	if state.isCharging and not state.chargeFired then
		botCheckChargeHit(state)
		-- charging bots plow through breakable walls like players do
		tryBotVoxelSmash(state, root.CFrame.LookVector)
	end

	local impulseThisFrame = Vector3.zero
	if state.impulseActive then
		state.impulseElapsed += dt
		if state.impulseElapsed >= state.impulseDur then
			state.impulseActive = false; state.impulseVel = Vector3.zero
		else
			impulseThisFrame = state.impulseVel * (1 - state.impulseElapsed / state.impulseDur) * dt
		end
	end

	local inputDir = state.moveDir or Vector3.zero
	local controlMul = state.impulseActive and 0.2 or 1
	if inputDir.Magnitude > 0.01 then
		state.mountVelocity = state.mountVelocity:Lerp(inputDir.Unit * topSpeed * controlMul, math.min(dt * MOUNT_ACCEL / topSpeed, 1))
	else
		state.mountVelocity = state.mountVelocity:Lerp(Vector3.zero, math.min(dt * MOUNT_FRICTION, 1))
	end

	local moveVec = state.mountVelocity
	if not state.isCharging then
		local faceVec = state.faceTarget and state.faceDir or (moveVec.Magnitude > 0.5 and moveVec or nil)
		if faceVec and faceVec.Magnitude > 0.01 then
			state.yaw = lerpAngle(state.yaw, math.atan2(-faceVec.X, -faceVec.Z), math.min(dt * 10, 1))
		end
	end

	local cp  = root.Position
	local hm  = state.mountVelocity * dt + impulseThisFrame
	local nxz = Vector3.new(cp.X + hm.X, cp.Y, cp.Z + hm.Z)
	local now = os.clock()
	local gy = state.cachedGroundHitY
	if now >= state.nextGroundSample then
		gy = sampleGroundY(nxz, cp.Y - state.hrpToGround, { state.mount, state.rig })
		state.cachedGroundHitY = gy
		state.nextGroundSample = now + (state.isCharging and 0.033 or GROUND_SAMPLE_INTERVAL)
	end

	local wasAirborne = state.verticalVelocity ~= 0
	if gy then
		local groundTarget = gy + state.hrpToGround
		local heightAbove = cp.Y - groundTarget
		if state.verticalVelocity > 0 then
			state.verticalVelocity -= GRAVITY * dt
			state.groundY = cp.Y + state.verticalVelocity * dt
		elseif heightAbove <= 0.5 or (state.verticalVelocity <= 0 and heightAbove < 2) then
			state.groundY = groundTarget; state.verticalVelocity = 0
		else
			state.verticalVelocity = math.max(state.verticalVelocity - GRAVITY * dt, -TERMINAL_VELOCITY)
			state.groundY = cp.Y + state.verticalVelocity * dt
			if state.groundY <= groundTarget then state.groundY = groundTarget; state.verticalVelocity = 0 end
		end
	else
		state.verticalVelocity = math.max(state.verticalVelocity - GRAVITY * dt, -TERMINAL_VELOCITY)
		state.groundY = cp.Y + state.verticalVelocity * dt
	end

	if state.pendingLandPose and wasAirborne and state.verticalVelocity == 0 then
		if state.animData then AnimationEngine.setPose(state.animData, state.pendingLandPose, state.pendingLandPoseDur) end
		local landCfg = state.pendingLandCfg
		local landTarget = state.pendingLandTarget
		if landCfg and landTarget then
			local landingTargetRoot = targetRoot(landTarget)
			if landingTargetRoot then
				local offset = Vector3.new(landingTargetRoot.Position.X - root.Position.X, 0, landingTargetRoot.Position.Z - root.Position.Z)
				if offset.Magnitude > 0.05 and offset.Magnitude <= (landCfg.landRadius or 8) then
					botHitTarget(state, landTarget, offset.Unit, landCfg.landForce or 55, landCfg.landPop)
				end
			end
			local impactEffect = landCfg.landEffect
				or (state.animalName == "Slime" and "bounce_land")
				or (state.animalName == "Tung" and "tung_slam")
				or "slam"
			AbilityRemote:FireAllClients("fx", {
				effect = impactEffect, animal = state.animalName, position = root.Position, source = root,
				power = botAbilityFxPower(state, landCfg), radius = landCfg.landRadius,
				sound = state.animalName == "Tung" and "Slam" or landCfg.sound,
			})
		end
		state.pendingLandPose = nil
		state.pendingLandCfg = nil
		state.pendingLandTarget = nil
	end

	local newCF = CFrame.new(Vector3.new(nxz.X, state.groundY, nxz.Z)) * CFrame.Angles(0, state.yaw, 0)
	pcall(function()
		root.AssemblyLinearVelocity  = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	root.CFrame = newCF

	local spd = state.mountVelocity.Magnitude
	if state.impulseActive then spd = math.max(spd, state.impulseVel.Magnitude * (1 - state.impulseElapsed / state.impulseDur)) end
	if state.animData then AnimationEngine.update(state.animData, state.animalHum, dt, spd > 0.5, spd, topSpeed) end
end

-- OOB + stuck

local function isOOB(state)
	local floor = getFloor()
	if not floor then return false end
	local p  = state.animalRoot.Position
	local fp, fs = floor.Position, floor.Size
	if math.abs(p.X - fp.X) > fs.X * 0.5 + 4 then return true end
	if math.abs(p.Z - fp.Z) > fs.Z * 0.5 + 4 then return true end
	if p.Y < fp.Y + fs.Y * 0.5 - 25 then return true end
	return false
end

local function checkStuck(state, now)
	if now < state.stuckCheckAt then return end
	state.stuckCheckAt = now + STUCK_TIME
	if state.target and not state.inKnockback and flatDist(state.animalRoot.Position, state.stuckPos) < STUCK_DIST then
		local a = rng:NextNumber(0, 2 * math.pi)
		state.wanderDir = Vector3.new(math.cos(a), 0, math.sin(a))
		state.unstickUntil = now + 0.7
		state.orbitSign = -state.orbitSign
	end
	state.stuckPos = state.animalRoot.Position
end

-- Teardown helpers

local function destroyBotInstances(state)
	if state.sitTrack then pcall(function() state.sitTrack:Stop() end) end
	if state.mount and state.mount.Parent then
		pcall(function() CollectionService:RemoveTag(state.mount, BOT_TAG) end)
		state.mount:Destroy()
	end
	if state.rig and state.rig.Parent then state.rig:Destroy() end
end

local function removeFromRoster(state)
	for i = #bots, 1, -1 do if bots[i] == state then table.remove(bots, i); break end end
	botsById[state.botId] = nil
	freeId(state.idNum)
	freeName(state.displayName)
end

-- Population: how many bots SHOULD exist right now.
-- Scales against real alive fighters; zero bots once 4+ humans are brawling.
local function desiredBotCount()
	if not active then return 0 end
	if #Players:GetPlayers() == 0 then return 0 end
	local realFighters = #PlayerManager.getAlivePlayers()
	return math.clamp(TARGET_FILL - realFighters, 0, MAX_AI)
end

-- When humans fill the arena, peel off the bot farthest from any player —
-- the one nobody is fighting — so the departure goes unnoticed. No feed spam.
local function despawnQuietest()
	local playerRoots = {}
	for _, p in ipairs(PlayerManager.getAlivePlayers()) do
		local data = AnimalManager.getAnimalData(p)
		local model = data and data.model
		local r = model and model:FindFirstChild("HumanoidRootPart")
		if r then table.insert(playerRoots, r.Position) end
	end

	local farthest, farDist = nil, -1
	for _, state in ipairs(bots) do
		if not state.dead and state.animalRoot and state.animalRoot.Parent then
			local nearest = math.huge
			for _, pr in ipairs(playerRoots) do
				nearest = math.min(nearest, flatDist(state.animalRoot.Position, pr))
			end
			if #playerRoots == 0 then nearest = 0 end
			if nearest > farDist then farDist = nearest; farthest = state end
		end
	end

	if farthest then
		farthest.dead = true; farthest.alive = false
		removeFromRoster(farthest)
		destroyBotInstances(farthest)
	end
end

local function syncPopulation()
	local want = desiredBotCount()
	local have = #bots
	if have < want then
		AIManager._spawnOne()        -- one per tick: gradual fill, no spawn burst
	elseif have > want then
		despawnQuietest()            -- one per tick: gradual drain
	end
end

-- Elimination (knocked off / fell)

function AIManager._eliminate(state, killer)
	if state.dead then return end
	state.dead = true; state.alive = false

	removeFromRoster(state)

	local now = os.clock()
	if killer and killer.Parent and RoundManager and RoundManager.creditElim then
		-- a real player knocked this bot off — full credit, cash, feed entry.
		-- pass the bot's elim count so RoundManager can run the bounty check
		pcall(RoundManager.creditElim, killer, state.displayName, state.avatarUserId or 0, state.elims or 0)
	elseif state.lastBotHitBy and (now - state.lastBotHitTime) <= KILL_CREDIT_WINDOW then
		-- bot-on-bot kill: bump the killer's score, show it in the feed
		local b = botsById[state.lastBotHitBy]
		if b then
			b.elims = (b.elims or 0) + 1
			refreshElimTag(b)
			if RoundManager and RoundManager.recordBotElim then
				pcall(RoundManager.recordBotElim, b.displayName, b.avatarUserId or 0, state.displayName, state.avatarUserId or 0)
			end
		end
	elseif RoundManager and RoundManager.recordBotElim then
		-- fell off on its own
		pcall(RoundManager.recordBotElim, state.displayName, state.avatarUserId or 0, state.displayName, state.avatarUserId or 0)
	end

	destroyBotInstances(state)

	-- respawn is just a population re-sync after a delay: if humans have filled
	-- the arena since, the dead bot simply never comes back
	if active then task.delay(RESPAWN_DELAY, syncPopulation) end
end

-- Master loop

local accum = 0
local function onHeartbeat(dt)
	if not active then return end
	dt = math.min(dt, 0.1)
	local now = os.clock()
	accum += dt
	local doThink = accum >= BEHAVIOR_TICK
	if doThink then accum = 0 end

	if now >= nextPopCheck then
		nextPopCheck = now + POP_INTERVAL
		pcall(syncPopulation)
	end

	for i = #bots, 1, -1 do
		local state = bots[i]
		if state and not state.dead then
			if not state.inKnockback and now >= state.spawnGraceUntil and isOOB(state) then
				if state.rebirthReady then
					state.rebirthReady = false
					local floor = getFloor()
					if floor then
						state.groundY = floor.Position.Y + floor.Size.Y * 0.5 + state.hrpToGround
						state.animalRoot.CFrame = CFrame.new(floor.Position.X, state.groundY, floor.Position.Z)
						state.mountVelocity = Vector3.zero
						state.verticalVelocity = 0
						state.spawnGraceUntil = now + 2
						AbilityRemote:FireAllClients("fx", { effect = "rebirth", animal = state.animalName, position = state.animalRoot.Position, power = 1 })
					end
				else
					local killer = (state.lastHitBy and (now - state.lastHitTime) <= KILL_CREDIT_WINDOW) and state.lastHitBy or nil
					AIManager._eliminate(state, killer)
				end
			else
				if not state.inKnockback then checkRammedByPlayer(state, now) end
				if doThink and not state.inKnockback then
					checkStuck(state, now)
					think(state, now)
				end
				driveBot(state, dt)
			end
		end
	end
end

-- Public API

function AIManager.init(playerMgr, animalMgr, roundMgr)
	PlayerManager = playerMgr
	AnimalManager = animalMgr
	RoundManager  = roundMgr
	if not RIG_TEMPLATE then warn("[AIManager] ReplicatedStorage.Rig missing, AI disabled") end
	if not ANIMALS     then warn("[AIManager] ServerStorage.Animals missing, AI disabled") end
end

function AIManager.spawnForRound()
	AIManager.clearAll()
	if not RIG_TEMPLATE or not ANIMALS or not PlayerManager then return end
	refreshEnv()
	if not getFloor() then return end
	active = true
	nextPopCheck = 0  -- population sync fires on the first heartbeat
	if not heartbeat then heartbeat = RunService.Heartbeat:Connect(onHeartbeat) end
end

function AIManager.clearAll()
	active = false
	if heartbeat then heartbeat:Disconnect(); heartbeat = nil end
	for _, state in ipairs(bots) do
		state.dead = true; state.alive = false
		destroyBotInstances(state)
	end
	table.clear(bots)
	table.clear(botsById)
	table.clear(idInUse)
	table.clear(nameInUse)
	table.clear(recentAnimals)
	accum = 0
end

return AIManager

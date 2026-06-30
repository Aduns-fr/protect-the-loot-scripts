--[[
	CombatManager (ModuleScript - ServerScriptService.Modules)

	Validates charge hits, applies knockback, and runs the server half of the
	per-animal ability system (AbilityConfig).

	MOMENTUM FIX: the old version read the attacker's AssemblyLinearVelocity,
	but the kinematic mount drive zeroes that every frame, so every hit landed
	at the 0.8x floor and knockback felt weak. Now the server samples the
	attacker's position when the charge starts and measures real displacement
	speed at impact. Momentum only ever ADDS now: 1.0x floor, 1.45x ceiling.

	Base knockback also raised 105 to 115 and the lag fallback distance
	loosened 16 to 20 so high-ping hits register.

	ABILITIES: client fires CombatRemote("ability") for its equipped animal.
	The server resolves the animal itself (mount model name, then the client
	claim as a checked fallback), validates the cooldown, and runs whatever
	has authority here: shoves, guards, empowers, rebirth arming, the raccoon
	wall, golden goose cash bonus, prism reflect. Movement kinds run on the
	client and the server just gates the cooldown and broadcasts fx.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")

local RemoteEvents  = ReplicatedStorage:WaitForChild("RemoteEvents")
local CombatRemote  = RemoteEvents:WaitForChild("CombatRemote")
local AbilityRemote = RemoteEvents:WaitForChild("AbilityRemote")

local Modules       = script.Parent
local HitboxModule  = require(Modules:WaitForChild("HitboxModule"))
local VoxelManager  = require(Modules:WaitForChild("VoxelManager"))
local AbilityConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AbilityConfig"))

local CHARGE_COOLDOWN        = 3
local DASH_COOLDOWN          = 1.5
local CHARGE_KNOCKBACK_FORCE = 115
local SERVER_CHARGE_WINDOW   = 0.85
local HIT_FORWARD_DOT        = 0.55
local MAX_HIT_DISTANCE       = 32
local BOT_MAX_HIT_DISTANCE   = 18
local FALLBACK_HIT_DISTANCE  = 20

local ATTACKER_EXPIRY = 10

-- momentum: only ever boosts, never weakens a hit
local MOMENTUM_MAX_SCALE = 1.45
local MOMENTUM_REF_SPEED = 40

local ABILITY_CD_TOLERANCE = 0.9
local LAND_WINDOW          = 3

local cooldowns     = {}
local lastAttacker  = {}
local chargeWindows = {}
local chargeStart   = {}

local abilityLast = {}
local abilityChargeState = {}
local guardState   = {}
local empowerState = {}
local rebirthState = {}
local cashBonus    = {}
local pendingLand  = {}

local PlayerManager
local AnimalManager
local RoundManager
local AIManager

local CombatManager = {}

local function canUse(player, ability)
	local cd = cooldowns[player]
	if not cd then
		cooldowns[player] = {}
		return true
	end
	local needed = ability == "charge" and CHARGE_COOLDOWN or DASH_COOLDOWN
	return (tick() - (cd[ability] or 0)) >= needed
end

local function setCooldown(player, ability)
	if not cooldowns[player] then cooldowns[player] = {} end
	cooldowns[player][ability] = tick()
end

local function getChargeWindow(player)
	local window = chargeWindows[player]
	if not window or tick() > window.untilT then
		chargeWindows[player] = nil
		return nil
	end
	return window
end

local function getAttackerHRP(player)
	local animalData = AnimalManager.getAnimalData(player)
	if animalData then
		local model = animalData.model or animalData.animalModel or animalData.rig
		if model and model.Parent then
			local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if hrp then return hrp end
		end
	end
	local char = player.Character
	if char then return char:FindFirstChild("HumanoidRootPart") end
	return nil
end

-- measured from real displacement since the charge started, because the
-- kinematic drive zeroes physics velocity every frame
local function momentumScale(player, attackerHRP)
	local sample = chargeStart[player]
	if not sample or not attackerHRP then return 1 end
	local dt = math.max(tick() - sample.t, 0.08)
	local moved = (attackerHRP.Position - sample.pos)
	local speed = Vector3.new(moved.X, 0, moved.Z).Magnitude / dt
	local t = math.clamp(speed / MOMENTUM_REF_SPEED, 0, 1)
	return 1 + (MOMENTUM_MAX_SCALE - 1) * t
end

-- ability state helpers

function CombatManager.getDefenseScale(player)
	local g = guardState[player]
	if g and tick() <= g.untilT then
		return 1 - (g.resist or 0)
	end
	return 1
end

function CombatManager.consumeCashBonus(player)
	local b = cashBonus[player]
	if b and tick() <= b.untilT then
		cashBonus[player] = nil
		return 1 + (b.mult or 0)
	end
	return 1
end

function CombatManager.tryConsumeRebirth(victim)
	local r = rebirthState[victim]
	if r and r.armed and tick() <= r.untilT and not r.usedThisRound then
		r.armed = false
		r.usedThisRound = true
		return true
	end
	return false
end

function CombatManager.onRoundStart()
	for _, r in pairs(rebirthState) do
		r.usedThisRound = false
		r.armed = false
	end
	table.clear(abilityLast)
	table.clear(abilityChargeState)
	table.clear(guardState)
	table.clear(empowerState)
	table.clear(cashBonus)
	table.clear(pendingLand)
end

local function fxAll(name, position, power, details)
	local payload = details or {}
	payload.effect = name
	payload.position = position
	payload.power = power or 1
	pcall(function()
		AbilityRemote:FireAllClients("fx", payload)
	end)
end

local function buildFxDetails(player, animal, attackerHRP, cfg)
	local look = attackerHRP.CFrame.LookVector
	local direction = Vector3.new(look.X, 0, look.Z)
	if direction.Magnitude > 0.01 then direction = direction.Unit end
	return {
		animal = animal,
		source = attackerHRP,
		direction = direction,
		radius = cfg.radius or cfg.landRadius,
		range = cfg.range or cfg.dist,
		angle = cfg.angle,
		duration = cfg.dur or cfg.window or cfg.armDur or cfg.extraWindow,
		sound = cfg.sound,
		ownerUserId = player and player.UserId or nil,
	}
end

local function measuredFxPower(animalData, cfg, basePower)
	local geometryScale = 1
	local model = animalData and animalData.model
	if model and model.Parent then
		local ok, _, size = pcall(model.GetBoundingBox, model)
		if ok and size then geometryScale = math.clamp(size.Magnitude / 7, 0.72, 1.42) end
	end
	local reach = cfg.radius or cfg.range or cfg.landRadius or cfg.dist or 8
	local reachScale = math.clamp(reach / 10, 0.72, 1.35)
	return math.clamp((basePower or 1) * (0.68 + geometryScale * 0.22 + reachScale * 0.10), 0.35, 2)
end

-- shove helpers hit both real players and bots

local function shovePlayerVictims(user, originPos, getDir, range, force, opts)
	opts = opts or {}
	for _, p in ipairs(PlayerManager.getAlivePlayers()) do
		if p ~= user then
			local data = AnimalManager.getAnimalData(p)
			if data and data.mode == "mount" and data.model and data.model.Parent then
				local r = data.model:FindFirstChild("HumanoidRootPart")
				if r then
					local off = Vector3.new(r.Position.X - originPos.X, 0, r.Position.Z - originPos.Z)
					local dist = off.Magnitude
					if dist > 0.1 and dist <= range then
						local dir = getDir(off, dist)
						if dir then
							if RoundManager and RoundManager.registerKnockback then
								RoundManager.registerKnockback(p)
							end
							lastAttacker[p] = { player = user, time = tick() }
							AnimalManager.applyPhysicsKnockback(p, dir, force, opts.pop)
						end
					end
				end
			end
		end
	end
end

local function shoveBotVictims(user, originPos, getDir, range, force)
	if not AIManager then return end
	for _, mount in ipairs(CollectionService:GetTagged("AIMount")) do
		local botId = mount:GetAttribute("BotId")
		local r = mount:FindFirstChild("HumanoidRootPart")
		if botId and r then
			local off = Vector3.new(r.Position.X - originPos.X, 0, r.Position.Z - originPos.Z)
			local dist = off.Magnitude
			if dist > 0.1 and dist <= range then
				local dir = getDir(off, dist)
				if dir then
					AIManager.applyKnockbackToBot(botId, user, dir, force)
				end
			end
		end
	end
end

local function radialShove(user, originPos, cfg)
	local getDir = function(off) return off.Unit end
	shovePlayerVictims(user, originPos, getDir, cfg.radius, cfg.force, cfg)
	shoveBotVictims(user, originPos, getDir, cfg.radius, cfg.force)
	if cfg.voxel then
		pcall(VoxelManager.breakAt, originPos)
	end
end

local function scheduleAbilityBurst(user, animal, expectedModel, delayTime, burst)
	if not expectedModel or not burst.radius or not burst.force then return end
	task.delay(math.max(delayTime or 0, 0), function()
		if not user.Parent or not PlayerManager.isInRound(user) or not PlayerManager.isAlive(user) then return end
		local data = AnimalManager.getAnimalData(user)
		if not data or data.mode ~= "mount" or data.model ~= expectedModel or not expectedModel.Parent then return end
		local root = expectedModel:FindFirstChild("HumanoidRootPart") or expectedModel.PrimaryPart
		if not root then return end

		local cfg = {
			radius = burst.radius,
			force = burst.force,
			pop = burst.pop,
			voxel = burst.voxel,
		}
		radialShove(user, root.Position, cfg)
		local details = buildFxDetails(user, animal, root, cfg)
		details.radius = burst.radius
		details.sound = nil
		fxAll(burst.effect or "slam", root.Position, measuredFxPower(data, cfg, burst.power or 0.9), details)
	end)
end

local function coneShove(user, attackerHRP, cfg)
	local look = attackerHRP.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 0.01 then return end
	facing = facing.Unit
	if cfg.behind then facing = -facing end
	local minDot = math.cos(math.rad((cfg.angle or 60) * 0.5))
	local origin = attackerHRP.Position
	local getDir = function(off, dist)
		if facing:Dot(off.Unit) < minDot then return nil end
		return off.Unit
	end
	shovePlayerVictims(user, origin, getDir, cfg.range, cfg.force, cfg)
	shoveBotVictims(user, origin, getDir, cfg.range, cfg.force)
end

-- raccoon barricade: destroyable cover that shoves whoever runs into it

local function spawnTrashWall(user, attackerHRP, cfg)
	local look = attackerHRP.CFrame.LookVector
	local back = -Vector3.new(look.X, 0, look.Z)
	if back.Magnitude < 0.01 then return end
	back = back.Unit

	local basePos = attackerHRP.Position + back * 5
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { attackerHRP.Parent }
	local groundHit = workspace:Raycast(basePos + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), rayParams)
	if groundHit then basePos = Vector3.new(basePos.X, groundHit.Position.Y, basePos.Z) end
	local baseCF = CFrame.lookAt(basePos, basePos + back)

	local wall = Instance.new("Model")
	wall.Name = "TrashWall"
	wall:SetAttribute("OwnerUserId", user.UserId)
	wall.Parent = workspace

	local touchCd = {}
	local function onTouched(hit, wallPart)
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model then return end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root or root == attackerHRP then return end
		local now = tick()
		if touchCd[model] and now - touchCd[model] < 0.65 then return end
		touchCd[model] = now
		local away = Vector3.new(root.Position.X - wallPart.Position.X, 0, root.Position.Z - wallPart.Position.Z)
		if away.Magnitude < 0.01 then away = back end
		away = away.Unit
		local botId = model:GetAttribute("BotId")
		if botId and AIManager then
			AIManager.applyKnockbackToBot(botId, user, away, 58)
			return
		end
		for _, targetPlayer in ipairs(PlayerManager.getAlivePlayers()) do
			if targetPlayer ~= user then
				local data = AnimalManager.getAnimalData(targetPlayer)
				if data and data.model == model then
					if RoundManager and RoundManager.registerKnockback then RoundManager.registerKnockback(targetPlayer) end
					AnimalManager.applyPhysicsKnockback(targetPlayer, away, 58, 32)
					return
				end
			end
		end
	end

	-- Keep the generated barricade on the shared MaterialService surface.
	local width  = cfg.width or 8
	local height = cfg.height or 5
	local part = Instance.new("Part")
	part.Name = "Brick"
	part.Size = Vector3.new(width, height, 1.4)
	part.CFrame = baseCF * CFrame.new(0, height * 0.5, 0)
	part.Anchored = true
	part.Material = Enum.Material.Plastic
	part.MaterialVariant = "Universal"
	part.Color = Color3.fromRGB(120, 85, 50)
	part:SetAttribute("Destroyable", true)
	part.Parent = wall
	part.Touched:Connect(function(hit) onTouched(hit, part) end)

	Debris:AddItem(wall, cfg.life or 6)
	return basePos
end

-- resolve which animal the player is actually riding, server authoritative
local function resolveAnimal(player, claimed)
	local data = AnimalManager.getAnimalData(player)
	if data and AbilityConfig.Abilities[data.name] then return data.name end
	local model = data and data.model
	local modelAnimal = model and AbilityConfig.resolveAnimalName(model:GetAttribute("AnimalName") or model.Name)
	if modelAnimal then return modelAnimal end
	return "Snail"
end

local function handleAbility(player, claimedAnimal)
	local data = AnimalManager.getAnimalData(player)
	if not data or data.mode ~= "mount" then return end
	local attackerHRP = getAttackerHRP(player)
	if not attackerHRP then return end

	local animal = resolveAnimal(player, claimedAnimal)
	local cfg = AbilityConfig.Abilities[animal]
	if not cfg then return end

	local cooldownNow = tick()
	if cfg.charges and cfg.charges > 1 then
		local interval = cfg.cd / cfg.charges
		local bank = abilityChargeState[player]
		if not bank or bank.animal ~= animal then
			bank = { animal = animal, tokens = cfg.charges, regenAt = cooldownNow + interval }
			abilityChargeState[player] = bank
		end
		while bank.tokens < cfg.charges and cooldownNow >= bank.regenAt do
			bank.tokens += 1
			bank.regenAt += interval
		end
		if bank.tokens < 1 then return end
		bank.tokens -= 1
		if bank.tokens == cfg.charges - 1 then bank.regenAt = cooldownNow + interval end
	else
		local last = abilityLast[player] or 0
		if cooldownNow - last < cfg.cd * ABILITY_CD_TOLERANCE then return end
		abilityLast[player] = cooldownNow
	end

	local now = tick()
	local pos = attackerHRP.Position
	local fxPower = measuredFxPower(data, cfg, 1)
	local presentation = AbilityConfig.getPresentation(animal, cfg)
	local fxDetails = buildFxDetails(player, animal, attackerHRP, cfg)

	if cfg.kind == "cone" then
		coneShove(player, attackerHRP, cfg)
		fxAll(presentation.effect, pos, fxPower, fxDetails)

	elseif cfg.kind == "radial" then
		radialShove(player, pos, cfg)
		if cfg.reflect then
			guardState[player] = { untilT = now + (cfg.reflectDur or 2), resist = 0, reflect = cfg.reflect }
			fxDetails.duration = cfg.reflectDur or 2
		end
		if cfg.cashBonus then
			cashBonus[player] = { untilT = now + (cfg.bonusWindow or 4), mult = cfg.cashBonus }
			fxDetails.duration = cfg.bonusWindow or 4
		end
		fxAll(presentation.effect, pos, fxPower * (cfg.voxel and 1.2 or 1), fxDetails)

	elseif cfg.kind == "guard" then
		guardState[player] = {
			untilT = now + cfg.dur,
			resist = cfg.resist or 0,
			reflect = cfg.reflect,
		}
		fxDetails.duration = cfg.dur
		fxAll(presentation.effect, pos, fxPower * 0.82, fxDetails)

	elseif cfg.kind == "empower" then
		empowerState[player] = {
			untilT = now + (cfg.window or 4),
			forceMult = cfg.forceMult or 1,
			radiusMult = cfg.radiusMult or 1,
			yank = cfg.yank or false,
		}
		fxDetails.duration = cfg.window or 4
		fxAll(presentation.effect, pos, fxPower, fxDetails)

	elseif cfg.kind == "rebirth" then
		local r = rebirthState[player]
		if not r then r = { usedThisRound = false }; rebirthState[player] = r end
		if r.usedThisRound then return end
		r.armed = true
		r.untilT = now + (cfg.armDur or 6)
		fxDetails.duration = cfg.armDur or 6
		fxAll(presentation.effect, pos, fxPower * 1.2, fxDetails)

	elseif cfg.kind == "wall" then
		local wallPosition = spawnTrashWall(player, attackerHRP, cfg) or pos
		fxDetails.position = wallPosition
		fxAll(presentation.effect, wallPosition, fxPower, fxDetails)

	elseif cfg.kind == "leap" then
		if cfg.landRadius then
			pendingLand[player] = { untilT = now + LAND_WINDOW, cfg = cfg, animal = animal }
		end
		fxAll(presentation.effect, pos, fxPower * 0.72, fxDetails)

	elseif cfg.kind == "burrow" then
		guardState[player] = { untilT = now + (cfg.dur or 1.2), resist = 1 }
		fxDetails.duration = cfg.dur or 1.2
		fxAll(presentation.effect, pos, fxPower, fxDetails)
		scheduleAbilityBurst(player, animal, data.model, cfg.dur or 1.2, {
			radius = cfg.emergeRadius,
			force = cfg.emergeForce,
			pop = cfg.emergePop,
			effect = cfg.emergeEffect,
			voxel = cfg.emergeVoxel,
			power = 1.05,
		})

	else
		if cfg.kind == "dash" and (cfg.immunity or 0) > 0 then
			guardState[player] = { untilT = now + cfg.immunity, resist = 1 }
		end
		if cfg.kind == "speed" and (cfg.resist or 0) > 0 then
			guardState[player] = { untilT = now + (cfg.dur or 3), resist = cfg.resist }
		end
		if cfg.kind == "refresh" and (cfg.resist or 0) > 0 then
			guardState[player] = { untilT = now + (cfg.resistDur or 0.5), resist = cfg.resist }
		end
		if cfg.kind == "blink" then
			fxDetails.destination = pos + fxDetails.direction * (cfg.dist or 14)
		end
		fxAll(presentation.effect, pos, fxPower * 0.82, fxDetails)
		scheduleAbilityBurst(player, animal, data.model, cfg.endDelay or cfg.dur or 0, {
			radius = cfg.endRadius,
			force = cfg.endForce,
			pop = cfg.endPop,
			effect = cfg.endEffect,
			voxel = cfg.endVoxel,
		})
	end
end

local function handleAbilityLand(player)
	local pend = pendingLand[player]
	if not pend then return end
	pendingLand[player] = nil
	if tick() > pend.untilT then return end
	local attackerHRP = getAttackerHRP(player)
	if not attackerHRP then return end
	local cfg = pend.cfg
	local pos = attackerHRP.Position
	radialShove(player, pos, {
		radius = cfg.landRadius,
		force = cfg.landForce or 55,
		pop = cfg.landPop,
		voxel = cfg.voxel,
	})
	local data = AnimalManager.getAnimalData(player)
	local animal = pend.animal or resolveAnimal(player)
	local impactPower = measuredFxPower(data, cfg, cfg.voxel and 1.4 or 1)
	local details = buildFxDetails(player, animal, attackerHRP, cfg)
	details.radius = cfg.landRadius
	details.sound = animal == "Tung" and "Slam" or cfg.sound
	local effect = cfg.landEffect
		or (animal == "Slime" and "bounce_land")
		or (animal == "Tung" and "tung_slam")
		or "slam"
	fxAll(effect, pos, impactPower, details)
end

-- public api

function CombatManager.getLastAttacker(victim)
	local entry = lastAttacker[victim]
	if not entry then return nil end
	if tick() - entry.time > ATTACKER_EXPIRY then
		lastAttacker[victim] = nil
		return nil
	end
	return entry.player
end

function CombatManager.clearAttacker(victim)
	lastAttacker[victim] = nil
end

function CombatManager.init(playerMgr, animalMgr, roundMgr)
	PlayerManager = playerMgr
	AnimalManager = animalMgr
	RoundManager  = roundMgr
	-- guards scale every knockback that flows through AnimalManager
	AnimalManager.setDefenseProvider(CombatManager.getDefenseScale)
end

function CombatManager.setAIManager(ai)
	AIManager = ai
end

function CombatManager.start()
	CombatRemote.OnServerEvent:Connect(function(player, action, ...)
		if typeof(action) ~= "string" then return end
		if not PlayerManager.isInRound(player) then return end
		if not AnimalManager.hasAnimal(player)  then return end

		local data = AnimalManager.getAnimalData(player)
		if not data or data.mode ~= "mount" then return end

		if action == "charge" then
			if not canUse(player, "charge") then return end
			setCooldown(player, "charge")
			chargeWindows[player] = {
				untilT = tick() + SERVER_CHARGE_WINDOW,
				hits = {},
			}
			-- sample the start position so momentum can be measured at impact
			local hrp = getAttackerHRP(player)
			if hrp then chargeStart[player] = { pos = hrp.Position, t = tick() } end
			-- flag the mount so WarningClient on other players can detect the charge
			if data.model and data.model.Parent then
				data.model:SetAttribute("ChargeActive", true)
				task.delay(SERVER_CHARGE_WINDOW, function()
					if data.model and data.model.Parent then
						data.model:SetAttribute("ChargeActive", false)
					end
				end)
			end
			if AIManager and AIManager.onPlayerCharge then
				pcall(AIManager.onPlayerCharge, player)
			end

		elseif action == "dash" then
			local dir = select(1, ...)
			if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.01 then return end
			if not canUse(player, "dash") then return end
			setCooldown(player, "dash")

		elseif action == "ability" then
			handleAbility(player, select(1, ...))

		elseif action == "abilityLand" then
			handleAbilityLand(player)

		elseif action == "knockback" then
			local target = select(1, ...)

			-- bot target path, same gates as pvp
			if typeof(target) == "string" then
				if not AIManager then return end
				local window = getChargeWindow(player)
				if not window or window.hits[target] then return end
				local botRoot = AIManager.getBotRoot(target)
				if not botRoot then return end
				local attackerHRP = getAttackerHRP(player)
				if not attackerHRP then return end
				local toBot = Vector3.new(
					botRoot.Position.X - attackerHRP.Position.X,
					0,
					botRoot.Position.Z - attackerHRP.Position.Z
				)
				if toBot.Magnitude > BOT_MAX_HIT_DISTANCE or toBot.Magnitude < 0.1 then return end
				local facing = Vector3.new(attackerHRP.CFrame.LookVector.X, 0, attackerHRP.CFrame.LookVector.Z)
				if facing.Magnitude < 0.01 or facing.Unit:Dot(toBot.Unit) < HIT_FORWARD_DOT then return end

				local force = CHARGE_KNOCKBACK_FORCE * momentumScale(player, attackerHRP)
				local emp = empowerState[player]
				if emp and tick() <= emp.untilT then
					force = force * (emp.forceMult or 1)
					empowerState[player] = nil
				end
				if AIManager.applyKnockbackToBot(target, player, attackerHRP.CFrame.LookVector, force) then
					window.hits[target] = true
				end
				return
			end

			local targetPlayer = target

			if typeof(targetPlayer) ~= "Instance"      then return end
			if not targetPlayer:IsA("Player")          then return end
			if targetPlayer == player                  then return end
			if not Players:GetPlayerByUserId(targetPlayer.UserId) then return end

			if not PlayerManager.isInRound(targetPlayer) then return end
			if not PlayerManager.isAlive(targetPlayer)   then return end

			local victimData = AnimalManager.getAnimalData(targetPlayer)
			if not victimData or victimData.mode ~= "mount" then return end

			local window = getChargeWindow(player)
			if not window or window.hits[targetPlayer] then return end

			local attackerHRP = getAttackerHRP(player)
			if not attackerHRP then return end

			local attackerChar = player.Character
			if not attackerChar then return end

			local targetChar = targetPlayer.Character
			if not targetChar then return end

			local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
			if not targetHRP then return end

			local toTarget = Vector3.new(
				targetHRP.Position.X - attackerHRP.Position.X,
				0,
				targetHRP.Position.Z - attackerHRP.Position.Z
			)
			local dist = toTarget.Magnitude

			-- empower can grow the effective hit radius
			local emp = empowerState[player]
			local radiusMult = (emp and tick() <= emp.untilT and emp.radiusMult) or 1
			if dist > MAX_HIT_DISTANCE * radiusMult or dist < 0.1 then return end

			local facing = Vector3.new(attackerHRP.CFrame.LookVector.X, 0, attackerHRP.CFrame.LookVector.Z)
			if facing.Magnitude < 0.01 or facing.Unit:Dot(toTarget.Unit) < HIT_FORWARD_DOT then return end

			local victimAnimalModel = victimData.model or nil
			local hitIsValid = HitboxModule.validateChargeHit(
				attackerHRP, attackerChar, targetChar, victimAnimalModel
			)

			-- spatial box can miss valid hits under lag, the distance gate
			-- above already blocks ranged abuse so a close miss still counts
			if not hitIsValid and dist > FALLBACK_HIT_DISTANCE * radiusMult then
				return
			end

			local direction = attackerHRP.CFrame.LookVector
			local force = CHARGE_KNOCKBACK_FORCE * momentumScale(player, attackerHRP)

			local yank = false
			if emp and tick() <= emp.untilT then
				force = force * (emp.forceMult or 1)
				yank = emp.yank or false
				empowerState[player] = nil
			end

			lastAttacker[targetPlayer] = { player = player, time = tick() }
			window.hits[targetPlayer] = true

			if RoundManager then
				RoundManager.registerKnockback(targetPlayer)
			end

			if yank then
				-- gravity yank: pull the victim toward the attacker, the
				-- client side vertical pop turns it into a straight launch up
				AnimalManager.applyPhysicsKnockback(targetPlayer, -direction, force * 0.5)
			else
				AnimalManager.applyPhysicsKnockback(targetPlayer, direction, force)
			end

			-- prism reflect: a guarded victim mirrors part of the hit back
			local vg = guardState[targetPlayer]
			if vg and tick() <= vg.untilT and vg.reflect and vg.reflect > 0 then
				if RoundManager then RoundManager.registerKnockback(player) end
				AnimalManager.applyPhysicsKnockback(player, -direction, force * vg.reflect)
			end
		end
	end)
end

function CombatManager.cleanup(player)
	cooldowns[player]     = nil
	lastAttacker[player]  = nil
	chargeWindows[player] = nil
	chargeStart[player]   = nil
	abilityLast[player] = nil
	abilityChargeState[player] = nil
	guardState[player]    = nil
	empowerState[player]  = nil
	rebirthState[player]  = nil
	cashBonus[player]     = nil
	pendingLand[player]   = nil

	local toRemove = {}
	for victim, entry in pairs(lastAttacker) do
		if entry and entry.player == player then
			table.insert(toRemove, victim)
		end
	end
	for _, victim in ipairs(toRemove) do
		lastAttacker[victim] = nil
	end
end

return CombatManager

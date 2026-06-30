--[[
    AbilityController (ModuleScript - client)

    The old dash button is now the ABILITY button. Every animal has a unique
    active ability defined in ReplicatedStorage.Modules.AbilityConfig. Charge
    stays universal on Q / L2, the ability lives on E / R2 / the second touch
    button.

    Movement kinds (dash, leap, blink, speed, burrow) execute here on the
    client through AnimalController. Authority kinds (shoves, guards,
    empowers, rebirth, wall) are validated and executed by the server, the
    client just fires the request and plays sound and pose.

    The mid-air RECOVERY dash stays universal for every animal: pressing the
    ability button while flying from a knockback kills your momentum and
    dashes toward your input. It runs on its own short cooldown so defensive
    pets are not punished for having long ability cooldowns.

    The button cooldown ring reads getDashCooldown(), which now returns the
    equipped animal's cooldown so the UI always matches.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local RemoteEvents  = ReplicatedStorage:WaitForChild("RemoteEvents")
local CombatRemote  = RemoteEvents:WaitForChild("CombatRemote")
local AbilityConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AbilityConfig"))

local CHARGE_COOLDOWN   = 3
local RECOVERY_COOLDOWN = 1.5
local POSE_BLEND_IN     = 0.12
local POSE_BLEND_OUT    = 0.25

local AbilityController = {}

local AnimalController = nil
local AnimationEngine  = nil

local abilitiesEnabled = true
local chargeLastUsed   = 0
local abilityLastUsed  = 0
local recoveryLastUsed = 0
local abilityBusyUntil = 0
local abilitySerial = 0

-- charge-based abilities (Cat) bank uses client side
local storedCharges  = nil
local chargeRegenAt  = 0
local chargesAnimal  = nil

local activePose     = "none"
local poseStrength   = 0
local poseEndTime    = 0
local poseBlendIn    = false
local poseBlendStart = 0

-- sounds: ability sounds live in SFX.Abilities, fall back to the old dash hit

local function playSoundByName(name)
	local sfx = SoundService:FindFirstChild("SFX")
	if not sfx then return end
	local abilities = sfx:FindFirstChild("Abilities")
	local snd = abilities and name and abilities:FindFirstChild(name)
	if snd and snd.SoundId ~= "" then
		pcall(function() snd:Play() end)
		return
	end
	local misc = sfx:FindFirstChild("Misc")
	local fallback = misc and misc:FindFirstChild("Dash")
	if fallback then pcall(function() fallback:Play() end) end
end

local function playAbilitySFX()
	playSoundByName(nil)
end

-- pose management

local function setPose(name, duration)
	activePose     = name
	poseStrength   = 0
	poseEndTime    = tick() + duration
	poseBlendIn    = true
	poseBlendStart = tick()
end

local function clearPose()
	activePose   = "none"
	poseStrength = 0
end

function AbilityController.getAbilityPose()
	local now = tick()
	if activePose == "none" then return "none", 0 end
	if now >= poseEndTime then clearPose(); return "none", 0 end
	local remaining = poseEndTime - now
	if poseBlendIn then
		local elapsed = now - poseBlendStart
		if elapsed < POSE_BLEND_IN then
			poseStrength = elapsed / POSE_BLEND_IN
		else
			poseStrength = 1; poseBlendIn = false
		end
	elseif remaining < POSE_BLEND_OUT then
		poseStrength = remaining / POSE_BLEND_OUT
	else
		poseStrength = 1
	end
	return activePose, poseStrength
end

-- config helpers

local function currentAbility()
	local animalName = AnimalController and AnimalController.getAnimalName() or nil
	return AbilityConfig.getFor(animalName)
end

function AbilityController.getChargeCooldown() return CHARGE_COOLDOWN end

function AbilityController.getDashCooldown()
	local cfg = currentAbility()
	if cfg and cfg.charges and cfg.charges > 1 then
		return cfg.cd / cfg.charges
	end
	return cfg and cfg.cd or 5
end

function AbilityController.setAbilitiesEnabled(v)
	if v and not abilitiesEnabled then
		chargeLastUsed = 0
		abilityLastUsed = 0
		recoveryLastUsed = 0
		abilityBusyUntil = 0
		storedCharges = nil
		chargesAnimal = nil
		abilitySerial += 1
		clearPose()
	end
	abilitiesEnabled = v
end

function AbilityController.canCharge()
	return abilitiesEnabled and (tick() - chargeLastUsed) >= CHARGE_COOLDOWN
end

local function canUseAbility(cfg)
	if not abilitiesEnabled or tick() < abilityBusyUntil then return false end
	-- charge-banked abilities track their own tokens
	if cfg.charges and cfg.charges > 1 then
		local animalName = AnimalController and AnimalController.getAnimalName()
		if chargesAnimal ~= animalName then
			chargesAnimal = animalName
			storedCharges = cfg.charges
			chargeRegenAt = 0
		end
		if storedCharges < cfg.charges and tick() >= chargeRegenAt then
			storedCharges = math.min(cfg.charges, storedCharges + 1)
			if storedCharges < cfg.charges then chargeRegenAt = tick() + cfg.cd / cfg.charges end
		end
		return storedCharges > 0
	end
	return (tick() - abilityLastUsed) >= cfg.cd
end

function AbilityController.canDash()
	local cfg = currentAbility()
	if not cfg then return false end
	return canUseAbility(cfg)
end

-- charge, unchanged and universal

function AbilityController.charge()
	if not AbilityController.canCharge() then return false end
	if not AnimalController               then return false end
	if not AnimalController.isInRound()  then return false end
	if not AnimalController.isMounted()  then return false end

	chargeLastUsed = tick()
	CombatRemote:FireServer("charge")
	AnimalController.startCharge()
	playAbilitySFX()
	setPose("charge", 0.65)
	return true
end

-- the ability button

local function consumeAbilityUse(cfg)
	if cfg.charges and cfg.charges > 1 then
		storedCharges = math.max(0, (storedCharges or cfg.charges) - 1)
		if chargeRegenAt < tick() then chargeRegenAt = tick() + cfg.cd / cfg.charges end
	else
		abilityLastUsed = tick()
	end
end

local function executeAbility(cfg, animalName, direction, presentation, serial)
	if serial ~= abilitySerial then return end
	if not AnimalController or not AnimalController.isInRound() or not AnimalController.isMounted() then return end
	if AnimalController.getAnimalName() ~= animalName then return end
	if AnimalController.isInKnockback() then return end

	local executed = false
	local kind = cfg.kind

	if kind == "dash" then
		if cfg.lowControl then
			executed = AnimalController.performSlide(cfg.force, cfg.dur)
		else
			executed = AnimalController.startDash(direction, cfg.force, cfg.dur, cfg.immunity)
		end
	elseif kind == "leap" then
		executed = AnimalController.performLeap(cfg.vert, cfg.horiz, cfg.landPose, cfg.landPoseDur)
	elseif kind == "blink" then
		executed = AnimalController.performBlink(cfg.dist or 14)
	elseif kind == "speed" then
		executed = AnimalController.performSpeedBoost(cfg.mult, cfg.dur)
	elseif kind == "burrow" then
		executed = AnimalController.performBurrow(cfg.dur, cfg.moveMult)
	elseif kind == "refresh" then
		executed = AnimalController.grantExtraRecovery(cfg.extraWindow)
	elseif kind == "guard" then
		executed = AnimalController.performGuard(cfg.dur, cfg.canMove, cfg.moveMult)
	else
		executed = true
	end

	if not executed then return end
	if cfg.moveBoostMult then
		AnimalController.performSpeedBoost(cfg.moveBoostMult, cfg.moveBoostDur or 2)
	end
	consumeAbilityUse(cfg)
	CombatRemote:FireServer("ability", animalName)
	setPose(presentation.actionPose or cfg.pose or "charge", presentation.actionDur or AbilityConfig.getPoseDuration(cfg))

	if cfg.airPose then
		task.delay(cfg.poseDur or 0.16, function()
			if serial == abilitySerial and AnimalController and AnimalController.getAnimalName() == animalName then
				setPose(cfg.airPose, cfg.airPoseDur or 0.65)
			end
		end)
	end
end

function AbilityController.dash()
	if not AnimalController then return false end
	if not AnimalController.isInRound() or not AnimalController.isMounted() then return false end

	local direction = AnimalController.getDashDirection()
	if not direction or direction.Magnitude < 0.01 then
		direction = AnimalController.getPlayerForwardDirection()
	end

	if AnimalController.isInKnockback() then
		if tick() - recoveryLastUsed < RECOVERY_COOLDOWN then return false end
		if AnimalController.tryRecoveryDash(direction) then
			recoveryLastUsed = tick()
			CombatRemote:FireServer("dash", direction)
			playSoundByName("Dash")
			setPose("dashForward", 0.45)
			return true
		end
		return false
	end

	local cfg, animalName = currentAbility()
	if not cfg or not canUseAbility(cfg) then return false end

	local presentation = AbilityConfig.getPresentation(animalName, cfg)
	local windup = presentation.windup or 0
	abilitySerial += 1
	local serial = abilitySerial
	abilityBusyUntil = tick() + windup + 0.08

	if presentation.windupPose and windup > 0 then
		setPose(presentation.windupPose, windup + 0.08)
	end

	if windup <= 0 then
		executeAbility(cfg, animalName, direction, presentation, serial)
	else
		task.delay(windup, function()
			executeAbility(cfg, animalName, direction, presentation, serial)
		end)
	end
	return true
end

-- init

function AbilityController.init(animalCtrl, animEngine)
	AnimalController = animalCtrl
	AnimationEngine  = animEngine
	if AnimationEngine and AnimationEngine.setAbilityController then
		AnimationEngine.setAbilityController(AbilityController)
	end
end

-- server to client combat events, most importantly knockback delivery
function AbilityController.startListening()
	CombatRemote.OnClientEvent:Connect(function(action, ...)
		if action == "physicsKnockback" then
			local dir, force, verticalPop = ...
			if AnimalController and typeof(dir) == "Vector3" then
				AnimalController.receivePhysicsKnockback(dir, force, verticalPop)
			end
		end
	end)
end

return AbilityController

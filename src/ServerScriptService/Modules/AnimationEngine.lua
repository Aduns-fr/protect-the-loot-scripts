--[[
	AnimationEngine
	Procedural animation system for animal models.

	CHANGES:
	  * IGNORE_PARTS: beak, facedecor, frontdecor, bodydecor, tailfin, fin, battip.
	  * IS_ARM / IS_BAT tables for Tung.
	  * Arm walk: leftarm phase=0, rightarm phase=pi - deterministic opposite swing,
	    25 degrees arc so the walk reads clearly on Tung's chunky arms.
	  * Bat: menacing slow waggle that ramps with movement.
	  * dashLeft / dashRight leg/backleg Z-rotation sign fix (unchanged).
]]

local AnimationEngine = {}

local CONFIG = {
	walkFreq      = 2.8,
	walkBounce    = 0.18,
	walkLean      = 4,
	walkHeadBob   = 5,
	walkLegSwing  = 22,
	walkTailWag   = 18,
	idleFreq      = 0.9,
	idleBounce    = 0.03,
	idleBodySway  = 1.2,
	idleHeadLook  = 5,
	idleTailSway  = 6,
	blendRate     = 4,
	backLegSwing  = 28,
	wingFreq      = 3.5,
	wingSwing     = 30,
	neckBob       = 6,
	shellSway     = 0.8,
}

local IGNORE_PARTS = {
	seat             = true,
	humanoidrootpart = true,
	eye = true, eyes = true, nose = true, nostrils = true,
	beakupper = true, beaklower = true, beak = true,
	facedecor = true, frontdecor = true, bodydecor = true,
	tailfin = true, fin = true,
	pattern = true,
	cluck = true, mane = true, hooves = true, hoof = true, decor = true,
	battip = true,  -- static sub-joint of Tung's bat
}

local IS_BODY      = { stomach=true, torso=true, body=true, chest=true }
local IS_HEAD      = { head=true, hair=true }
local IS_TAIL      = { tail=true, bum=true }
local IS_NECK      = { neck=true, neck2=true }
local IS_SHELL     = { shell=true }
local IS_WING      = { lw=true, rw=true }
local IS_BACK_LEG  = { bl=true, br=true }
local IS_FRONT_LEG = { fl=true, fr=true }
local IS_LOWER_LEG = { foot=true, feet=true }
local IS_ARM       = { leftarm=true, rightarm=true }
local IS_BAT       = { bat=true }

local ABILITY_POSES = {
	charge = {
		body     = CFrame.Angles(math.rad(-15), 0, 0),
		head     = CFrame.Angles(math.rad(-10), 0, 0),
		neck     = CFrame.Angles(math.rad(-8),  0, 0),
		leg      = CFrame.Angles(math.rad( 20), 0, 0),
		backleg  = CFrame.Angles(math.rad( 25), 0, 0),
		lowerleg = CFrame.Angles(math.rad( 10), 0, 0),
		tail     = CFrame.Angles(math.rad( 25), 0, 0),
		tailseg  = CFrame.Angles(math.rad( 15), 0, 0),
		wing     = CFrame.Angles(0, 0, math.rad(-20)),
		shell    = CFrame.Angles(math.rad(-5),  0, 0),
		arm      = CFrame.Angles(math.rad(-25), 0, 0),
		bat      = CFrame.Angles(0, math.rad(30), 0),
	},
	dashLeft = {
		body    = CFrame.Angles(0, 0, math.rad( 12)),
		head    = CFrame.Angles(0, math.rad( 10), math.rad( 5)),
		neck    = CFrame.Angles(0, math.rad(  8), math.rad( 3)),
		leg     = CFrame.Angles(0, 0, math.rad( 8)),
		backleg = CFrame.Angles(0, 0, math.rad( 6)),
		tail    = CFrame.Angles(0, math.rad(-15), 0),
		wing    = CFrame.Angles(0, 0, math.rad(-15)),
		arm     = CFrame.Angles(0, 0, math.rad(-12)),
	},
	dashRight = {
		body    = CFrame.Angles(0, 0, math.rad(-12)),
		head    = CFrame.Angles(0, math.rad(-10), math.rad(-5)),
		neck    = CFrame.Angles(0, math.rad( -8), math.rad(-3)),
		leg     = CFrame.Angles(0, 0, math.rad(-8)),
		backleg = CFrame.Angles(0, 0, math.rad(-6)),
		tail    = CFrame.Angles(0, math.rad( 15), 0),
		wing    = CFrame.Angles(0, 0, math.rad( 15)),
		arm     = CFrame.Angles(0, 0, math.rad(12)),
	},
	dashForward = {
		body    = CFrame.Angles(math.rad(-10), 0, 0),
		head    = CFrame.Angles(math.rad( -8), 0, 0),
		neck    = CFrame.Angles(math.rad( -6), 0, 0),
		leg     = CFrame.Angles(math.rad( 12), 0, 0),
		backleg = CFrame.Angles(math.rad( 16), 0, 0),
		tail    = CFrame.Angles(math.rad( 15), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad(-10)),
		arm     = CFrame.Angles(math.rad(-18), 0, 0),
		bat     = CFrame.Angles(0, 0, math.rad(-10)),
	},
	dashBack = {
		body    = CFrame.Angles(math.rad( 10), 0, 0),
		head    = CFrame.Angles(math.rad(  8), 0, 0),
		neck    = CFrame.Angles(math.rad(  6), 0, 0),
		leg     = CFrame.Angles(math.rad(-12), 0, 0),
		backleg = CFrame.Angles(math.rad(-16), 0, 0),
		tail    = CFrame.Angles(math.rad(-10), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad( 10)),
		arm     = CFrame.Angles(math.rad(12), 0, 0),
	},
	-- ability poses below, one entry per visual verb shared across the roster
	shellTuck = {
		body     = CFrame.Angles(math.rad(-12), 0, 0),
		head     = CFrame.Angles(math.rad( 35), 0, 0),
		neck     = CFrame.Angles(math.rad( 20), 0, 0),
		leg      = CFrame.Angles(math.rad( 55), 0, 0),
		backleg  = CFrame.Angles(math.rad(-55), 0, 0),
		tail     = CFrame.Angles(math.rad( 30), 0, 0),
		shell    = CFrame.Angles(math.rad( -8), 0, 0),
		arm      = CFrame.Angles(math.rad( 40), 0, 0),
	},
	puffUp = {
		body    = CFrame.Angles(math.rad(  6), 0, 0),
		head    = CFrame.Angles(math.rad(-14), 0, 0),
		neck    = CFrame.Angles(math.rad( -8), 0, 0),
		leg     = CFrame.Angles(0, 0, math.rad( 14)),
		backleg = CFrame.Angles(0, 0, math.rad(-14)),
		tail    = CFrame.Angles(math.rad(-22), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad(-28)),
		arm     = CFrame.Angles(0, 0, math.rad(-20)),
	},
	rearUp = {
		body    = CFrame.Angles(math.rad( 24), 0, 0),
		head    = CFrame.Angles(math.rad( 14), 0, 0),
		neck    = CFrame.Angles(math.rad( 12), 0, 0),
		leg     = CFrame.Angles(math.rad(-48), 0, 0),
		backleg = CFrame.Angles(math.rad( 12), 0, 0),
		tail    = CFrame.Angles(math.rad(-18), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad(-35)),
		arm     = CFrame.Angles(math.rad(-45), 0, 0),
		bat     = CFrame.Angles(0, math.rad(45), 0),
	},
	headbutt = {
		body    = CFrame.Angles(math.rad(-14), 0, 0),
		head    = CFrame.Angles(math.rad(-34), 0, 0),
		neck    = CFrame.Angles(math.rad(-20), 0, 0),
		leg     = CFrame.Angles(math.rad( 18), 0, 0),
		backleg = CFrame.Angles(math.rad( 26), 0, 0),
		tail    = CFrame.Angles(math.rad( 20), 0, 0),
	},
	slam = {
		body     = CFrame.Angles(math.rad(-20), 0, 0),
		head     = CFrame.Angles(math.rad(-12), 0, 0),
		neck     = CFrame.Angles(math.rad(-10), 0, 0),
		leg      = CFrame.Angles(0, 0, math.rad( 22)),
		backleg  = CFrame.Angles(0, 0, math.rad(-22)),
		tail     = CFrame.Angles(math.rad( 25), 0, 0),
		wing     = CFrame.Angles(0, 0, math.rad(-40)),
		arm      = CFrame.Angles(math.rad(-70), 0, 0),
		bat      = CFrame.Angles(math.rad(-60), 0, 0),
	},
	burrowDown = {
		body    = CFrame.Angles(math.rad(-30), 0, 0),
		head    = CFrame.Angles(math.rad(-25), 0, 0),
		neck    = CFrame.Angles(math.rad(-15), 0, 0),
		leg     = CFrame.Angles(math.rad( 35), 0, 0),
		backleg = CFrame.Angles(math.rad( 40), 0, 0),
		tail    = CFrame.Angles(math.rad( 35), 0, 0),
	},
	bellySlide = {
		body    = CFrame.Angles(math.rad(-65), 0, 0),
		head    = CFrame.Angles(math.rad( 45), 0, 0),
		neck    = CFrame.Angles(math.rad( 25), 0, 0),
		leg     = CFrame.Angles(math.rad( 70), 0, 0),
		backleg = CFrame.Angles(math.rad(-70), 0, 0),
		tail    = CFrame.Angles(math.rad(-20), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad( 45)),
	},
	wingFlare = {
		body    = CFrame.Angles(math.rad( 12), 0, 0),
		head    = CFrame.Angles(math.rad(  8), 0, 0),
		neck    = CFrame.Angles(math.rad(  6), 0, 0),
		leg     = CFrame.Angles(math.rad(-14), 0, 0),
		backleg = CFrame.Angles(math.rad(  8), 0, 0),
		tail    = CFrame.Angles(math.rad( 15), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad(-62)),
		arm     = CFrame.Angles(0, 0, math.rad(-40)),
	},
	squash = {
		body    = CFrame.Angles(math.rad(-18), 0, 0),
		head    = CFrame.Angles(math.rad( 12), 0, 0),
		leg     = CFrame.Angles(math.rad( 45), 0, 0),
		backleg = CFrame.Angles(math.rad(-45), 0, 0),
		tail    = CFrame.Angles(math.rad( 18), 0, 0),
	},
	leapStretch = {
		body    = CFrame.Angles(math.rad(-12), 0, 0),
		head    = CFrame.Angles(math.rad(-10), 0, 0),
		neck    = CFrame.Angles(math.rad( -8), 0, 0),
		leg     = CFrame.Angles(math.rad(-30), 0, 0),
		backleg = CFrame.Angles(math.rad( 38), 0, 0),
		tail    = CFrame.Angles(math.rad( 28), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad(-50)),
		arm     = CFrame.Angles(math.rad(-35), 0, 0),
	},
	honk = {
		body    = CFrame.Angles(math.rad( 10), 0, 0),
		head    = CFrame.Angles(math.rad(-28), 0, 0),
		neck    = CFrame.Angles(math.rad(-32), 0, 0),
		tail    = CFrame.Angles(math.rad(-15), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad(-45)),
	},
	backKick = {
		body    = CFrame.Angles(math.rad(-22), 0, 0),
		head    = CFrame.Angles(math.rad(-12), 0, 0),
		neck    = CFrame.Angles(math.rad(-10), 0, 0),
		leg     = CFrame.Angles(math.rad( 15), 0, 0),
		backleg = CFrame.Angles(math.rad(-55), 0, 0),
		tail    = CFrame.Angles(math.rad(-30), 0, 0),
	},
	brace = {
		body    = CFrame.Angles(math.rad(-8), 0, 0),
		head    = CFrame.Angles(math.rad(-5), 0, 0),
		neck    = CFrame.Angles(math.rad(-4), 0, 0),
		leg     = CFrame.Angles(math.rad(18), 0, math.rad(12)),
		backleg = CFrame.Angles(math.rad(-12), 0, math.rad(-12)),
		tail    = CFrame.Angles(math.rad(18), 0, 0),
		wing    = CFrame.Angles(0, 0, math.rad(-22)),
		arm     = CFrame.Angles(math.rad(20), 0, math.rad(-12)),
	},
	calm = {
		head    = CFrame.Angles(0, 0, math.rad(6)),
	},
}

local function buildKnockbackPose()
	return {
		body     = CFrame.Angles(math.rad(18), 0, math.rad(math.random(-5, 5))),
		head     = CFrame.Angles(math.rad(15), math.rad(math.random(-8, 8)), 0),
		neck     = CFrame.Angles(math.rad(10), math.rad(math.random(-5, 5)), 0),
		leg      = CFrame.Angles(math.rad(-15), 0, math.rad(10)),
		backleg  = CFrame.Angles(math.rad(-18), 0, math.rad(12)),
		lowerleg = CFrame.Angles(math.rad(-8),  0, 0),
		tail     = CFrame.Angles(math.rad(-20), math.rad(math.random(-10, 10)), 0),
		tailseg  = CFrame.Angles(math.rad(-10), math.rad(math.random(-15, 15)), 0),
		wing     = CFrame.Angles(0, 0, math.rad(math.random(-20, 20))),
		arm      = CFrame.Angles(math.rad(20), math.rad(math.random(-25, 25)), math.rad(math.random(-15, 15))),
		bat      = CFrame.Angles(math.rad(math.random(-35, 35)), math.rad(math.random(-35, 35)), 0),
	}
end

local AbilityController = nil

function AnimationEngine.setAbilityController(ctrl)
	AbilityController = ctrl
end

function AnimationEngine.setPose(data, poseName, duration)
	if not data then return end
	local now = tick()
	local poseDuration = duration or 0.6
	data.abilityPose = poseName or "none"
	data.abilityPoseStarted = now
	data.abilityPoseBlendIn = math.min(0.1, poseDuration * 0.3)
	data.abilityPoseUntil = now + poseDuration
end

local function scalePose(poseCF, strength)
	if not poseCF    then return CFrame.new() end
	if strength >= 1 then return poseCF       end
	if strength <= 0 then return CFrame.new() end
	return CFrame.new():Lerp(poseCF, strength)
end

local POSE_HIP_RATIO = {
	shellTuck = -0.16, puffUp = 0.03, rearUp = 0.08, headbutt = -0.05,
	slam = -0.12, burrowDown = -0.28, bellySlide = -0.22, wingFlare = 0.05,
	squash = -0.20, leapStretch = 0.10, honk = 0.04, backKick = 0.03,
}

local ANIMAL_STYLE = {
	Snail={head=0.78,shell=1.22,hip=1.10}, Chicken={wing=1.24,leg=0.92},
	Sheep={pose=0.96}, Pig={pose=1.04}, Cow={head=1.12,leg=1.06,backleg=1.06},
	Rabbit={leg=1.12,backleg=1.28,hip=1.08}, Duck={wing=1.18,neck=1.08},
	Goat={head=1.28,leg=1.08}, Worm={head=0.88,tail=1.18,hip=1.12},
	Fox={pose=1.06}, Wolf={head=1.14,pose=1.05}, Cat={pose=1.10},
	Panda={pose=1.15,hip=1.08}, Lion={head=1.22,pose=1.08},
	Horse={leg=1.16,backleg=1.20}, Capybara={pose=0.72,head=0.78},
	Axolotl={tail=1.28,leg=0.92}, Unicorn={head=1.08,pose=1.06},
	Dragon={wing=1.24,tail=1.16,head=1.08}, Slime={body=1.34,hip=1.30},
	Phoenix={wing=1.28,neck=1.12}, ArcticFox={pose=1.10},
	GoldenGoose={wing=1.22,head=1.16,neck=1.12}, GoldenSnail={head=0.82,shell=1.28,hip=1.08},
	Giraffe={neck=1.26,backleg=1.34,leg=0.94}, Raccoon={pose=1.06},
	KoiFish={tailseg=1.32,head=0.88,hip=0.70}, Penguin={wing=1.14,leg=1.10,hip=1.18},
	RedPanda={pose=1.18}, Tung={arm=1.28,leg=1.16,hip=1.20},
	RainbowSheep={pose=1.12}, UpsideDownCow={head=1.12,leg=1.10,backleg=1.10},
}

local function adaptPose(poseCF, joint, data, poseName, poseDef)
	if not poseCF then return CFrame.new() end
	local combined = poseCF
	if data.animalName == "Tung" and poseName == "slam" and joint.cat == "arm" and joint.side < 0 and poseDef.bat then
		combined = combined * poseDef.bat
	end
	local rx, ry, rz = combined:ToOrientation()
	local style = data.style
	local styleScale = (style.pose or 1) * (style[joint.cat] or 1)
	local geometryScale = joint.motionScale or 1
	if joint.cat == "body" then
		geometryScale *= math.clamp((data.modelSize.Z / math.max(data.modelSize.Y, 0.1)) ^ 0.18, 0.82, 1.18)
	elseif joint.cat == "neck" then
		geometryScale *= math.clamp((data.modelSize.Y / math.max(joint.partSize.Y, 0.1)) ^ 0.08, 0.88, 1.16)
	end
	local scale = math.clamp(styleScale * geometryScale, 0.55, 1.65)
	local translation = combined.Position * math.clamp(data.modelSize.Magnitude / 7, 0.75, 1.35)
	return CFrame.new(translation) * CFrame.Angles(rx * scale, ry * scale, rz * scale)
end

function AnimationEngine.setup(model, animalHumanoid, animalRoot)
	local _, boxSize = model:GetBoundingBox()
	boxSize = Vector3.new(math.max(boxSize.X, 0.1), math.max(boxSize.Y, 0.1), math.max(boxSize.Z, 0.1))
	local childJoints = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("Motor6D") and desc.Part0 and desc.Part1 then
			if not childJoints[desc.Part0] then childJoints[desc.Part0] = {} end
			table.insert(childJoints[desc.Part0], desc)
		end
	end

	local lowestY = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local bottom = part.Position.Y - part.Size.Y * 0.5
			if bottom < lowestY then lowestY = bottom end
		end
	end

	local resolvedAnimalName = model:GetAttribute("AnimalName") or string.match(model.Name, "_([%w]+)$") or model.Name
	local data = {
		animalName          = resolvedAnimalName,
		modelSize           = boxSize,
		style               = ANIMAL_STYLE[resolvedAnimalName] or {},
		baseHip             = animalHumanoid.HipHeight,
		hrpToGround         = animalRoot.Position.Y - lowestY,
		blend               = 0,
		smoothVel           = 0,
		settling            = 0,
		wasMoving           = false,
		joints              = {},
		_knockbackPoseCache = nil,
		_lastKnockbackId    = 0,
	}

	local function addJoint(motor, category, phase)
		local part = motor.Part1
		local relative = animalRoot.CFrame:PointToObjectSpace(part.Position)
		local modelDiag = math.max(boxSize.Magnitude, 0.1)
		local partDiag = math.max(part.Size.Magnitude, 0.05)
		local lever = math.max(motor.C0.Position.Magnitude, motor.C1.Position.Magnitude, partDiag * 0.28, 0.05)
		local referenceLever = modelDiag * 0.16
		local leverageScale = math.clamp(math.sqrt(referenceLever / lever), 0.72, 1.34)
		local visualWeight = math.clamp((partDiag / modelDiag) * 4.5, 0.55, 1.35)
		local motionScale = math.clamp(leverageScale * (0.88 + visualWeight * 0.12), 0.70, 1.38)
		table.insert(data.joints, {
			motor       = motor,
			origC0      = motor.C0,
			cat         = category,
			phase       = phase or 0,
			partSize    = part.Size,
			relative    = relative,
			side        = relative.X < -0.05 and -1 or (relative.X > 0.05 and 1 or 0),
			motionScale = motionScale,
		})
	end

	local function legPhase(part)
		local relative = animalRoot.CFrame:PointToObjectSpace(part.Position)
		return ((relative.Z < 0) == (relative.X > 0)) and 0 or math.pi
	end

	local function walkTailChain(parentPart, depth, basePhase)
		for _, subMotor in ipairs(childJoints[parentPart] or {}) do
			local segName = subMotor.Part1.Name:lower()
			if IGNORE_PARTS[segName] then continue end
			addJoint(subMotor, "tailseg", basePhase + depth * 0.3)
			walkTailChain(subMotor.Part1, depth + 1, basePhase)
		end
	end

	local function walkNeckChain(parentPart, depth)
		for _, subMotor in ipairs(childJoints[parentPart] or {}) do
			local segName = subMotor.Part1.Name:lower()
			if IGNORE_PARTS[segName] then continue end
			if IS_NECK[segName] then
				addJoint(subMotor, "neck", depth * 0.4)
				walkNeckChain(subMotor.Part1, depth + 1)
			elseif IS_HEAD[segName] then
				addJoint(subMotor, "head")
				for _, headChild in ipairs(childJoints[subMotor.Part1] or {}) do
					if headChild.Part1.Name:lower() == "ear" then
						addJoint(headChild, "antenna", math.random() * math.pi)
					end
				end
			end
		end
	end

	local function walkArmChain(armPart, armPhase)
		for _, subMotor in ipairs(childJoints[armPart] or {}) do
			local subName = subMotor.Part1.Name:lower()
			if IGNORE_PARTS[subName] then continue end
			if IS_BAT[subName] then
				addJoint(subMotor, "bat", 0)
			else
				addJoint(subMotor, "arm", armPhase)
			end
		end
	end

	for _, motor in ipairs(childJoints[animalRoot] or {}) do
		local part = motor.Part1
		local name = part.Name:lower()

		if IGNORE_PARTS[name] then
			continue

		elseif IS_BODY[name] then
			if data.animalName == "KoiFish" then
				local relative = animalRoot.CFrame:PointToObjectSpace(part.Position)
				addJoint(motor, "tailseg", math.abs(relative.Y) * 0.55 + math.abs(relative.Z) * 0.25)
				continue
			end
			addJoint(motor, "body")
			for _, subMotor in ipairs(childJoints[part] or {}) do
				local subName = subMotor.Part1.Name:lower()
				if IGNORE_PARTS[subName] then continue end
				if IS_NECK[subName] then
					addJoint(subMotor, "neck", 0)
					walkNeckChain(subMotor.Part1, 1)
				elseif IS_HEAD[subName] then
					addJoint(subMotor, "head")
				elseif IS_ARM[subName] then
					local armPhase = (subName == "leftarm") and 0 or math.pi
					addJoint(subMotor, "arm", armPhase)
					walkArmChain(subMotor.Part1, armPhase)
				elseif IS_BAT[subName] then
					addJoint(subMotor, "bat", 0)
				end
			end

		elseif IS_HEAD[name] then
			addJoint(motor, "head")
			for _, subMotor in ipairs(childJoints[part] or {}) do
				if subMotor.Part1.Name:lower() == "ear" then
					addJoint(subMotor, "antenna", math.random() * math.pi)
				end
			end

		elseif IS_NECK[name] then
			addJoint(motor, "neck", 0)
			walkNeckChain(part, 1)

		elseif IS_TAIL[name] then
			addJoint(motor, "tail")
			walkTailChain(part, 1, 0)

		elseif IS_SHELL[name] then
			addJoint(motor, "shell")

		elseif IS_WING[name] then
			local phase = (name == "lw") and 0 or math.pi
			addJoint(motor, "wing", phase)
			for _, subMotor in ipairs(childJoints[part] or {}) do
				if not IGNORE_PARTS[subMotor.Part1.Name:lower()] then
					addJoint(subMotor, "wingfold", phase)
				end
			end

		elseif IS_BACK_LEG[name] then
			local phase = legPhase(part)
			addJoint(motor, "backleg", phase)
			for _, subMotor in ipairs(childJoints[part] or {}) do
				local subName = subMotor.Part1.Name:lower()
				if IGNORE_PARTS[subName] then continue end
				if IS_LOWER_LEG[subName] or not childJoints[subMotor.Part1] then
					addJoint(subMotor, "lowerleg", phase)
				end
			end

		elseif IS_LOWER_LEG[name] then
			addJoint(motor, "lowerleg", legPhase(part))

		elseif IS_ARM[name] then
			-- leftarm=0, rightarm=pi so they swing opposite (standard walk)
			local armPhase = (name == "leftarm") and 0 or math.pi
			addJoint(motor, "arm", armPhase)
			walkArmChain(part, armPhase)

		elseif IS_BAT[name] then
			addJoint(motor, "bat", 0)

		else
			local phase = legPhase(part)
			addJoint(motor, "leg", phase)
			for _, subMotor in ipairs(childJoints[part] or {}) do
				local subName = subMotor.Part1.Name:lower()
				if IGNORE_PARTS[subName] then continue end
				if IS_LOWER_LEG[subName] or not childJoints[subMotor.Part1] then
					addJoint(subMotor, "lowerleg", phase)
				end
			end
		end
	end

	return data
end

function AnimationEngine.reset(data, animalHumanoid)
	if not data then return end
	for _, joint in data.joints do
		if joint.motor and joint.motor.Parent then
			joint.motor.C0 = joint.origC0
		end
	end
	if animalHumanoid and animalHumanoid.Parent and data.baseHip then
		animalHumanoid.HipHeight = data.baseHip
	end
end

function AnimationEngine.update(data, animalHumanoid, dt, isMoving, speed, maxSpeed)
	if not data or not animalHumanoid or not animalHumanoid.Parent then return end

	local t = tick()
	maxSpeed = maxSpeed or 40

	data.smoothVel += ((isMoving and speed or 0) - data.smoothVel) * math.min(dt * 7, 1)
	local sv = data.smoothVel

	local blendTarget = isMoving and math.clamp(sv / 8, 0.2, 1) or 0
	data.blend        += (blendTarget - data.blend) * math.min(dt * CONFIG.blendRate, 1)
	local b           = data.blend
	local speedMul    = math.clamp(sv / maxSpeed, 0.35, 1.2)

	if data.wasMoving and not isMoving then data.settling = 0.35 end
	data.wasMoving = isMoving
	data.settling  = math.max(0, data.settling - dt)

	local currentPose  = "none"
	local poseStrength = 0
	if data.abilityPose and tick() < (data.abilityPoseUntil or 0) then
		currentPose = data.abilityPose
		local remaining = data.abilityPoseUntil - tick()
		local elapsed = tick() - (data.abilityPoseStarted or tick())
		local blendIn = math.max(data.abilityPoseBlendIn or 0.08, 0.01)
		poseStrength = math.min(
			math.clamp(elapsed / blendIn, 0, 1),
			math.clamp(remaining / 0.18, 0, 1)
		)
	elseif AbilityController then
		currentPose, poseStrength = AbilityController.getAbilityPose()
	else
		data.abilityPose = nil
	end

	local activePoseDef
	if currentPose == "knockback" then
		if not data._knockbackPoseCache then
			data._knockbackPoseCache = buildKnockbackPose()
		end
		activePoseDef = data._knockbackPoseCache
	else
		data._knockbackPoseCache = nil
		activePoseDef = ABILITY_POSES[currentPose]
	end

	local walkBob = math.sin(t * CONFIG.walkFreq * math.pi * 2) * CONFIG.walkBounce * speedMul
	local idleBob = math.sin(t * CONFIG.idleFreq * math.pi * 2) * CONFIG.idleBounce
	local settle  = 0
	if data.settling > 0 then
		local p = data.settling / 0.35
		settle  = math.sin((1 - p) * math.pi * 3) * 0.12 * p
	end

	local abilityBounce = 0
	if currentPose == "charge"    then abilityBounce = -0.08 * poseStrength end
	if currentPose == "knockback" then abilityBounce =  0.12 * poseStrength end
	local poseHipRatio = POSE_HIP_RATIO[currentPose]
	if poseHipRatio then
		abilityBounce += math.clamp(poseHipRatio * data.modelSize.Y * (data.style.hip or 1), -1.5, 0.9) * poseStrength
	end

	animalHumanoid.HipHeight = data.baseHip
		+ (walkBob * b)
		+ (idleBob * (1 - b))
		+ settle
		+ abilityBounce

	local freq     = t * CONFIG.walkFreq * math.pi * 2
	local wingFreq = t * CONFIG.wingFreq * math.pi * 2

	for _, j in data.joints do
		if not j.motor or not j.motor.Parent then continue end

		local offset = CFrame.new()

		if j.cat == "body" then
			local walkLean = CFrame.Angles(-math.rad(CONFIG.walkLean) * b * speedMul, 0, 0)
			local idleSway = CFrame.Angles(
				math.sin(t * CONFIG.idleFreq * math.pi * 1.4) * math.rad(CONFIG.idleBodySway * 0.4) * (1 - b),
				0,
				math.sin(t * CONFIG.idleFreq * math.pi)       * math.rad(CONFIG.idleBodySway * 0.6) * (1 - b)
			)
			offset = walkLean * idleSway

		elseif j.cat == "head" then
			local walkBobHead = CFrame.Angles(
				math.sin(freq + math.pi) * math.rad(CONFIG.walkHeadBob) * b * speedMul,
				math.sin(freq * 0.5)     * math.rad(2) * b, 0
			)
			local idleLook = CFrame.Angles(
				math.sin(t * 0.6)  * math.rad(CONFIG.idleHeadLook * 0.3) * (1 - b),
				math.sin(t * 0.35) * math.rad(CONFIG.idleHeadLook)       * (1 - b),
				math.sin(t * 0.5)  * math.rad(1.5)                       * (1 - b)
			)
			offset = walkBobHead * idleLook

		elseif j.cat == "neck" then
			local decay = math.max(0.3, 1 - j.phase * 0.25)
			offset = CFrame.Angles(
				math.sin(freq + math.pi * 0.7) * math.rad(CONFIG.neckBob) * decay * b * speedMul
					+ math.sin(t * CONFIG.idleFreq * 1.2) * math.rad(CONFIG.idleHeadLook * 0.2) * decay * (1 - b),
				0, 0
			)

		elseif j.cat == "leg" then
			local swing     = math.sin(freq + j.phase) * math.rad(CONFIG.walkLegSwing) * b * speedMul
			local idleSplay = math.rad(1.5) * (1 - b)
			offset = CFrame.Angles(swing, 0, idleSplay)

		elseif j.cat == "backleg" then
			local swing     = math.sin(freq * 1.1 + j.phase) * math.rad(CONFIG.backLegSwing) * b * speedMul
			local idleSplay = math.rad(2) * (1 - b)
			offset = CFrame.Angles(swing, 0, idleSplay)

		elseif j.cat == "lowerleg" then
			local rawSwing = math.sin(freq + j.phase)
			local bend     = math.max(0, rawSwing) * math.rad(CONFIG.walkLegSwing * 0.5) * b * speedMul
			offset = CFrame.Angles(bend, 0, 0)

		elseif j.cat == "tail" then
			local walkWag = math.sin(freq * 1.4 + math.pi * 0.5) * math.rad(CONFIG.walkTailWag) * b * speedMul
			local idleWag = math.sin(t * 0.55)                   * math.rad(CONFIG.idleTailSway) * (1 - b)
			offset = CFrame.Angles(math.rad(-10), walkWag + idleWag, 0)

		elseif j.cat == "tailseg" then
			local decay   = math.max(0.2, 1 - j.phase * 0.2)
			local walkWag = math.sin(freq * 1.4 + math.pi * 0.5 + j.phase) * math.rad(CONFIG.walkTailWag * decay) * b * speedMul
			local idleWag = math.sin(t * 0.55 + j.phase)                   * math.rad(CONFIG.idleTailSway * decay) * (1 - b)
			offset = CFrame.Angles(math.rad(-5), walkWag + idleWag, 0)

		elseif j.cat == "wing" then
			local flap      = math.sin(wingFreq + j.phase) * math.rad(CONFIG.wingSwing) * b * speedMul
			local idleDroop = math.rad(8) * (1 - b)
			offset = CFrame.Angles(0, 0, flap - idleDroop)

		elseif j.cat == "wingfold" then
			local flap = math.sin(wingFreq + j.phase + 0.3) * math.rad(CONFIG.wingSwing * 0.5) * b * speedMul
			offset = CFrame.Angles(0, 0, flap)

		elseif j.cat == "shell" then
			local sway = math.sin(t * CONFIG.idleFreq * 0.7) * math.rad(CONFIG.shellSway)
			offset = CFrame.Angles(0, sway * (1 - b * 0.6), 0)

		elseif j.cat == "antenna" then
			local wobble = math.sin(t * 1.2 + j.phase) * math.rad(6)
			local tip    = math.sin(t * 0.9 + j.phase + 1) * math.rad(4)
			offset = CFrame.Angles(tip, wobble, 0)

		elseif j.cat == "arm" then
			-- phase=0 (left) vs phase=pi (right) gives proper opposite swing
			-- 25 degrees arc so it reads clearly even on chunky arms
			local walkSwing = math.sin(freq + j.phase) * math.rad(25) * b * speedMul
			local idleSway  = math.sin(t * CONFIG.idleFreq * 0.9 + j.phase) * math.rad(4) * (1 - b)
			local idleDroop = math.rad(4) * (1 - b)
			offset = CFrame.Angles(walkSwing + idleSway, 0, idleDroop)

		elseif j.cat == "bat" then
			-- menacing waggle; ramps up slightly when moving
			local waggle = math.sin(t * 2.1) * math.rad(10 + b * 6)
			local bob    = math.sin(t * 1.4) * math.rad(5)
			offset = CFrame.Angles(bob, waggle, 0)
		end

		if activePoseDef and poseStrength > 0 then
			local poseCF = activePoseDef[j.cat]
			if poseCF then
				local measuredPose = adaptPose(poseCF, j, data, currentPose, activePoseDef)
				offset = offset * scalePose(measuredPose, poseStrength)
			end
		end

		j.motor.C0 = j.origC0 * offset
	end
end

return AnimationEngine

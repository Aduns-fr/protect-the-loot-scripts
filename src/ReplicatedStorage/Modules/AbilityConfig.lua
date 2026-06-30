--[[
	AbilityConfig (ModuleScript - ReplicatedStorage.Modules)

	One table drives every animal's signature ability. Shared by:
	  - AbilityController (client): executes movement, plays sound and pose
	  - CombatManager (server): validates cooldowns, runs shoves, guards,
	    empowers, rebirth, the raccoon wall, and broadcasts fx
	  - AIManager (server): bots pick their usage by ability kind
	  - InventoryClient: shows buffText in the equip panel Buff label

	kind values and their params:
	  dash    - force, dur, immunity (s of post-dash immunity), charges,
	            endRadius/endForce/endPop/endEffect (arrival burst)
	  leap    - vert (jump velocity), horiz (forward force), landRadius,
	            landForce/landPop/landEffect (radial landing shove)
	  blink   - dist (studs teleported forward), optional arrival burst
	  speed   - mult, dur (movement speed buff), optional ending burst
	  cone    - range, force, pop (extra vertical), behind (true = rear cone)
	  radial  - radius, force, pop, voxel (break ground decor), cashBonus
	  guard   - dur, resist (0..1 reduction), canMove, moveMult, reflect
	  empower - window, forceMult, radiusMult, yank (pull-then-pop hits)
	  rebirth - armDur (s the save stays primed), oncePerRound
	  refresh - extraWindow (s a second mid-air recovery stays available),
	            optional movement boost and brief resistance
	  wall    - width, height, life (raccoon barricade)
	  burrow  - dur, moveMult (underground immunity crawl), emerge burst

	sound is a Sound name inside SoundService.SFX.Abilities.
	pose is an ABILITY_POSES entry in AnimationEngine.
]]

local AbilityConfig = {}

AbilityConfig.Abilities = {
	-- free default
	Snail        = { name = "Shell Tuck",   buffText = "Tucks into its shell and ignores knockback for 1 second.",      kind = "guard",   cd = 11, dur = 1.0, resist = 1.0, canMove = false, sound = "Shell",    pose = "shellTuck" },

	-- egg 1
	Chicken      = { name = "Feather Frenzy", buffText = "Stores two aerial flaps. Each surges forward and the final landing scatters nearby rivals.", kind = "leap", cd = 7, charges = 2, vert = 50, horiz = 52, landRadius = 6, landForce = 48, landPop = 14, landEffect = "feather_burst", sound = "Leap", pose = "leapStretch", landPose = "puffUp", landPoseDur = 0.35 },
	Sheep        = { name = "Wool Rebound", buffText = "Wraps up in springy wool, heavily reducing hits and reflecting part of their force.", kind = "guard", cd = 9, dur = 3.5, resist = 0.65, reflect = 0.2, canMove = true, moveMult = 1.05, sound = "Guard", pose = "puffUp" },
	Pig          = { name = "Truffle Tackle", buffText = "Tackles forward, then kicks up a close-range burst at the finish.", kind = "dash", cd = 5.5, force = 84, dur = 0.55, endRadius = 5.5, endForce = 55, endPop = 10, endEffect = "truffle_burst", sound = "Dash", pose = "dashForward" },
	Cow          = { name = "Beef Up",      buffText = "Powers up the next attack with much stronger force and reach.", kind = "empower", cd = 9, window = 4.5, forceMult = 1.45, radiusMult = 1.3, sound = "Empower", pose = "rearUp" },

	-- egg 2
	Rabbit       = { name = "Pogo Pop",     buffText = "Vaults skyward and pops nearby rivals upward when it lands.", kind = "leap", cd = 5.5, vert = 74, horiz = 18, landRadius = 5, landForce = 48, landPop = 22, landEffect = "bunny_burst", sound = "Leap", pose = "leapStretch", landPose = "squash", landPoseDur = 0.3 },
	Duck         = { name = "Waddle Splash", buffText = "Dashes safely through danger and splashes rivals away at the finish.", kind = "dash", cd = 5.8, force = 78, dur = 0.55, immunity = 0.5, endRadius = 4.5, endForce = 42, endPop = 8, endEffect = "splash_burst", sound = "Dash", pose = "dashForward" },
	Goat         = { name = "Meteor Headbutt", buffText = "Drives a focused headbutt forward with heavy force and a sharp upward pop.", kind = "cone", cd = 6.5, range = 10, force = 78, pop = 10, angle = 50, sound = "Headbutt", pose = "headbutt" },
	Worm         = { name = "Burrow Breakout", buffText = "Digs underground with full immunity, then erupts beneath nearby rivals.", kind = "burrow", cd = 10, dur = 1.35, moveMult = 0.65, emergeRadius = 7, emergeForce = 60, emergePop = 20, emergeEffect = "burrow_burst", sound = "Burrow", pose = "burrowDown" },

	-- egg 3
	Fox          = { name = "Fox Rush",     buffText = "Explodes into a fast, evasive directional rush.", kind = "dash", cd = 5, force = 90, dur = 0.5, immunity = 0.2, sound = "Dash", pose = "dashForward" },
	Wolf         = { name = "Predator Pounce", buffText = "Pounces hard and mauls the landing zone with force and lift.", kind = "leap", cd = 6.5, vert = 48, horiz = 66, landRadius = 7.5, landForce = 66, landPop = 12, landEffect = "pounce_burst", sound = "Leap", pose = "leapStretch", landPose = "slam", landPoseDur = 0.35 },
	Cat          = { name = "Nine Step",    buffText = "Stores three crisp dashes that recharge over time.", kind = "dash", cd = 8.4, force = 78, dur = 0.42, charges = 3, sound = "Dash", pose = "dashForward" },
	Panda        = { name = "Ground Pound", buffText = "Slams the ground and shoves everyone nearby.",    kind = "radial",  cd = 9,  radius = 10, force = 75, pop = 25, voxel = true, sound = "Pound", pose = "slam" },

	-- egg 4
	Lion         = { name = "Royal Roar",   buffText = "Unleashes a wide royal roar with strong force and lift.", kind = "cone", cd = 8, range = 13, force = 74, pop = 8, angle = 78, sound = "Roar", pose = "rearUp" },
	Horse        = { name = "Stampede",     buffText = "Gallops at top speed with resistance, then sends out a finishing stomp.", kind = "speed", cd = 9.5, mult = 1.55, dur = 4, resist = 0.3, endRadius = 7, endForce = 58, endPop = 12, endEffect = "stampede_burst", sound = "Gallop", pose = "dashForward" },
	Capybara     = { name = "Unbothered",   buffText = "Stays completely composed, heavily resisting and softly reflecting incoming hits.", kind = "guard", cd = 12, dur = 2.5, resist = 0.75, reflect = 0.15, canMove = true, moveMult = 1, sound = "Guard", pose = "calm" },
	Axolotl      = { name = "Regenerate",   buffText = "Refreshes recovery, grants an extra air save, and surges safely back into motion.", kind = "refresh", cd = 10, extraWindow = 7, resist = 1, resistDur = 0.65, moveBoostMult = 1.35, moveBoostDur = 2, sound = "Guard", pose = "puffUp" },

	-- egg 5
	Unicorn      = { name = "Star Blink",   buffText = "Blinks through danger and detonates a lifting starburst on arrival.", kind = "blink", cd = 7, dist = 16, endDelay = 0.1, endRadius = 5, endForce = 50, endPop = 18, endEffect = "blink_burst", sound = "Blink", pose = "dashForward" },
	Dragon       = { name = "Wing Gust",    buffText = "Blasts a long gust that pushes enemies upward.",       kind = "cone",    cd = 8,  range = 16, force = 70, pop = 18, angle = 60, sound = "Gust", pose = "wingFlare" },
	Slime        = { name = "Super Bounce", buffText = "Bounces high and launches nearby enemies on landing.",  kind = "leap",    cd = 8,  vert = 95, horiz = 8, landRadius = 9, landForce = 55, landPop = 35, voxel = true, sound = "Bounce", pose = "squash", poseDur = 0.18, airPose = "leapStretch", airPoseDur = 0.7, landPose = "slam", landPoseDur = 0.4 },
	Phoenix      = { name = "Rebirth",      buffText = "Primes one fall save for 12 seconds and gains a brief fiery speed surge.", kind = "rebirth", cd = 60, armDur = 12, oncePerRound = true, moveBoostMult = 1.25, moveBoostDur = 2.5, sound = "Rebirth", pose = "wingFlare" },

	-- specials
	ArcticFox    = { name = "Frost Dash",   buffText = "Frost-dashes with speed and brief immunity.",  kind = "dash",    cd = 4.5, force = 85, dur = 0.55, immunity = 0.5, sound = "Dash", pose = "dashForward" },
	GoldenGoose  = { name = "Golden HONK",  buffText = "Honks enemies away and boosts cash from quick eliminations.",    kind = "radial",  cd = 10, radius = 10, force = 60, cashBonus = 0.5, bonusWindow = 4, sound = "Honk", pose = "honk" },
	GoldenSnail  = { name = "Golden Shell", buffText = "Ignores knockback while moving at reduced speed.", kind = "guard", cd = 11, dur = 1.5, resist = 1.0, canMove = true, moveMult = 0.6, sound = "Shell", pose = "shellTuck" },
	Giraffe      = { name = "Sky Kick",     buffText = "Kicks backward to punish enemies behind it.",    kind = "cone",    cd = 7,  range = 10, force = 80, behind = true, sound = "Kick", pose = "backKick" },
	Raccoon      = { name = "Trash Wall",   buffText = "Drops a barricade that shoves anyone who runs into it.", kind = "wall",    cd = 12, width = 8, height = 5, life = 8, sound = "Wall", pose = "puffUp" },
	KoiFish      = { name = "Slipstream",   buffText = "Cuts forward with immunity and erupts in a lifting splash at the finish.", kind = "dash", cd = 6, force = 82, dur = 0.55, immunity = 0.65, endRadius = 5, endForce = 44, endPop = 16, endEffect = "splash_burst", sound = "Dash", pose = "dashForward" },
	Penguin      = { name = "Belly Bowling", buffText = "Slides low and far, bowling nearby rivals away at the finish.", kind = "dash", cd = 6.5, force = 76, dur = 1.1, lowControl = true, endRadius = 5.5, endForce = 58, endPop = 8, endEffect = "slide_burst", sound = "Slide", pose = "bellySlide" },
	RedPanda     = { name = "Quickstep",    buffText = "Stores two frequent precision dashes for rapid direction changes.", kind = "dash", cd = 5, force = 72, dur = 0.4, charges = 2, sound = "Dash", pose = "dashForward" },
	Tung         = { name = "TUNG SLAM",    buffText = "Leaps into a huge ground-breaking slam.",   kind = "leap",    cd = 10, vert = 60, horiz = 20, landRadius = 12, landForce = 80, landPop = 30, voxel = true, sound = "Slam", pose = "rearUp", poseDur = 0.2, airPose = "leapStretch", airPoseDur = 0.65, landPose = "slam", landPoseDur = 0.55 },
	RainbowSheep = { name = "Prism Burst",  buffText = "Bursts outward with lift and strongly reflects knockback for a short time.", kind = "radial", cd = 11, radius = 10.5, force = 72, pop = 10, reflect = 0.45, reflectDur = 2.5, sound = "Burst", pose = "puffUp" },
	UpsideDownCow = { name = "Gravity Yank", buffText = "Supercharges the next attack to pull enemies inward, then launch them up.", kind = "empower", cd = 10, window = 3.5, forceMult = 1.3, radiusMult = 1.2, yank = true, sound = "Yank", pose = "rearUp" },
}

function AbilityConfig.resolveAnimalName(animalName)
	if typeof(animalName) ~= "string" then return nil end
	if AbilityConfig.Abilities[animalName] then return animalName end
	local bestMatch = nil
	for configuredName in pairs(AbilityConfig.Abilities) do
		local suffix = "_" .. configuredName
		if #animalName > #suffix and string.sub(animalName, -#suffix) == suffix then
			if not bestMatch or #configuredName > #bestMatch then bestMatch = configuredName end
		end
	end
	return bestMatch
end

function AbilityConfig.getFor(animalName)
	local resolved = AbilityConfig.resolveAnimalName(animalName)
	if resolved then return AbilityConfig.Abilities[resolved], resolved end
	return AbilityConfig.Abilities.Snail, "Snail"
end

function AbilityConfig.getBuffText(animalName)
	local a = AbilityConfig.getFor(animalName)
	return a and a.buffText or ""
end

local PRESENTATION_BY_KIND = {
	dash = { windupPose = "squash", windup = 0.06, actionPose = "dashForward", actionDur = 0.38, effect = "dash" },
	leap = { windupPose = "squash", windup = 0.14, actionPose = "leapStretch", actionDur = 0.7, effect = "leap" },
	blink = { windupPose = "squash", windup = 0.1, actionPose = "dashForward", actionDur = 0.32, effect = "blink" },
	speed = { windupPose = "rearUp", windup = 0.12, actionPose = "dashForward", actionDur = 0.48, effect = "gallop" },
	cone = { windupPose = "rearUp", windup = 0.16, actionPose = "headbutt", actionDur = 0.34, effect = "headbutt" },
	radial = { windupPose = "rearUp", windup = 0.2, actionPose = "slam", actionDur = 0.42, effect = "ground_pound" },
	guard = { windupPose = "brace", windup = 0.08, actionPose = "shellTuck", actionDur = 0.55, effect = "guard" },
	empower = { windupPose = "rearUp", windup = 0.14, actionPose = "charge", actionDur = 0.5, effect = "empower" },
	rebirth = { windupPose = "rearUp", windup = 0.18, actionPose = "wingFlare", actionDur = 0.8, effect = "rebirth" },
	refresh = { windupPose = "squash", windup = 0.12, actionPose = "puffUp", actionDur = 0.62, effect = "refresh" },
	wall = { windupPose = "rearUp", windup = 0.18, actionPose = "backKick", actionDur = 0.38, effect = "wall" },
	burrow = { windupPose = "squash", windup = 0.16, actionPose = "burrowDown", actionDur = 0.65, effect = "burrow" },
}

local PRESENTATION_OVERRIDES = {
	Snail = { effect = "shell", actionPose = "shellTuck" },
	Chicken = { effect = "feather_frenzy", windupPose = "squash", windup = 0.1, actionPose = "wingFlare" },
	Sheep = { effect = "wool_guard", actionPose = "puffUp" },
	Cow = { effect = "beef_up" },
	Duck = { effect = "dash" },
	Goat = { effect = "headbutt" },
	Wolf = { effect = "pounce_start" },
	Panda = { effect = "ground_pound" },
	Lion = { effect = "roar", actionPose = "honk" },
	Capybara = { effect = "unbothered", windupPose = "calm", actionPose = "calm" },
	Unicorn = { effect = "blink" },
	Dragon = { effect = "wing_gust", windupPose = "rearUp", actionPose = "wingFlare" },
	Slime = { effect = "bounce_start", windupPose = "squash", windup = 0.2, actionPose = "leapStretch" },
	Phoenix = { effect = "rebirth", actionPose = "wingFlare" },
	ArcticFox = { effect = "frost_dash" },
	GoldenGoose = { effect = "honk", actionPose = "honk" },
	GoldenSnail = { effect = "shell", actionPose = "shellTuck" },
	Giraffe = { effect = "sky_kick", windupPose = "rearUp", actionPose = "backKick" },
	Raccoon = { effect = "wall", windupPose = "rearUp", actionPose = "puffUp" },
	KoiFish = { effect = "slipstream" },
	Penguin = { effect = "belly_slide", windupPose = "squash", actionPose = "bellySlide" },
	RedPanda = { effect = "quickstep", windup = 0.035 },
	Tung = { effect = "tung_launch", windupPose = "rearUp", windup = 0.24, actionPose = "leapStretch" },
	RainbowSheep = { effect = "prism_burst", windupPose = "puffUp", actionPose = "slam" },
	UpsideDownCow = { effect = "gravity_yank", actionPose = "charge" },
}

function AbilityConfig.getPresentation(animalName, config)
	local resolvedName = AbilityConfig.resolveAnimalName(animalName) or animalName
	config = config or AbilityConfig.getFor(resolvedName)
	local base = PRESENTATION_BY_KIND[config.kind] or {}
	local override = PRESENTATION_OVERRIDES[resolvedName] or {}
	local result = {}
	for key, value in pairs(base) do result[key] = value end
	for key, value in pairs(override) do result[key] = value end
	return result
end

function AbilityConfig.getPoseDuration(config)
	if not config then return 0.6 end
	if config.poseDur then return config.poseDur end
	local durations = {
		dash = 0.5, leap = 0.65, blink = 0.45, speed = 0.7, cone = 0.7,
		radial = 0.8, guard = math.min(config.dur or 1, 1.2), empower = 0.85,
		rebirth = 1.1, refresh = 0.7, wall = 0.7, burrow = math.min(config.dur or 1, 1.2),
	}
	return durations[config.kind] or 0.6
end

return AbilityConfig

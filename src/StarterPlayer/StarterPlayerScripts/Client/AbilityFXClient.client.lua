local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local abilityRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("AbilityRemote")
local roundRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("RoundRemote")
local particleLibrary = ReplicatedStorage:FindFirstChild("VFX")
particleLibrary = particleLibrary and particleLibrary:FindFirstChild("AbilityParticles")

local fxFolder = workspace:FindFirstChild("LocalAbilityFX")
if not fxFolder then
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalAbilityFX"
	fxFolder.Parent = workspace
end

local PALETTES = {
	default = { Color3.fromRGB(245, 250, 255), Color3.fromRGB(95, 205, 255) },
	Snail = { Color3.fromRGB(120, 230, 175), Color3.fromRGB(45, 130, 95) },
	GoldenSnail = { Color3.fromRGB(255, 235, 90), Color3.fromRGB(255, 150, 35) },
	Chicken = { Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 150, 65) },
	Sheep = { Color3.fromRGB(235, 245, 255), Color3.fromRGB(145, 195, 255) },
	RainbowSheep = { Color3.fromRGB(255, 100, 215), Color3.fromRGB(90, 235, 255) },
	Pig = { Color3.fromRGB(255, 155, 190), Color3.fromRGB(255, 95, 125) },
	Cow = { Color3.fromRGB(255, 230, 170), Color3.fromRGB(255, 125, 55) },
	UpsideDownCow = { Color3.fromRGB(190, 105, 255), Color3.fromRGB(80, 220, 255) },
	Rabbit = { Color3.fromRGB(255, 245, 255), Color3.fromRGB(255, 145, 220) },
	Duck = { Color3.fromRGB(255, 235, 85), Color3.fromRGB(255, 145, 30) },
	Goat = { Color3.fromRGB(255, 225, 170), Color3.fromRGB(200, 105, 65) },
	Worm = { Color3.fromRGB(180, 120, 75), Color3.fromRGB(105, 65, 40) },
	Fox = { Color3.fromRGB(255, 155, 55), Color3.fromRGB(255, 235, 180) },
	ArcticFox = { Color3.fromRGB(210, 250, 255), Color3.fromRGB(65, 190, 255) },
	Wolf = { Color3.fromRGB(205, 220, 240), Color3.fromRGB(85, 110, 150) },
	Cat = { Color3.fromRGB(255, 210, 105), Color3.fromRGB(255, 120, 65) },
	Panda = { Color3.fromRGB(245, 245, 255), Color3.fromRGB(90, 110, 145) },
	Lion = { Color3.fromRGB(255, 205, 55), Color3.fromRGB(255, 100, 25) },
	Horse = { Color3.fromRGB(255, 185, 95), Color3.fromRGB(150, 75, 45) },
	Capybara = { Color3.fromRGB(210, 165, 105), Color3.fromRGB(115, 85, 60) },
	Axolotl = { Color3.fromRGB(255, 135, 215), Color3.fromRGB(75, 245, 225) },
	Unicorn = { Color3.fromRGB(235, 150, 255), Color3.fromRGB(100, 220, 255) },
	Dragon = { Color3.fromRGB(115, 255, 165), Color3.fromRGB(40, 125, 85) },
	Slime = { Color3.fromRGB(100, 255, 125), Color3.fromRGB(35, 185, 105) },
	Phoenix = { Color3.fromRGB(255, 225, 70), Color3.fromRGB(255, 65, 20) },
	GoldenGoose = { Color3.fromRGB(255, 240, 75), Color3.fromRGB(255, 145, 15) },
	Giraffe = { Color3.fromRGB(255, 205, 70), Color3.fromRGB(175, 90, 35) },
	Raccoon = { Color3.fromRGB(170, 195, 220), Color3.fromRGB(70, 85, 105) },
	KoiFish = { Color3.fromRGB(255, 110, 70), Color3.fromRGB(85, 220, 255) },
	Penguin = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(55, 90, 145) },
	RedPanda = { Color3.fromRGB(255, 115, 45), Color3.fromRGB(125, 45, 35) },
	Tung = { Color3.fromRGB(255, 70, 55), Color3.fromRGB(95, 20, 30) },
}

local cameraTrauma = 0
local cameraFovKick = 0
local cameraSeed = math.random() * 1000
local baseFov = 70

local function addCameraImpulse(trauma, fov)
	cameraTrauma = math.clamp(cameraTrauma + trauma, 0, 1.4)
	cameraFovKick = math.max(cameraFovKick, fov or 0)
end

RunService:BindToRenderStep("RodeoAbilityCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end

	if cameraTrauma <= 0.002 and cameraFovKick <= 0.02 then
		baseFov = camera.FieldOfView
		return
	end

	local t = os.clock() * 26
	local strength = cameraTrauma * cameraTrauma
	local x = math.noise(cameraSeed, t, 0) * 0.42 * strength
	local y = math.noise(cameraSeed + 13, t, 0) * 0.34 * strength
	local roll = math.noise(cameraSeed + 29, t, 0) * math.rad(2.2) * strength
	camera.CFrame *= CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
	camera.FieldOfView = baseFov + cameraFovKick

	cameraTrauma = math.max(0, cameraTrauma - dt * 2.8)
	cameraFovKick = math.max(0, cameraFovKick - dt * 22)
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { fxFolder }

local function paletteFor(animal)
	return PALETTES[animal] or PALETTES.default
end

local function groundInfo(position)
	local character = player.Character
	rayParams.FilterDescendantsInstances = character and { fxFolder, character } or { fxFolder }
	local result = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rayParams)
	if result then
		return result.Position, result.Material, result.Instance.Color
	end
	return position, Enum.Material.Slate, Color3.fromRGB(105, 90, 75)
end

local function makePart(name, size, cframe, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Neon
	part.Transparency = transparency or 0
	part.Parent = fxFolder
	return part
end

local function tween(instance, duration, properties, style, direction)
	local info = TweenInfo.new(
		duration,
		style or Enum.EasingStyle.Quint,
		direction or Enum.EasingDirection.Out
	)
	local animation = TweenService:Create(instance, info, properties)
	animation:Play()
	return animation
end

local function ring(position, color, startDiameter, endDiameter, duration, thickness, inward)
	local start = inward and endDiameter or startDiameter
	local finish = inward and startDiameter or endDiameter
	local part = makePart(
		"Shockwave",
		Vector3.new(thickness or 0.12, start, start),
		CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.Material.Neon,
		0.12
	)
	part.Shape = Enum.PartType.Cylinder
	tween(part, duration, {
		Size = Vector3.new(math.max(0.03, (thickness or 0.12) * 0.35), finish, finish),
		Transparency = 1,
	}, inward and Enum.EasingStyle.Quart or Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	Debris:AddItem(part, duration + 0.1)
end

local function line(a, b, color, width, duration)
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.05 then return end
	local part = makePart(
		"EnergyStreak",
		Vector3.new(width, width, length),
		CFrame.lookAt((a + b) * 0.5, b),
		color,
		Enum.Material.Neon,
		0.08
	)
	tween(part, duration, {
		Size = Vector3.new(0.02, 0.02, length * 0.45),
		CFrame = part.CFrame * CFrame.new(0, 0, length * 0.25),
		Transparency = 1,
	})
	Debris:AddItem(part, duration + 0.1)
end

local function flash(position, color, size, duration)
	local part = makePart("ImpactFlash", Vector3.one * 0.2, CFrame.new(position), color, Enum.Material.Neon, 0.05)
	part.Shape = Enum.PartType.Ball
	tween(part, duration, { Size = Vector3.one * size, Transparency = 1 }, Enum.EasingStyle.Exponential)
	Debris:AddItem(part, duration + 0.05)
end

local function emitPreset(name, position, color, amount, scale)
	local source = particleLibrary and particleLibrary:FindFirstChild(name)
	if not source then return end
	local anchor = makePart("ParticleAnchor", Vector3.one * 0.1, CFrame.new(position), color, Enum.Material.SmoothPlastic, 1)
	for _, emitter in ipairs(source:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			local clone = emitter:Clone()
			clone.Enabled = false
			clone.Color = ColorSequence.new(color)
			if scale and scale ~= 1 then
				local keys = {}
				for _, key in ipairs(clone.Size.Keypoints) do
					table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale))
				end
				clone.Size = NumberSequence.new(keys)
			end
			clone.Parent = anchor
			clone:Emit(amount or 5)
		end
	end
	Debris:AddItem(anchor, 2)
end

-- real particle kits cloned from the workspace vfx pack into ReplicatedStorage.VFX.AbilityKit
local abilityKit = ReplicatedStorage:FindFirstChild("VFX")
abilityKit = abilityKit and abilityKit:FindFirstChild("AbilityKit")

-- spawn a one-shot burst kit at a world position. emitters fire a short burst
-- then the holder is cleaned up. scale grows the emitted particle sizes.
local function spawnKit(kitName, position, scale, lifetime)
	if not abilityKit then return end
	local source = abilityKit:FindFirstChild(kitName)
	if not source then return end
	scale = scale or 1
	lifetime = lifetime or 1.2

	local holder
	if source:IsA("BasePart") then
		holder = source:Clone()
		holder.Anchored = true
		holder.CFrame = CFrame.new(position)
	else
		-- model or attachment based kit: drop emitters onto a fresh anchor
		holder = makePart("KitAnchor", Vector3.one * 0.2, CFrame.new(position), Color3.new(), Enum.Material.SmoothPlastic, 1)
		for _, d in ipairs(source:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Beam") then
				d:Clone().Parent = holder
			end
		end
	end
	holder.Parent = fxFolder

	for _, e in ipairs(holder:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			if scale ~= 1 then
				local keys = {}
				for _, key in ipairs(e.Size.Keypoints) do
					table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale))
				end
				e.Size = NumberSequence.new(keys)
			end
			-- a burst proportional to the emitter's normal rate, capped so dense
			-- emitters don't lag, then leave it off
			local burst = math.clamp(math.floor((e.Rate or 10) * 0.2), 3, 40)
			e.Enabled = false
			e:Emit(burst)
		elseif e:IsA("Beam") then
			e.Enabled = true
		end
	end
	Debris:AddItem(holder, lifetime + 1.5)
end

-- attach a looping aura kit to a model for a duration. the aura emitters are
-- copied onto the model's root so the glow follows the mount, then removed.
local function attachAura(kitName, model, duration, scale)
	if not abilityKit or typeof(model) ~= "Instance" then return end
	local source = abilityKit:FindFirstChild(kitName)
	if not source then return end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then return end
	duration = duration or 2
	scale = scale or 1

	local live = {}
	for _, e in ipairs(source:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			local clone = e:Clone()
			if scale ~= 1 then
				local keys = {}
				for _, key in ipairs(clone.Size.Keypoints) do
					table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * scale, key.Envelope * scale))
				end
				clone.Size = NumberSequence.new(keys)
			end
			clone.Enabled = true
			clone.Parent = root
			table.insert(live, clone)
		end
	end
	if #live == 0 then return end
	task.delay(math.max(0.1, duration), function()
		for _, e in ipairs(live) do
			if e.Parent then
				e.Enabled = false
				Debris:AddItem(e, 2)
			end
		end
	end)
end

local function groundChunks(position, count, radius, power)
	local groundPosition, material, groundColor = groundInfo(position)
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + math.random() * 0.3
		local size = math.random(35, 80) / 100 * power
		local part = makePart(
			"GroundChunk",
			Vector3.new(size * 1.2, size * 0.65, size),
			CFrame.new(groundPosition + Vector3.new(0, 0.2, 0))
				* CFrame.Angles(math.random(), math.random(), math.random()),
			groundColor,
			material,
			0
		)
		part.Anchored = false
		part.AssemblyLinearVelocity = Vector3.new(
			math.cos(angle) * radius * math.random(75, 115) / 100,
			math.random(18, 31) * power,
			math.sin(angle) * radius * math.random(75, 115) / 100
		)
		part.AssemblyAngularVelocity = Vector3.new(
			math.random(-12, 12),
			math.random(-12, 12),
			math.random(-12, 12)
		)
		task.delay(0.32, function()
			if part.Parent then tween(part, 0.28, { Transparency = 1, Size = part.Size * 0.4 }) end
		end)
		Debris:AddItem(part, 0.7)
	end
end

local function fan(position, direction, color, range, angle, count, power)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	flat = flat.Unit
	for index = 1, count do
		local alpha = count == 1 and 0.5 or (index - 1) / (count - 1)
		local yaw = math.rad(-angle * 0.5 + angle * alpha)
		local rotated = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(flat)
		local start = position + Vector3.new(0, 1.1, 0) + rotated * 0.8
		local finish = start + rotated * range * (0.82 + 0.18 * math.sin(alpha * math.pi))
		task.delay(index * 0.012, function()
			line(start, finish, color, (0.13 + 0.1 * math.sin(alpha * math.pi)) * power, 0.32)
		end)
	end
end

local function dashTrail(payload, primary, secondary)
	local direction = payload.direction or Vector3.new(0, 0, -1)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	flat = flat.Unit
	local position = payload.position
	local right = flat:Cross(Vector3.yAxis)
	local length = 7 * payload.power

	for index = -1, 1 do
		local offset = right * index * 0.8 + Vector3.new(0, 0.45 + math.abs(index) * 0.2, 0)
		local head = position + offset
		line(head, head - flat * length * (1 - math.abs(index) * 0.12), index == 0 and primary or secondary, 0.18, 0.28)
	end
	ring(position, secondary, 1.2, 5.5 * payload.power, 0.28, 0.08)
	emitPreset("Bonk2", position + Vector3.new(0, 0.8, 0), primary, 2, 0.8 * payload.power)
	addCameraImpulse(0.12 * payload.power, 2.5 * payload.power)
end

local function leapEffect(payload, primary, secondary)
	local position = groundInfo(payload.position)
	ring(position, secondary, 1.5, 7 * payload.power, 0.38, 0.1)
	emitPreset("Bonk3", position + Vector3.new(0, 0.25, 0), primary, 8, payload.power)
	for index = 1, 5 do
		local angle = (index / 5) * math.pi * 2
		local base = position + Vector3.new(math.cos(angle) * 1.4, 0.2, math.sin(angle) * 1.4)
		line(base, base + Vector3.new(0, 3.5 + math.random(), 0), primary, 0.1, 0.3)
	end
	addCameraImpulse(0.08 * payload.power, 1.5)
end

local function slamEffect(payload, primary, secondary)
	local position = groundInfo(payload.position)
	local radius = payload.radius or 10
	flash(position + Vector3.new(0, 0.45, 0), primary, 2.4 * payload.power, 0.16)
	ring(position, primary, 1.2, radius * 2.1, 0.42, 0.18)
	task.delay(0.05, function()
		ring(position, secondary, 2.5, radius * 1.6, 0.5, 0.09)
	end)
	groundChunks(position, math.clamp(math.floor(8 + payload.power * 5), 9, 16), 8, payload.power)
	emitPreset("Bonk3", position + Vector3.new(0, 0.25, 0), primary, 7, 0.85 * payload.power)
	emitPreset("Bonk4", position + Vector3.new(0, 0.4, 0), secondary, 2, 0.7 * payload.power)
	addCameraImpulse(0.58 * payload.power, 6 * payload.power)
end

local function impactBurst(payload, primary, secondary, kitName, chunkCount)
	local position = groundInfo(payload.position)
	local radius = payload.radius or 6
	flash(position + Vector3.new(0, 0.7, 0), primary, 2.2 * payload.power, 0.16)
	ring(position, primary, 1.2, radius * 1.25, 0.36, 0.08)
	task.delay(0.045, function()
		ring(position, secondary, 1.8, radius * 1.55, 0.44, 0.07)
	end)
	if chunkCount and chunkCount > 0 then
		groundChunks(position, chunkCount, math.max(radius * 0.7, 3), 0.7 * payload.power)
	end
	spawnKit(kitName or "QuickImpact", position + Vector3.new(0, 0.35, 0), 0.9 * payload.power)
	addCameraImpulse(0.22 * payload.power, 3.5 * payload.power)
end

local function coneEffect(payload, primary, secondary)
	local effect = payload.effect
	local range = payload.range or 11
	local angle = payload.angle or 65
	fan(payload.position, payload.direction or Vector3.new(0, 0, -1), primary, range, angle, 7, payload.power)
	flash(payload.position + Vector3.new(0, 1, 0), secondary, 2.2 * payload.power, 0.2)
	emitPreset("Bonk1", payload.position + Vector3.new(0, 1, 0), primary, 2, payload.power)
	if effect == "roar" or effect == "honk" then
		for index = 1, 3 do
			task.delay(index * 0.055, function()
				ring(payload.position + (payload.direction or Vector3.zero) * index * 1.2, primary, index, 5 + index * 2.2, 0.32, 0.08)
			end)
		end
	end
	addCameraImpulse((effect == "roar" and 0.32 or 0.18) * payload.power, effect == "roar" and 3.5 or 2)
end

local function honkEffect(payload, primary, secondary)
	for index = 1, 4 do
		task.delay((index - 1) * 0.045, function()
			ring(
				payload.position,
				index % 2 == 0 and secondary or primary,
				1.2 + index * 0.45,
				(payload.radius or 10) * (1.25 + index * 0.13),
				0.38,
				0.08
			)
		end)
	end
	flash(payload.position + Vector3.new(0, 1.2, 0), primary, 3.8 * payload.power, 0.24)
	emitPreset("Bonk5", payload.position + Vector3.new(0, 1, 0), secondary, 4, payload.power)
	addCameraImpulse(0.24 * payload.power, 2.5)
end

local function attachBubble(payload, primary, secondary)
	local source = payload.source
	if typeof(source) ~= "Instance" or not source:IsA("BasePart") or not source.Parent then
		flash(payload.position, primary, 5, 0.4)
		return
	end
	local duration = payload.duration or 1.2
	local bubble = makePart(
		"AbilityShield",
		Vector3.one * 5.2 * payload.power,
		source.CFrame,
		primary,
		Enum.Material.ForceField,
		0.55
	)
	bubble.Shape = Enum.PartType.Ball
	bubble.Anchored = false
	bubble.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bubble
	weld.Part1 = source
	weld.Parent = bubble
	tween(bubble, 0.18, { Size = bubble.Size * 1.18, Transparency = 0.38 }, Enum.EasingStyle.Back)
	for index = 1, 3 do
		task.delay(index * 0.08, function()
			if source.Parent then ring(source.Position, index == 2 and secondary or primary, 1.4, 5.5 + index, 0.38, 0.07) end
		end)
	end
	task.delay(math.max(0.1, duration - 0.28), function()
		if bubble.Parent then tween(bubble, 0.28, { Size = bubble.Size * 1.15, Transparency = 1 }) end
	end)
	Debris:AddItem(bubble, duration + 0.1)
end

local function orbitEffect(payload, primary, secondary, inward)
	local source = payload.source
	if typeof(source) ~= "Instance" or not source:IsA("BasePart") or not source.Parent then return end
	local duration = payload.duration or 1
	local pieces = {}
	for index = 1, 4 do
		local piece = makePart(
			"OrbitSpark",
			Vector3.new(0.24, 0.24, 1.2),
			source.CFrame,
			index % 2 == 0 and primary or secondary,
			Enum.Material.Neon,
			0.08
		)
		piece.Shape = Enum.PartType.Cylinder
		table.insert(pieces, piece)
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not source.Parent or os.clock() - started >= duration then
			connection:Disconnect()
			for _, piece in ipairs(pieces) do
				if piece.Parent then tween(piece, 0.2, { Transparency = 1, Size = piece.Size * 0.2 }) end
			end
			return
		end
		local progress = (os.clock() - started) / duration
		local radius = inward and (4.2 - progress * 2.7) or (2.1 + math.sin(progress * math.pi) * 0.7)
		for index, piece in ipairs(pieces) do
			local angle = os.clock() * 5 + index * math.pi * 0.5
			local y = 0.6 + index * 0.38 + math.sin(angle * 1.7) * 0.25
			piece.CFrame = CFrame.new(source.Position + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius))
				* CFrame.Angles(0, -angle, math.rad(90))
		end
	end)
	for _, piece in ipairs(pieces) do Debris:AddItem(piece, duration + 0.35) end
	if inward then
		ring(source.Position, primary, 1.5, 9, 0.5, 0.12, true)
	else
		ring(source.Position, secondary, 1.2, 6.5, 0.4, 0.09)
	end
end

local function rebirthEffect(payload, primary, secondary)
	local position = payload.position
	flash(position + Vector3.new(0, 1.5, 0), primary, 7 * payload.power, 0.48)
	for index = 1, 12 do
		local angle = index * math.pi * 0.58
		local start = position + Vector3.new(math.cos(angle) * 2.4, 0.2, math.sin(angle) * 2.4)
		local finish = position + Vector3.new(math.cos(angle + 1.4) * 0.5, 6 + index * 0.25, math.sin(angle + 1.4) * 0.5)
		task.delay(index * 0.018, function()
			line(start, finish, index % 2 == 0 and primary or secondary, 0.2, 0.55)
		end)
	end
	emitPreset("Win", position + Vector3.new(0, 1, 0), primary, 12, payload.power)
	addCameraImpulse(0.42 * payload.power, 5)
end

local function burrowEffect(payload, primary)
	local source = payload.source
	local duration = payload.duration or 1.2
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if os.clock() - started >= duration or typeof(source) ~= "Instance" or not source.Parent then
			connection:Disconnect()
			return
		end
		if math.floor((os.clock() - started) * 18) % 3 == 0 then
			local position = groundInfo(source.Position)
			ring(position, primary, 0.8, 3.2, 0.25, 0.06)
			groundChunks(position, 2, 2.5, 0.55)
		end
	end)
end

local function prismEffect(payload)
	local colors = {
		Color3.fromRGB(255, 75, 115),
		Color3.fromRGB(255, 210, 65),
		Color3.fromRGB(80, 255, 150),
		Color3.fromRGB(80, 190, 255),
		Color3.fromRGB(195, 90, 255),
	}
	for index, color in ipairs(colors) do
		task.delay((index - 1) * 0.035, function()
			ring(payload.position, color, 1 + index * 0.4, (payload.radius or 10) * 1.8, 0.42, 0.08)
		end)
	end
	flash(payload.position + Vector3.new(0, 1, 0), colors[1], 3.5, 0.25)
	addCameraImpulse(0.28 * payload.power, 3)
end

local function playSound(payload)
	local soundName = payload.sound
	if not soundName or soundName == "" then return end
	local sfx = SoundService:FindFirstChild("SFX")
	local abilities = sfx and sfx:FindFirstChild("Abilities")
	local source = abilities and abilities:FindFirstChild(soundName)
	if not source or source.SoundId == "" then return end

	local anchor = makePart("AbilitySound", Vector3.one * 0.1, CFrame.new(payload.position), Color3.new(), Enum.Material.SmoothPlastic, 1)
	local sound = source:Clone()
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, math.max(sound.TimeLength + 0.5, 2))
end

local function normalizePayload(name, position, power)
	if typeof(name) == "table" then
		local payload = name
		payload.effect = tostring(payload.effect or "dash")
		payload.position = typeof(payload.position) == "Vector3" and payload.position or Vector3.zero
		payload.power = math.clamp(tonumber(payload.power) or 1, 0.35, 2)
		return payload
	end
	return {
		effect = tostring(name or "dash"),
		position = typeof(position) == "Vector3" and position or Vector3.zero,
		power = math.clamp(tonumber(power) or 1, 0.35, 2),
	}
end

local function showEffect(raw, position, power)
	local payload = normalizePayload(raw, position, power)
	local effect = string.lower(payload.effect)
	local palette = paletteFor(payload.animal)
	local primary, secondary = palette[1], palette[2]
	local pos = payload.position
	local model = typeof(payload.source) == "Instance" and payload.source.Parent or nil

	if effect == "feather_frenzy" then
		leapEffect(payload, primary, secondary)
		spawnKit("Wind", pos + Vector3.new(0, 1, 0), 0.75 * payload.power)
		spawnKit("Stars", pos + Vector3.new(0, 1.5, 0), 0.65 * payload.power)
	elseif effect == "feather_burst" then
		impactBurst(payload, primary, secondary, "Stars", 2)
		spawnKit("Wind", groundInfo(pos) + Vector3.new(0, 0.5, 0), 0.8 * payload.power)
	elseif effect == "bunny_burst" then
		impactBurst(payload, primary, secondary, "QuickImpact", 3)
	elseif effect == "pounce_burst" then
		impactBurst(payload, primary, secondary, "SlashImpact", 5)
	elseif effect == "truffle_burst" then
		impactBurst(payload, primary, secondary, "QuickImpact", 5)
	elseif effect == "slide_burst" then
		impactBurst(payload, primary, secondary, "BigImpact", 3)
	elseif effect == "stampede_burst" then
		impactBurst(payload, primary, secondary, "BigImpact", 6)
	elseif effect == "splash_burst" then
		impactBurst(payload, primary, secondary, "Splash", 0)
	elseif effect == "burrow_burst" then
		impactBurst(payload, primary, secondary, "Crack", 7)
	elseif effect == "blink_burst" then
		impactBurst(payload, primary, secondary, "Lightning", 0)
		spawnKit("Stars", pos + Vector3.new(0, 1.2, 0), 0.8 * payload.power)
	elseif effect == "dash" or effect == "frost_dash" or effect == "slipstream"
		or effect == "quickstep" or effect == "belly_slide" then
		dashTrail(payload, primary, secondary)
		spawnKit("Wind", pos + Vector3.new(0, 1, 0), 0.7 * payload.power)
	elseif effect == "leap" or effect == "bounce_start" or effect == "pounce_start"
		or effect == "tung_launch" then
		leapEffect(payload, primary, secondary)
		spawnKit("QuickImpact", groundInfo(pos), 0.8 * payload.power)
	elseif effect == "slam" or effect == "ground_pound" or effect == "tung_slam"
		or effect == "bounce_land" then
		slamEffect(payload, primary, secondary)
		-- the big crack reads as a heavy ground slam, splash uses the wet variant
		local kitName = effect == "bounce_land" and "Splash" or "Slam"
		spawnKit(kitName, groundInfo(pos), 1.2 * payload.power)
		if effect == "tung_slam" then spawnKit("Crack", groundInfo(pos), 1.1) end
	elseif effect == "honk" then
		honkEffect(payload, primary, secondary)
		spawnKit("Stars", pos + Vector3.new(0, 1, 0), 1 * payload.power)
		if payload.duration then orbitEffect(payload, primary, secondary, false) end
	elseif effect == "headbutt" or effect == "roar" or effect == "wing_gust"
		or effect == "sky_kick" then
		coneEffect(payload, primary, secondary)
		-- roar/gust read as wind, the kick/headbutt read as a slash
		if effect == "roar" or effect == "wing_gust" then
			spawnKit("Wind", pos + (payload.direction or Vector3.zero) * 3 + Vector3.new(0, 1.2, 0), 1 * payload.power)
		else
			spawnKit("Slash", pos + (payload.direction or Vector3.zero) * 2.5 + Vector3.new(0, 1.2, 0), 0.9 * payload.power)
			spawnKit("SlashImpact", pos + (payload.direction or Vector3.zero) * 3.5 + Vector3.new(0, 1.2, 0), 0.8 * payload.power)
		end
	elseif effect == "guard" or effect == "shell" or effect == "wool_guard"
		or effect == "unbothered" then
		attachBubble(payload, primary, secondary)
		spawnKit("Shield", pos + Vector3.new(0, 1, 0), 1)
	elseif effect == "empower" or effect == "beef_up" then
		orbitEffect(payload, primary, secondary, false)
		if model then attachAura("FireAura", model, payload.duration or 4, 0.9) end
		spawnKit("Charge", pos + Vector3.new(0, 1, 0), 0.9 * payload.power)
	elseif effect == "gravity_yank" then
		orbitEffect(payload, primary, secondary, true)
		if model then attachAura("RngAura", model, payload.duration or 3, 0.8) end
	elseif effect == "rebirth" then
		rebirthEffect(payload, primary, secondary)
		orbitEffect(payload, secondary, primary, false)
		spawnKit("FireBall", pos + Vector3.new(0, 2, 0), 1.2)
		if model then attachAura("FireAura", model, payload.duration or 6, 1) end
	elseif effect == "burrow" then
		local groundPosition = groundInfo(payload.position)
		ring(groundPosition, primary, 1, 6, 0.35, 0.1)
		groundChunks(groundPosition, 7, 4.5, 0.8)
		burrowEffect(payload, primary)
		spawnKit("QuickImpact", groundPosition, 0.7)
	elseif effect == "wall" then
		local groundPosition = groundInfo(payload.position)
		groundChunks(groundPosition, 10, 5.5, 0.9)
		emitPreset("Bonk4", groundPosition + Vector3.new(0, 0.5, 0), primary, 5, payload.power)
		spawnKit("QuickImpact", groundPosition, 0.9)
		addCameraImpulse(0.22, 2)
	elseif effect == "refresh" then
		orbitEffect(payload, primary, secondary, false)
		emitPreset("Bonk5", payload.position + Vector3.new(0, 1, 0), secondary, 4, payload.power)
		if model then attachAura("WaterAura", model, payload.duration or 5, 0.8) end
	elseif effect == "prism_burst" then
		prismEffect(payload)
		orbitEffect(payload, primary, secondary, false)
		spawnKit("RngAura", pos + Vector3.new(0, 1, 0), 1)
	elseif effect == "blink" then
		flash(payload.position + Vector3.new(0, 1, 0), primary, 4, 0.22)
		local destination = payload.destination or (payload.position + (payload.direction or Vector3.new(0, 0, -1)) * (payload.range or 14))
		spawnKit("PortalEnter", payload.position + Vector3.new(0, 1.5, 0), 0.9)
		spawnKit("Portal", destination + Vector3.new(0, 1.5, 0), 0.9)
		for index = 1, 5 do
			local alpha = index / 6
			local point = payload.position:Lerp(destination, alpha) + Vector3.new(0, 0.5 + math.sin(alpha * math.pi) * 0.8, 0)
			flash(point, index % 2 == 0 and primary or secondary, 1.3, 0.25)
		end
		task.delay(0.08, function() flash(destination + Vector3.new(0, 1, 0), secondary, 4.5, 0.26) end)
		addCameraImpulse(0.16, 4)
	elseif effect == "gallop" then
		dashTrail(payload, primary, secondary)
		orbitEffect(payload, primary, secondary, false)
		spawnKit("Wind", pos + Vector3.new(0, 1, 0), 0.8 * payload.power)
	else
		ring(payload.position, primary, 1.5, 7 * payload.power, 0.38, 0.1)
		flash(payload.position + Vector3.new(0, 1, 0), secondary, 2.5, 0.22)
	end

	playSound(payload)
end

abilityRemote.OnClientEvent:Connect(function(action, ...)
	if action == "fx" then showEffect(...) end
end)

roundRemote.OnClientEvent:Connect(function(action)
	if action ~= "rebirthSaved" then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		showEffect({
			effect = "rebirth",
			animal = "Phoenix",
			position = root.Position,
			source = root,
			power = 1.35,
			sound = "Rebirth",
		})
	end
end)

--// Smooth Admin Flight LocalScript
--// Put in StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--// Optional owner lock
if Player.Name ~= "yo_aduns" then
	return
end

--// Controls
local TOGGLE_KEY = Enum.KeyCode.F
local BOOST_KEY  = Enum.KeyCode.LeftShift
local UP_KEY     = Enum.KeyCode.Space
local DOWN_KEY   = Enum.KeyCode.LeftControl

--// Flight tuning
local NORMAL_SPEED = 60
local BOOST_SPEED  = 115
local VERT_SPEED   = 45

local ACCEL_RATE = 10
local BRAKE_RATE = 14
local ORIENTATION_RESPONSIVENESS = 28

local NORMAL_FOV = 70
local MOVE_FOV   = 82
local BOOST_FOV  = 96

local FOV_SMOOTHNESS = 8
local WIND_SMOOTHNESS = 10

local ANIM_FADE = 0.14
local INPUT_DEADZONE = 0.15
local LAND_DIST = 12

local ANIM_IDS = {
	idle     = "rbxassetid://135029208234034",
	forward  = "rbxassetid://73127122395560",
	backward = "rbxassetid://124760299748835",
	left     = "rbxassetid://95638633594915",
	right    = "rbxassetid://80530165492451",
	land     = "rbxassetid://127512022861856",
}

local STATES_TO_DISABLE = {
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
}

local activeCleanup = nil

local function expAlpha(rate, dt)
	return 1 - math.exp(-rate * dt)
end

local function flatUnit(v)
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function getThumbstick()
	local stickX, stickY = 0, 0

	local ok, states = pcall(function()
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)

	if ok and states then
		for _, state in ipairs(states) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 then
				stickX = state.Position.X
				stickY = state.Position.Y
				break
			end
		end
	end

	if math.abs(stickX) < INPUT_DEADZONE then
		stickX = 0
	end

	if math.abs(stickY) < INPUT_DEADZONE then
		stickY = 0
	end

	return stickX, stickY
end

local function setupFlight(character)
	if activeCleanup then
		activeCleanup()
		activeCleanup = nil
	end

	local humanoid = character:WaitForChild("Humanoid")
	local hrp = character:WaitForChild("HumanoidRootPart")
	local animator = humanoid:WaitForChild("Animator")
	local animateScript = character:FindFirstChild("Animate")

	local originalAutoRotate = humanoid.AutoRotate
	local originalCameraFOV = Camera.FieldOfView

	local flying = false
	local destroyed = false

	local smoothVelocity = Vector3.zero
	local currentTrack = nil
	local renderConnection = nil
	local inputConnection = nil
	local diedConnection = nil
	local stateConnection = nil

	--// Animations
	local tracks = {}

	for name, id in pairs(ANIM_IDS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id

		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action4

		tracks[name] = track
	end

	--// Attachment
	local flightAttachment = Instance.new("Attachment")
	flightAttachment.Name = "SmoothFlightAttachment"
	flightAttachment.Parent = hrp

	--// Modern velocity mover
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "SmoothFlightVelocity"
	linearVelocity.Attachment0 = flightAttachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.MaxForce = math.huge
	linearVelocity.Enabled = false
	linearVelocity.Parent = hrp

	--// Modern orientation mover
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "SmoothFlightOrientation"
	alignOrientation.Attachment0 = flightAttachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Responsiveness = ORIENTATION_RESPONSIVENESS
	alignOrientation.MaxTorque = math.huge
	alignOrientation.MaxAngularVelocity = math.huge
	alignOrientation.RigidityEnabled = false
	alignOrientation.Enabled = false
	alignOrientation.Parent = hrp

	--// Wind sound
	local windSound = Instance.new("Sound")
	windSound.Name = "FlightWind"
	windSound.SoundId = "rbxassetid://3308152153"
	windSound.Volume = 0
	windSound.Looped = true
	windSound.Parent = hrp

	local function stopAllFlightTracks(fadeTime)
		for _, track in pairs(tracks) do
			if track.IsPlaying then
				track:Stop(fadeTime or ANIM_FADE)
			end
		end

		currentTrack = nil
	end

	local function blendTo(name)
		local track = tracks[name]
		if not track then
			return
		end

		if currentTrack == track and track.IsPlaying then
			return
		end

		if currentTrack and currentTrack ~= track and currentTrack.IsPlaying then
			currentTrack:Stop(ANIM_FADE)
		end

		currentTrack = track

		if not track.IsPlaying then
			track:Play(ANIM_FADE)
		end
	end

	local function getFlightInput()
		local camCF = Camera.CFrame
		local camLook = camCF.LookVector
		local camRight = camCF.RightVector

		local f = 0
		local r = 0

		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			f += 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			f -= 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			r += 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			r -= 1
		end

		local rawDir = "none"

		if f ~= 0 or r ~= 0 then
			local worldDir = camLook * f + camRight * r

			if worldDir.Magnitude > 0.001 then
				worldDir = worldDir.Unit
			else
				worldDir = Vector3.zero
			end

			if math.abs(f) >= math.abs(r) then
				rawDir = f > 0 and "forward" or "backward"
			else
				rawDir = r > 0 and "right" or "left"
			end

			return worldDir, rawDir
		end

		--// Gamepad fallback
		if UserInputService.GamepadEnabled and #UserInputService:GetConnectedGamepads() > 0 then
			local stickX, stickY = getThumbstick()

			if stickX ~= 0 or stickY ~= 0 then
				local worldDir = camLook * stickY + camRight * stickX

				if worldDir.Magnitude > 0.001 then
					worldDir = worldDir.Unit
				else
					worldDir = Vector3.zero
				end

				if math.abs(stickY) >= math.abs(stickX) then
					rawDir = stickY > 0 and "forward" or "backward"
				else
					rawDir = stickX > 0 and "right" or "left"
				end

				return worldDir, rawDir
			end
		end

		return Vector3.zero, "none"
	end

	local function getVerticalInput()
		local y = 0

		if UserInputService:IsKeyDown(UP_KEY) then
			y += 1
		end

		if UserInputService:IsKeyDown(DOWN_KEY) then
			y -= 1
		end

		return y
	end

	local function isNearGround()
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true

		local result = workspace:Raycast(hrp.Position, Vector3.new(0, -LAND_DIST, 0), params)
		return result ~= nil
	end

	local function setFlightStates(enabled)
		for _, state in ipairs(STATES_TO_DISABLE) do
			pcall(function()
				humanoid:SetStateEnabled(state, enabled)
			end)
		end
	end

	local function stopFlying(playLand)
		if not flying then
			return
		end

		flying = false
		character:SetAttribute("Flying", false)

		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end

		if stateConnection then
			stateConnection:Disconnect()
			stateConnection = nil
		end

		linearVelocity.VectorVelocity = Vector3.zero
		linearVelocity.Enabled = false
		alignOrientation.Enabled = false

		smoothVelocity = Vector3.zero

		humanoid.AutoRotate = originalAutoRotate
		setFlightStates(true)

		if animateScript then
			animateScript.Enabled = true
		end

		stopAllFlightTracks(ANIM_FADE)

		if windSound.IsPlaying then
			windSound.Volume = 0
			windSound:Stop()
		end

		Camera.FieldOfView = NORMAL_FOV

		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end

		if playLand and humanoid.Health > 0 and isNearGround() and tracks.land then
			tracks.land:Play(0.05)
		end
	end

	local function startFlying()
		if flying or destroyed then
			return
		end

		if humanoid.Health <= 0 then
			return
		end

		flying = true
		character:SetAttribute("Flying", true)

		smoothVelocity = Vector3.zero
		linearVelocity.VectorVelocity = Vector3.zero
		linearVelocity.Enabled = true
		alignOrientation.Enabled = true

		humanoid.AutoRotate = false
		setFlightStates(false)
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)

		if animateScript then
			animateScript.Enabled = false
		end

		for _, playingTrack in ipairs(humanoid:GetPlayingAnimationTracks()) do
			playingTrack:Stop(0)
		end

		blendTo("idle")

		windSound.Volume = 0
		windSound:Play()

		stateConnection = humanoid.StateChanged:Connect(function(_, newState)
			if flying and newState ~= Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end)

		renderConnection = RunService.RenderStepped:Connect(function(dt)
			if not flying then
				return
			end

			if humanoid.Health <= 0 then
				stopFlying(false)
				return
			end

			local worldDir, rawDir = getFlightInput()
			local vertical = getVerticalInput()

			local boosting = UserInputService:IsKeyDown(BOOST_KEY)
			local hasMoveInput = worldDir.Magnitude > 0.001
			local hasVerticalInput = vertical ~= 0
			local movingAny = hasMoveInput or hasVerticalInput

			local speed = boosting and BOOST_SPEED or NORMAL_SPEED

			local targetVelocity = Vector3.zero

			if hasMoveInput then
				targetVelocity += worldDir * speed
			end

			if hasVerticalInput then
				targetVelocity += Vector3.new(0, vertical * VERT_SPEED, 0)
			end

			local rate = movingAny and ACCEL_RATE or BRAKE_RATE
			local alpha = expAlpha(rate, dt)

			smoothVelocity = smoothVelocity:Lerp(targetVelocity, alpha)

			if smoothVelocity.Magnitude < 0.05 and not movingAny then
				smoothVelocity = Vector3.zero
			end

			linearVelocity.VectorVelocity = smoothVelocity

			--// Smooth body orientation.
			--// Important: we do NOT set hrp.CFrame directly.
			local camLookFlat = flatUnit(Camera.CFrame.LookVector)
			local targetLook = camLookFlat

			-- When boosting forward, let the body lean/follow the camera direction a bit.
			if boosting and rawDir == "forward" and hasMoveInput then
				local camLook = Camera.CFrame.LookVector

				if camLook.Magnitude > 0.001 then
					targetLook = camLook.Unit
				end
			end

			local upVector = Vector3.yAxis
			if math.abs(targetLook:Dot(Vector3.yAxis)) > 0.95 then
				upVector = Camera.CFrame.UpVector
			end

			alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, targetLook, upVector)

			--// Camera FOV smoothing
			local targetFOV = NORMAL_FOV

			if movingAny then
				targetFOV = boosting and BOOST_FOV or MOVE_FOV
			end

			Camera.FieldOfView += (targetFOV - Camera.FieldOfView) * expAlpha(FOV_SMOOTHNESS, dt)

			--// Wind smoothing
			local targetWindVolume = 0

			if flying then
				targetWindVolume = boosting and 1.05 or 0.72
			end

			windSound.Volume += (targetWindVolume - windSound.Volume) * expAlpha(WIND_SMOOTHNESS, dt)

			--// Animation state
			if rawDir == "none" then
				blendTo("idle")
			elseif rawDir == "forward" then
				blendTo("forward")
			elseif rawDir == "backward" then
				blendTo("backward")
			elseif rawDir == "left" then
				blendTo("left")
			elseif rawDir == "right" then
				blendTo("right")
			end
		end)
	end

	inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		if input.KeyCode == TOGGLE_KEY then
			if flying then
				stopFlying(true)
			else
				startFlying()
			end
		end
	end)

	diedConnection = humanoid.Died:Connect(function()
		stopFlying(false)
	end)

	activeCleanup = function()
		if destroyed then
			return
		end

		destroyed = true

		stopFlying(false)

		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end

		if diedConnection then
			diedConnection:Disconnect()
			diedConnection = nil
		end

		if stateConnection then
			stateConnection:Disconnect()
			stateConnection = nil
		end

		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end

		stopAllFlightTracks(0)

		if windSound then
			windSound:Destroy()
		end

		if linearVelocity then
			linearVelocity:Destroy()
		end

		if alignOrientation then
			alignOrientation:Destroy()
		end

		if flightAttachment then
			flightAttachment:Destroy()
		end

		Camera.FieldOfView = originalCameraFOV
	end
end

Player.CharacterAdded:Connect(setupFlight)

if Player.Character then
	setupFlight(Player.Character)
end
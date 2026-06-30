--[[
	ViewportEffects (ModuleScript - ReplicatedStorage.Modules)

	PARTICLE LIMITATION: ViewportFrames cannot render ParticleEmitters - this is
	a hard Roblox engine limit. Two known workarounds exist:
	  1. Camera Trick - put a real Part in workspace and lock it to the camera
	  2. UI Tween Trick - fake particles with ImageLabels/Frames over the display

	We use approach 2 here. Effects spawn UI elements parented to displayFrame
	(the Frame that CONTAINS the ViewportFrame), so they layer on top correctly.

	RAINBOW SHEEP: Matches the exact in-game script behaviour.
	  * Targets: FurHead, FurStomach, BLF, BRF, FRF, FLF (specific named parts)
	  * All parts the same color simultaneously (uniform, not per-part)
	  * Speed: 0.01 * 0.5 per 0.03s = 0.1667 hue/s, Color3.fromHSV(hue, 1, 1)

	PHOENIX: UI fake-particle fire effect. Rising orange/red/yellow dots that
	fade and shrink, simulating the fire aura. Needs displayFrame to be passed.

	Usage:
	  local conn = ViewportEffects.apply(animalName, model3D.Object3D, displayFrame)
	  if conn then conn:Disconnect() end  -- works for both RBXScriptConnection and table
]]

local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")

local EFFECTS = {}

local function isGuiVisible(gui)
	local current = gui
	while current and current:IsA("GuiObject") do
		if not current.Visible then return false end
		current = current.Parent
	end
	return gui ~= nil and gui.Parent ~= nil
end

-- Rainbow Sheep

EFFECTS["RainbowSheep"] = function(model, displayFrame)
	local PART_NAMES = { "FurHead", "FurStomach", "BLF", "BRF", "FRF", "FLF" }
	local parts = {}

	for _, name in ipairs(PART_NAMES) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then table.insert(parts, part) end
	end

	-- fallback if naming changed
	if #parts == 0 then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	end
	if #parts == 0 then return nil end

	local hue = 0
	local accumulated = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not model or not model.Parent then
			connection:Disconnect()
			return
		end
		if displayFrame and not isGuiVisible(displayFrame) then return end
		accumulated += dt
		if accumulated < 0.05 then return end
		hue = (hue + accumulated * 0.1667) % 1
		accumulated = 0
		local color = Color3.fromHSV(hue, 1, 1)
		for _, part in ipairs(parts) do
			part.Color = color
		end
	end)
	return connection
end

-- Phoenix - UI fake fire particles
-- Particles can't render in ViewportFrames. Instead we spawn rising, fading
-- colored Frames on top of the displayFrame to simulate fire/sparks.

EFFECTS["Phoenix"] = function(_model, displayFrame)
	if not displayFrame then return nil end

	local FIRE_COLORS = {
		Color3.fromRGB(255, 60,  0),   -- deep red-orange
		Color3.fromRGB(255, 120, 0),   -- orange
		Color3.fromRGB(255, 180, 0),   -- amber
		Color3.fromRGB(255, 220, 40),  -- yellow
		Color3.fromRGB(255, 80,  20),  -- red-orange
	}

	local running = true

	task.spawn(function()
		while running do
			if not displayFrame.Parent then break end
			if not isGuiVisible(displayFrame) then
				task.wait(0.25)
				continue
			end

			local p    = Instance.new("Frame")
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = p

			p.BackgroundColor3    = FIRE_COLORS[math.random(#FIRE_COLORS)]
			p.BackgroundTransparency = 0.1
			p.BorderSizePixel     = 0
			p.ZIndex              = 20  -- above ViewportFrame, below overlays
			p.AnchorPoint         = Vector2.new(0.5, 0.5)

			local sz = math.random(5, 14)
			p.Size = UDim2.new(0, sz, 0, sz)

			-- spawn in the lower-center area (where the Phoenix body sits)
			local x = 0.5 + (math.random() - 0.5) * 0.45
			local y = 0.55 + (math.random() - 0.5) * 0.25
			p.Position = UDim2.new(x, 0, y, 0)
			p.Parent   = displayFrame

			local duration = 0.35 + math.random() * 0.45
			local driftX   = (math.random() - 0.5) * 0.18

			-- rise, shrink, fade
			TweenService:Create(p,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position             = UDim2.new(x + driftX, 0, y - 0.4, 0),
					Size                 = UDim2.new(0, 0, 0, 0),
					BackgroundTransparency = 1,
				}
			):Play()

			task.delay(duration + 0.05, function()
				if p.Parent then p:Destroy() end
			end)

			-- ~20-25 particles per second - fast enough to look like fire
			task.wait(0.04 + math.random() * 0.04)
		end
	end)

	-- return a table with Disconnect so it matches the RBXScriptConnection API
	return { Disconnect = function() running = false end }
end

-- Public API

local ViewportEffects = {}

-- modelObject  : model3D.Object3D (the actual Model inside the ViewportFrame)
-- displayFrame : the Frame containing the ViewportFrame (needed for UI particle effects)
function ViewportEffects.apply(animalName, modelObject, displayFrame)
	if not animalName then return nil end
	local fn = EFFECTS[animalName]
	return fn and fn(modelObject, displayFrame) or nil
end

function ViewportEffects.has(animalName)
	return EFFECTS[animalName] ~= nil
end

return ViewportEffects
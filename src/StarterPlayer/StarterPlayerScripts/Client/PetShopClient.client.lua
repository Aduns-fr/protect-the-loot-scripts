--[[
    PShopClient (LocalScript)

    HATCH CHANGES:
      - Removed rarity banner (LEGENDARY!/RARE! text label)
      - Removed DOF blur effect
      - Stars burst from bottom-center of egg like fireworks with a small
        reveal shockwave/ring flourish on open
      - Confetti only fires on legendary
]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local SoundService       = game:GetService("SoundService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local Modules         = ReplicatedStorage:WaitForChild("Modules")
local AnimalConfig    = require(Modules:WaitForChild("AnimalConfig"))
local Module3D        = require(Modules:WaitForChild("Module3D"))
local ViewportEffects = require(Modules:WaitForChild("ViewportEffects"))

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseCash = RemoteEvents:WaitForChild("PurchaseCash")
local HatchResult  = RemoteEvents:WaitForChild("HatchResult")

local interface    = playerGui:WaitForChild("Interface", 30)
local framesFolder = interface:WaitForChild("Frames")
local pShop        = framesFolder:WaitForChild("PShop")
local holder       = pShop:WaitForChild("ScrollingFrame")
local hatchOverlay = framesFolder:WaitForChild("HatchOverlay")
local petDisplay   = hatchOverlay:WaitForChild("PetDisplay")
local petNameLabel = hatchOverlay:WaitForChild("PetName")

local ray = petDisplay:WaitForChild("Ray")

hatchOverlay.Visible  = false
petDisplay.Visible    = false
ray.Visible           = false
ray.Rotation          = 0
ray.ImageTransparency = 1

local sfxEgg = SoundService:FindFirstChild("SFX") and SoundService.SFX:FindFirstChild("Egg")

local function playEggSound(name)
	if not sfxEgg then return end
	local s = sfxEgg:FindFirstChild(name)
	if s then pcall(function() s:Play() end) end
end

local AUTO_HATCH_GAMEPASS = 1793152566
local EGG_SLOTS           = { "Egg1","Egg2","Egg3","Egg4","Egg5" }
local EGG_CASH_PRICES     = { Egg1=100, Egg2=250, Egg3=500, Egg4=1000, Egg5=2500 }
local EGG_ROBUX = {
	Egg1=3574482544, Egg2=3574482582, Egg3=3574482616,
	Egg4=3574482655, Egg5=3574482708,
}

local INDEX_TO_EGG = {}
for i, name in ipairs(EGG_SLOTS) do INDEX_TO_EGG[i] = name end


local isHatching        = false
local hasAutoHatch      = false
local autoRunning       = {}
local anyAutoRunning    = false
local activeAutoEgg     = nil
local suppressCashPopup = false
local raysConn          = nil
local shopPreviewModels = {}
local shopPreviewAccum  = 0

RunService.Heartbeat:Connect(function(dt)
	if not pShop.Visible then return end
	shopPreviewAccum += dt
	if shopPreviewAccum < 1 / 24 then return end
	shopPreviewAccum = 0
	local rotation = CFrame.Angles(0, tick() % (math.pi * 2), 0) * CFrame.Angles(math.rad(-10), 0, 0)
	for i = #shopPreviewModels, 1, -1 do
		local preview = shopPreviewModels[i]
		local model = preview.model
		if not model or not model.Parent or not preview.display or not preview.display.Parent then
			if preview.effectConn then preview.effectConn:Disconnect() end
			table.remove(shopPreviewModels, i)
		else
			model:SetCFrame(rotation)
		end
	end
end)

-- Star assets

local STAR_IDS = {
	"rbxassetid://125927517123180", "rbxassetid://82022593272428",
	"rbxassetid://127192590767266", "rbxassetid://101489421070496",
	"rbxassetid://74182100671170",  "rbxassetid://81052531466578",
}
local STAR_COLORS = {
	Color3.fromRGB(255,220,50),  Color3.fromRGB(255,255,180),
	Color3.fromRGB(255,180,50),  Color3.fromRGB(255,255,255),
	Color3.fromRGB(255,140,200), Color3.fromRGB(140,220,255),
	Color3.fromRGB(180,255,140), Color3.fromRGB(255,160,100),
}

-- Stars

local function spawnStars(count, colorOverride, delayOffset, ringBurst)
	-- spawn from the bottom-center of the egg, burst upward and outward like fireworks
	-- they spin as they travel then fade mid-air before fully stopping
	local cx, cy = 0.5, ringBurst and 0.55 or 0.63

	for _ = 1, count do
		task.spawn(function()
			task.wait((delayOffset or 0) + math.random() * 0.09)
			if not hatchOverlay or not hatchOverlay.Parent then return end

			local star = Instance.new("ImageLabel")
			star.BackgroundTransparency = 1
			star.BorderSizePixel        = 0
			star.ZIndex                 = 74
			star.AnchorPoint            = Vector2.new(0.5, 0.5)
			star.Image                  = STAR_IDS[math.random(#STAR_IDS)]
			star.ImageColor3            = colorOverride or STAR_COLORS[math.random(#STAR_COLORS)]
			star.ImageTransparency      = 0

			-- mix of sizes, a few big ones make it feel punchy
			local sz = math.random() < 0.2 and math.random(24, 36) or math.random(8, 22)
			star.Size     = UDim2.new(0, sz, 0, sz)
			star.Position = UDim2.new(cx, 0, cy, 0)
			star.Rotation = math.random(0, 360)
			star.Parent   = hatchOverlay

			local angle
			if ringBurst then
				angle = math.random() * math.pi * 2
			elseif math.random() < 0.80 then
				angle = math.pi + math.random() * math.pi
			else
				angle = math.random() * math.pi
			end

			local dist = ringBurst and (0.18 + math.random() * 0.24) or (0.14 + math.random() * 0.30)
			local tx   = cx + math.cos(angle) * dist
			local ty   = cy + math.sin(angle) * dist * (ringBurst and 0.55 or 0.75)

			local travelTime = 0.30 + math.random() * 0.22
			local spin       = math.random(180, 500) * (math.random() > 0.5 and 1 or -1)

			-- travel outward with spin, decelerating like something launched into air
			TweenService:Create(star,
				TweenInfo.new(travelTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = UDim2.new(tx, 0, ty, 0), Rotation = star.Rotation + spin }
			):Play()

			-- fade starts around 50% through the flight so it burns out mid-arc
			local fadeStart = travelTime * 0.48
			task.wait(fadeStart)
			if not star.Parent then return end

			local fadeTime = travelTime - fadeStart + 0.06
			TweenService:Create(star,
				TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ ImageTransparency = 1, Size = UDim2.new(0, sz * 0.25, 0, sz * 0.25) }
			):Play()
			task.delay(fadeTime + 0.05, function()
				if star.Parent then star:Destroy() end
			end)
		end)
	end
end

-- FOV effects

local fovTweenIn, fovTweenOut = nil, nil
local fovGeneration = 0
local fovRestoreValue = nil

local function cancelFovTweens()
	fovGeneration += 1
	if fovTweenIn  then fovTweenIn:Cancel();  fovTweenIn  = nil end
	if fovTweenOut then fovTweenOut:Cancel(); fovTweenOut = nil end
	if fovRestoreValue then
		camera.FieldOfView = fovRestoreValue
		fovRestoreValue = nil
	end
end

local function fovClickPunch(clickNum)
	cancelFovTweens()
	local baseFov   = camera.FieldOfView
	fovRestoreValue = baseFov
	local generation = fovGeneration
	local zoomDepth = clickNum == 1 and 4 or clickNum == 2 and 8 or 14
	local tweenIn = TweenService:Create(camera,
		TweenInfo.new(0.05 + clickNum * 0.02, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov - zoomDepth })
	fovTweenIn = tweenIn
	tweenIn:Play()
	tweenIn.Completed:Once(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed
			or fovGeneration ~= generation
			or fovTweenIn ~= tweenIn then return end
		fovTweenIn = nil
		local tweenOut = TweenService:Create(camera,
			TweenInfo.new(0.22 + clickNum * 0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = baseFov })
		fovTweenOut = tweenOut
		tweenOut:Play()
		tweenOut.Completed:Once(function()
			if fovGeneration == generation and fovTweenOut == tweenOut then
				fovTweenOut = nil
				fovRestoreValue = nil
			end
		end)
	end)
end

local function fovRevealEffect()
	cancelFovTweens()
	local baseFov = camera.FieldOfView
	fovRestoreValue = baseFov
	local generation = fovGeneration
	local tweenIn = TweenService:Create(camera,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov + 12 })
	fovTweenIn = tweenIn
	tweenIn:Play()
	tweenIn.Completed:Once(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed
			or fovGeneration ~= generation
			or fovTweenIn ~= tweenIn then return end
		fovTweenIn = nil
		local tweenOut = TweenService:Create(camera,
			TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ FieldOfView = baseFov })
		fovTweenOut = tweenOut
		tweenOut:Play()
		tweenOut.Completed:Once(function()
			if fovGeneration == generation and fovTweenOut == tweenOut then
				fovTweenOut = nil
				fovRestoreValue = nil
			end
		end)
	end)
end

-- Flash helpers

local function flash(alpha)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1,1); f.BackgroundColor3 = Color3.new(1,1,1)
	f.BackgroundTransparency = alpha; f.BorderSizePixel = 0; f.ZIndex = 90; f.Parent = hatchOverlay
	TweenService:Create(f, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	task.delay(0.25, function() if f.Parent then f:Destroy() end end)
end

local function flashColor(alpha, color)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1,1); f.BackgroundColor3 = color
	f.BackgroundTransparency = alpha; f.BorderSizePixel = 0; f.ZIndex = 91; f.Parent = hatchOverlay
	TweenService:Create(f, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
	task.delay(0.45, function() if f.Parent then f:Destroy() end end)
end

local function spawnRevealRing(color)
	for i = 1, 2 do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.Position = UDim2.fromScale(0.5, 0.55)
		ring.Size = UDim2.fromOffset(20, 20)
		ring.ZIndex = 73
		ring.Parent = hatchOverlay

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ring

		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = i == 1 and 4 or 2
		stroke.Transparency = 0.15
		stroke.Parent = ring

		local target = i == 1 and 320 or 470
		TweenService:Create(ring,
			TweenInfo.new(i == 1 and 0.42 or 0.62, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(target, target) }
		):Play()
		TweenService:Create(stroke,
			TweenInfo.new(i == 1 and 0.38 or 0.56, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1 }
		):Play()
		task.delay(i == 1 and 0.45 or 0.65, function()
			if ring.Parent then ring:Destroy() end
		end)
	end
end

-- Confetti (legendary only)

local CONFETTI_COLORS = {
	Color3.fromRGB(255,213,0), Color3.fromRGB(255,59,59),   Color3.fromRGB(54,196,255),
	Color3.fromRGB(74,255,128), Color3.fromRGB(245,100,245), Color3.fromRGB(255,150,0),
	Color3.fromRGB(255,255,255), Color3.fromRGB(100,255,200), Color3.fromRGB(190,100,255),
}

local function spawnConfetti(parent)
	local screenW = parent.AbsoluteSize.X
	local screenH = parent.AbsoluteSize.Y

	local function piece(originX, originY, launchAngleDeg, spread, delay)
		task.delay(delay, function()
			if not parent.Parent then return end
			local p = Instance.new("Frame")
			local isRect = math.random() > 0.45
			p.Size = UDim2.fromOffset(
				isRect and math.random(6,18) or math.random(8,18),
				isRect and math.random(12,28) or math.random(8,18)
			)
			p.BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)]
			p.BackgroundTransparency = math.random(0,15)/100
			p.BorderSizePixel = 0; p.Rotation = math.random(0,360)
			p.AnchorPoint = Vector2.new(0.5, 0)
			p.Position = UDim2.new(0, originX, 0, originY); p.Parent = parent
			if math.random() < 0.3 then Instance.new("UICorner",p).CornerRadius = UDim.new(0.5,0) end
			local angleRad = math.rad(launchAngleDeg + math.random(-spread,spread))
			local speed = math.random(600,1400)
			local vX = math.cos(angleRad)*speed; local vY = math.sin(angleRad)*speed
			local gravity = math.random(1300,2100)
			local rotS = math.random(200,700)*(math.random(0,1)==0 and 1 or -1)
			local life = math.random(200,360)/100
			local startT = tick(); local posX,posY = originX,originY
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not p.Parent then if conn then conn:Disconnect() end; return end
				local e = tick()-startT
				if e >= life or posY > screenH+80 then
					p:Destroy()
					if conn then conn:Disconnect() end
					return
				end
				vY = vY+gravity*dt; posX = posX+vX*dt; posY = posY+vY*dt
				p.Position = UDim2.new(0,posX,0,posY); p.Rotation = p.Rotation+rotS*dt
				if e > life*0.75 then p.BackgroundTransparency=(e-life*0.75)/(life*0.25) end
			end)
		end)
	end

	for _ = 1, 55 do piece(screenW*0.12, screenH*0.88, -75, 36, math.random(0,30)/100) end
	for _ = 1, 55 do piece(screenW*0.88, screenH*0.88, -105, 36, math.random(0,30)/100) end
	for _ = 1, 40 do piece(screenW*0.5, screenH*0.55, math.random(-160,-20), 0, math.random(0,18)/100) end
end

-- Auto hatch helpers

local function setAutoState(offBtn, onBtn, isOn)
	if offBtn then offBtn.Visible = not isOn end
	if onBtn  then onBtn.Visible  = isOn     end
end

local function stopAllAuto()
	for egg in pairs(autoRunning) do autoRunning[egg] = false end
	anyAutoRunning = false; activeAutoEgg = nil
	for i, eggName in ipairs(EGG_SLOTS) do
		local frame = holder:FindFirstChild(tostring(i)); if not frame then continue end
		setAutoState(frame:FindFirstChild("OffAuto"), frame:FindFirstChild("OnAuto"), false)
	end
end

_G.stopAutoHatch = stopAllAuto

pShop:GetPropertyChangedSignal("Visible"):Connect(function()
	if not pShop.Visible and not isHatching then stopAllAuto() end
end)

task.spawn(function()
	local ok, res = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, AUTO_HATCH_GAMEPASS)
	if ok then hasAutoHatch = res end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, bought)
	if plr == player and passId == AUTO_HATCH_GAMEPASS and bought then hasAutoHatch = true end
end)

-- Rarity (color only, no banner)

local function getRarity(animalName)
	local cfg    = AnimalConfig.getConfig(animalName)
	local chance = cfg and cfg.Obtainability and cfg.Obtainability.Chance or 1
	if     chance >= 0.60 then return Color3.fromRGB(180,180,180), false
	elseif chance >= 0.20 then return Color3.fromRGB(80,210,80),   false
	elseif chance >= 0.03 then return Color3.fromRGB(80,150,255),  false
	else                       return Color3.fromRGB(255,175,0),   true
	end
end

-- 3D display helpers

local function clearDisplay(frame)
	for _, v in ipairs(frame:GetChildren()) do
		if v:IsA("ViewportFrame") then v:Destroy() end
	end
end

local function attach3D(frame, model)
	local m = Module3D:Attach3D(frame, model); if not m then return nil end
	m:SetDepthMultiplier(1.2); m.Camera.FieldOfView = 5; m.Visible = true
	m:Update()
	return m
end

-- Ray

local function startRay(rarityColor, isLegendary)
	if raysConn then raysConn:Disconnect(); raysConn = nil end
	ray.ImageColor3 = rarityColor; ray.ImageTransparency = 1; ray.Rotation = 0; ray.Visible = true
	TweenService:Create(ray, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { ImageTransparency = 0.15 }):Play()
	local angle = 0; local speed = isLegendary and 120 or 55
	raysConn = RunService.RenderStepped:Connect(function(dt)
		angle = (angle + dt * speed) % 360; ray.Rotation = angle
	end)
end

local function stopRay()
	if raysConn then raysConn:Disconnect(); raysConn = nil end
	TweenService:Create(ray, TweenInfo.new(0.2), { ImageTransparency = 1 }):Play()
	task.delay(0.25, function() ray.Visible = false; ray.Rotation = 0 end)
end

-- Overlay

local function showOverlay()
	local old = hatchOverlay:FindFirstChildOfClass("UIScale"); if old then old:Destroy() end
	local s = Instance.new("UIScale"); s.Scale = 1; s.Parent = hatchOverlay
	hatchOverlay.Visible = true; petDisplay.Visible = true; task.wait()
end

local function hideOverlay()
	stopRay(); cancelFovTweens(); petDisplay.Visible = false
	local s = hatchOverlay:FindFirstChildOfClass("UIScale")
	if s then
		TweenService:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 0 }):Play()
		task.delay(0.18, function()
			hatchOverlay.Visible = false
			if s and s.Parent then s:Destroy() end
		end)
	else
		hatchOverlay.Visible = false
	end
end

local displayScale = nil

local function ensureDisplayScale()
	if displayScale and displayScale.Parent then return end
	for _, v in ipairs(petDisplay:GetChildren()) do if v:IsA("UIScale") then v:Destroy() end end
	displayScale = Instance.new("UIScale"); displayScale.Scale = 1; displayScale.Parent = petDisplay
end

local POP_SIZES = { 1.45, 1.72, 2.05 }

local function popViewport(clickNum)
	ensureDisplayScale()
	displayScale.Scale = POP_SIZES[math.clamp(clickNum, 1, 3)]
	TweenService:Create(displayScale,
		TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function shake(intensity)
	local orig = hatchOverlay.Position
	task.spawn(function()
		for i = 1, 7 do
			local mag = intensity * (1 - i/9)
			TweenService:Create(hatchOverlay, TweenInfo.new(0.035), {
				Position = UDim2.new(
					orig.X.Scale + (math.random()-0.5)*mag, 0,
					orig.Y.Scale + (math.random()-0.5)*mag*0.5, 0)
			}):Play()
			task.wait(0.035)
		end
		TweenService:Create(hatchOverlay, TweenInfo.new(0.05), { Position = orig }):Play()
	end)
end

local function waitClick(onFire)
	local done = Instance.new("BindableEvent"); local clicked = false
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(1,1); btn.BackgroundTransparency = 1
	btn.Text = ""; btn.ZIndex = 60; btn.Parent = hatchOverlay
	local conn = btn.Activated:Connect(function()
		if clicked then return end; clicked = true; if onFire then onFire() end; done:Fire()
	end)
	done.Event:Wait(); conn:Disconnect(); btn:Destroy(); done:Destroy()
end

local function waitClickOrTimeout(timeout)
	local done = Instance.new("BindableEvent"); local fired = false
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromScale(1,1); btn.BackgroundTransparency = 1
	btn.Text = ""; btn.ZIndex = 60; btn.Parent = hatchOverlay
	local conn = btn.Activated:Connect(function()
		if fired then return end; fired = true; done:Fire()
	end)
	local timer = task.delay(timeout, function()
		if not fired then fired = true; done:Fire() end
	end)
	done.Event:Wait(); conn:Disconnect(); pcall(task.cancel, timer); btn:Destroy(); done:Destroy()
end

-- Egg / pet loading

local function loadEgg(frame, eggIndex)
	clearDisplay(frame)
	local Eggs = ReplicatedStorage:FindFirstChild("Eggs"); if not Eggs then return nil, nil end
	local tmpl = Eggs:FindFirstChild(tostring(eggIndex))
	if not tmpl then
		local slotName = INDEX_TO_EGG[eggIndex]
		if slotName then tmpl = Eggs:FindFirstChild(slotName) end
	end
	if not tmpl then return nil, nil end
	local m = attach3D(frame, tmpl:Clone()); if not m then return nil, nil end
	local state = { clickCount = 0, punchVel = 0, angle = 0 }
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not m or not m.Parent then return end
		state.punchVel = state.punchVel * (1 - math.min(1, dt*13))
		local t = tick(); local intensity = state.clickCount/3; local punch = state.punchVel
		local wobAmp = 0.02 + intensity*0.05 + punch*0.07
		local wobX = math.sin(t*(4.5+intensity*6)) * wobAmp
		local wobZ = math.sin(t*2.6) * (0.008+intensity*0.015)
		state.angle = (state.angle + dt*(0.7+intensity*2.0+punch*1.5)) % (math.pi*2)
		m:SetDepthMultiplier(math.max(0.65, 1.2+punch*0.2))
		m:SetCFrame(
			CFrame.new(wobX*0.4, math.sin(t*1.4)*0.01+punch*0.05, 0)
				* CFrame.Angles(math.rad(-10+wobZ*18), state.angle,
					math.rad(wobX*22+punch*math.sin(t*38)*12))
		)
	end)
	return conn, state
end

local function loadPet(frame, animalName)
	clearDisplay(frame)
	local cfg = AnimalConfig.getConfig(animalName); if not cfg then return nil, nil end
	local Animals = ReplicatedStorage:FindFirstChild("Animals"); if not Animals then return nil, nil end
	local tmpl = Animals:FindFirstChild(cfg.ModelName, true); if not tmpl then return nil, nil end
	local m = attach3D(frame, tmpl:Clone()); if not m then return nil, nil end
	local rotConn = RunService.RenderStepped:Connect(function()
		if not m or not m.Parent then return end
		m:SetCFrame(
			CFrame.Angles(0, (tick()*1.1) % (math.pi*2), 0) * CFrame.Angles(math.rad(-10),0,0)
		)
	end)
	local effectConn = ViewportEffects.apply(animalName, m.Object3D, frame)
	return rotConn, effectConn
end

local function bouncePetIn()
	for _, v in ipairs(petDisplay:GetChildren()) do if v:IsA("UIScale") then v:Destroy() end end
	local s = Instance.new("UIScale"); s.Scale = 0; s.Parent = petDisplay
	TweenService:Create(s, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	return s
end

-- Main hatch sequence

local function playHatch(animalName, eggIndex, skipClicks, isDuplicate, dupCash)
	if isHatching then return end
	isHatching = true; _G.isHatching = true

	local rarityColor, isLegendary = getRarity(animalName)

	pShop.Visible = false

	local eggConn, eggState
	local petScaleInst  = nil
	local petEffectConn = nil

	local function cleanup()
		isHatching = false; _G.isHatching = false
		petNameLabel.Text = ""; petNameLabel.TextColor3 = Color3.new(1,1,1)
		if displayScale and displayScale.Parent then displayScale:Destroy(); displayScale = nil end
		cancelFovTweens()
	end

	showOverlay()
	eggConn, eggState = loadEgg(petDisplay, eggIndex or 1)
	ensureDisplayScale()
	petNameLabel.Text = "Click to open"; petNameLabel.Visible = true

	if not skipClicks then
		waitClick(function()
			playEggSound("Crack"); fovClickPunch(1)
			if eggState then eggState.clickCount = 1; eggState.punchVel = 0.7 end
			popViewport(1); shake(0.022)
			spawnStars(18, nil)
		end)
		waitClick(function()
			playEggSound("Crack"); fovClickPunch(2)
			if eggState then eggState.clickCount = 2; eggState.punchVel = 0.88 end
			popViewport(2); shake(0.03)
			spawnStars(30, nil)
		end)
		waitClick(function()
			playEggSound("Crack2"); fovClickPunch(3)
			if eggState then eggState.clickCount = 3; eggState.punchVel = 1.1 end
			popViewport(3); shake(0.04); flash(0.3)
			spawnStars(45, nil); spawnStars(25, nil, 0.12)
		end)
	else
		petNameLabel.Text = "Hatching..."
		for clickNum = 1, 3 do
			task.wait(0.3)
			playEggSound(clickNum < 3 and "Crack" or "Crack2"); fovClickPunch(clickNum)
			if eggState then eggState.clickCount = clickNum; eggState.punchVel = 0.7+clickNum*0.2 end
			popViewport(clickNum); shake(0.022+clickNum*0.01)
			spawnStars(12+clickNum*5, nil)
		end
		task.wait(0.32)
	end

	task.wait(0.30)
	-- Brief anticipation squeeze before the shell disappears. It gives the
	-- reveal a cleaner impact without making the hatch sequence feel slower.
	ensureDisplayScale()
	if displayScale and displayScale.Parent then
		TweenService:Create(displayScale,
			TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.82 }
		):Play()
		task.wait(0.13)
	end
	if eggConn then eggConn:Disconnect(); eggConn = nil end
	clearDisplay(petDisplay)
	if displayScale and displayScale.Parent then displayScale:Destroy(); displayScale = nil end

	flash(0.22)
	flashColor(0.30, rarityColor)
	if isLegendary then shake(0.05) end
	task.wait(0.12)

	startRay(rarityColor, isLegendary)
	task.wait()

	local petConn
	petConn, petEffectConn = loadPet(petDisplay, animalName)
	petScaleInst = bouncePetIn()
	playEggSound("Open")
	fovRevealEffect()

	-- star burst on reveal: a tight ring pop plus the existing firework scatter
	spawnRevealRing(rarityColor)
	local revealCount = isLegendary and 80 or 55
	spawnStars(revealCount, rarityColor, 0, true)
	spawnStars(isLegendary and 40 or 22, rarityColor, 0.13)

	-- confetti only for legendary, keeps it feeling special
	if isLegendary then
		task.delay(0.15, function() spawnConfetti(hatchOverlay) end)
	end

	task.wait(0.2)
	local cfg = AnimalConfig.getConfig(animalName)
	petNameLabel.TextColor3 = rarityColor
	petNameLabel.Text       = (cfg and cfg.DisplayName) or animalName

	waitClickOrTimeout(isLegendary and 5.5 or 3)

	if petConn       then petConn:Disconnect()      end
	if petEffectConn then petEffectConn:Disconnect() end
	clearDisplay(petDisplay)

	hideOverlay()
	task.wait(0.22)
	if petScaleInst and petScaleInst.Parent then petScaleInst:Destroy() end
	cleanup()

	pShop.Visible = true

	if isDuplicate and dupCash and dupCash > 0 then
		task.defer(function() if _G.ShowCashPopup then _G.ShowCashPopup(dupCash) end end)
	end
	if _G.newTemplate then _G.newTemplate(animalName) end
end

local function parseResult(result)
	if type(result) ~= "string" then return nil, false, 0 end
	if result:sub(1,9) == "duplicate" then
		local p = result:split(":")
		return p[2] or "Unknown", true, tonumber(p[3]) or 0
	end
	return result, false, 0
end

HatchResult.OnClientEvent:Connect(function(animalName, eggIndex, isDuplicate)
	task.spawn(playHatch, animalName, eggIndex or 1, false, isDuplicate, 0)
end)

-- Egg frame population

local function populateEggFrame(frame, eggName)
	local animals = AnimalConfig.getBySource(eggName); if not animals then return end
	local list = {}
	for name, cfg in pairs(animals) do
		table.insert(list, { name = name, chance = cfg.Obtainability.Chance, config = cfg })
	end
	table.sort(list, function(a,b) return a.chance > b.chance end)
	local holderFrame = frame:FindFirstChild("Holder"); if not holderFrame then return end
	local slots = {}
	for _, child in ipairs(holderFrame:GetChildren()) do
		local n = tonumber(child.Name); if n then table.insert(slots, child) end
	end
	table.sort(slots, function(a,b) return tonumber(a.Name) < tonumber(b.Name) end)
	for i = 1, math.min(4, #slots) do
		local slot = slots[i]; local petData = list[i]; if not slot then continue end
		local cl = slot:FindFirstChild("Chance")
		if cl then cl.Text = petData and string.format("%.1f%%", petData.chance*100) or "?" end
		local nl = slot:FindFirstChild("Name")
		if nl then nl.Text = petData and petData.config.DisplayName or "?" end
		local df = slot:FindFirstChild("Display")
		if df and petData then
			local Animals = ReplicatedStorage:FindFirstChild("Animals")
			if Animals then
				local tmpl = Animals:FindFirstChild(petData.config.ModelName, true)
				if tmpl then
					local m = Module3D:Attach3D(df, tmpl:Clone())
					if m then
						m:SetDepthMultiplier(1.2); m.Camera.FieldOfView = 5; m.Visible = true
						df:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
							if not m or not m.Parent then return end
							local sz = df.AbsoluteSize; local min = math.min(sz.X, sz.Y)
							if min > 0 then m.AdornFrame.Size = UDim2.new(0, min, 0, min) end; m:Update()
						end)
						local sz = df.AbsoluteSize; local min = math.min(sz.X, sz.Y)
						if min > 0 then m.AdornFrame.Size = UDim2.new(0, min, 0, min) end; m:Update()
						local effectConn = ViewportEffects.apply(petData.name, m.Object3D, df)
						table.insert(shopPreviewModels, {
							model = m,
							display = df,
							effectConn = effectConn,
						})
					end
				end
			end
		end
	end
end

local function setupAutoButton(eggName, eggIndex, offBtn, onBtn)
	autoRunning[eggName] = false
	setAutoState(offBtn, onBtn, false)

	local function deactivate()
		autoRunning[eggName] = false
		if activeAutoEgg == eggName then anyAutoRunning = false; activeAutoEgg = nil end
		setAutoState(offBtn, onBtn, false)
	end

	local function activate()
		if anyAutoRunning then return end
		if not hasAutoHatch then
			MarketplaceService:PromptGamePassPurchase(player, AUTO_HATCH_GAMEPASS); return
		end
		if isHatching then return end
		anyAutoRunning = true; activeAutoEgg = eggName; autoRunning[eggName] = true
		setAutoState(offBtn, onBtn, true)
		task.spawn(function()
			while autoRunning[eggName] do
				if not pShop.Visible and not isHatching then autoRunning[eggName] = false; break end
				if isHatching then task.wait(0.2); continue end
				local result = PurchaseCash:InvokeServer(eggName)
				if not autoRunning[eggName] then break end
				if result == "Cannot Afford" or result == "Error" then
					autoRunning[eggName] = false; break
				end
				local animal, isDup, dupC = parseResult(result)
				if not animal then break end
				suppressCashPopup = isDup
				playHatch(animal, eggIndex, true, isDup, dupC)
				suppressCashPopup = false
				if not autoRunning[eggName] then break end
				task.wait(0.9)
			end
			deactivate()
		end)
	end

	if offBtn then offBtn.MouseButton1Click:Connect(activate)   end
	if onBtn  then onBtn.MouseButton1Click:Connect(deactivate)  end
end

for i, eggName in ipairs(EGG_SLOTS) do
	local frame = holder:FindFirstChild(tostring(i)); if not frame then continue end
	populateEggFrame(frame, eggName)

	local cashBtn = frame:FindFirstChild("Cash")
	if cashBtn then
		local priceLabel = cashBtn:FindFirstChild("Price")
		if priceLabel then priceLabel.Text = EGG_CASH_PRICES[eggName] .. " Cash" end
		cashBtn.MouseButton1Click:Connect(function()
			if isHatching then return end
			local result = PurchaseCash:InvokeServer(eggName)
			if result == "Cannot Afford" or result == "Error" then return end
			local animal, isDup, dupC = parseResult(result); if not animal then return end
			suppressCashPopup = isDup
			task.spawn(function() playHatch(animal, i, false, isDup, dupC); suppressCashPopup = false end)
		end)
	end

	local robuxBtn = frame:FindFirstChild("Robux")
	if robuxBtn then
		robuxBtn.MouseButton1Click:Connect(function()
			if not isHatching then
				MarketplaceService:PromptProductPurchase(player, EGG_ROBUX[eggName])
			end
		end)
	end

	local offBtn = frame:FindFirstChild("OffAuto")
	local onBtn  = frame:FindFirstChild("OnAuto")
	setupAutoButton(eggName, i, offBtn, onBtn)
end

_G.isSuppressingHatchPopup = function() return suppressCashPopup end





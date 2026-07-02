local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local rollScreen = gui:WaitForChild("RollScreen")
local rewardFrame = gui:WaitForChild("RewardFrame")
local openedRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CrateOpened")
local skipPromptRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ChestSkipPrompt")

local rarityColors = {
	Common = Color3.fromRGB(150, 165, 180),
	Uncommon = Color3.fromRGB(75, 225, 115),
	Rare = Color3.fromRGB(75, 145, 255),
	Epic = Color3.fromRGB(180, 85, 255),
	Legendary = Color3.fromRGB(255, 195, 45),
}

local activeChests = {}
local rolling = false
local modalState = nil

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function getHitboxPart(model)
	local hitbox = model:FindFirstChild("Part")

	if hitbox and hitbox:IsA("BasePart") then
		return hitbox
	end

	for _, obj in ipairs(model:GetChildren()) do
		if obj:IsA("BasePart") and obj.Name == "Part" then
			return obj
		end
	end

	return nil
end

local function setupHitbox(model)
	local hitbox = getHitboxPart(model)

	if not hitbox then
		warn("Chest model has no child named Part:", model:GetFullName())
		return nil
	end

	model.PrimaryPart = hitbox

	hitbox.Name = "Part"
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Massless = true

	return hitbox
end

local function addChest(instance)
	local model = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")

	if not model then
		return
	end

	if not model:GetAttribute("PlacedChest") then
		return
	end

	if activeChests[model] then
		return
	end

	local hitbox = setupHitbox(model)

	if not hitbox then
		return
	end

	-- Use IdleBasePivot if your placement/server script already sets it.
	-- Otherwise use the model's current pivot.
	local basePivot = model:GetAttribute("IdleBasePivot")

	if typeof(basePivot) ~= "CFrame" then
		basePivot = model:GetPivot()
		model:SetAttribute("IdleBasePivot", basePivot)
	end

	-- Only keep position + Y rotation for the animation anchor.
	-- No X tilt. No Z tilt.
	local _, baseYaw, _ = basePivot:ToOrientation()

	activeChests[model] = {
		hitbox = hitbox,
		basePosition = basePivot.Position,
		baseYaw = baseYaw,
		phase = math.random() * math.pi * 2,
	}
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	addChest(descendant)
end

Workspace.DescendantAdded:Connect(addChest)

Workspace.DescendantRemoving:Connect(function(instance)
	if activeChests[instance] then
		activeChests[instance] = nil
	end
end)

local animationAccumulator = 0

RunService.RenderStepped:Connect(function(dt)
	animationAccumulator += dt

	if animationAccumulator < 1 / 30 then
		return
	end

	animationAccumulator = 0

	local now = os.clock()

	for model, data in pairs(activeChests) do
		if not model.Parent then
			activeChests[model] = nil
			continue
		end

		if not data.hitbox or not data.hitbox.Parent then
			activeChests[model] = nil
			continue
		end

		local bob = math.sin(now * 1.8 + data.phase) * 0.22
		local spinYaw = (now * 0.32 + data.phase) % (math.pi * 2)

		local finalPosition = data.basePosition + Vector3.new(0, bob, 0)

		-- This rotates the model using the Part hitbox as the PrimaryPart.
		-- The Union keeps its proper local offset inside the model.
		local finalPivot =
			CFrame.new(finalPosition)
			* CFrame.Angles(0, data.baseYaw + spinYaw, 0)

		model:PivotTo(finalPivot)
	end
end)

task.spawn(function()
	while true do
		local now = os.time()

		for model in pairs(activeChests) do
			if model.Parent then
				local remaining = math.max(0, (tonumber(model:GetAttribute("ReadyAt")) or 0) - now)
				local ready = remaining <= 0

				local timer = model:FindFirstChild("Timer", true)
				local label = timer and timer:FindFirstChildWhichIsA("TextLabel", true)

				if label then
					label.Text = ready and "Ready!" or formatTime(remaining)
				end

				local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)

				if prompt then
					prompt.Enabled = model:GetAttribute("OwnerUserId") == player.UserId
					prompt.ActionText = ready and "Open" or "Skip Wait"
				end
			end
		end

		task.wait(1)
	end
end)

local function tween(object, info, goal)
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end

local function captureModalState()
	local state = {}

	local function capture(object)
		if object:IsA("GuiObject") and object ~= rollScreen and object ~= rewardFrame and object.Visible then
			state[object] = {
				Position = object.Position,
				Size = object.Size,
				Rotation = object.Rotation,
				Visible = true,
			}
		end
	end

	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") then
			capture(child)
		elseif child.Name == "Frames" then
			for _, frame in ipairs(child:GetChildren()) do
				capture(frame)
			end
		end
	end

	return state
end

local function exitGoal(object, original)
	local name = object.Name

	if name == "Top" or name == "GameDetails" then
		return {
			Position = UDim2.new(
				original.Position.X.Scale,
				original.Position.X.Offset,
				original.Position.Y.Scale - 1.15,
				original.Position.Y.Offset
			),
		}
	elseif name == "Bottom" or name == "Base" then
		return {
			Position = UDim2.new(
				original.Position.X.Scale,
				original.Position.X.Offset,
				original.Position.Y.Scale + 1.15,
				original.Position.Y.Offset
			),
		}
	end

	return {
		Position = UDim2.new(
			original.Position.X.Scale - 1.2,
			original.Position.X.Offset,
			original.Position.Y.Scale,
			original.Position.Y.Offset
		),
	}
end

local function enterModal()
	gui:SetAttribute("ChestModalActive", true)
	modalState = captureModalState()

	for object, original in pairs(modalState) do
		tween(object, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In), exitGoal(object, original))

		task.delay(0.25, function()
			if gui:GetAttribute("ChestModalActive") and object.Parent then
				object.Visible = false
			end
		end)
	end

	task.wait(0.27)
end

local function restoreModal()
	rollScreen.Visible = false
	rewardFrame.Visible = false
	gui:SetAttribute("ChestModalActive", false)

	local state = modalState or {}
	modalState = nil

	for object, original in pairs(state) do
		if object.Parent then
			object.Size = original.Size
			object.Rotation = original.Rotation
			object.Visible = original.Visible

			tween(object, TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = original.Position,
			})
		end
	end
end

local function clearRollItems()
	for _, child in ipairs(rollScreen:GetChildren()) do
		if child:GetAttribute("ChestRollRuntime") then
			child:Destroy()
		end
	end
end

local function setRollItem(frame, item, transparency)
	local holder = frame:FindFirstChild("RolledIcon")

	if not holder then
		return
	end

	local nameLabel = holder:FindFirstChild("Name")
	local oddsLabel = holder:FindFirstChild("Odds")
	local icon = holder:FindFirstChild("IconPlaceholder")
	local burst = holder:FindFirstChild("PlaceholderBurst")
	local color = rarityColors[item and item.rarity or "Common"] or rarityColors.Common

	if nameLabel then
		nameLabel.Text = item and item.name or ""
	end

	if oddsLabel then
		oddsLabel.Text = item and ((item.chance or 0) .. "%  " .. (item.rarity or "")) or ""
	end

	if icon then
		icon.ImageColor3 = color

		if item and item.imageId and item.imageId ~= "" then
			icon.Image = item.imageId
		end

		icon.ImageTransparency = transparency
	end

	if burst and burst:IsA("ImageLabel") then
		burst.ImageColor3 = color
		burst.ImageTransparency = math.clamp(0.18 + transparency * 0.82, 0, 1)
	end

	for _, descendant in ipairs(holder:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.TextTransparency = transparency
			descendant.TextStrokeTransparency = math.clamp(0.2 + transparency * 0.8, 0, 1)
		end
	end
end

local function transformedProgress(progress)
	if progress < 0.713094 then
		return (progress - 1) ^ 2 * -1.112 + 1.112
	end

	if progress < 0.792065 then
		return 1.03 - (progress - 0.75) ^ 2 * 7
	end

	return (progress - 0.919) ^ 2 * 1.9 + 0.987
end

local function focusFor(phase)
	local focus = 1 - math.clamp((phase * 2 - 1) ^ 2, 0, 1)
	return focus * focus * (3 - 2 * focus)
end

local function randomPoolItem(pool, avoidId)
	if #pool == 0 then
		return {
			name = "Unknown",
			rarity = "Common",
			damage = 0,
			chance = 0,
		}
	end

	local item = pool[math.random(1, #pool)]

	for _ = 1, 8 do
		if item.id ~= avoidId then
			break
		end

		item = pool[math.random(1, #pool)]
	end

	return item
end

local function playRoll(data)
	clearRollItems()

	local background = rollScreen:WaitForChild("BackgroundDim")
	local pointerLeft = rollScreen:WaitForChild("PointerLeft")
	local pointerRight = rollScreen:WaitForChild("PointerRight")
	local templates = rollScreen:WaitForChild("Templates")
	local columnTemplate = templates:WaitForChild("RollColumnTemplate")
	local itemTemplate = templates:WaitForChild("RollItemTemplate")

	local pool = type(data.pool) == "table" and data.pool or {}

	local final = {
		id = data.weapon,
		name = data.config.DisplayName,
		damage = data.config.Damage,
		rarity = data.config.Rarity,
		imageId = data.config.ImageId or "",
		chance = 0,
	}

	rollScreen.Visible = true
	background.Visible = true
	pointerLeft.Visible = true
	pointerRight.Visible = true

	background.BackgroundTransparency = 1
	pointerLeft.BackgroundTransparency = 1
	pointerRight.BackgroundTransparency = 1

	tween(background, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.38,
	})

	tween(pointerLeft, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.35,
	})

	tween(pointerRight, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.35,
	})

	local column = columnTemplate:Clone()
	column.Name = "ChestRollColumn"
	column:SetAttribute("ChestRollRuntime", true)
	column.Position = UDim2.fromScale(0.5, 0.48)
	column.Visible = true
	column.Parent = rollScreen

	local items = {}

	for i = 1, 4 do
		local frame = itemTemplate:Clone()
		frame.Name = "ChestRollItem" .. i
		frame.Visible = true
		frame.Parent = column

		local scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", frame)
		scale.Scale = 0

		items[i] = {
			frame = frame,
			scale = scale,
			shown = randomPoolItem(pool),
			lastPhase = 0,
		}

		setRollItem(frame, items[i].shown, 1)
	end

	local duration = 3.15
	local elapsed = 0
	local cycles = 6

	while elapsed < duration do
		local dt = RunService.RenderStepped:Wait()
		elapsed += dt

		local progress = math.clamp(elapsed / duration, 0, 1)
		local transformed = transformedProgress(progress)

		for i, state in ipairs(items) do
			local phase = (transformed * cycles % 1 + (i - 1) / 4) % 1

			if phase < state.lastPhase and progress < 0.78 then
				state.shown = randomPoolItem(pool, state.shown and state.shown.id)
				setRollItem(state.frame, state.shown, 0)
				-- tied directly to the visual wraparound, same frame it happens
				-- speed tracks the animation curve so sound matches what you see
				if _G.PlaySound then
					local tickSpeed = 1.85 - (progress * 1.25)
					_G.PlaySound("Roll", math.max(0.6, tickSpeed))
				end
			end

			if i == 3 and progress > 0.72 then
				state.shown = final
			end

			local focus = focusFor(phase)

			state.frame.Position = UDim2.fromScale(0.5, 0.5 + (phase - 0.5) * 3.65)
			state.scale.Scale = math.max(focus, 0.02)

			setRollItem(state.frame, state.shown, 1 - focus)

			state.lastPhase = phase
		end
	end

	for i, state in ipairs(items) do
		if i == 3 then
			state.shown = final
			setRollItem(state.frame, final, 0)

			tween(state.frame, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(0.5, 0.5),
				Rotation = 0,
			})

			tween(state.scale, TweenInfo.new(0.44, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1.36,
			})
		else
			tween(state.scale, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Scale = 0,
			})
		end
	end

	-- winner is locked in center right now — this is the exact frame to play open + confetti
	if _G.PlaySound then _G.PlaySound("Open") end
	if _G.ShowConfetti then task.spawn(_G.ShowConfetti) end

	task.wait(2.0)

	tween(background, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})

	tween(pointerLeft, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})

	tween(pointerRight, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})

	tween(items[3].scale, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		Scale = 0,
	})

	task.wait(0.26)

	rollScreen.Visible = false
	clearRollItems()
end

local function showReward(data)
	local item = rewardFrame:WaitForChild("Item")
	local nameLabel = item:FindFirstChild("Name")
	local damageLabel = item:FindFirstChild("Damage")

	if nameLabel then
		nameLabel.Text = data.config.DisplayName or data.weapon
	end

	if damageLabel then
		damageLabel.Text = tostring(data.config.Damage or 0) .. " Damage"
	end

	if data.config.ImageId and data.config.ImageId ~= "" then
		item.Image = data.config.ImageId
	end

	local originalPosition = rewardFrame.Position
	local originalSize = rewardFrame.Size
	local originalRotation = rewardFrame.Rotation

	rewardFrame.Position = UDim2.new(
		originalPosition.X.Scale,
		originalPosition.X.Offset,
		originalPosition.Y.Scale + 0.08,
		originalPosition.Y.Offset
	)

	rewardFrame.Size = UDim2.new(
		originalSize.X.Scale * 0.72,
		math.floor(originalSize.X.Offset * 0.72),
		originalSize.Y.Scale * 0.72,
		math.floor(originalSize.Y.Offset * 0.72)
	)

	rewardFrame.Rotation = originalRotation - 8
	rewardFrame.Visible = true

	tween(rewardFrame, TweenInfo.new(0.46, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = originalPosition,
		Size = originalSize,
		Rotation = originalRotation,
	})

	task.wait(2.6)

	tween(rewardFrame, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = UDim2.new(
			originalPosition.X.Scale,
			originalPosition.X.Offset,
			originalPosition.Y.Scale - 0.08,
			originalPosition.Y.Offset
		),
		Size = UDim2.new(
			originalSize.X.Scale * 0.72,
			math.floor(originalSize.X.Offset * 0.72),
			originalSize.Y.Scale * 0.72,
			math.floor(originalSize.Y.Offset * 0.72)
		),
		Rotation = originalRotation + 8,
	})

	task.wait(0.3)

	rewardFrame.Visible = false
	rewardFrame.Position = originalPosition
	rewardFrame.Size = originalSize
	rewardFrame.Rotation = originalRotation
end

openedRemote.OnClientEvent:Connect(function(data)
	if rolling or type(data) ~= "table" or type(data.config) ~= "table" then
		return
	end

	rolling = true

	task.spawn(function()
		enterModal()
		playRoll(data)

		if data.isNew then
			showReward(data)
		end

		restoreModal()
		rolling = false
	end)
end)

skipPromptRemote.OnClientEvent:Connect(function(productId)
	productId = tonumber(productId) or 0
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	end
end)

rollScreen.Visible = false
rewardFrame.Visible = false

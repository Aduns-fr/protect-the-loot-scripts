local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local holder = script.Parent
local template = holder:WaitForChild("Cash")
local layer = holder:WaitForChild("CashRainLayer")

holder.ClipsDescendants = true
layer.ClipsDescendants = true
layer.BackgroundTransparency = 1
layer.BorderSizePixel = 0
layer.Size = UDim2.fromScale(1, 1)
layer.Position = UDim2.fromScale(0, 0)
layer.Active = false
layer.Selectable = false
layer.ZIndex = math.max(1, template.ZIndex - 1)
template.Visible = false

local MAX_ICONS = 12
local SPAWN_MIN = 0.18
local SPAWN_MAX = 0.34
local MIN_DURATION = 2.9
local MAX_DURATION = 4.4

local rng = Random.new()
local alive = 0
local lanes = { 0.08, 0.22, 0.36, 0.50, 0.64, 0.78, 0.92 }

local function isActuallyVisible(guiObject)
	local current = guiObject
	while current and current:IsA("GuiObject") do
		if not current.Visible then return false end
		current = current.Parent
	end
	return true
end

local function getIconSize()
	if template.AbsoluteSize.X > 2 and template.AbsoluteSize.Y > 2 then
		local scale = rng:NextNumber(0.62, 1.08)
		return UDim2.fromOffset(template.AbsoluteSize.X * scale, template.AbsoluteSize.Y * scale)
	end
	local scale = rng:NextNumber(0.72, 1.08)
	return UDim2.fromScale(template.Size.X.Scale * scale, template.Size.Y.Scale * scale)
end

local function spawnCash()
	if alive >= MAX_ICONS or not isActuallyVisible(holder) then return end
	if layer.AbsoluteSize.X <= 0 or layer.AbsoluteSize.Y <= 0 then return end
	alive += 1

	local icon = template:Clone()
	icon.Name = "CashDrop"
	icon.Visible = true
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = getIconSize()
	icon.ImageTransparency = math.clamp(template.ImageTransparency, 0, 0.72)
	icon.ZIndex = layer.ZIndex
	icon.Active = false
	icon.Selectable = false

	local lane = lanes[rng:NextInteger(1, #lanes)]
	local startX = math.clamp(lane + rng:NextNumber(-0.055, 0.055), 0.04, 0.96)
	local endX = math.clamp(startX + rng:NextNumber(-0.12, 0.12), -0.08, 1.08)
	local duration = rng:NextNumber(MIN_DURATION, MAX_DURATION)

	icon.Position = UDim2.fromScale(startX, -0.18)
	icon.Rotation = rng:NextInteger(-24, 24)
	icon.Parent = layer

	TweenService:Create(icon, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Position = UDim2.fromScale(endX, 1.18),
		Rotation = icon.Rotation + rng:NextInteger(-80, 80),
	}):Play()

	task.delay(duration * 0.72, function()
		if icon.Parent then
			TweenService:Create(icon, TweenInfo.new(duration * 0.25, Enum.EasingStyle.Quad), {
				ImageTransparency = 1,
			}):Play()
		end
	end)

	Debris:AddItem(icon, duration + 0.15)
	task.delay(duration + 0.15, function()
		alive = math.max(0, alive - 1)
	end)
end

task.spawn(function()
	task.wait(rng:NextNumber(0.2, 0.6))
	while holder:IsDescendantOf(game) do
		spawnCash()
		task.wait(rng:NextNumber(SPAWN_MIN, SPAWN_MAX))
	end
end)

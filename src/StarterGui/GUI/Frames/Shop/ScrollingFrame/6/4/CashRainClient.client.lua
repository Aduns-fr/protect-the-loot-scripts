local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local holder = script.Parent
local template = holder:WaitForChild("Cash")
local layer = holder:WaitForChild("CashRainLayer")

holder.ClipsDescendants = true
template.Visible = false
template.ZIndex = 11

layer.ClipsDescendants = true
layer.BackgroundTransparency = 1
layer.BorderSizePixel = 0
layer.Position = UDim2.fromScale(0, 0)
layer.Size = UDim2.fromScale(1, 1)
layer.Active = false
layer.Selectable = false
layer.ZIndex = 11

local MAX_ICONS = 16
local SPAWN_MIN = 0.13
local SPAWN_MAX = 0.22
local MIN_DURATION = 2.4
local MAX_DURATION = 3.6

local rng = Random.new()
local alive = 0
local lanes = { 0.08, 0.2, 0.32, 0.44, 0.56, 0.68, 0.8, 0.92 }

local function isActuallyVisible(guiObject)
	local current = guiObject
	while current and current:IsA("GuiObject") do
		if not current.Visible then return false end
		current = current.Parent
	end
	return true
end

local function getIconSize()
	local abs = template.AbsoluteSize
	if abs.X > 2 and abs.Y > 2 then
		local scale = rng:NextNumber(0.52, 0.82)
		local maxHeight = math.max(22, layer.AbsoluteSize.Y * 0.26)
		local height = math.min(abs.Y * scale, maxHeight)
		return UDim2.fromOffset(height, height)
	end
	return UDim2.fromScale(0.1, 0.26)
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
	icon.ImageTransparency = 0.22
	icon.ZIndex = 11
	icon.Rotation = 0
	icon.Active = false
	icon.Selectable = false

	local startX = math.clamp(lanes[rng:NextInteger(1, #lanes)] + rng:NextNumber(-0.035, 0.035), 0.06, 0.94)
	local endX = math.clamp(startX + rng:NextNumber(-0.08, 0.08), 0.06, 0.94)
	local duration = rng:NextNumber(MIN_DURATION, MAX_DURATION)

	icon.Position = UDim2.fromScale(startX, 0.05)
	icon.Parent = layer

	TweenService:Create(icon, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Position = UDim2.fromScale(endX, 0.95),
		ImageTransparency = 0.42,
	}):Play()

	task.delay(duration * 0.72, function()
		if icon.Parent then
			TweenService:Create(icon, TweenInfo.new(duration * 0.25, Enum.EasingStyle.Quad), {
				ImageTransparency = 1,
			}):Play()
		end
	end)

	Debris:AddItem(icon, duration + 0.1)
	task.delay(duration + 0.1, function()
		alive = math.max(0, alive - 1)
	end)
end

task.spawn(function()
	task.wait(rng:NextNumber(0.15, 0.35))
	while holder:IsDescendantOf(game) do
		spawnCash()
		task.wait(rng:NextNumber(SPAWN_MIN, SPAWN_MAX))
	end
end)

local RunService = game:GetService("RunService")

local holder = script.Parent
local template = holder:WaitForChild("Cash")
local layer = holder:WaitForChild("CashRainLayer")

local RAIN_Z_INDEX = 11
local DROP_COUNT = 18
local MIN_SPEED = 0.18
local MAX_SPEED = 0.34
local MIN_ALPHA = 0.18
local MAX_ALPHA = 0.36

holder.ClipsDescendants = true
template.Visible = false
template.ZIndex = RAIN_Z_INDEX

layer.ClipsDescendants = true
layer.BackgroundTransparency = 1
layer.BorderSizePixel = 0
layer.Position = UDim2.fromScale(0, 0)
layer.Size = UDim2.fromScale(1, 1)
layer.Active = false
layer.Selectable = false
layer.ZIndex = RAIN_Z_INDEX

local rng = Random.new()
local drops = {}
local lanes = { 0.07, 0.17, 0.27, 0.37, 0.47, 0.57, 0.67, 0.77, 0.87, 0.95 }

local function isActuallyVisible(guiObject)
	local current = guiObject
	while current and current:IsA("GuiObject") do
		if not current.Visible then return false end
		current = current.Parent
	end
	return true
end

local function iconSize(scale)
	local abs = template.AbsoluteSize
	if abs.X > 2 and abs.Y > 2 then
		local maxHeight = math.max(24, layer.AbsoluteSize.Y * 0.24)
		local height = math.min(abs.Y * scale, maxHeight)
		return UDim2.fromOffset(height, height)
	end
	return UDim2.fromScale(0.09 * scale, 0.22 * scale)
end

local function chooseDrop(drop, stagger)
	local lane = lanes[rng:NextInteger(1, #lanes)]
	drop.baseX = math.clamp(lane + rng:NextNumber(-0.028, 0.028), 0.06, 0.94)
	drop.y = stagger and rng:NextNumber(0.03, 0.96) or -rng:NextNumber(0.04, 0.18)
	drop.speed = rng:NextNumber(MIN_SPEED, MAX_SPEED)
	drop.drift = rng:NextNumber(0.012, 0.038)
	drop.driftSpeed = rng:NextNumber(1.0, 2.1)
	drop.phase = rng:NextNumber(0, math.pi * 2)
	drop.alpha = rng:NextNumber(MIN_ALPHA, MAX_ALPHA)
	drop.scale = rng:NextNumber(0.62, 0.95)

	drop.icon.Size = iconSize(drop.scale)
	drop.icon.ImageTransparency = drop.alpha
	drop.icon.Rotation = 0
	drop.icon.ZIndex = RAIN_Z_INDEX
	drop.icon.Visible = true
end

local function makeDrop(index)
	local icon = template:Clone()
	icon.Name = "CashDrop"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Active = false
	icon.Selectable = false
	icon.Parent = layer

	local drop = {
		icon = icon,
		baseX = 0.5,
		y = 0,
		speed = 0.2,
		drift = 0.02,
		driftSpeed = 1,
		phase = 0,
		alpha = 0.25,
		scale = 0.8,
	}
	chooseDrop(drop, index > 1)
	return drop
end

for i = 1, DROP_COUNT do
	drops[i] = makeDrop(i)
end

local connection
connection = RunService.RenderStepped:Connect(function(dt)
	if not holder:IsDescendantOf(game) then
		if connection then connection:Disconnect() end
		return
	end

	local visible = isActuallyVisible(holder) and layer.AbsoluteSize.X > 0 and layer.AbsoluteSize.Y > 0
	for _, drop in ipairs(drops) do
		local icon = drop.icon
		if not icon.Parent then continue end

		if not visible then
			icon.Visible = false
			continue
		end

		if not icon.Visible then
			chooseDrop(drop, true)
		end

		drop.y += drop.speed * dt
		if drop.y > 1.05 then
			chooseDrop(drop, false)
		end

		local x = math.clamp(drop.baseX + math.sin(os.clock() * drop.driftSpeed + drop.phase) * drop.drift, 0.05, 0.95)
		local y = math.clamp(drop.y, 0.03, 0.97)
		local edgeFade = math.clamp(math.min(y / 0.12, (1 - y) / 0.12), 0, 1)
		icon.ImageTransparency = 1 - ((1 - drop.alpha) * edgeFade)
		icon.Position = UDim2.fromScale(x, y)
	end
end)

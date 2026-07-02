local ReplicatedStorage = game:GetService("ReplicatedStorage")

local frame = script.Parent
local scroll = frame:WaitForChild("ScrollingFrame")
local template = scroll:WaitForChild("Template")
local ownedLabel = frame:FindFirstChild("Owned")
local BadgeConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("BadgeConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateRemote = remotes:WaitForChild("BadgeState")
local updateRemote = remotes:WaitForChild("BadgeUpdate")

local cards = {}

scroll.ScrollingEnabled = true
scroll.Active = true
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.ClipsDescendants = true
scroll.ScrollBarThickness = math.max(scroll.ScrollBarThickness, 8)

local function setTextWithChildren(label, text)
	if not label or not label:IsA("TextLabel") then
		return
	end
	label.Text = text
	for _, descendant in ipairs(label:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.Text = text
		end
	end
end

local function applyCard(card, badge)
	local unlocked = badge.Unlocked == true
	local title = unlocked and tostring(badge.Title or "") or "???"
	local how = unlocked and tostring(badge.How or "") or "???"
	local tip = unlocked and tostring(badge.Tip or "") or "???"

	setTextWithChildren(card:FindFirstChild("Title1"), title)
	setTextWithChildren(card:FindFirstChild("Title2"), how)
	setTextWithChildren(card:FindFirstChild("Title3"), tip)

	local claimed = card:FindFirstChild("Claimed")
	if claimed and claimed:IsA("GuiObject") then
		claimed.Visible = unlocked
	end

	local icon = card:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		if unlocked and badge.Icon and badge.Icon ~= "" then
			icon.Image = badge.Icon
		end
		icon.ImageTransparency = unlocked and 0 or 0.35
		for _, descendant in ipairs(icon:GetDescendants()) do
			if descendant:IsA("ImageLabel") then
				descendant.ImageTransparency = icon.ImageTransparency
			end
		end
	end
end

local function refreshCanvas()
	local layout = scroll:FindFirstChildOfClass("UIListLayout") or scroll:FindFirstChildOfClass("UIGridLayout")
	task.defer(function()
		local contentHeight = layout and layout.AbsoluteContentSize.Y or 0
		local top = math.huge
		local bottom = -math.huge
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") and child ~= template and child.Visible then
				local y = child.AbsolutePosition.Y - scroll.AbsolutePosition.Y
				top = math.min(top, y)
				bottom = math.max(bottom, y + child.AbsoluteSize.Y)
			end
		end
		if bottom > top then
			contentHeight = math.max(contentHeight, bottom - math.min(0, top))
		end
		local padding = scroll:FindFirstChildOfClass("UIPadding")
		if padding then
			contentHeight += padding.PaddingTop.Offset + padding.PaddingBottom.Offset
		end
		scroll.CanvasSize = UDim2.fromOffset(0, math.ceil(contentHeight + 42))
	end)
end

local layout = scroll:FindFirstChildOfClass("UIListLayout") or scroll:FindFirstChildOfClass("UIGridLayout")
if layout then
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)
end
scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refreshCanvas)

local function render(payload)
	if type(payload) ~= "table" or type(payload.Badges) ~= "table" then
		return
	end

	template.Visible = false
	local seen = {}
	for index, badge in ipairs(payload.Badges) do
		local key = tostring(badge.Key or index)
		seen[key] = true
		local card = cards[key]
		if not card then
			card = template:Clone()
			card.Name = key
			card.Parent = scroll
			cards[key] = card
		end
		card.LayoutOrder = index
		card.Visible = true
		applyCard(card, badge)
	end
	for key, card in pairs(cards) do
		if not seen[key] and card.Parent then
			card.Visible = false
		end
	end

	if ownedLabel and ownedLabel:IsA("TextLabel") then
		local text = tostring(payload.Owned or 0) .. "/" .. tostring(payload.Total or #payload.Badges)
		setTextWithChildren(ownedLabel, text)
	end
	refreshCanvas()
end

local function renderLockedFromConfig()
	local badges = {}
	for index, badgeKey in ipairs(BadgeConfig.Order or {}) do
		local config = BadgeConfig.Badges and BadgeConfig.Badges[badgeKey]
		if config then
			badges[index] = {
				Key = badgeKey,
				BadgeId = tonumber(config.BadgeId) or 0,
				Title = config.Title,
				How = config.How,
				Tip = config.Tip,
				Icon = config.Icon,
				Unlocked = false,
			}
		end
	end
	render({
		Owned = 0,
		Total = #badges,
		Badges = badges,
	})
end

local function requestState()
	local ok, payload = pcall(function()
		return stateRemote:InvokeServer()
	end)
	if ok then
		render(payload)
	else
		warn("[BadgesClient]", payload)
	end
end

updateRemote.OnClientEvent:Connect(render)
renderLockedFromConfig()
requestState()
frame:GetPropertyChangedSignal("Visible"):Connect(function()
	if frame.Visible then
		requestState()
	end
end)

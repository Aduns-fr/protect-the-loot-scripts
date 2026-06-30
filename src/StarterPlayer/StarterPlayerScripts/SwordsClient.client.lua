local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local closeFrameRequest = gui:WaitForChild("CloseFrameRequest")
local swordsFrame = frames:WaitForChild("Swords")
local scroll = swordsFrame:WaitForChild("ScrollingFrame")
local template = scroll:WaitForChild("Template")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local equipRemote = remotes:WaitForChild("EquipSword")
local crateOpenedRemote = remotes:WaitForChild("CrateOpened")
local swordsUpdateRemote = remotes:WaitForChild("SwordsUpdate")

local SwordsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SwordsConfig"))

local CLICK_IN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLICK_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- which sword button is currently selected (highlighted)
local selectedButton = nil

local function scaleButton(button)
	if not button or not button:IsA("GuiButton") or button:GetAttribute("ClickAnimBound") then return end
	button:SetAttribute("ClickAnimBound", true)
	local scale = button:FindFirstChild("ClickScale") or Instance.new("UIScale")
	scale.Name = "ClickScale"
	scale.Parent = button
	button.MouseButton1Down:Connect(function() TweenService:Create(scale, CLICK_IN, { Scale = 0.92 }):Play() end)
	local function release() TweenService:Create(scale, CLICK_OUT, { Scale = 1 }):Play() end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

local function setSelected(button)
	-- unhighlight old
	if selectedButton and selectedButton.Parent then
		for _, stroke in ipairs(selectedButton:GetDescendants()) do
			if stroke:IsA("UIStroke") then
				local orig = stroke:GetAttribute("OriginalColor")
				if orig then stroke.Color = orig end
			end
		end
	end
	selectedButton = button
	if not button then return end
	-- highlight new one green
	for _, stroke in ipairs(button:GetDescendants()) do
		if stroke:IsA("UIStroke") then
			if stroke:GetAttribute("OriginalColor") == nil then
				stroke:SetAttribute("OriginalColor", stroke.Color)
			end
			stroke.Color = Color3.fromRGB(79, 200, 50)
		end
	end
end

-- owned swords set, starts with just the wooden sword
local ownedSwords = { WoodenSword = true }

local function addSwordCard(swordId)
	local cfg = SwordsConfig.Swords[swordId]
	if not cfg then return end

	-- don't add dupes
	if scroll:FindFirstChild(swordId) then return end

	local card = template:Clone()
	card.Name = swordId
	card.Visible = true
	card.Parent = scroll

	local nameLabel = card:FindFirstChild("Name")
	local dmgLabel = card:FindFirstChild("Dmg")
	if nameLabel then nameLabel.Text = cfg.DisplayName or swordId end
	if dmgLabel then dmgLabel.Text = tostring(cfg.Damage or 0) .. " DMG" end

	scaleButton(card)

	card.Activated:Connect(function()
		local ok, success, message = pcall(function()
			return equipRemote:InvokeServer(swordId)
		end)
		if ok and success then
			setSelected(card)
			gui:SetAttribute("LastEquippedSword", swordId)
			gui:SetAttribute("DeleteMode", false)
			gui:SetAttribute("SwordEquipped", true)
			closeFrameRequest:Fire()
		elseif not ok then
			warn("[SwordsClient] equip failed:", success)
		else
			warn("[SwordsClient] equip rejected:", message)
		end
	end)
end

local function rebuildSwordsFrame()
	-- clear old cards (keep template hidden)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("ImageButton") and child ~= template then
			child:Destroy()
		end
	end
	selectedButton = nil

	-- always add wooden sword first
	addSwordCard("WoodenSword")

	-- add everything else the player owns
	for swordId in pairs(ownedSwords) do
		if swordId ~= "WoodenSword" then
			addSwordCard(swordId)
		end
	end

	-- update canvas size for the grid
	local grid = scroll:FindFirstChildOfClass("UIGridLayout")
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	if grid then
		task.defer(function()
			scroll.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 24)
		end)
	end
end

-- server sends the full owned swords list on join / after earning one
swordsUpdateRemote.OnClientEvent:Connect(function(swordsList)
	if type(swordsList) ~= "table" then return end
	ownedSwords = { WoodenSword = true }
	for _, swordId in ipairs(swordsList) do
		ownedSwords[swordId] = true
	end
	rebuildSwordsFrame()
end)

-- when a crate rolls a sword, add it live without waiting for a server resync
crateOpenedRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local swordId = data.sword or data.weapon
	if not swordId or not SwordsConfig.Swords[swordId] then return end
	ownedSwords[swordId] = true
	addSwordCard(swordId)
end)

template.Visible = false
rebuildSwordsFrame()

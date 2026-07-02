local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local giftFrame = script.Parent
local shopFrame = frames:WaitForChild("Shop")
local shopScroll = shopFrame:WaitForChild("ScrollingFrame")
local openFrameRequest = gui:WaitForChild("OpenFrameRequest")
local closeFrameRequest = gui:WaitForChild("CloseFrameRequest")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local giftPurchaseRemote = remotes:WaitForChild("GiftPurchase")
local DeveloperProductsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DeveloperProductsConfig"))

local ROBUX_ICON = utf8.char(0xE002)
local playerScroll = giftFrame:WaitForChild("ScrollingFrame1")
local productScroll = giftFrame:WaitForChild("ScrollingFrame2")
local playerTemplate = playerScroll:WaitForChild("Template")
local productTemplate = productScroll:WaitForChild("Template")
local sendButton = giftFrame:WaitForChild("Send")
local title1 = giftFrame:FindFirstChild("Title1") or giftFrame:FindFirstChild("TextLabel1")
local title2 = giftFrame:FindFirstChild("Title2") or giftFrame:FindFirstChild("TextLabel2")

local selectedPlayer = nil
local selectedGiftKey = nil
local playerButtons = {}
local productButtons = {}

local function setTextWithChildren(label, text)
	if not label then return end
	if label:IsA("TextLabel") or label:IsA("TextButton") then
		label.Text = text
	end
	for _, descendant in ipairs(label:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			descendant.Text = text
		end
	end
end

local function textTarget(button)
	return button:FindFirstChild("Title") or button:FindFirstChildWhichIsA("TextLabel", true)
end

local function canvas(scroll)
	scroll.ScrollingEnabled = true
	scroll.Active = true
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollBarThickness = math.max(scroll.ScrollBarThickness, 6)
	local layout = scroll:FindFirstChildOfClass("UIListLayout") or scroll:FindFirstChildOfClass("UIGridLayout")
	task.defer(function()
		local contentHeight = layout and layout.AbsoluteContentSize.Y or 0
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible and child:GetAttribute("GiftRuntime") then
				local y = child.AbsolutePosition.Y - scroll.AbsolutePosition.Y
				contentHeight = math.max(contentHeight, y + child.AbsoluteSize.Y)
			end
		end
		scroll.CanvasSize = UDim2.fromOffset(0, math.ceil(contentHeight + 28))
	end)
end

local function forceGiftRowSize(button, scroll)
	if not button or not button:IsA("GuiObject") then return end
	local height = scroll == productScroll and 44 or 50
	button.Size = UDim2.new(1, -12, 0, height)
	button.AutomaticSize = Enum.AutomaticSize.None
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("UIAspectRatioConstraint") then
			descendant:Destroy()
		elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			descendant.TextScaled = true
		end
	end
end

local function scaleButton(button)
	if not button or not button:IsA("GuiButton") or button:GetAttribute("GiftAnimBound") then return end
	button:SetAttribute("GiftAnimBound", true)
	local scale = button:FindFirstChild("GiftScale") or Instance.new("UIScale")
	scale.Name = "GiftScale"
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = 0.94 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

local function setSelected(buttons, selectedButton)
	for _, button in pairs(buttons) do
		local stroke = button:FindFirstChildWhichIsA("UIStroke", true)
		if stroke then
			if stroke:GetAttribute("OriginalColor") == nil then
				stroke:SetAttribute("OriginalColor", stroke.Color)
			end
			stroke.Color = button == selectedButton and Color3.fromRGB(85, 255, 120) or stroke:GetAttribute("OriginalColor")
		end
	end
end

local function updateTitles()
	if selectedPlayer then
		setTextWithChildren(title1, "Sending to: " .. selectedPlayer.Name)
	else
		setTextWithChildren(title1, "Select a Player")
	end
	local config = selectedGiftKey and DeveloperProductsConfig.Gifts[selectedGiftKey]
	if config then
		setTextWithChildren(title2, "Sending " .. tostring(config.DisplayName or selectedGiftKey))
	else
		setTextWithChildren(title2, "Select a product")
	end
end

local function clearRuntime(scroll, template)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") and child ~= template and child:GetAttribute("GiftRuntime") then
			child:Destroy()
		end
	end
end

local function renderPlayers()
	clearRuntime(playerScroll, playerTemplate)
	table.clear(playerButtons)
	playerTemplate.Visible = false
	if selectedPlayer and (not selectedPlayer.Parent or selectedPlayer == player) then
		selectedPlayer = nil
	end
	local order = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			order += 1
			local button = playerTemplate:Clone()
			button.Name = other.Name
			button.LayoutOrder = order
			button.Visible = true
			button:SetAttribute("GiftRuntime", true)
			button.Parent = playerScroll
			forceGiftRowSize(button, playerScroll)
			playerButtons[other.UserId] = button
			setTextWithChildren(textTarget(button), other.Name)
			scaleButton(button)
			button.Activated:Connect(function()
				selectedPlayer = other
				setSelected(playerButtons, button)
				updateTitles()
			end)
		end
	end
	canvas(playerScroll)
	updateTitles()
end

local function renderProducts()
	clearRuntime(productScroll, productTemplate)
	table.clear(productButtons)
	productTemplate.Visible = false
	for index, giftKey in ipairs(DeveloperProductsConfig.GiftOrder or {}) do
		local config = DeveloperProductsConfig.Gifts[giftKey]
		if config then
			local button = productTemplate:Clone()
			button.Name = giftKey
			button.LayoutOrder = index
			button.Visible = true
			button:SetAttribute("GiftRuntime", true)
			button.Parent = productScroll
			forceGiftRowSize(button, productScroll)
			productButtons[giftKey] = button
			setTextWithChildren(textTarget(button), string.format("%s  %s%d", config.DisplayName or giftKey, ROBUX_ICON, config.RobuxPrice or 0))
			scaleButton(button)
			button.Activated:Connect(function()
				selectedGiftKey = giftKey
				setSelected(productButtons, button)
				updateTitles()
			end)
		end
	end
	canvas(productScroll)
	updateTitles()
end

local openGift = shopScroll:FindFirstChild("7") and shopScroll["7"]:FindFirstChild("Open")
if openGift and openGift:IsA("GuiButton") then
	scaleButton(openGift)
	openGift.Activated:Connect(function()
		closeFrameRequest:Fire()
		task.wait(0.12)
		openFrameRequest:Fire("Gift")
	end)
end

scaleButton(sendButton)
sendButton.Activated:Connect(function()
	if not selectedPlayer then
		if _G.ShowNotif then _G.ShowNotif("Select a player first", Color3.fromRGB(255, 70, 70)) end
		return
	end
	if not selectedGiftKey then
		if _G.ShowNotif then _G.ShowNotif("Select a product first", Color3.fromRGB(255, 70, 70)) end
		return
	end
	local ok, success, message, productId = pcall(function()
		return giftPurchaseRemote:InvokeServer(selectedPlayer.UserId, selectedGiftKey)
	end)
	if ok and success and tonumber(productId) and tonumber(productId) > 0 then
		MarketplaceService:PromptProductPurchase(player, tonumber(productId))
	elseif _G.ShowNotif then
		_G.ShowNotif(tostring(ok and message or success or "Gift unavailable"), Color3.fromRGB(255, 70, 70))
	end
end)

Players.PlayerAdded:Connect(renderPlayers)
Players.PlayerRemoving:Connect(function(leavingPlayer)
	if selectedPlayer == leavingPlayer then
		selectedPlayer = nil
	end
	renderPlayers()
end)

renderPlayers()
renderProducts()

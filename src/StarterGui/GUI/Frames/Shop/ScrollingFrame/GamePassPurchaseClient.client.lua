local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local scroll = script.Parent
local GamePassConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GamePassConfig"))

local ROBUX_ICON = utf8.char(0xE002)

local passCards = {
	{
		key = "VIP",
		entitlementKey = "VIP",
		passId = GamePassConfig.VIP,
		price = GamePassConfig.Prices and GamePassConfig.Prices.VIP or 399,
		button = function()
			local frame = scroll:FindFirstChild("1")
			return frame and frame:FindFirstChild("Buy")
		end,
		label = function(button)
			return button and button:FindFirstChild("Title")
		end,
	},
	{
		key = "DoubleCash",
		entitlementKey = "DoubleCash",
		passId = GamePassConfig.DoubleCash,
		price = GamePassConfig.Prices and GamePassConfig.Prices.DoubleCash or 399,
		button = function()
			local frame = scroll:FindFirstChild("5")
			return frame and frame:FindFirstChild("1")
		end,
		label = function(button)
			return button and button:FindFirstChild("Price")
		end,
	},
	{
		key = "TripleSpeed",
		entitlementKey = "TripleSpeed",
		passId = GamePassConfig.TripleSpeed,
		price = GamePassConfig.Prices and GamePassConfig.Prices.TripleSpeed or 149,
		button = function()
			local frame = scroll:FindFirstChild("5")
			return frame and frame:FindFirstChild("2")
		end,
		label = function(button)
			return button and button:FindFirstChild("Price")
		end,
	},
}

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

local function priceText(price)
	return ROBUX_ICON .. tostring(math.max(0, math.floor(tonumber(price) or 0)))
end

local function ownsPass(passId)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	return ok and owns == true
end

local function ownsCard(card)
	return player:GetAttribute("GiftPass_" .. tostring(card.entitlementKey or "")) == true or ownsPass(card.passId)
end

local function render(card)
	local button = card.button()
	if not button or not button:IsA("GuiButton") then return end
	local label = card.label(button)
	local owned = ownsCard(card)
	setTextWithChildren(label, owned and "Owned" or priceText(card.price))
	button.Active = not owned
	button.AutoButtonColor = not owned
	button:SetAttribute("GamePassKey", card.key)
	button:SetAttribute("GamePassId", card.passId)
end

for _, card in ipairs(passCards) do
	local button = card.button()
	if button and button:IsA("GuiButton") then
		render(card)
		button.Activated:Connect(function()
			if ownsCard(card) then
				render(card)
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, card.passId)
		end)
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasedPlayer, passId)
	if purchasedPlayer ~= player then return end
	for _, card in ipairs(passCards) do
		if card.passId == passId then
			task.defer(render, card)
			break
		end
	end
end)

for _, card in ipairs(passCards) do
	player:GetAttributeChangedSignal("GiftPass_" .. tostring(card.entitlementKey)):Connect(function()
		render(card)
	end)
end

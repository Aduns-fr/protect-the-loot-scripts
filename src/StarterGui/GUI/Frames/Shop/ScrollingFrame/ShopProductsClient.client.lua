local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local scroll = script.Parent
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shopProductPurchaseRemote = remotes:WaitForChild("ShopProductPurchase")

local DeveloperProductsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DeveloperProductsConfig"))
local UnitsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitsConfig"))
local SwordsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SwordsConfig"))

local ROBUX_ICON = utf8.char(0xE002)

local cards = {
	StarterPack = { FramePath = { "2" } },
	StarterPack2 = { FramePath = { "3" } },
	Bundle1 = { FramePath = { "4", "1" } },
	Bundle2 = { FramePath = { "4", "2" } },
}

local function comma(value)
	value = math.floor(tonumber(value) or 0)
	local text = tostring(value)
	while true do
		local nextText, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = nextText
		if count == 0 then break end
	end
	return text
end

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

local function textObject(parent, path)
	local current = parent
	for segment in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(segment)
	end
	return current
end

local function findPath(parent, path)
	local current = parent
	for _, segment in ipairs(path or {}) do
		current = current and current:FindFirstChild(segment)
	end
	return current
end

local function displayName(config)
	return tostring(config.DisplayName or config.Name or "Reward")
end

local function unitName(unitId)
	local unit = UnitsConfig.Units[unitId]
	return unit and displayName(unit) or tostring(unitId or "Unit")
end

local function weaponName(weaponId)
	local sword = SwordsConfig.Swords[weaponId]
	return sword and displayName(sword) or tostring(weaponId or "Weapon")
end

local function setRewardText(frame, config)
	local cashText = "$" .. comma(config.Cash or 0)
	local unitText = "1x " .. unitName(config.UnitId)
	local weaponText = weaponName(config.WeaponId)

	setTextWithChildren(textObject(frame, "Rewards.Cash1.Amount"), cashText)
	setTextWithChildren(textObject(frame, "Rewards.Item1.Name"), unitText)
	setTextWithChildren(textObject(frame, "Rewards.Item2.Name"), weaponText)
	setTextWithChildren(textObject(frame, "Items.1.Amount"), cashText)
	setTextWithChildren(textObject(frame, "Items.2.Amount"), unitText)
	setTextWithChildren(textObject(frame, "Items.3.Amount"), weaponText)
end

local function bindCard(bundleKey, card)
	local frame = findPath(scroll, card.FramePath)
	local config = DeveloperProductsConfig.Bundles[bundleKey]
	if not frame or not config then return end

	local button = frame:FindFirstChild("Buy", true)
	if not button or not button:IsA("GuiButton") then return end

	setTextWithChildren(button:FindFirstChild("Title"), ROBUX_ICON .. tostring(config.RobuxPrice or 0))
	setRewardText(frame, config)
	button:SetAttribute("DeveloperProductKey", bundleKey)
	button.Activated:Connect(function()
		local ok, success, msg, productId = pcall(function()
			return shopProductPurchaseRemote:InvokeServer(bundleKey)
		end)
		if ok and success and tonumber(productId) and tonumber(productId) > 0 then
			MarketplaceService:PromptProductPurchase(player, tonumber(productId))
		elseif _G.ShowNotif then
			_G.ShowNotif(tostring(ok and msg or success or "Product unavailable"), Color3.fromRGB(255, 35, 35))
		end
	end)
end

for bundleKey, card in pairs(cards) do
	bindCard(bundleKey, card)
end

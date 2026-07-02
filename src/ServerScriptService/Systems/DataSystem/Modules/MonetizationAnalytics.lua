local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashProductsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CashProductsConfig"))

local MonetizationAnalytics = {}

local shopSessions = {}
local clickCooldown = {}
local remoteBound = false

local function fields(category, sku, location)
	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(category or "General"),
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = tostring(sku or "None"),
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = tostring(location or "Unknown"),
	}
end

local function safeLog(callback)
	local ok, err = pcall(callback)
	if not ok then
		warn("[MonetizationAnalytics]", err)
	end
end

local function getShopSession(player)
	local sessionId = shopSessions[player]
	if not sessionId then
		sessionId = HttpService:GenerateGUID(false)
		shopSessions[player] = sessionId
	end
	return sessionId
end

function MonetizationAnalytics.LogShopOpened(player)
	if not player or not player.Parent then return end
	local sessionId = HttpService:GenerateGUID(false)
	shopSessions[player] = sessionId
	safeLog(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			"CashShopCheckout",
			sessionId,
			1,
			"Shop Opened",
			fields("CashPacks", "None", "Shop")
		)
	end)
end

function MonetizationAnalytics.LogCashPackClicked(player, pack)
	if not player or not player.Parent or type(pack) ~= "table" then return end
	local sessionId = getShopSession(player)
	safeLog(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			"CashShopCheckout",
			sessionId,
			2,
			"Cash Pack Clicked",
			fields("CashPacks", pack.Sku, "Shop")
		)
	end)
	safeLog(function()
		AnalyticsService:LogCustomEvent(
			player,
			"CashPackPromptOpened",
			1,
			fields("CashPacks", pack.Sku, "Shop")
		)
	end)
end

function MonetizationAnalytics.LogCashPackPurchased(player, pack, endingBalance)
	if not player or not player.Parent or type(pack) ~= "table" then return end
	local sessionId = getShopSession(player)
	safeLog(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			"CashShopCheckout",
			sessionId,
			3,
			"Purchase Completed",
			fields("CashPacks", pack.Sku, "Receipt")
		)
	end)
	MonetizationAnalytics.LogCashSource(
		player,
		Enum.AnalyticsEconomyTransactionType.IAP.Name,
		pack.Amount,
		endingBalance,
		pack.Sku,
		"CashPacks"
	)
	safeLog(function()
		AnalyticsService:LogCustomEvent(
			player,
			"CashPackPurchased",
			pack.RobuxPrice or 0,
			fields("CashPacks", pack.Sku, "Receipt")
		)
	end)
end

function MonetizationAnalytics.LogProductPrompt(player, category, sku, robuxPrice)
	if not player or not player.Parent then return end
	safeLog(function()
		AnalyticsService:LogCustomEvent(
			player,
			"RobuxPromptOpened",
			math.max(0, math.floor(tonumber(robuxPrice) or 0)),
			fields(category or "Robux", sku or "Unknown", "Prompt")
		)
	end)
end

function MonetizationAnalytics.LogProductGranted(player, category, sku, robuxPrice)
	if not player or not player.Parent then return end
	safeLog(function()
		AnalyticsService:LogCustomEvent(
			player,
			"RobuxProductGranted",
			math.max(0, math.floor(tonumber(robuxPrice) or 0)),
			fields(category or "Robux", sku or "Unknown", "Receipt")
		)
	end)
end

function MonetizationAnalytics.LogGiftSent(sender, recipientUserId, giftKey, robuxPrice)
	if not sender or not sender.Parent then return end
	safeLog(function()
		AnalyticsService:LogCustomEvent(
			sender,
			"GiftSent",
			math.max(0, math.floor(tonumber(robuxPrice) or 0)),
			fields("Gifts", giftKey or "Unknown", "Recipient_" .. tostring(recipientUserId or 0))
		)
	end)
end

function MonetizationAnalytics.LogRaidResult(player, wavesCleared, reason, lootProtected)
	if not player or not player.Parent then return end
	safeLog(function()
		AnalyticsService:LogCustomEvent(
			player,
			"RaidResult",
			math.max(0, math.floor(tonumber(wavesCleared) or 0)),
			fields("Raid", reason or "Ended", "Loot_" .. tostring(math.max(0, math.floor(tonumber(lootProtected) or 0))))
		)
	end)
end

function MonetizationAnalytics.LogCashSource(player, transactionType, amount, endingBalance, itemSku, category)
	amount = math.floor(tonumber(amount) or 0)
	endingBalance = math.max(0, math.floor(tonumber(endingBalance) or 0))
	if not player or not player.Parent or amount <= 0 then return end
	safeLog(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			CashProductsConfig.CurrencyName,
			amount,
			endingBalance,
			tostring(transactionType or Enum.AnalyticsEconomyTransactionType.Gameplay.Name),
			tostring(itemSku or "CashSource"),
			fields(category or "CashSource", itemSku or "CashSource", "Server")
		)
	end)
end

function MonetizationAnalytics.LogCashSink(player, transactionType, amount, endingBalance, itemSku, category)
	amount = math.floor(tonumber(amount) or 0)
	endingBalance = math.max(0, math.floor(tonumber(endingBalance) or 0))
	if not player or not player.Parent or amount <= 0 then return end
	safeLog(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			CashProductsConfig.CurrencyName,
			amount,
			endingBalance,
			tostring(transactionType or Enum.AnalyticsEconomyTransactionType.Shop.Name),
			tostring(itemSku or "CashSink"),
			fields(category or "CashSink", itemSku or "CashSink", "Server")
		)
	end)
end

function MonetizationAnalytics.LogOnboardingStep(player, step, stepName)
	if not player or not player.Parent then return end
	safeLog(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, fields("Onboarding", stepName, "Server"))
	end)
end

function MonetizationAnalytics.LogRaidStep(player, step, stepName, sessionId)
	if not player or not player.Parent then return end
	sessionId = sessionId or HttpService:GenerateGUID(false)
	safeLog(function()
		AnalyticsService:LogFunnelStepEvent(player, "RaidLoop", sessionId, step, stepName, fields("Raid", stepName, "Server"))
	end)
	return sessionId
end

function MonetizationAnalytics.Start(remotes)
	if remoteBound then return end
	remoteBound = true
	local remote = remotes:FindFirstChild("MonetizationAnalytics")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "MonetizationAnalytics"
		remote.Parent = remotes
	end
	remote.OnServerEvent:Connect(function(player, action, payload)
		if typeof(action) ~= "string" then return end
		local now = os.clock()
		clickCooldown[player] = clickCooldown[player] or 0
		if now - clickCooldown[player] < 0.25 then return end
		clickCooldown[player] = now
		if action == "ShopOpened" then
			MonetizationAnalytics.LogShopOpened(player)
		elseif action == "CashPackClicked" and type(payload) == "table" then
			local pack = CashProductsConfig.GetBySku(payload.sku)
			if pack then
				MonetizationAnalytics.LogCashPackClicked(player, pack)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		shopSessions[player] = nil
		clickCooldown[player] = nil
	end)
end

return MonetizationAnalytics

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePassConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GamePassConfig"))

local GamePassService = {}

local owned = {} -- [player] = { [passId] = true }

local function entitlementKey(passId)
    if passId == GamePassConfig.VIP then return "VIP" end
    if passId == GamePassConfig.DoubleCash then return "DoubleCash" end
    if passId == GamePassConfig.TripleSpeed then return "TripleSpeed" end
    return nil
end

local function hasGiftEntitlement(player, passId)
    local key = entitlementKey(passId)
    return key ~= nil and player:GetAttribute("GiftPass_" .. key) == true
end

local function checkOwnership(player, passId)
    if hasGiftEntitlement(player, passId) then
        return true
    end
    local ok, result = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
    end)
    return ok and result or false
end

local function applyWalkSpeed(player, character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local playerOwned = owned[player]
    local hasSpeed = (playerOwned and playerOwned[GamePassConfig.TripleSpeed]) or hasGiftEntitlement(player, GamePassConfig.TripleSpeed)
    humanoid.WalkSpeed = hasSpeed and (GamePassConfig.BaseWalkSpeed * GamePassConfig.TripleSpeedMultiplier) or GamePassConfig.BaseWalkSpeed
end

local function loadOwnership(player)
    local playerOwned = {}
    for _, passId in ipairs({ GamePassConfig.VIP, GamePassConfig.TripleSpeed, GamePassConfig.DoubleCash }) do
        playerOwned[passId] = checkOwnership(player, passId)
    end
    owned[player] = playerOwned
    player:SetAttribute("VIP", playerOwned[GamePassConfig.VIP] or false)
    if player.Character then applyWalkSpeed(player, player.Character) end
end

function GamePassService.HasPass(player, passId)
    if hasGiftEntitlement(player, passId) then
        return true
    end
    local playerOwned = owned[player]
    if not playerOwned then
        playerOwned = {}
        owned[player] = playerOwned
    end
    if playerOwned[passId] == nil or playerOwned[passId] == false then
        playerOwned[passId] = checkOwnership(player, passId)
    end
    return playerOwned[passId] == true
end

-- multiplier applied to gameplay-earned cash (wave/raid rewards); does not affect IAP cash packs or admin grants
function GamePassService.GetCashMultiplier(player)
    local multiplier = 1
    if GamePassService.HasPass(player, GamePassConfig.DoubleCash) then multiplier = GamePassConfig.DoubleCashMultiplier end
    if GamePassService.HasPass(player, GamePassConfig.VIP) then multiplier += GamePassConfig.VIPCashBonus end
    multiplier += tonumber(player:GetAttribute("GroupCashBoost")) or 0
    multiplier += tonumber(player:GetAttribute("PremiumCashBoost")) or 0
    return multiplier
end

function GamePassService.Start()
    Players.PlayerAdded:Connect(function(player)
        task.spawn(loadOwnership, player)
        player.CharacterAdded:Connect(function(character) applyWalkSpeed(player, character) end)
    end)
    Players.PlayerRemoving:Connect(function(player) owned[player] = nil end)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(loadOwnership, player)
        player.CharacterAdded:Connect(function(character) applyWalkSpeed(player, character) end)
    end

    local function hookEntitlements(player)
        for _, key in ipairs({ "VIP", "DoubleCash", "TripleSpeed" }) do
            player:GetAttributeChangedSignal("GiftPass_" .. key):Connect(function()
                local playerOwned = owned[player]
                if playerOwned then
                    playerOwned[GamePassConfig[key]] = player:GetAttribute("GiftPass_" .. key) == true or playerOwned[GamePassConfig[key]]
                end
                if key == "VIP" and player:GetAttribute("GiftPass_VIP") == true then
                    player:SetAttribute("VIP", true)
                end
                if key == "TripleSpeed" and player.Character then
                    applyWalkSpeed(player, player.Character)
                end
            end)
        end
    end
    Players.PlayerAdded:Connect(hookEntitlements)
    for _, player in ipairs(Players:GetPlayers()) do hookEntitlements(player) end

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
        if not purchased then return end
        local playerOwned = owned[player]
        if not playerOwned then return end
        playerOwned[passId] = true
        if passId == GamePassConfig.VIP then player:SetAttribute("VIP", true) end
        if passId == GamePassConfig.TripleSpeed and player.Character then applyWalkSpeed(player, player.Character) end
    end)
end

return GamePassService

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local PlayerDataService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("DataSystem"):WaitForChild("Modules"):WaitForChild("PlayerDataService"))

local COMMAND = "!cash"
local MAX_CASH_GRANT = 1000000000

local function getOwnerGroupId()
    if game.CreatorType == Enum.CreatorType.Group then
        return game.CreatorId
    end
    return nil
end

local function hasHighestRank(player)
    local groupId = getOwnerGroupId()
    if groupId then
        local ok, rank = pcall(function()
            return player:GetRankInGroup(groupId)
        end)
        return ok and rank >= 255
    end

    return RunService:IsStudio() and player.UserId == game.CreatorId
end

local function parseCashCommand(message)
    local amountText = string.match(message, "^%s*!cash%s+([%d,]+)%s*$")
    if not amountText then return nil end
    amountText = amountText:gsub(",", "")
    local amount = tonumber(amountText)
    if not amount then return nil end
    return math.clamp(math.floor(amount), 0, MAX_CASH_GRANT)
end

local function onChatted(player, message)
    local amount = parseCashCommand(message)
    if not amount then return end
    if not hasHighestRank(player) then return end
    PlayerDataService.AddCash(player, amount)
end

Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(message)
        onChatted(player, message)
    end)
end)

for _, player in ipairs(Players:GetPlayers()) do
    player.Chatted:Connect(function(message)
        onChatted(player, message)
    end)
end

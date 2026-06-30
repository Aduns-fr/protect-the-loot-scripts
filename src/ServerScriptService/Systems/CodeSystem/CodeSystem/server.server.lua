local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CodesConfig = require(ReplicatedStorage.Configs.CodesConfig)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local remote = ReplicatedStorage.Remotes.RedeemCode
remote.OnServerInvoke = function(player, rawCode)
    local code = string.upper(tostring(rawCode or ""):gsub("%s+", ""))
    if code == "" then return false, "Invalid" end
    local reward = CodesConfig.Codes[code]
    if not reward then return false, "Invalid" end
    if reward.ExpiresAt and os.time() > reward.ExpiresAt then return false, "Timed-out" end
    if PlayerDataService.HasRedeemedCode(player, code) then return false, "Redeemed" end
    PlayerDataService.MarkRedeemedCode(player, code)
    if reward.Cash then PlayerDataService.AddCash(player, reward.Cash) end
    return true, "Redeemed"
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local remote = ReplicatedStorage.Remotes.BaseUpgrade
local LEVELS = {
    [1] = { Health = 500, UpgradeCost = 350 }, [2] = { Health = 800, UpgradeCost = 900 }, [3] = { Health = 1250, UpgradeCost = 1800 },
    [4] = { Health = 1850, UpgradeCost = 3600 }, [5] = { Health = 2700, UpgradeCost = 7000 }, [6] = { Health = 3800, UpgradeCost = 12500 }, [7] = { Health = 5200 },
}
task.wait(1)
remote.OnServerInvoke = function(player)
    if player:GetAttribute("RaidActive") == true then return false, "Cannot upgrade during a raid" end
    local data = PlayerDataService.GetData(player)
    if not data then return false, "Data not ready" end
    local currentLevel = math.clamp(math.floor(tonumber(player:GetAttribute("BaseLevel")) or tonumber(data.BaseLevel) or 1), 1, 7)
    if currentLevel >= 7 then return false, "Max level" end
    local price = LEVELS[currentLevel].UpgradeCost
    local leaderstats = player:FindFirstChild("leaderstats")
    local cash = leaderstats and leaderstats:FindFirstChild("Cash")
    if not cash or cash.Value < price then return false, "Not enough cash" end
    cash.Value -= price
    data.Cash = cash.Value
    data.BaseLevel = currentLevel + 1
    player:SetAttribute("BaseLevel", data.BaseLevel)
    ReplicatedStorage.Remotes.BaseDataUpdate:FireClient(player, { level = data.BaseLevel })
    return true, "Upgraded", data.BaseLevel
end

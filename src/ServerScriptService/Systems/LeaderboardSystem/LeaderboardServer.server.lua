local ServerScriptService = game:GetService("ServerScriptService")
local LeaderboardManager  = require(script.Parent.LeaderboardManager)
local PlayerDataService   = require(
    ServerScriptService:FindFirstChild("Systems", true)
    :FindFirstChild("DataSystem"):FindFirstChild("Modules"):FindFirstChild("PlayerDataService")
)
LeaderboardManager.init(PlayerDataService)

local BaseUpgradesConfig = {}

BaseUpgradesConfig.Base = {
    StartingHealth = 500,
}

BaseUpgradesConfig.Levels = {
    [1] = { Health = 500, UpgradeCost = 350 },
    [2] = { Health = 800, UpgradeCost = 900 },
    [3] = { Health = 1250, UpgradeCost = 1800 },
    [4] = { Health = 1850, UpgradeCost = 3600 },
    [5] = { Health = 2700, UpgradeCost = 7000 },
    [6] = { Health = 3800, UpgradeCost = 12500 },
    [7] = { Health = 5200 },
}

function BaseUpgradesConfig.GetLevel(level)
    level = math.clamp(math.floor(tonumber(level) or 1), 1, 7)
    return BaseUpgradesConfig.Levels[level] or BaseUpgradesConfig.Levels[1]
end

BaseUpgradesConfig.RaidSpeed = {
    FreeSpeeds = { 1, 2 },
    PaidSpeed = 3,
    Speed3ProductId = 0, -- Set this to the developer product id before enabling paid x3 speed.
}

return BaseUpgradesConfig

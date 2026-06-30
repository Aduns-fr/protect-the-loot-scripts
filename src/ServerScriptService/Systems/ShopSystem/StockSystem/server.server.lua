local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UnitsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitsConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stockRemote = remotes:WaitForChild("UnitStockUpdate")
local notifRemote  = remotes:WaitForChild("Notif")
local stock = {}
local nextReset = 0
local function weightedAppears(cfg, rng)
    local weight = UnitsConfig.RarityWeights[cfg.Rarity or "Common"] or 50
    return rng:NextNumber(0,100) <= weight
end
local function refresh()
    local bucket = math.floor(os.time() / UnitsConfig.StockResetSeconds)
    local rng = Random.new(bucket)
    nextReset = (bucket + 1) * UnitsConfig.StockResetSeconds
    stock = {}
    for _,unitId in ipairs(UnitsConfig.Order) do
        local cfg=UnitsConfig.Units[unitId]
        if cfg and weightedAppears(cfg, rng) then
            local min=math.max(0, math.floor(cfg.StockMin or 1)); local max=math.max(min, math.floor(cfg.StockMax or min))
            stock[unitId]=rng:NextInteger(min,max)
        else
            stock[unitId]=0
        end
    end
end
local function payload() return { stock=stock, nextReset=nextReset, resetSeconds=UnitsConfig.StockResetSeconds } end
local function broadcast() stockRemote:FireAllClients(payload()) end
_G.MyEvilLairStock = {
    Get = function() return stock, nextReset end,
    TryTake = function(unitId)
        if (stock[unitId] or 0) <= 0 then return false end
        stock[unitId] -= 1
        broadcast()
        return true
    end,
}
refresh(); broadcast()
Players.PlayerAdded:Connect(function(player) task.defer(function() stockRemote:FireClient(player, payload()) end) end)
task.spawn(function()
    while true do
        if os.time() >= nextReset then refresh(); broadcast(); notifRemote:FireAllClients("Stock has refreshed!", 255, 255, 255) end
        task.wait(1)
    end
end)

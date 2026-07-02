local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UnitsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitsConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stockRemote = remotes:WaitForChild("UnitStockUpdate")
local notifRemote  = remotes:WaitForChild("Notif")
local stock = {}
local nextReset = 0
local forceSerial = 0
local broadcast
local function weightedAppears(cfg, rng)
    local weight = UnitsConfig.RarityWeights[cfg.Rarity or "Common"] or 50
    return rng:NextNumber(0,100) <= weight
end
local function refresh(seedOverride, resetFromNow)
    local bucket = math.floor(os.time() / UnitsConfig.StockResetSeconds)
    local rng = Random.new(seedOverride or bucket)
    nextReset = resetFromNow and (os.time() + UnitsConfig.StockResetSeconds) or ((bucket + 1) * UnitsConfig.StockResetSeconds)
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
local function forceRefresh()
    forceSerial += 1
    refresh(os.time() + forceSerial * 10007, true)
    broadcast()
end
local function payload() return { stock=stock, nextReset=nextReset, resetSeconds=UnitsConfig.StockResetSeconds } end
broadcast = function() stockRemote:FireAllClients(payload()) end
_G.MyEvilLairStock = {
    Get = function() return stock, nextReset end,
    TryTake = function(unitId)
        if (stock[unitId] or 0) <= 0 then return false end
        stock[unitId] -= 1
        broadcast()
        return true
    end,
    ForceRefresh = forceRefresh,
    Return = function(unitId)
        if not UnitsConfig.Units[unitId] then return false end
        stock[unitId] = (stock[unitId] or 0) + 1
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

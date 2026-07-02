local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")

local UnitsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitsConfig"))
local BaseUpgradesConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("BaseUpgradesConfig"))
local CashProductsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CashProductsConfig"))
local CratesConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CratesConfig"))
local DeveloperProductsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DeveloperProductsConfig"))
local DailyRewardsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DailyRewardsConfig"))
local GamePassConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GamePassConfig"))
local SwordsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SwordsConfig"))
local CrateGrantAPI = require(ServerScriptService.Systems.ShopSystem.CrateSystem.CrateGrantAPI)
local MonetizationAnalytics = require(script.Parent:WaitForChild("MonetizationAnalytics"))
local BadgeProgressService = require(script.Parent:WaitForChild("BadgeProgressService"))
local MAX_BASE_LEVEL = 7
local GROUP_CASH_BONUS = 50000
local GROUP_CASH_BOOST = 0.15
local PREMIUM_CASH_BOOST = 0.1
local LEGACY_UNIT_ALIASES = {
    ScrapTurret="BlockTower", SlimeSprayer="RapidBlock", BoneLauncher="HeavyBlock", ZapCoil="RangeBlock", GooCannon="SplashBlock",
    SpikeThrower="PulseBlock", LaserEye="SniperBlock", MiniMech="BeamBlock", DoomSpeaker="FrostBlock", AcidBarrel="GoldBlock",
    MeteorMortar="MegaBlock", ShadowOrb="OrbitBlock", FreezeRay="ChainBlock", SawDrone="SpikeBlock", VolcanoVent="NovaBlock",
    VoidPylon="VoidBlock", GoldGatling="HyperBlock", MoonLaser="LunarBlock", RealityRipper="PrismBlock", DoomCore="CoreBlock",
}
local function getBaseLevelConfig(level)
    if BaseUpgradesConfig.GetLevel then return BaseUpgradesConfig.GetLevel(level) end
    local levels = BaseUpgradesConfig.Levels or { [1] = { Health = BaseUpgradesConfig.Base and BaseUpgradesConfig.Base.StartingHealth or 500 } }
    level = math.clamp(tonumber(level) or 1, 1, MAX_BASE_LEVEL)
    return levels[level] or levels[1]
end

local PlayerDataService = {}

local DATASTORE_NAME = "MyEvilLair_PlayerData_v1"

-- per-map fields that are completely separate per map
-- shared fields (Weapons, Swords, RedeemedCodes) live at the top level
local MAP_DEFAULTS = {
    Cash = 500,
    HighestWave = 0,
    RaidCheckpoint = 0,
    BaseLevel = 1,
    Units = {},
    Crates = {},
    PlacedUnits = {},
}

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local giftInboxStore = DataStoreService:GetDataStore("MyEvilLair_GiftInbox_v1")
local giftIntentStore = DataStoreService:GetDataStore("MyEvilLair_GiftIntents_v1")
local sessionData = {}      -- full raw data per player
local activeMap = {}        -- current mapId per player (integer)
local joinTime = {}         -- os.time() when player joined, for TimePlayed tracking
local pendingRobuxPurchases = {} -- [userId] = { [productId] = { Kind = "Unit"|"Crate", ItemId = string } }
local pendingGiftPurchases = {} -- [userId] = { [productId] = { GiftKey, RecipientUserId, RecipientName, ExpiresAt } }

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function getOrCreateRemoteFunction(name)
    local remote = remotes:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = name
        remote.Parent = remotes
    end
    return remote
end
local boostRemote = remotes:WaitForChild("FriendBoostUpdate")
local unitPurchaseRemote = remotes:WaitForChild("UnitPurchase")
local stockRefreshPurchaseRemote = getOrCreateRemoteFunction("StockRefreshPurchase")
local shopProductPurchaseRemote = getOrCreateRemoteFunction("ShopProductPurchase")
local raidRevivePurchaseRemote = getOrCreateRemoteFunction("RaidRevivePurchase")
local giftPurchaseRemote = getOrCreateRemoteFunction("GiftPurchase")
local dailyRewardRemote = getOrCreateRemoteFunction("DailyReward")
local dailyRewardUpdateRemote = remotes:FindFirstChild("DailyRewardUpdate")
if not dailyRewardUpdateRemote then
    dailyRewardUpdateRemote = Instance.new("RemoteEvent")
    dailyRewardUpdateRemote.Name = "DailyRewardUpdate"
    dailyRewardUpdateRemote.Parent = remotes
end
local inventoryRemote = remotes:WaitForChild("UnitInventoryUpdate")
local baseUpgradeRemote = remotes:WaitForChild("BaseUpgrade")
local baseDataRemote = remotes:WaitForChild("BaseDataUpdate")
local mapDataSyncRemote = remotes:WaitForChild("MapDataSync")
local cashPopupRemote = remotes:WaitForChild("CashPopup")
local notifRemote = remotes:WaitForChild("Notif")

local function deepCopyUnits(units)
    local copy = {}
    if type(units) == "table" then
        for unitId, amount in pairs(units) do
            if type(unitId) == "string" then copy[unitId] = math.max(0, math.floor(tonumber(amount) or 0)) end
        end
    end
    return copy
end

local function createValue(className, name, value, parent)
    local object = Instance.new(className)
    object.Name = name
    object.Value = value
    object.Parent = parent
    return object
end

local function normalizeMapData(d)
    d = type(d) == "table" and d or {}
    d.Cash = math.max(0, math.floor(tonumber(d.Cash) or MAP_DEFAULTS.Cash))
    d.HighestWave = math.max(0, math.floor(tonumber(d.HighestWave) or 0))
    local cp = d.RaidCheckpoint
    if cp == nil then cp = math.floor(d.HighestWave / 5) * 5 end
    d.RaidCheckpoint = math.clamp(math.floor(tonumber(cp) or 0), 0, 100)
    d.RaidCheckpoint = d.RaidCheckpoint - d.RaidCheckpoint % 5
    d.BaseLevel = math.clamp(math.floor(tonumber(d.BaseLevel) or 1), 1, MAX_BASE_LEVEL)
    d.Units = deepCopyUnits(d.Units)
    for oldId, newId in pairs(LEGACY_UNIT_ALIASES) do
        local amount = tonumber(d.Units[oldId]) or 0
        if amount > 0 then
            d.Units[newId] = (tonumber(d.Units[newId]) or 0) + amount
            d.Units[oldId] = nil
        end
    end
    d.Crates = type(d.Crates) == "table" and d.Crates or {}
    d.PlacedUnits = type(d.PlacedUnits) == "table" and d.PlacedUnits or {}
    for _, placed in ipairs(d.PlacedUnits) do
        if type(placed) == "table" and LEGACY_UNIT_ALIASES[placed.UnitId] then
            placed.UnitId = LEGACY_UNIT_ALIASES[placed.UnitId]
        end
    end
    return d
end

local function normalizeData(data)
    data = type(data) == "table" and data or {}

    -- migrate old flat data into map 1 slot if not already done
    if not data.Maps then
        data.Maps = {}
        -- promote old top-level fields into map 1
        data.Maps[1] = normalizeMapData({
            Cash = data.Cash,
            HighestWave = data.HighestWave or data.MaxLevel,
            RaidCheckpoint = data.RaidCheckpoint,
            BaseLevel = data.BaseLevel,
            Units = data.Units,
            Crates = data.Crates,
            PlacedUnits = data.PlacedUnits,
        })
        data.Maps[2] = normalizeMapData({})
    else
        for mapId = 1, 2 do
            data.Maps[mapId] = normalizeMapData(data.Maps[mapId] or {})
        end
    end

    -- shared across all maps
    data.Swords = type(data.Swords) == "table" and data.Swords or {}
    data.Weapons = type(data.Weapons) == "table" and data.Weapons or {}
    for weaponId, amount in pairs(data.Swords) do
        data.Weapons[weaponId] = math.max(tonumber(data.Weapons[weaponId]) or 0, tonumber(amount) or 0)
    end
    data.RedeemedCodes = type(data.RedeemedCodes) == "table" and data.RedeemedCodes or {}
    data.GamePassEntitlements = type(data.GamePassEntitlements) == "table" and data.GamePassEntitlements or {}
    data.DailyRewards = type(data.DailyRewards) == "table" and data.DailyRewards or {}
    data.DailyRewards.Streak = math.max(1, math.floor(tonumber(data.DailyRewards.Streak) or 1))
    data.DailyRewards.NextClaimAt = math.max(0, math.floor(tonumber(data.DailyRewards.NextClaimAt) or 0))
    data.DailyRewards.LastClaimAt = math.max(0, math.floor(tonumber(data.DailyRewards.LastClaimAt) or 0))
    data.GroupBonusClaimed = data.GroupBonusClaimed == true
    data.ActiveMap = math.clamp(math.floor(tonumber(data.ActiveMap) or 1), 1, 2)
    data.TimePlayed = math.max(0, math.floor(tonumber(data.TimePlayed) or 0))

    return data
end

-- returns the active map's data table
local function mapData(player)
    local data = sessionData[player]
    if not data then return nil end
    local mid = activeMap[player] or 1
    return data.Maps[mid]
end

local function loadData(player)
    local ok, result = pcall(function()
        return store:GetAsync(tostring(player.UserId))
    end)
    if ok then return normalizeData(result) end
    warn("[PlayerDataService] Load failed for", player.Name, result)
    return normalizeData(nil)
end

local function getLeaderValue(player, name)
    local leaderstats = player:FindFirstChild("leaderstats")
    return leaderstats and leaderstats:FindFirstChild(name) or nil
end

-- sync leaderstats back into the active map's data before saving
local function syncLeaderstats(player)
    local data = sessionData[player]
    if not data then return end
    local md = mapData(player)
    if not md then return end
    local cash = getLeaderValue(player, "Cash")
    local maxLevel = getLeaderValue(player, "Highest Wave")
    if cash then md.Cash = cash.Value end
    if maxLevel then md.HighestWave = maxLevel.Value end
    -- accumulate time played from this session
    if joinTime[player] then
        local elapsed = os.time() - joinTime[player]
        data.TimePlayed = (data.TimePlayed or 0) + elapsed
        joinTime[player] = os.time() -- reset so repeated saves don't double-count
    end
end

local function saveData(player)
    local data = sessionData[player]
    if not data then return end
    syncLeaderstats(player)
    data.ActiveMap = activeMap[player] or 1
    pcall(function()
        store:SetAsync(tostring(player.UserId), data)
    end)
end

local function calculateFriendBoost(player)
    local friends = 0
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local ok, isFriend = pcall(function()
                return player:IsFriendsWith(other.UserId)
            end)
            if ok and isFriend then friends += 1 end
        end
    end
    return math.clamp(friends * 10, 0, 100)
end

local function updateFriendBoosts()
    for _, player in ipairs(Players:GetPlayers()) do
        boostRemote:FireClient(player, calculateFriendBoost(player))
    end
end

local function ownerGroupId()
    if game.CreatorType == Enum.CreatorType.Group then
        return game.CreatorId
    end
    return nil
end

local function updateMembershipBoost(player)
    local data = sessionData[player]
    local groupId = ownerGroupId()
    local inGroup = false
    if groupId then
        local ok, result = pcall(function()
            return player:IsInGroup(groupId)
        end)
        inGroup = ok and result == true
    end

    player:SetAttribute("GroupCashBoost", inGroup and GROUP_CASH_BOOST or 0)
    local premium = player.MembershipType == Enum.MembershipType.Premium
    player:SetAttribute("PremiumCashBoost", premium and PREMIUM_CASH_BOOST or 0)

    if data and inGroup and not data.GroupBonusClaimed then
        data.GroupBonusClaimed = true
        local ok, endingBalance = PlayerDataService.AddCash(player, GROUP_CASH_BONUS)
        if ok then
            cashPopupRemote:FireClient(player, GROUP_CASH_BONUS)
            MonetizationAnalytics.LogCashSource(player, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, GROUP_CASH_BONUS, endingBalance, "GroupJoinBonus", "Membership")
            task.spawn(saveData, player)
        end
    end
end

local function applyGiftEntitlementAttributes(player)
    local data = sessionData[player]
    local entitlements = data and data.GamePassEntitlements or {}
    for _, key in ipairs({ "VIP", "DoubleCash", "TripleSpeed" }) do
        player:SetAttribute("GiftPass_" .. key, entitlements[key] == true)
    end
    if entitlements.VIP == true then
        player:SetAttribute("VIP", true)
    end
end

local function giftIntentKey(senderUserId, productId)
    return tostring(senderUserId) .. ":" .. tostring(productId)
end

local function playerOwnsGamePassReward(player, rewardKey)
    local data = sessionData[player]
    if data and data.GamePassEntitlements and data.GamePassEntitlements[rewardKey] == true then
        return true
    end
    local passId = tonumber(GamePassConfig[rewardKey]) or 0
    if passId <= 0 then return false end
    local ok, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
    end)
    return ok and owns == true
end

local function playerAlreadyOwnsGiftReward(player, config)
    if not player or not player.Parent or type(config) ~= "table" then return false end
    if config.RewardType == "GamePass" then
        return playerOwnsGamePassReward(player, tostring(config.RewardKey or ""))
    end
    return false
end

local function startMembershipWatcher(player)
    task.spawn(function()
        while player.Parent and sessionData[player] do
            updateMembershipBoost(player)
            task.wait(15)
        end
    end)
end

local function sendInventory(player)
    local md = mapData(player)
    if md then inventoryRemote:FireClient(player, md.Units) end
end

local function sendBase(player)
    local md = mapData(player)
    if not md then return end
    local levelConfig = getBaseLevelConfig(md.BaseLevel)
    baseDataRemote:FireClient(player, { level = md.BaseLevel, maxLoot = levelConfig.Health, health = levelConfig.Health })
    player:SetAttribute("BaseLevel", md.BaseLevel)
    player:SetAttribute("BaseMaxLoot", levelConfig.Health)
    player:SetAttribute("RaidCheckpoint", md.RaidCheckpoint)
    player:SetAttribute("RaidActive", false)
end

-- sync leaderstats to the active map and update displays
local function applyMapData(player)
    local data = sessionData[player]
    local md = mapData(player)
    if not data or not md then return end

    -- update cash leaderstat
    local cash = getLeaderValue(player, "Cash")
    local hw = getLeaderValue(player, "Highest Wave")
    if cash then cash.Value = md.Cash end
    if hw then hw.Value = md.HighestWave end

    sendInventory(player)
    sendBase(player)

    -- send all map wave data to client so the UI can show correct waves
    local allWaves = {}
    for mapId = 1, 2 do
        allWaves[mapId] = (data.Maps[mapId] or {}).HighestWave or 0
    end
    mapDataSyncRemote:FireClient(player, {
        activeMap = activeMap[player] or 1,
        mapWaves = allWaves,
    })
end

-- public API --

function PlayerDataService.GetData(player)
    return sessionData[player]
end

function PlayerDataService.GetActiveMap(player)
    return activeMap[player] or 1
end

function PlayerDataService.GetRaidCheckpoint(player)
    local md = mapData(player)
    return md and (tonumber(md.RaidCheckpoint) or 0) or 0
end

function PlayerDataService.SetRaidCheckpoint(player, wave)
    local md = mapData(player)
    if not md then return false end
    wave = math.clamp(math.floor(tonumber(wave) or 0), 0, 100)
    wave = wave - wave % 5
    if wave <= (tonumber(md.RaidCheckpoint) or 0) then return false end
    md.RaidCheckpoint = wave
    player:SetAttribute("RaidCheckpoint", wave)
    task.spawn(saveData, player)
    return true
end

function PlayerDataService.GetBaseLevel(player)
    local md = mapData(player)
    return md and md.BaseLevel or 1
end

function PlayerDataService.GetBaseMaxHealth(player)
    local level = PlayerDataService.GetBaseLevel(player)
    return getBaseLevelConfig(level).Health
end

function PlayerDataService.AddCash(player, amount)
    local md = mapData(player)
    local cash = getLeaderValue(player, "Cash")
    amount = math.floor(tonumber(amount) or 0)
    if not md or not cash or amount == 0 then return false end
    cash.Value = math.max(0, cash.Value + amount)
    md.Cash = cash.Value
    return true, cash.Value
end

function PlayerDataService.RemoveUnit(player, unitId, amount)
    local md = mapData(player)
    if not md or not UnitsConfig.Units[unitId] then return false end
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if (md.Units[unitId] or 0) < amount then return false end
    md.Units[unitId] -= amount
    if md.Units[unitId] <= 0 then md.Units[unitId] = nil end
    sendInventory(player)
    return true
end

function PlayerDataService.GetUnitCount(player, unitId)
    local md = mapData(player)
    return md and (md.Units[unitId] or 0) or 0
end

function PlayerDataService.AddUnit(player, unitId, amount)
    local md = mapData(player)
    if not md or not UnitsConfig.Units[unitId] then return false end
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    md.Units[unitId] = (md.Units[unitId] or 0) + amount
    sendInventory(player)
    return true
end

function PlayerDataService.GetPlacedUnits(player)
    local md = mapData(player)
    return md and md.PlacedUnits or {}
end

function PlayerDataService.SetPlacedUnits(player, placedUnits)
    local md = mapData(player)
    if not md then return false end
    md.PlacedUnits = type(placedUnits) == "table" and placedUnits or {}
    return true
end

function PlayerDataService.HasRedeemedCode(player, code)
    local data = sessionData[player]
    return data and data.RedeemedCodes and data.RedeemedCodes[code] == true
end

function PlayerDataService.MarkRedeemedCode(player, code)
    local data = sessionData[player]
    if not data then return false end
    data.RedeemedCodes = data.RedeemedCodes or {}
    data.RedeemedCodes[code] = true
    return true
end

function PlayerDataService.SaveNow(player)
    if not sessionData[player] then return false end
    saveData(player)
    return true
end

function PlayerDataService.GetCrates(player)
    local md = mapData(player)
    return md and md.Crates or {}
end

function PlayerDataService.SetCrates(player, crates, saveImmediately)
    local md = mapData(player)
    if not md then return false end
    md.Crates = type(crates) == "table" and crates or {}
    if saveImmediately then task.spawn(saveData, player) end
    return true
end

function PlayerDataService.AddWeapon(player, weaponId)
    local data = sessionData[player]
    if not data or type(weaponId) ~= "string" then return false, false end
    data.Weapons = data.Weapons or {}
    data.Swords = data.Swords or {}
    local wasNew = (tonumber(data.Weapons[weaponId]) or 0) <= 0
    data.Weapons[weaponId] = (tonumber(data.Weapons[weaponId]) or 0) + 1
    data.Swords[weaponId] = (tonumber(data.Swords[weaponId]) or 0) + 1
    BadgeProgressService.Award(player, "ChestCracker")
    return true, wasNew
end

local function hasAnySpecialWeapon(data)
    for weaponId, amount in pairs(data.Weapons or {}) do
        if weaponId ~= SwordsConfig.DefaultSword and (tonumber(amount) or 0) > 0 then
            return true
        end
    end
    for weaponId, amount in pairs(data.Swords or {}) do
        if weaponId ~= SwordsConfig.DefaultSword and (tonumber(amount) or 0) > 0 then
            return true
        end
    end
    return false
end

local function awardEarnedBadges(player)
    local data = sessionData[player]
    if not data then return end
    BadgeProgressService.Award(player, "FirstSail")
    local highestWave = 0
    local hasPlacedUnit = false
    for _, md in pairs(data.Maps or {}) do
        highestWave = math.max(highestWave, tonumber(md.HighestWave) or 0, tonumber(md.RaidCheckpoint) or 0)
        if type(md.PlacedUnits) == "table" and #md.PlacedUnits > 0 then
            hasPlacedUnit = true
        end
    end
    if highestWave > 0 then BadgeProgressService.Award(player, "RaidCaller") end
    if highestWave >= 5 then BadgeProgressService.Award(player, "TreasureGuard") end
    if hasPlacedUnit then BadgeProgressService.Award(player, "MasterBuilder") end
    if hasAnySpecialWeapon(data) then BadgeProgressService.Award(player, "ChestCracker") end
end

local processQueuedGifts
local sendDailyState

-- saves current map data and switches active map, reloads leaderstats etc.
function PlayerDataService.SwitchMap(player, targetMapId)
    local data = sessionData[player]
    if not data then return false, "Data not ready" end
    if player:GetAttribute("RaidActive") == true then return false, "Stop your raid first" end
    targetMapId = math.clamp(math.floor(tonumber(targetMapId) or 1), 1, 2)
    if (activeMap[player] or 1) == targetMapId then return false, "Already on that map" end

    -- flush current leaderstats into current map slot before switching
    syncLeaderstats(player)

    -- switch
    activeMap[player] = targetMapId
    data.ActiveMap = targetMapId

    -- apply the new map's data to leaderstats + UI
    applyMapData(player)
    task.spawn(saveData, player)
    return true
end

function PlayerDataService.GetTimePlayed(player)
    local data = sessionData[player]
    if not data then return 0 end
    local base = data.TimePlayed or 0
    local live = joinTime[player] and (os.time() - joinTime[player]) or 0
    return base + live
end

function PlayerDataService.GetMapHighestWaves(player)
    local data = sessionData[player]
    if not data then return {} end
    local out = {}
    for mapId = 1, 2 do
        out[mapId] = (data.Maps[mapId] or {}).HighestWave or 0
    end
    return out
end

function PlayerDataService.SetupPlayer(player)
    local data = loadData(player)
    sessionData[player] = data
    activeMap[player] = data.ActiveMap or 1
    joinTime[player] = os.time()

    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local md = data.Maps[activeMap[player]] or data.Maps[1]
    createValue("IntValue", "Cash", md.Cash, leaderstats)
    createValue("IntValue", "Highest Wave", md.HighestWave, leaderstats)
    player:SetAttribute("BaseLevel", md.BaseLevel)
    player:SetAttribute("RaidActive", false)
    applyGiftEntitlementAttributes(player)

    task.defer(updateFriendBoosts)
    task.defer(startMembershipWatcher, player)
    task.defer(MonetizationAnalytics.LogOnboardingStep, player, 1, "Joined Game")
    task.defer(awardEarnedBadges, player)
    task.defer(sendInventory, player)
    task.defer(sendBase, player)
    task.defer(sendDailyState, player)
    task.defer(processQueuedGifts, player)
    task.defer(function()
        local allWaves = {}
        for mapId = 1, 2 do
            allWaves[mapId] = (data.Maps[mapId] or {}).HighestWave or 0
        end
        mapDataSyncRemote:FireClient(player, {
            activeMap = activeMap[player],
            mapWaves = allWaves,
        })
    end)
end

function PlayerDataService.CleanupPlayer(player)
    local pending = pendingRobuxPurchases[player.UserId]
    if pending then
        for productId in pairs(pending) do
            clearRobuxReservation(player, productId, true)
        end
        pendingRobuxPurchases[player.UserId] = nil
    end
    pendingGiftPurchases[player.UserId] = nil
    saveData(player)
    sessionData[player] = nil
    activeMap[player] = nil
    joinTime[player] = nil
    task.defer(updateFriendBoosts)
end

local function buyUnitWithCash(player, unitId)
    local md = mapData(player)
    local config = UnitsConfig.Units[unitId]
    if not md or not config then return false, "Unit unavailable" end

    local cash = getLeaderValue(player, "Cash")
    local price = math.max(0, math.floor(tonumber(config.CashPrice or config.Cost) or 0))
    if not cash or cash.Value < price then return false, "Not enough cash" end
    if not _G.MyEvilLairStock or not _G.MyEvilLairStock.TryTake(unitId) then return false, "Out of stock" end

    cash.Value -= price
    md.Cash = cash.Value
    PlayerDataService.AddUnit(player, unitId, 1)
    MonetizationAnalytics.LogCashSink(player, Enum.AnalyticsEconomyTransactionType.Shop.Name, price, cash.Value, "Unit_" .. unitId, "Units")
    return true, "Purchased"
end

local function pendingFor(player)
    local userId = player.UserId
    local pending = pendingRobuxPurchases[userId]
    if not pending then
        pending = {}
        pendingRobuxPurchases[userId] = pending
    end
    return pending
end

local function returnReservedStock(kind, itemId)
    if kind == "Unit" then
        local stockApi = _G.MyEvilLairStock
        if stockApi and stockApi.Return then stockApi.Return(itemId) end
    elseif kind == "Crate" then
        local stockApi = _G.MyEvilLairCrateStock
        if stockApi and stockApi.Return then stockApi.Return(itemId) end
    end
end

local function clearRobuxReservation(player, productId, shouldReturnStock)
    productId = tonumber(productId) or 0
    local pending = pendingRobuxPurchases[player.UserId]
    local reservation = pending and pending[productId]
    if reservation then
        pending[productId] = nil
        if shouldReturnStock then
            returnReservedStock(reservation.Kind, reservation.ItemId)
        end
    end
    return reservation
end

local function reserveRobuxPurchase(player, kind, itemId, productId)
    productId = tonumber(productId) or 0
    if productId <= 0 then return false end
    local pending = pendingFor(player)
    if pending[productId] then return false end
    pending[productId] = { Kind = kind, ItemId = itemId, ExpiresAt = os.clock() + 120 }
    task.delay(120, function()
        if not player.Parent then return end
        local current = pendingRobuxPurchases[player.UserId] and pendingRobuxPurchases[player.UserId][productId]
        if current and current.Kind == kind and current.ItemId == itemId and os.clock() >= (current.ExpiresAt or 0) then
            clearRobuxReservation(player, productId, true)
        end
    end)
    return true
end

local function reserveUnitWithRobux(player, unitId)
    local config = UnitsConfig.Units[unitId]
    local productId = config and tonumber(config.RobuxProductId) or 0
    if not config or productId <= 0 then return false, "Robux purchase unavailable" end
    local stockApi = _G.MyEvilLairStock
    if not stockApi or not stockApi.TryTake then return false, "Stock not ready" end
    if not stockApi.TryTake(unitId) then return false, "Out of stock" end
    if not reserveRobuxPurchase(player, "Unit", unitId, productId) then
        if stockApi.Return then stockApi.Return(unitId) end
        return false, "Purchase already pending"
    end
    return true, "Prompt", productId
end

function PlayerDataService.ReserveRobuxCrate(player, crateId, productId)
    if not player or not player.Parent or not CratesConfig.Crates[crateId] then return false end
    return reserveRobuxPurchase(player, "Crate", crateId, productId)
end

local function upgradeBase(player)
    local md = mapData(player)
    if not md then return false, "Data not ready" end
    if player:GetAttribute("RaidActive") == true then return false, "Cannot upgrade during a raid" end

    local levels = BaseUpgradesConfig.Levels or {}
    local maxLevel = 7
    local currentLevel = math.clamp(math.floor(tonumber(player:GetAttribute("BaseLevel")) or tonumber(md.BaseLevel) or 1), 1, maxLevel)
    md.BaseLevel = currentLevel

    if currentLevel >= maxLevel then return false, "Max level" end
    local current = levels[currentLevel] or getBaseLevelConfig(currentLevel)
    local price = current and current.UpgradeCost
    if not price then return false, "Max level" end

    local cash = getLeaderValue(player, "Cash")
    if not cash or cash.Value < price then return false, "Not enough cash" end

    cash.Value -= price
    md.Cash = cash.Value
    md.BaseLevel = currentLevel + 1
    sendBase(player)
    MonetizationAnalytics.LogCashSink(player, Enum.AnalyticsEconomyTransactionType.Shop.Name, price, cash.Value, "BaseLevel" .. tostring(md.BaseLevel), "BaseUpgrade")
    task.spawn(saveData, player)
    return true, "Upgraded", md.BaseLevel
end

local function refreshAllStock()
    local units = _G.MyEvilLairStock
    local crates = _G.MyEvilLairCrateStock
    if units and units.ForceRefresh then units.ForceRefresh() end
    if crates and crates.ForceRefresh then crates.ForceRefresh() end
    return true
end

local function dailyRewardData(player)
    local data = sessionData[player]
    if not data then return nil end
    data.DailyRewards = type(data.DailyRewards) == "table" and data.DailyRewards or {}
    data.DailyRewards.Streak = math.max(1, math.floor(tonumber(data.DailyRewards.Streak) or 1))
    data.DailyRewards.NextClaimAt = math.max(0, math.floor(tonumber(data.DailyRewards.NextClaimAt) or 0))
    data.DailyRewards.LastClaimAt = math.max(0, math.floor(tonumber(data.DailyRewards.LastClaimAt) or 0))
    return data.DailyRewards
end

local function dailyState(player)
    local daily = dailyRewardData(player)
    if not daily then return nil end
    local now = os.time()
    local currentStreak = math.max(1, math.floor(tonumber(daily.Streak) or 1))
    local nextStreak = currentStreak + 1
    return {
        ready = now >= (daily.NextClaimAt or 0),
        now = now,
        nextClaimAt = daily.NextClaimAt or 0,
        cooldownSeconds = DailyRewardsConfig.CooldownSeconds,
        current = {
            day = currentStreak,
            claimed = now < (daily.NextClaimAt or 0),
            quantity = DailyRewardsConfig.Describe(DailyRewardsConfig.GetReward(currentStreak)),
        },
        next = {
            day = nextStreak,
            claimed = false,
            quantity = DailyRewardsConfig.Describe(DailyRewardsConfig.GetReward(nextStreak)),
        },
        skipProductId = tonumber(DeveloperProductsConfig.DailyRewardSkip and DeveloperProductsConfig.DailyRewardSkip.ProductId) or 0,
        skipRobuxPrice = tonumber(DeveloperProductsConfig.DailyRewardSkip and DeveloperProductsConfig.DailyRewardSkip.RobuxPrice) or 0,
    }
end

sendDailyState = function(player)
    local statePayload = dailyState(player)
    if statePayload then
        dailyRewardUpdateRemote:FireClient(player, statePayload)
    end
end

local function grantDailyReward(player, forced)
    local daily = dailyRewardData(player)
    if not daily then return false, "Data not ready" end
    local now = os.time()
    if not forced and now < (daily.NextClaimAt or 0) then
        return false, "Reward is not ready", dailyState(player)
    end

    local streak = math.max(1, math.floor(tonumber(daily.Streak) or 1))
    local reward = DailyRewardsConfig.RollChest(streak)
    if not reward then return false, "Reward unavailable" end

    -- everything grants instantly: no placed crates, no open timers
    local granted = false
    if reward.Type == "Unit" and reward.UnitId and UnitsConfig.Units[reward.UnitId] then
        granted = PlayerDataService.AddUnit(player, reward.UnitId, math.max(1, math.floor(tonumber(reward.UnitAmount) or 1)))
    elseif reward.Type == "Sword" and reward.SwordId then
        granted = PlayerDataService.AddWeapon(player, reward.SwordId)
    end
    local cashAmount = math.max(0, math.floor(tonumber(reward.Cash) or 0))
    if cashAmount > 0 then
        local ok, endingBalance = PlayerDataService.AddCash(player, cashAmount)
        if ok then
            granted = true
            cashPopupRemote:FireClient(player, cashAmount)
            MonetizationAnalytics.LogCashSource(player, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, cashAmount, endingBalance, "DailyChest_Day" .. tostring(streak), "DailyRewards")
        end
    end

    if not granted then return false, "Reward could not be granted" end

    daily.LastClaimAt = now
    daily.NextClaimAt = now + DailyRewardsConfig.CooldownSeconds
    daily.Streak = streak + 1
    task.spawn(saveData, player)
    sendDailyState(player)

    -- play the crate-style roulette on the client; pool = every obtainable at this day
    local crateOpened = remotes:FindFirstChild("CrateOpened")
    if crateOpened then
        crateOpened:FireClient(player, {
            crateId = "DailyChest",
            weapon = reward.UnitId or reward.SwordId or "Cash",
            isNew = false,
            config = { DisplayName = reward.Label, Damage = 0, Rarity = reward.Rarity or "Common", ImageId = "" },
            pool = DailyRewardsConfig.BuildRollPool(streak),
        })
    end
    return true, DailyRewardsConfig.Describe(reward), dailyState(player)
end

local function grantBundle(player, bundleKey, config)
    if not config then return false end
    local grantedSomething = false
    local cashAmount = math.max(0, math.floor(tonumber(config.Cash) or 0))
    if cashAmount > 0 then
        local ok, endingBalance = PlayerDataService.AddCash(player, cashAmount)
        if ok then
            cashPopupRemote:FireClient(player, cashAmount)
            MonetizationAnalytics.LogCashSource(player, Enum.AnalyticsEconomyTransactionType.IAP.Name, cashAmount, endingBalance, "Bundle_" .. tostring(bundleKey), "Bundles")
            grantedSomething = true
        end
    end
    if config.UnitId and UnitsConfig.Units[config.UnitId] then
        grantedSomething = PlayerDataService.AddUnit(player, config.UnitId, 1) or grantedSomething
    end
    if config.WeaponId and SwordsConfig.Swords[config.WeaponId] then
        local ok = PlayerDataService.AddWeapon(player, config.WeaponId)
        grantedSomething = ok or grantedSomething
    end
    if grantedSomething then
        MonetizationAnalytics.LogProductGranted(player, "Bundles", bundleKey, config.RobuxPrice or 0)
        task.spawn(saveData, player)
    end
    return grantedSomething
end

local function giftDisplayName(giftKey, config)
    return tostring((config and config.DisplayName) or giftKey or "Gift")
end

local function sendNotif(player, text, color)
    if not player or not player.Parent then return end
    color = color or Color3.fromRGB(255, 255, 255)
    notifRemote:FireClient(player, text, math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function grantGiftReward(recipient, giftKey)
    local config = DeveloperProductsConfig.Gifts[giftKey]
    local data = sessionData[recipient]
    if not config or not data then return false end

    if config.RewardType == "GamePass" then
        if playerOwnsGamePassReward(recipient, tostring(config.RewardKey or "")) then
            local fallbackCash = math.max(25000, math.floor((tonumber(config.RobuxPrice) or 0) * 1000))
            local ok, endingBalance = PlayerDataService.AddCash(recipient, fallbackCash)
            if ok then
                cashPopupRemote:FireClient(recipient, fallbackCash)
                MonetizationAnalytics.LogCashSource(recipient, Enum.AnalyticsEconomyTransactionType.IAP.Name, fallbackCash, endingBalance, "DuplicateGift_" .. tostring(giftKey), "Gifts")
                task.spawn(saveData, recipient)
            end
            return ok == true
        end
        data.GamePassEntitlements = data.GamePassEntitlements or {}
        data.GamePassEntitlements[config.RewardKey] = true
        applyGiftEntitlementAttributes(recipient)
        MonetizationAnalytics.LogProductGranted(recipient, "GiftGamePass", giftKey, config.RobuxPrice or 0)
        task.spawn(saveData, recipient)
        return true
    elseif config.RewardType == "CashPack" then
        local pack = CashProductsConfig.GetBySku(config.RewardKey)
        if not pack then return false end
        local ok, endingBalance = PlayerDataService.AddCash(recipient, pack.Amount)
        if ok then
            cashPopupRemote:FireClient(recipient, pack.Amount)
            MonetizationAnalytics.LogCashPackPurchased(recipient, pack, endingBalance)
            task.spawn(saveData, recipient)
        end
        return ok == true
    elseif config.RewardType == "Bundle" then
        return grantBundle(recipient, config.RewardKey, DeveloperProductsConfig.Bundles[config.RewardKey])
    end

    return false
end

local function queueOfflineGift(recipientUserId, giftKey, senderName, senderUserId)
    local ok = pcall(function()
        giftInboxStore:UpdateAsync(tostring(recipientUserId), function(inbox)
            inbox = type(inbox) == "table" and inbox or {}
            table.insert(inbox, {
                GiftKey = giftKey,
                SenderName = senderName,
                SenderUserId = senderUserId,
                CreatedAt = os.time(),
            })
            return inbox
        end)
    end)
    return ok
end

local function saveGiftIntent(sender, productId, giftKey, recipient)
    local intent = {
        GiftKey = giftKey,
        RecipientUserId = recipient.UserId,
        RecipientName = recipient.Name,
        SenderUserId = sender.UserId,
        SenderName = sender.Name,
        CreatedAt = os.time(),
    }
    local ok = pcall(function()
        giftIntentStore:SetAsync(giftIntentKey(sender.UserId, productId), intent)
    end)
    if ok then
        pendingGiftPurchases[sender.UserId] = pendingGiftPurchases[sender.UserId] or {}
        pendingGiftPurchases[sender.UserId][productId] = intent
    end
    return ok
end

local function loadGiftIntent(senderUserId, productId)
    local ok, intent = pcall(function()
        return giftIntentStore:GetAsync(giftIntentKey(senderUserId, productId))
    end)
    if ok and type(intent) == "table" then
        return intent
    end
    return nil
end

local function clearGiftIntent(senderUserId, productId)
    local pendingForPlayer = pendingGiftPurchases[senderUserId]
    if pendingForPlayer then
        pendingForPlayer[productId] = nil
    end
    task.spawn(function()
        pcall(function()
            giftIntentStore:RemoveAsync(giftIntentKey(senderUserId, productId))
        end)
    end)
end

local function deliverGift(sender, recipientUserId, recipientName, giftKey)
    local config = DeveloperProductsConfig.Gifts[giftKey]
    if not config then return false end
    local giftName = giftDisplayName(giftKey, config)
    local recipient = Players:GetPlayerByUserId(recipientUserId)

    if recipient and sessionData[recipient] then
        local granted = grantGiftReward(recipient, giftKey)
        if granted then
            sendNotif(recipient, "Received " .. giftName .. " from " .. sender.Name, Color3.fromRGB(85, 255, 120))
            MonetizationAnalytics.LogGiftSent(sender, recipientUserId, giftKey, config.RobuxPrice or 0)
        end
        return granted
    end

    local queued = queueOfflineGift(recipientUserId, giftKey, sender.Name, sender.UserId)
    if queued then
        MonetizationAnalytics.LogGiftSent(sender, recipientUserId, giftKey, config.RobuxPrice or 0)
    end
    return queued
end

processQueuedGifts = function(player)
    local ok, inbox = pcall(function()
        return giftInboxStore:GetAsync(tostring(player.UserId))
    end)
    if not ok or type(inbox) ~= "table" or #inbox == 0 then return end

    local deliveredAny = false
    local remaining = {}
    for _, gift in ipairs(inbox) do
        if type(gift) == "table" and DeveloperProductsConfig.Gifts[gift.GiftKey] then
            local granted = grantGiftReward(player, gift.GiftKey)
            if granted then
                deliveredAny = true
                local giftName = giftDisplayName(gift.GiftKey, DeveloperProductsConfig.Gifts[gift.GiftKey])
                sendNotif(player, "Received " .. giftName .. " from " .. tostring(gift.SenderName or "Someone"), Color3.fromRGB(85, 255, 120))
            else
                table.insert(remaining, gift)
            end
        end
    end

    if deliveredAny then
        task.spawn(saveData, player)
    end
    pcall(function()
        if #remaining > 0 then
            giftInboxStore:SetAsync(tostring(player.UserId), remaining)
        else
            giftInboxStore:RemoveAsync(tostring(player.UserId))
        end
    end)
end

local function grantGiftProduct(player, giftKey, config)
    local productId = tonumber(config and config.ProductId) or 0
    local pendingForPlayer = pendingGiftPurchases[player.UserId]
    local pending = pendingForPlayer and pendingForPlayer[productId]
    if not pending then
        pending = loadGiftIntent(player.UserId, productId)
    end

    local recipientUserId = pending and tonumber(pending.RecipientUserId) or player.UserId
    local recipientName = pending and tostring(pending.RecipientName or "") or player.Name
    local finalGiftKey = pending and tostring(pending.GiftKey or giftKey) or giftKey
    local granted = deliverGift(player, recipientUserId, recipientName, finalGiftKey)
    if granted then
        clearGiftIntent(player.UserId, productId)
        local giftName = giftDisplayName(finalGiftKey, DeveloperProductsConfig.Gifts[finalGiftKey])
        if recipientUserId == player.UserId and not pending then
            sendNotif(player, "Gift target expired; applied " .. giftName .. " to you", Color3.fromRGB(255, 230, 90))
        else
            sendNotif(player, "Sent " .. giftName .. " to " .. recipientName, Color3.fromRGB(85, 255, 120))
        end
    end
    return granted
end

local function grantDeveloperProduct(player, productId)
    local cashPack = CashProductsConfig.GetByProductId(productId)
    if cashPack then
        local ok, endingBalance = PlayerDataService.AddCash(player, cashPack.Amount)
        if not ok then return false end
        cashPopupRemote:FireClient(player, cashPack.Amount)
        MonetizationAnalytics.LogCashPackPurchased(player, cashPack, endingBalance)
        task.spawn(saveData, player)
        return true
    end

    local configuredProduct = DeveloperProductsConfig.GetByProductId(productId)
    if configuredProduct then
        if configuredProduct.Type == "StockRefresh" then
            local refreshed = refreshAllStock()
            if refreshed then
                MonetizationAnalytics.LogProductGranted(player, "Stock", "Refresh", configuredProduct.Config.RobuxPrice or 0)
            end
            return refreshed
        elseif configuredProduct.Type == "Bundle" then
            return grantBundle(player, configuredProduct.Key, configuredProduct.Config)
        elseif configuredProduct.Type == "Revive" then
            local reviveApi = _G.MyEvilLairRaidRevive
            return reviveApi and reviveApi.Grant and reviveApi.Grant(player, configuredProduct.Key) or false
        elseif configuredProduct.Type == "ChestSkip" then
            local skipApi = _G.MyEvilLairChestSkip
            return skipApi and skipApi.Grant and skipApi.Grant(player) or false
        elseif configuredProduct.Type == "DailyRewardSkip" then
            local granted = grantDailyReward(player, true)
            if granted then
                MonetizationAnalytics.LogProductGranted(player, "DailyRewards", "ClaimNow", configuredProduct.Config.RobuxPrice or 0)
            end
            return granted
        elseif configuredProduct.Type == "Gift" then
            return grantGiftProduct(player, configuredProduct.Key, configuredProduct.Config)
        end
    end

    for unitId, config in pairs(UnitsConfig.Units) do
        if config.RobuxProductId and config.RobuxProductId > 0 and config.RobuxProductId == productId then
            local reservation = clearRobuxReservation(player, productId, false)
            if not reservation then
                local stockApi = _G.MyEvilLairStock
                if not stockApi or not stockApi.TryTake or not stockApi.TryTake(unitId) then return false end
            elseif reservation.Kind ~= "Unit" or reservation.ItemId ~= unitId then
                returnReservedStock(reservation.Kind, reservation.ItemId)
                return false
            end
            local granted = PlayerDataService.AddUnit(player, unitId, 1)
            if granted then
                MonetizationAnalytics.LogCashSource(player, Enum.AnalyticsEconomyTransactionType.IAP.Name, 0, 0, "Unit_" .. unitId, "Units")
                MonetizationAnalytics.LogProductGranted(player, "Units", unitId, config.RobuxPrice or 0)
                task.spawn(saveData, player)
            else
                returnReservedStock("Unit", unitId)
            end
            return granted
        end
    end

    for crateId, config in pairs(CratesConfig.Crates) do
        if config.RobuxProductId and config.RobuxProductId > 0 and config.RobuxProductId == productId then
            local reservation = clearRobuxReservation(player, productId, false)
            local tookStockAtReceipt = false
            if not reservation then
                local stockApi = _G.MyEvilLairCrateStock
                if not stockApi or not stockApi.TryTake or not stockApi.TryTake(crateId) then return false end
                tookStockAtReceipt = true
            elseif reservation.Kind ~= "Crate" or reservation.ItemId ~= crateId then
                returnReservedStock(reservation.Kind, reservation.ItemId)
                return false
            end
            local granted = CrateGrantAPI.Grant(player, crateId)
            if granted then
                MonetizationAnalytics.LogCashSource(player, Enum.AnalyticsEconomyTransactionType.IAP.Name, 0, 0, "Crate_" .. crateId, "Crates")
                MonetizationAnalytics.LogProductGranted(player, "Crates", crateId, config.RobuxPrice or 0)
            else
                if tookStockAtReceipt then
                    returnReservedStock("Crate", crateId)
                else
                    reserveRobuxPurchase(player, "Crate", crateId, productId)
                end
            end
            return granted
        end
    end

    return nil
end

local startedOnce = false
function PlayerDataService.Start()
    if startedOnce then return end -- guard against duplicate bootstrap scripts double-connecting PlayerAdded
    startedOnce = true
    MonetizationAnalytics.Start(remotes)

    unitPurchaseRemote.OnServerInvoke = function(player, unitId, purchaseType)
        if purchaseType == "Robux" then
            local ok, msg, productId = reserveUnitWithRobux(player, tostring(unitId))
            if ok then
                local cfg = UnitsConfig.Units[tostring(unitId)]
                MonetizationAnalytics.LogProductPrompt(player, "Units", tostring(unitId), cfg and cfg.RobuxPrice or 0)
            end
            return ok, msg, productId
        end
        return buyUnitWithCash(player, tostring(unitId))
    end

    stockRefreshPurchaseRemote.OnServerInvoke = function(player)
        local productId = tonumber(DeveloperProductsConfig.StockRefresh.ProductId) or 0
        if productId <= 0 then return false, "Stock refresh product is not configured" end
        MonetizationAnalytics.LogProductPrompt(player, "Stock", "Refresh", DeveloperProductsConfig.StockRefresh.RobuxPrice or 0)
        return true, "Prompt", productId
    end

    shopProductPurchaseRemote.OnServerInvoke = function(player, bundleKey)
        bundleKey = tostring(bundleKey or "")
        local config = DeveloperProductsConfig.Bundles[bundleKey]
        local productId = config and tonumber(config.ProductId) or 0
        if productId <= 0 then return false, "Bundle product is not configured" end
        MonetizationAnalytics.LogProductPrompt(player, "Bundles", bundleKey, config.RobuxPrice or 0)
        return true, "Prompt", productId
    end

    raidRevivePurchaseRemote.OnServerInvoke = function(player)
        local reviveApi = _G.MyEvilLairRaidRevive
        if not reviveApi or not reviveApi.GetPromptProduct then
            return false, "Revive is not ready"
        end
        return reviveApi.GetPromptProduct(player)
    end

    dailyRewardRemote.OnServerInvoke = function(player, action)
        action = tostring(action or "State")
        if action == "Claim" then
            return grantDailyReward(player, false)
        elseif action == "PromptSkip" then
            local productId = tonumber(DeveloperProductsConfig.DailyRewardSkip.ProductId) or 0
            if productId <= 0 then return false, "Daily reward skip product is not configured", dailyState(player) end
            MonetizationAnalytics.LogProductPrompt(player, "DailyRewards", "ClaimNow", DeveloperProductsConfig.DailyRewardSkip.RobuxPrice or 0)
            return true, "Prompt", dailyState(player), productId
        end
        return true, "State", dailyState(player)
    end

    giftPurchaseRemote.OnServerInvoke = function(player, recipientUserId, giftKey)
        recipientUserId = tonumber(recipientUserId) or 0
        giftKey = tostring(giftKey or "")
        if recipientUserId <= 0 or recipientUserId == player.UserId then
            return false, "Pick another player"
        end
        local recipient = Players:GetPlayerByUserId(recipientUserId)
        if not recipient then
            return false, "That player left"
        end
        local config = DeveloperProductsConfig.Gifts[giftKey]
        local productId = config and tonumber(config.ProductId) or 0
        if productId <= 0 then
            return false, "Gift product is not configured"
        end
        if playerAlreadyOwnsGiftReward(recipient, config) then
            return false, recipient.Name .. " already has " .. tostring(config.DisplayName or "that perk")
        end
        local pendingForPlayer = pendingGiftPurchases[player.UserId]
        local existing = pendingForPlayer and pendingForPlayer[productId]
        if existing and (os.time() - (tonumber(existing.CreatedAt) or 0)) < 600 then
            return false, "Finish or cancel your current gift first"
        end
        if not saveGiftIntent(player, productId, giftKey, recipient) then
            return false, "Gift system is busy. Try again."
        end
        MonetizationAnalytics.LogProductPrompt(player, "Gifts", giftKey, config.RobuxPrice or 0)
        return true, "Prompt", productId
    end

    baseUpgradeRemote.OnServerInvoke = function(player)
        return upgradeBase(player)
    end

    MarketplaceService.ProcessReceipt = function(receiptInfo)
        local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
        if not player or not sessionData[player] then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local granted = grantDeveloperProduct(player, receiptInfo.ProductId)
        if granted == true then
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end
        if granted == false then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end

        warn("[PlayerDataService] Unhandled developer product receipt", receiptInfo.ProductId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
        if not purchased then
            local player = Players:GetPlayerByUserId(userId)
            if not player then return end
            clearRobuxReservation(player, productId, true)
            local gifts = pendingGiftPurchases[userId]
            if gifts then
                gifts[productId] = nil
            end
            local configured = DeveloperProductsConfig.GetByProductId(productId)
            if configured and configured.Type == "Gift" then
                clearGiftIntent(userId, productId)
            end
        end
    end)

    Players.PlayerAdded:Connect(PlayerDataService.SetupPlayer)
    Players.PlayerRemoving:Connect(PlayerDataService.CleanupPlayer)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(PlayerDataService.SetupPlayer, player)
    end
    game:BindToClose(function()
        for _, player in ipairs(Players:GetPlayers()) do saveData(player) end
    end)
end

return PlayerDataService

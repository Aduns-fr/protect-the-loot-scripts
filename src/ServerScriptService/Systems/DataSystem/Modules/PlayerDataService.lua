local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local UnitsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitsConfig"))
local BaseUpgradesConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("BaseUpgradesConfig"))
local MAX_BASE_LEVEL = 7
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
local sessionData = {}      -- full raw data per player
local activeMap = {}        -- current mapId per player (integer)
local joinTime = {}         -- os.time() when player joined, for TimePlayed tracking

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local boostRemote = remotes:WaitForChild("FriendBoostUpdate")
local unitPurchaseRemote = remotes:WaitForChild("UnitPurchase")
local inventoryRemote = remotes:WaitForChild("UnitInventoryUpdate")
local baseUpgradeRemote = remotes:WaitForChild("BaseUpgrade")
local baseDataRemote = remotes:WaitForChild("BaseDataUpdate")
local mapDataSyncRemote = remotes:WaitForChild("MapDataSync")

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

local function sendInventory(player)
    local md = mapData(player)
    if md then inventoryRemote:FireClient(player, md.Units) end
end

local function sendBase(player)
    local md = mapData(player)
    if not md then return end
    baseDataRemote:FireClient(player, { level = md.BaseLevel })
    player:SetAttribute("BaseLevel", md.BaseLevel)
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
    return true, wasNew
end

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

    task.defer(updateFriendBoosts)
    task.defer(sendInventory, player)
    task.defer(sendBase, player)
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
    return true, "Purchased"
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
    return true, "Upgraded", md.BaseLevel
end

function PlayerDataService.Start()
    unitPurchaseRemote.OnServerInvoke = function(player, unitId, purchaseType)
        if purchaseType == "Robux" then
            return false, "Use Robux prompt"
        end
        return buyUnitWithCash(player, tostring(unitId))
    end

    baseUpgradeRemote.OnServerInvoke = function(player)
        return upgradeBase(player)
    end

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerOrUserId, productId, wasPurchased)
        if not wasPurchased then return end
        local player = typeof(playerOrUserId) == "Instance" and playerOrUserId or Players:GetPlayerByUserId(playerOrUserId)
        if not player then return end
        for unitId, config in pairs(UnitsConfig.Units) do
            if config.RobuxProductId and config.RobuxProductId > 0 and config.RobuxProductId == productId then
                PlayerDataService.AddUnit(player, unitId, 1)
                break
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

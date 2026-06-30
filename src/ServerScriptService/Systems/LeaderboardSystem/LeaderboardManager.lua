local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REFRESH_INTERVAL = 90
local TOP_COUNT        = 50
local PERIODS          = { "Alltime", "Weekly" }

-- each board: name, which map's data to read, which stat
local BOARDS = {
    { name = "Map1Cash",  mapId = 1, stat = "Cash"  },
    { name = "Map1Waves", mapId = 1, stat = "Waves" },
    { name = "Map2Cash",  mapId = 2, stat = "Cash"  },
    { name = "Map2Waves", mapId = 2, stat = "Waves" },
    { name = "Time",      mapId = 0, stat = "Time"  },
}

local LeaderboardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LeaderboardRemote")

local cachedData = {}
for _, b in ipairs(BOARDS) do
    cachedData[b.name] = { Alltime = {}, Weekly = {} }
end

local isRefreshing   = false
local pendingPlayers = {}
local PlayerDataService

local function getWeekKey()
    return math.floor((math.floor(os.time() / 86400) + 4) / 7)
end

local storeCache = {}
local function getStore(boardName, period)
    local key = period == "Alltime"
        and ("MEL_LB_AT_" .. boardName)
        or  ("MEL_LB_W_%s_%d"):format(boardName, getWeekKey())
    if not storeCache[key] then
        storeCache[key] = DataStoreService:GetOrderedDataStore(key)
    end
    return storeCache[key], key
end

local function getStatForBoard(player, board, period)
    if not PlayerDataService then return 0 end
    local data = PlayerDataService.GetData(player)
    if not data then return 0 end

    local md = data.Maps and data.Maps[board.mapId]
    -- Time board doesn't use map data
    if board.stat == "Time" then
        return period == "Alltime"
            and math.max(0, math.floor(PlayerDataService.GetTimePlayed and PlayerDataService.GetTimePlayed(player) or 0))
            or 0
    end
    if not md then return 0 end

    if period == "Alltime" then
        if board.stat == "Time" then
            return math.max(0, math.floor(PlayerDataService.GetTimePlayed and PlayerDataService.GetTimePlayed(player) or 0))
        elseif board.stat == "Cash" then
            -- cash is tracked on the map's leaderstat
            local ls = player:FindFirstChild("leaderstats")
            local cv = ls and ls:FindFirstChild("Cash")
            -- if querying the active map use live leaderstat, else use saved
            local activeMap = PlayerDataService.GetActiveMap and PlayerDataService.GetActiveMap(player) or 1
            if activeMap == board.mapId then
                return math.max(0, math.floor(tonumber(cv and cv.Value) or 0))
            else
                return math.max(0, math.floor(tonumber(md.Cash) or 0))
            end
        elseif board.stat == "Waves" then
            return math.max(0, math.floor(tonumber(md.HighestWave) or 0))
        end

    elseif period == "Weekly" then
        if board.stat == "Time" then return 0 end
        local pb = md.periodBaselines
        local thisWeek = getWeekKey()
        if not pb or pb.weekKey ~= thisWeek then return 0 end
        if board.stat == "Cash" then
            local activeMap = PlayerDataService.GetActiveMap and PlayerDataService.GetActiveMap(player) or 1
            local current
            if activeMap == board.mapId then
                local ls = player:FindFirstChild("leaderstats")
                local cv = ls and ls:FindFirstChild("Cash")
                current = math.floor(tonumber(cv and cv.Value) or 0)
            else
                current = math.floor(tonumber(md.Cash) or 0)
            end
            return math.max(0, current - (pb.weekStartCash or 0))
        elseif board.stat == "Waves" then
            local current = math.floor(tonumber(md.HighestWave) or 0)
            return math.max(0, current - (pb.weekStartWave or 0))
        end
    end
    return 0
end

local function updatePeriodBaselines(player)
    if not PlayerDataService then return end
    local data = PlayerDataService.GetData(player)
    if not data then return end
    local thisWeek = getWeekKey()
    for mapId = 1, 2 do
        local md = data.Maps and data.Maps[mapId]
        if not md then continue end
        if not md.periodBaselines then md.periodBaselines = {} end
        local pb = md.periodBaselines
        if pb.weekKey ~= thisWeek then
            local activeMap = PlayerDataService.GetActiveMap and PlayerDataService.GetActiveMap(player) or 1
            local cashCurrent
            if activeMap == mapId then
                local ls = player:FindFirstChild("leaderstats")
                local cv = ls and ls:FindFirstChild("Cash")
                cashCurrent = math.floor(tonumber(cv and cv.Value) or 0)
            else
                cashCurrent = math.floor(tonumber(md.Cash) or 0)
            end
            pb.weekKey       = thisWeek
            pb.weekStartCash = cashCurrent
            pb.weekStartWave = math.floor(tonumber(md.HighestWave) or 0)
        end
    end
end

local function submitPlayerScores(player)
    updatePeriodBaselines(player)
    local uid = tostring(player.UserId)
    for _, board in ipairs(BOARDS) do
        for _, period in ipairs(PERIODS) do
            local value = getStatForBoard(player, board, period)
            if value < 1 then task.wait(0.06); continue end
            local store, name = getStore(board.name, period)
            local ok, err = pcall(function() store:SetAsync(uid, value) end)
            if not ok then warn("[LB] SetAsync failed:", name, err) end
            task.wait(0.06)
        end
    end
end

local usernameCache = {}
local function getUsername(userId)
    if usernameCache[userId] then return usernameCache[userId] end
    local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
    local result = ok and name or ("Player_" .. tostring(userId))
    usernameCache[userId] = result
    return result
end

local function fetchTop(boardName, period)
    local store, name = getStore(boardName, period)
    local ok, pages = pcall(function() return store:GetSortedAsync(false, TOP_COUNT) end)
    if not ok then warn("[LB] GetSortedAsync failed:", name, pages); return nil end
    local ok2, page = pcall(function() return pages:GetCurrentPage() end)
    if not ok2 then return nil end
    local results = {}
    for _, entry in ipairs(page) do
        local userId = tonumber(entry.key)
        if not userId or userId <= 0 then continue end
        table.insert(results, {
            rank     = #results + 1,
            userId   = userId,
            username = getUsername(userId),
            value    = entry.value or 0,
        })
    end
    return (#results > 0) and results or nil
end

local function isCacheEmpty()
    for _, b in ipairs(BOARDS) do
        for _, p in ipairs(PERIODS) do
            if #(cachedData[b.name][p] or {}) > 0 then return false end
        end
    end
    return true
end

local function pushToPlayer(player)
    if not player or not player.Parent then return end
    LeaderboardRemote:FireClient(player, "update", cachedData)
end

local function pushToAll()
    for _, p in ipairs(Players:GetPlayers()) do task.spawn(pushToPlayer, p) end
end

local LeaderboardManager = {}

function LeaderboardManager.refresh()
    if isRefreshing then return end
    isRefreshing = true
    local ok, err = pcall(function()
        local anyUpdated = false
        for _, board in ipairs(BOARDS) do
            for _, period in ipairs(PERIODS) do
                local results = fetchTop(board.name, period)
                if results then
                    cachedData[board.name][period] = results
                    anyUpdated = true
                end
                task.wait(0.2)
            end
        end
        if anyUpdated or not isCacheEmpty() then pushToAll() end
        for _, p in ipairs(pendingPlayers) do task.spawn(pushToPlayer, p) end
        pendingPlayers = {}
    end)
    if not ok then warn("[LB] Refresh error:", err) end
    isRefreshing = false
end

function LeaderboardManager.submitPlayer(player)
    task.spawn(function()
        pcall(submitPlayerScores, player)
        if isCacheEmpty() and not isRefreshing then
            task.wait(2); pcall(LeaderboardManager.refresh)
        end
    end)
end

function LeaderboardManager.sendToPlayer(player)
    if isCacheEmpty() then
        if isRefreshing then table.insert(pendingPlayers, player)
        else task.spawn(LeaderboardManager.refresh) end
    else
        task.spawn(pushToPlayer, player)
    end
end

function LeaderboardManager.init(playerDataService)
    PlayerDataService = playerDataService

    LeaderboardRemote.OnServerEvent:Connect(function(player, action)
        if action == "requestUpdate" then LeaderboardManager.sendToPlayer(player) end
    end)

    Players.PlayerAdded:Connect(function(player)
        task.delay(5, function()
            if player.Parent then LeaderboardManager.sendToPlayer(player) end
        end)
    end)

    Players.PlayerRemoving:Connect(function(player)
        pcall(submitPlayerScores, player)
        for i = #pendingPlayers, 1, -1 do
            if pendingPlayers[i] == player then table.remove(pendingPlayers, i) end
        end
    end)

    task.delay(8, function() pcall(LeaderboardManager.refresh) end)
    task.spawn(function()
        while true do
            task.wait(REFRESH_INTERVAL)
            pcall(LeaderboardManager.refresh)
        end
    end)
end

return LeaderboardManager

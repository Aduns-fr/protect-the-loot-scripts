local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LeaderboardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LeaderboardRemote")

-- must match SurfaceGui names in StarterGui.Leaderboards (skip Robux)
local BOARDS  = { "Map1Cash", "Map1Waves", "Map2Cash", "Map2Waves", "Time" }
local PERIODS = { "Weekly", "Alltime" }

local ACTIVE_COLOR  = Color3.fromRGB(255, 215, 0)
local DEFAULT_COLOR = Color3.fromRGB(45, 45, 45)
local CYCLE_TIME    = 30

local lastData = nil

local function fmt(n, boardName)
    n = math.floor(tonumber(n) or 0)
    if boardName == "Time" then
        -- format seconds as Xh Ym or Xm
        local h = math.floor(n / 3600)
        local m = math.floor((n % 3600) / 60)
        if h > 0 then return h .. "h " .. m .. "m"
        else return m .. "m" end
    end
    if     n >= 1e12 then return ("%.1fT"):format(n / 1e12)
    elseif n >= 1e9  then return ("%.1fB"):format(n / 1e9)
    elseif n >= 1e6  then return ("%.1fM"):format(n / 1e6)
    elseif n >= 1e3  then return ("%.1fK"):format(n / 1e3)
    else                  return tostring(n) end
end

local function loadThumbnail(pic, userId)
    if not pic or not userId or userId == 0 then return end
    task.spawn(function()
        local ok, img = pcall(Players.GetUserThumbnailAsync, Players, userId,
            Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        if ok and pic and pic.Parent then pic.Image = img end
    end)
end

-- SurfaceGuis live inside StarterGui.Leaderboards (a Folder), so they
-- replicate to PlayerGui.Leaderboards -- not directly into PlayerGui
local lbFolder = playerGui:WaitForChild("Leaderboards", 10)

local function getGui(boardName)
    return lbFolder and lbFolder:FindFirstChild(boardName)
end

local function fillRow(frame, rank, entry, boardName)
    local posLbl  = frame:FindFirstChild("Pos",   true)
    local nameLbl = frame:FindFirstChild("Name",  true)
    local valLbl  = frame:FindFirstChild("Value", true)
    local pic     = frame:FindFirstChild("Pic",   true)
    if posLbl then posLbl.Text = "#" .. rank end
    if entry then
        if nameLbl then nameLbl.Text = "@" .. (entry.username or "?") end
        if valLbl  then valLbl.Text  = fmt(entry.value or 0, boardName) end
        if pic     then loadThumbnail(pic, entry.userId) end
    else
        if nameLbl then nameLbl.Text = "---" end
        if valLbl  then valLbl.Text  = "---" end
        if pic     then pic.Image = "" end
    end
end

local function populatePage(page, entries, boardName)
    if not page then return end
    entries = entries or {}
    local template = page:FindFirstChild("Template")
    if template then template.Visible = false end

    for rank = 1, math.max(#entries, 3) do
        local entry = entries[rank]
        local frame = page:FindFirstChild(tostring(rank))
        if not frame then
            if not template then continue end
            frame = template:Clone()
            frame.Name = tostring(rank)
            frame.Parent = page
        end
        frame.Visible = true
        frame.LayoutOrder = rank
        fillRow(frame, rank, entry, boardName)
    end
end

local function populateBoard(boardName)
    local sg = getGui(boardName)
    if not sg then return end
    local fh = sg:FindFirstChild("Holder", true) and sg.Holder:FindFirstChild("FramesHolder")
    if not fh then return end
    for _, period in ipairs(PERIODS) do
        local page = fh:FindFirstChild(period)
        if page then
            local entries = lastData and lastData[boardName] and lastData[boardName][period] or {}
            populatePage(page, entries, boardName)
        end
    end
end

local function jumpToPeriod(boardName, period)
    local sg = getGui(boardName)
    if not sg then return end
    local holder  = sg:FindFirstChild("Holder")
    local fh      = holder and holder:FindFirstChild("FramesHolder")
    if not fh then return end
    local pl = fh:FindFirstChildOfClass("UIPageLayout")
    local pg = fh:FindFirstChild(period)
    if pl and pg then pcall(function() pl:JumpTo(pg) end) end
    local buttons = holder:FindFirstChild("Buttons")
    if buttons then
        for _, p in ipairs(PERIODS) do
            local btn = buttons:FindFirstChild(p)
            if btn then
                btn.BackgroundColor3 = (p == period) and ACTIVE_COLOR or DEFAULT_COLOR
            end
        end
    end
end

local function setupBoard(boardName)
    local sg = getGui(boardName)
    if not sg then warn("[LBC] gui not found in PlayerGui:", boardName); return end
    local holder = sg:FindFirstChild("Holder")
    local fh     = holder and holder:FindFirstChild("FramesHolder")
    if not fh then return end

    -- UIPageLayout should already exist from StarterGui but ensure it's configured
    local pl = fh:FindFirstChildOfClass("UIPageLayout")
    if not pl then
        pl = Instance.new("UIPageLayout")
        pl.SortOrder = Enum.SortOrder.LayoutOrder
        pl.Parent = fh
    end
    pcall(function()
        pl.TweenTime       = 0.35
        pl.EasingStyle     = Enum.EasingStyle.Quad
        pl.EasingDirection = Enum.EasingDirection.Out
        pl.SortOrder       = Enum.SortOrder.LayoutOrder
    end)

    -- hide template rows and set layout order
    for i, period in ipairs(PERIODS) do
        local pg = fh:FindFirstChild(period)
        if pg then
            pcall(function() pg.LayoutOrder = i end)
            local tmpl = pg:FindFirstChild("Template")
            if tmpl then tmpl.Visible = false end
        end
    end

    -- wire period buttons
    local buttons = holder and holder:FindFirstChild("Buttons")
    if buttons then
        for _, period in ipairs(PERIODS) do
            local btn = buttons:FindFirstChild(period)
            if btn then
                btn.BackgroundColor3 = DEFAULT_COLOR
                local cp, cb = period, boardName
                btn.Activated:Connect(function() jumpToPeriod(cb, cp) end)
            end
        end
    end
end

-- PlayerGui is populated from StarterGui on spawn — wait a frame for it
task.defer(function()
    for _, boardName in ipairs(BOARDS) do
        setupBoard(boardName)
        populateBoard(boardName)
    end

    -- auto-cycle each board between periods
    for _, boardName in ipairs(BOARDS) do
        local captured = boardName
        task.spawn(function()
            local idx = 1
            while true do
                jumpToPeriod(captured, PERIODS[idx])
                task.wait(CYCLE_TIME)
                idx = (idx % #PERIODS) + 1
            end
        end)
    end
end)

-- receive data from server and repopulate
LeaderboardRemote.OnClientEvent:Connect(function(action, data)
    if action ~= "update" or type(data) ~= "table" then return end
    -- merge so a partial response never blanks boards that were displaying
    for _, boardName in ipairs(BOARDS) do
        if type(data[boardName]) == "table" then
            if not lastData then lastData = {} end
            if not lastData[boardName] then lastData[boardName] = {} end
            for _, p in ipairs(PERIODS) do
                local incoming = data[boardName][p]
                if type(incoming) == "table" and #incoming > 0 then
                    lastData[boardName][p] = incoming
                end
            end
        end
    end
    for _, boardName in ipairs(BOARDS) do
        populateBoard(boardName)
    end
end)

-- request burst on join so boards fill quickly
task.delay(3,  function() LeaderboardRemote:FireServer("requestUpdate") end)
task.delay(10, function() LeaderboardRemote:FireServer("requestUpdate") end)
task.delay(30, function() LeaderboardRemote:FireServer("requestUpdate") end)

-- keep refreshing every 90s
task.spawn(function()
    task.wait(90)
    while true do
        LeaderboardRemote:FireServer("requestUpdate")
        task.wait(90)
    end
end)

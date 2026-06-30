local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local mapsFrame = frames:WaitForChild("Maps")
local sf = mapsFrame:WaitForChild("ScrollingFrame")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local mapSwitchRemote = remotes:WaitForChild("MapSwitch")
local mapDataSyncRemote = remotes:WaitForChild("MapDataSync")
local MapConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MapConfig"))

local currentMap = 1
local mapWaves = {}

local function updateMapUI()
    for mapId, cfg in pairs(MapConfig.Maps) do
        local card = sf:FindFirstChild(tostring(mapId))
        if not card then continue end

        local nameLabel = card:FindFirstChild("Name")
        local waveLabel = card:FindFirstChild("Wave")
        local goButton  = card:FindFirstChild("Go")

        if nameLabel then nameLabel.Text = cfg.Name end

        local wave = mapWaves[mapId] or 0
        if waveLabel then
            waveLabel.Text = wave > 0 and ("Best: Wave " .. wave) or "Not started"
        end

        -- dim Go button if already on this map
        if goButton then
            goButton.AutoButtonColor = (mapId ~= currentMap)
            goButton.BackgroundTransparency = (mapId == currentMap) and 0.5 or 0
        end
    end
end

-- wire Go buttons
for mapId = 1, 2 do
    local card = sf:FindFirstChild(tostring(mapId))
    if not card then continue end
    local goButton = card:FindFirstChild("Go")
    if not goButton or not goButton:IsA("GuiButton") then continue end

    local mid = mapId -- capture
    goButton.Activated:Connect(function()
        if mid == currentMap then return end
        if player:GetAttribute("RaidActive") == true then return end

        -- wait for transition module to be ready
        local tries = 0
        while not _G.PlayTransition and tries < 20 do
            task.wait(0.1)
            tries += 1
        end

        if _G.PlayTransition then
            _G.PlayTransition(function()
                -- mid-transition: fire the server switch
                local ok, err = mapSwitchRemote:InvokeServer(mid)
                if ok then
                    currentMap = mid
                else
                    warn("[MapsClient] switch failed:", err)
                end
            end)
        else
            -- fallback: just fire without transition
            local ok, err = mapSwitchRemote:InvokeServer(mid)
            if ok then currentMap = mid end
        end

        updateMapUI()
    end)
end

-- receive map data updates from server (on join and after switches)
mapDataSyncRemote.OnClientEvent:Connect(function(data)
    if type(data) ~= "table" then return end
    currentMap = tonumber(data.activeMap) or 1
    if type(data.mapWaves) == "table" then
        for mapId, wave in pairs(data.mapWaves) do
            mapWaves[tonumber(mapId)] = wave
        end
    end
    updateMapUI()
end)

updateMapUI()

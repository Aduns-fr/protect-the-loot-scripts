local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local GroupService = game:GetService("GroupService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local codes = frames:WaitForChild("Codes")
local settings = frames:WaitForChild("Settings")
local redeemRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RedeemCode")

local function promptGroupJoin()
    if game.CreatorType == Enum.CreatorType.Group then
        pcall(function() GroupService:PromptJoinAsync(game.CreatorId) end)
    end
end

local holder = codes:WaitForChild("Holder")
local textBox = holder:WaitForChild("TextBox")
local enter = holder:WaitForChild("Enter")
local status = holder:FindFirstChild("Text")
local join = holder:FindFirstChild("Join")
if join and join:IsA("GuiButton") then join.Activated:Connect(promptGroupJoin) end

local function setStatus(text, color)
    if status and status:IsA("TextLabel") then
        status.Text = text
        status.TextColor3 = color
    end
end
local function redeem()
    local ok, success, message = pcall(function() return redeemRemote:InvokeServer(textBox.Text) end)
    local result = ok and tostring(message) or "Invalid"
    if success then setStatus("Redeemed", Color3.fromRGB(80, 255, 80))
    elseif result == "Timed-out" then setStatus("Timed-out", Color3.fromRGB(255, 170, 40))
    elseif result == "Redeemed" then setStatus("Redeemed", Color3.fromRGB(80, 255, 80))
    else setStatus("Invalid", Color3.fromRGB(255, 70, 70)) end
end
enter.Activated:Connect(redeem)
textBox.FocusLost:Connect(function(enterPressed) if enterPressed then redeem() end end)

local musicEnabled = true
local sfxMuted = false
local namesVisible = true
local performance = false

-- wait for MusicPlayer to be ready (it sets _G.MusicPlayer after init)
local function getMusicPlayer()
    return _G.MusicPlayer
end

local function setMusic(on)
    musicEnabled = on
    -- route through the actual music player module if it's up
    local mp = getMusicPlayer()
    if mp and mp.setEnabled then
        mp.setEnabled(on)
    else
        -- fallback: mute the BackgroundMusic folder directly
        local bgMusic = SoundService:FindFirstChild("BackgroundMusic")
        if bgMusic then
            for _, s in ipairs(bgMusic:GetChildren()) do
                if s:IsA("Sound") then
                    if on then
                        s.Volume = s:GetAttribute("OriginalVolume") or 0.5
                    else
                        if s:GetAttribute("OriginalVolume") == nil then s:SetAttribute("OriginalVolume", s.Volume) end
                        s.Volume = 0
                    end
                end
            end
        end
    end
end

local function setSfx(on)
    sfxMuted = not on
    local sfx = SoundService:FindFirstChild("SFX")
    if not sfx then return end
    local ui = sfx:FindFirstChild("UI")
    for _, sound in ipairs(sfx:GetDescendants()) do
        if sound:IsA("Sound") and (not ui or not sound:IsDescendantOf(ui)) then
            if sound:GetAttribute("OriginalVolume") == nil then sound:SetAttribute("OriginalVolume", sound.Volume) end
            sound.Volume = sfxMuted and 0 or sound:GetAttribute("OriginalVolume")
        end
    end
end

-- apply name visibility to a single player's character
local function applyNamesTo(other)
    local hum = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.DisplayDistanceType = namesVisible
            and Enum.HumanoidDisplayDistanceType.Viewer
            or Enum.HumanoidDisplayDistanceType.None
    end
end

local charConns = {}

local function setNames(on)
    namesVisible = on
    -- apply to all current players
    for _, other in ipairs(Players:GetPlayers()) do
        applyNamesTo(other)
        -- also hook future character spawns for this player if not already hooked
        if not charConns[other] then
            charConns[other] = other.CharacterAdded:Connect(function()
                applyNamesTo(other)
            end)
        end
    end
end

-- clean up connections when players leave so we don't leak
Players.PlayerRemoving:Connect(function(other)
    if charConns[other] then
        charConns[other]:Disconnect()
        charConns[other] = nil
    end
end)

-- also hook any new players joining mid-session
Players.PlayerAdded:Connect(function(other)
    applyNamesTo(other)
    charConns[other] = other.CharacterAdded:Connect(function()
        applyNamesTo(other)
    end)
end)

local function setPerformance(on)
    performance = on
    Lighting.GlobalShadows = not on
    settings:SetAttribute("PerformanceMode", on)
    workspace:SetAttribute("PerformanceMode", on)

    -- particles/trails/beams
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            obj.Enabled = not on
        end
    end

    -- quality level
    pcall(function()
        local ugs = game:GetService("UserGameSettings")
        ugs.SavedQualityLevel = on and Enum.SavedQualitySetting.QualityLevel1 or Enum.SavedQualitySetting.Automatic
    end)

    -- LOD on all meshes
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("MeshPart") then
            pcall(function()
                obj.RenderFidelity = on and Enum.RenderFidelity.Automatic or Enum.RenderFidelity.Precise
            end)
        end
    end

    -- post-processing effects (Atmosphere doesn't have Enabled, skip it)
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("BlurEffect") or obj:IsA("DepthOfFieldEffect") or obj:IsA("SunRaysEffect") or obj:IsA("ColorCorrectionEffect") or obj:IsA("BloomEffect") then
            -- remember each effect's authored on/off state the first time we touch it
            if obj:GetAttribute("OriginalEnabled") == nil then obj:SetAttribute("OriginalEnabled", obj.Enabled) end
            -- performance mode forces them off; quality mode restores the authored state (so DepthOfField stays off)
            obj.Enabled = (not on) and (obj:GetAttribute("OriginalEnabled") == true)
        end
    end

    -- atmosphere: in performance mode, tank the density/haze to near zero instead
    local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmo then
        if on then
            if atmo:GetAttribute("OriginalDensity") == nil then atmo:SetAttribute("OriginalDensity", atmo.Density) end
            if atmo:GetAttribute("OriginalHaze") == nil then atmo:SetAttribute("OriginalHaze", atmo.Haze) end
            atmo.Density = 0
            atmo.Haze = 0
        else
            atmo.Density = atmo:GetAttribute("OriginalDensity") or atmo.Density
            atmo.Haze = atmo:GetAttribute("OriginalHaze") or atmo.Haze
        end
    end
end

local actions = {
    ["1"] = setMusic,
    ["2"] = setSfx,
    ["3"] = setNames,
    ["4"] = setPerformance,
}
for key, fn in pairs(actions) do
    local row = settings.Holder:FindFirstChild(key)
    if row then
        local on = row:FindFirstChild("On")
        local off = row:FindFirstChild("Off")
        if on and on:IsA("GuiButton") then on.Activated:Connect(function() fn(true) end) end
        if off and off:IsA("GuiButton") then off.Activated:Connect(function() fn(false) end) end
    end
end

setMusic(true); setSfx(true); setNames(true); setPerformance(false)

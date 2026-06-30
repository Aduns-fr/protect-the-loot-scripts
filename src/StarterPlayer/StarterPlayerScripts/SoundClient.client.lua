local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

local sfxStuff = SoundService:WaitForChild("SFX"):WaitForChild("Stuff")

-- build a name->sound lookup once
local soundMap = {}
for _, s in ipairs(sfxStuff:GetChildren()) do
    if s:IsA("Sound") then
        soundMap[s.Name] = s
    end
end

-- clone-and-play so multiple overlapping sounds work fine
local function playSound(name, speed)
    local s = soundMap[name]
    if not s then
        warn("[SoundClient] unknown sound:", name)
        return
    end
    local clone = s:Clone()
    clone.PlaybackSpeed = speed or 1
    clone.Parent = sfxStuff
    clone:Play()
    -- cleanup after it finishes (with a tiny buffer for float weirdness)
    local lifespan = (clone.TimeLength / (speed or 1)) + 0.5
    Debris:AddItem(clone, math.max(lifespan, 0.5))
end

-- expose globally so other scripts can call without requiring this module
_G.PlaySound = playSound

-- confetti layer - created on demand, reused between opens
local confettiLayer

local function getConfettiLayer()
    local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
    if confettiLayer and confettiLayer.Parent then return confettiLayer end
    local layer = Instance.new("Frame")
    layer.Name = "ConfettiLayer"
    layer.BackgroundTransparency = 1
    layer.Size = UDim2.fromScale(1, 1)
    layer.Position = UDim2.fromScale(0, 0)
    layer.ZIndex = 20
    layer.ClipsDescendants = false
    layer.Parent = gui
    confettiLayer = layer
    return layer
end

local CONFETTI_COLORS = {
    Color3.fromRGB(255, 75, 75),
    Color3.fromRGB(75, 210, 75),
    Color3.fromRGB(75, 130, 255),
    Color3.fromRGB(255, 220, 50),
    Color3.fromRGB(230, 75, 255),
    Color3.fromRGB(75, 220, 220),
    Color3.fromRGB(255, 155, 50),
    Color3.fromRGB(255, 255, 255),
}

local function spawnConfetti()
    local layer = getConfettiLayer()
    local count = 70

    for _ = 1, count do
        task.spawn(function()
            local piece = Instance.new("Frame")
            piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
            piece.BorderSizePixel = 0
            piece.Rotation = math.random(0, 360)
            piece.ZIndex = 21

            -- mix of squares and thin rectangles for visual variety
            local w = math.random(7, 18)
            local h = math.random(5, w + 6)
            piece.Size = UDim2.fromOffset(w, h)

            local startX = math.random(-8, 108) / 100
            local startY = math.random(-25, -5) / 100
            piece.Position = UDim2.fromScale(startX, startY)
            piece.Parent = layer

            -- stagger so they don't all appear at once
            task.wait(math.random(0, 70) / 100)

            local duration = 1.6 + math.random(0, 130) / 100
            local endX = startX + (math.random(-28, 28) / 100)
            local endY = startY + 1.05 + math.random(0, 45) / 100
            local endRot = piece.Rotation + math.random(-360, 360)

            TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.fromScale(endX, endY),
                Rotation = endRot,
            }):Play()

            task.wait(duration - 0.3)
            TweenService:Create(piece, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
            task.wait(0.4)
            if piece.Parent then piece:Destroy() end
        end)
    end
end

_G.ShowConfetti = spawnConfetti

-- money earned: cash leaderstat going up
local leaderstats = player:WaitForChild("leaderstats")
local cashValue = leaderstats:WaitForChild("Cash")
local prevCash = cashValue.Value

cashValue.Changed:Connect(function(newVal)
    if newVal > prevCash then
        playSound("Money")
    end
    prevCash = newVal
end)

-- victory when highest wave hits 100
local waveValue = leaderstats:WaitForChild("Highest Wave")
local victoryFired = waveValue.Value >= 100

waveValue.Changed:Connect(function(newVal)
    if newVal >= 100 and not victoryFired then
        victoryFired = true
        playSound("Victory")
    end
end)

-- fail/defeat at end of raid
local raidResultsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RaidResults")
raidResultsRemote.OnClientEvent:Connect(function(data)
    if type(data) ~= "table" then return end
    local status = tostring(data.status or "")
    if status == "Defeat" or status == "Game Over" then
        playSound("Fail")
    end
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local startRemote = remotes:WaitForChild("StartRaid")
local controlRemote = remotes:WaitForChild("RaidControl")
local top = script.Parent:WaitForChild("Top")

local BaseUpgradesConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("BaseUpgradesConfig"))
local speed3ProductId = BaseUpgradesConfig.RaidSpeed.Speed3ProductId or 0

local function getClick(frameName, legacyName)
    local instance = top:FindFirstChild(frameName) or top:FindFirstChild(legacyName)
    if instance and instance:IsA("GuiButton") then
        return instance
    end

    local click = instance and instance:FindFirstChild("Click")
    if click and click:IsA("GuiButton") then
        return click
    end

    warn("[StartRaidClient] Missing top button", frameName, legacyName)
    return nil
end

local startButton = getClick("StartButton", "Start")
local autoButton = top:WaitForChild("Auto")
local stopButton = top:WaitForChild("Stop")
local speedButton = top:WaitForChild("Speed")
local speed3Button = top:WaitForChild("x3")

local IMG_OFF = "rbxassetid://126153120865624"
local IMG_ON  = "rbxassetid://106218099677585"

local icon = autoButton:FindFirstChildOfClass("ImageLabel")
if icon then
    icon.Image = IMG_OFF
    icon.Rotation = 0
end

local spinning = false

local function spinIcon(turningOn)
    if not icon then return end
    spinning = true

    local startRot = icon.Rotation
    -- always spin a full 360 from wherever we are
    local endRot = startRot + 360
    -- the image swap happens at the halfway point (180 degrees in)
    local swapAt = startRot + 180

    local totalTime = 0.5
    local elapsed = 0

    -- using a stepped loop so we can intercept the exact swap point
    local conn
    conn = game:GetService("RunService").RenderStepped:Connect(function(dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / totalTime, 1)
        -- ease in-out so it doesn't feel robotic
        local eased = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2)^2 / 2)
        local currentRot = startRot + (360 * eased)
        icon.Rotation = currentRot

        -- swap image at the 180 degree mark
        if turningOn and currentRot >= swapAt then
            icon.Image = IMG_ON
        elseif not turningOn and currentRot >= swapAt then
            icon.Image = IMG_OFF
        end

        if t >= 1 then
            icon.Rotation = endRot % 360
            conn:Disconnect()
            spinning = false
        end
    end)
end

autoButton.Activated:Connect(function()
    if spinning then return end -- don't stack animations

    local nextValue = not (autoButton:GetAttribute("Enabled") == true)
    autoButton:SetAttribute("Enabled", nextValue)
    autoButton.Text = nextValue and "Auto: On" or "Auto: Off"
    controlRemote:FireServer("Auto", nextValue)

    spinIcon(nextValue)
end)

if startButton then
    startButton.Activated:Connect(function()
        startRemote:FireServer()
    end)
end

stopButton.Activated:Connect(function()
    controlRemote:FireServer("Stop")
end)

speedButton.Activated:Connect(function()
    local current = tonumber(speedButton:GetAttribute("Speed")) or 1
    local nextSpeed = current == 2 and 1 or 2
    speedButton:SetAttribute("Speed", nextSpeed)
    speedButton.Text = "x" .. tostring(nextSpeed)
    controlRemote:FireServer("Speed", nextSpeed)
end)

speed3Button.Activated:Connect(function()
    if speed3ProductId > 0 then
        MarketplaceService:PromptProductPurchase(player, speed3ProductId)
    else
        warn("[RaidUI] x3 speed needs BaseUpgradesConfig.RaidSpeed.Speed3ProductId configured.")
    end
end)

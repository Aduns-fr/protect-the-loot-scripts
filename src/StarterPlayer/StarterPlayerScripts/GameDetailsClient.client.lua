local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local top = gui:WaitForChild("Top")
local bottom = gui:WaitForChild("Bottom")
local details = gui:WaitForChild("GameDetails")
local baseFrame = gui:WaitForChild("Base")

local progress = details:WaitForChild("Progress")
local progressFill = progress:WaitForChild("Fill")
local progressText = progress:WaitForChild("Text")
local bossProgress = details:WaitForChild("BossProgress")
local bossFill = bossProgress:WaitForChild("Fill")
local bossText = bossProgress:WaitForChild("Text")
local targetText = details:WaitForChild("Text")
local text2 = details:WaitForChild("Text2")

local baseHealth = baseFrame:WaitForChild("Health")
local baseFill = baseHealth:FindFirstChild("Fill") or baseHealth:WaitForChild("Frame")
local baseText = baseHealth:WaitForChild("Text")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RaidStatus")

local BAR_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local UI_IN = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local UI_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local originalBottom = bottom.Position
local originalDetails = details.Position
local originalBase = baseFrame.Position
local topDefault = { Start = true, Base = true, Shops = true, Auto = false, Stop = false, Speed = false, x3 = false }
local topRaid = { Start = false, Base = false, Shops = false, Auto = true, Stop = true, Speed = true, x3 = true }
local topAliases = { Start = "StartButton", Base = "PlotButton", Shops = "ShopsButton" }

local function topControl(name)
    local control = top:FindFirstChild(name) or top:FindFirstChild(topAliases[name] or "")
    return control and control:IsA("GuiObject") and control or nil
end

local function topButton(name)
    local control = topControl(name)
    if control and control:IsA("GuiButton") then return control end
    local click = control and control:FindFirstChild("Click")
    return click and click:IsA("GuiButton") and click or nil
end

local function setTopMode(map)
    for name, visible in pairs(map) do
        local control = topControl(name)
        if control then control.Visible = visible end
    end
end

local function tween(object, info, props)
    if object then TweenService:Create(object, info, props):Play() end
end

local function offscreenBottom(object)
    return UDim2.new(object.Position.X.Scale, object.Position.X.Offset, object.Position.Y.Scale + 1.05, object.Position.Y.Offset)
end

local function offscreenTop(object)
    return UDim2.new(object.Position.X.Scale, object.Position.X.Offset, object.Position.Y.Scale - 1.05, object.Position.Y.Offset)
end

local function setFill(fill, ratio, reverse)
    ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
    if reverse then
        fill.AnchorPoint = Vector2.new(1, 0)
        fill.Position = UDim2.fromScale(1, 0)
    else
        fill.AnchorPoint = Vector2.new(0, 0)
        fill.Position = UDim2.fromScale(0, 0)
    end
    tween(fill, BAR_TWEEN, { Size = UDim2.fromScale(ratio, 1) })
end

local function nextBossWave(wave)
    wave = tonumber(wave) or 1
    return math.clamp((math.floor(wave / 10) + 1) * 10, 10, 100)
end

local function setBossVisible(visible)
    bossProgress.Visible = visible
    text2.Visible = visible
end

local function setRaidUi(active)
    gui:SetAttribute("RaidActive", active)
    if active then gui:SetAttribute("DeleteMode", false) end
    setTopMode(active and topRaid or topDefault)
    if active then
        details.Visible = true
        baseFrame.Visible = true
        bottom.Visible = true
        details.Position = offscreenTop(details)
        baseFrame.Position = offscreenBottom(baseFrame)
        tween(details, UI_IN, { Position = originalDetails })
        tween(baseFrame, UI_IN, { Position = originalBase })
        local tw = TweenService:Create(bottom, UI_OUT, { Position = offscreenBottom(bottom) })
        tw.Completed:Once(function()
            if gui:GetAttribute("RaidActive") == true then bottom.Visible = false end
        end)
        tw:Play()
    else
        setBossVisible(false)
        local bottomWasHidden = not bottom.Visible
        bottom.Visible = true
        if bottomWasHidden then bottom.Position = offscreenBottom(bottom) end
        tween(bottom, UI_IN, { Position = originalBottom })
        local detailsTw = TweenService:Create(details, UI_OUT, { Position = offscreenTop(details) })
        local baseTw = TweenService:Create(baseFrame, UI_OUT, { Position = offscreenBottom(baseFrame) })
        detailsTw.Completed:Once(function()
            if gui:GetAttribute("RaidActive") ~= true then
                details.Visible = false
                details.Position = originalDetails
            end
        end)
        baseTw.Completed:Once(function()
            if gui:GetAttribute("RaidActive") ~= true then
                baseFrame.Visible = false
                baseFrame.Position = originalBase
            end
        end)
        detailsTw:Play()
        baseTw:Play()
    end
end

local function showWave(wave, segmentRatio)
    details.Visible = true
    setBossVisible(wave % 10 == 0)
    progressText.Text = "Wave " .. tostring(wave)
    targetText.Text = "??? at wave " .. tostring(nextBossWave(wave))
    setFill(progressFill, segmentRatio or (((wave - 1) % 10 + 1) / 10), false)
end

local function showLoot(current, maxLoot, carriers)
    current = math.max(0, math.floor(tonumber(current) or 0))
    maxLoot = math.max(1, math.floor(tonumber(maxLoot) or 1))
    carriers = math.max(0, math.floor(tonumber(carriers) or 0))
    baseText.Text = carriers > 0 and (tostring(current) .. "  +" .. tostring(carriers) .. " carried") or tostring(current)
    setFill(baseFill, current / maxLoot, false)
end

local function resetControlText()
    local auto = topButton("Auto")
    local speed = topButton("Speed")
    if auto then
        auto:SetAttribute("Enabled", false)
        auto.Text = "Auto: Off"
    end
    if speed then
        speed:SetAttribute("Speed", 1)
        speed.Text = "x1"
    end
end

gui:SetAttribute("RaidActive", false) -- startup reset
setTopMode(topDefault)
details.Visible = false
baseFrame.Visible = false
setBossVisible(false)
resetControlText()

remote.OnClientEvent:Connect(function(action, data)
    data = type(data) == "table" and data or {}
    if action == "Start" then
        setRaidUi(true)
        setBossVisible(false)
        setFill(progressFill, 0, false)
        setFill(bossFill, 1, true)
        showLoot(data.loot or data.baseHealth, data.maxLoot or data.baseMaxHealth, data.carriers)
        task.defer(function() showLoot(data.loot or data.baseHealth, data.maxLoot or data.baseMaxHealth, data.carriers) end)
    elseif action == "Wave" then
        showWave(tonumber(data.wave) or 1, data.progress or 0)
    elseif action == "WaveProgress" then
        showWave(tonumber(data.wave) or 1, data.progress or 0)
    elseif action == "Boss" then
        details.Visible = true
        setBossVisible(true)
        local current = math.max(0, math.floor(tonumber(data.health) or 0))
        local maxHealth = math.max(1, math.floor(tonumber(data.maxHealth) or 1))
        bossText.Text = tostring(current)
        setFill(bossFill, current / maxHealth, true)
    elseif action == "Loot" or action == "Base" then
        showLoot(data.loot or data.health, data.maxLoot or data.maxHealth, data.carriers)
    elseif action == "Speed" then
        local speed = topButton("Speed")
        if speed then
            speed:SetAttribute("Speed", tonumber(data.speed) or 1)
            speed.Text = "x" .. tostring(tonumber(data.speed) or 1)
        end
    elseif action == "Auto" then
        local auto = topButton("Auto")
        if auto then
            local enabled = data.enabled == true
            auto:SetAttribute("Enabled", enabled)
            auto.Text = enabled and "Auto: On" or "Auto: Off"
        end
    elseif action == "End" then
        setRaidUi(false)
        resetControlText()
    end
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CashPopup")
local popupSound = SoundService:WaitForChild("SFX"):WaitForChild("UI"):FindFirstChild("Popup")
local active = {}
local serial = 0

local function comma(value)
    local text = tostring(math.max(0, math.floor(tonumber(value) or 0)))
    while true do
        local nextText, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = nextText
        if count == 0 then break end
    end
    return text
end

local function currentUi()
    local gui = playerGui:FindFirstChild("GUI") or playerGui:WaitForChild("GUI", 10)
    if not gui then return nil end
    local cashDisplay = gui:FindFirstChild("CashDisplay")
    if not cashDisplay then return nil end
    local layer = gui:FindFirstChild("CashPopupLayer")
    if not layer then
        layer = Instance.new("Frame")
        layer.Name = "CashPopupLayer"
        layer.BackgroundTransparency = 1
        layer.BorderSizePixel = 0
        layer.Position = UDim2.fromScale(0.02, 0.68)
        layer.Size = UDim2.fromScale(0.34, 0.22)
        layer.ZIndex = 40
        layer.ClipsDescendants = false
        layer.Parent = gui
    end
    return layer, cashDisplay
end

local function relayout()
    for index, popup in ipairs(active) do
        if popup.Parent then
            TweenService:Create(popup, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 0, 1 - index * 0.25, 0),
            }):Play()
        end
    end
end

local function removePopup(popup)
    local index = table.find(active, popup)
    if index then table.remove(active, index) end
    if popup.Parent then popup:Destroy() end
    relayout()
end

local function show(amount)
    amount = math.max(1, math.floor(tonumber(amount) or 0))
    local layer, cashDisplay = currentUi()
    if not layer then return end
    serial += 1

    local popup = Instance.new("TextLabel")
    popup.Name = "CashPopup" .. serial
    popup.BackgroundTransparency = 1
    popup.BorderSizePixel = 0
    popup.AnchorPoint = Vector2.new(0, 0.5)
    popup.Position = UDim2.new(-0.04, 0, 0.675, 0)
    popup.Size = UDim2.fromScale(0.72, 0.23)
    popup.ZIndex = 41
    popup.FontFace = cashDisplay.FontFace
    popup.Text = "+ $" .. comma(amount)
    popup.TextColor3 = Color3.new(1, 1, 1)
    popup.TextScaled = true
    popup.TextXAlignment = Enum.TextXAlignment.Left
    popup.TextTransparency = 1
    popup.TextStrokeColor3 = Color3.fromRGB(18, 55, 8)
    popup.TextStrokeTransparency = 1
    popup.Rotation = -3
    popup.Parent = layer

    local gradient = cashDisplay:FindFirstChildOfClass("UIGradient")
    if gradient then gradient:Clone().Parent = popup end
    local sourceStroke = cashDisplay:FindFirstChildOfClass("UIStroke")
    local popupStroke
    if sourceStroke then
        popupStroke = sourceStroke:Clone()
        popupStroke.Transparency = 1
        popupStroke.Parent = popup
    end
    local scale = Instance.new("UIScale")
    scale.Scale = 0.55
    scale.Parent = popup

    table.insert(active, 1, popup)
    while #active > 4 do removePopup(active[#active]) end
    relayout()

    if popupSound then
        local sound = popupSound:Clone()
        sound.Parent = SoundService
        sound:Play()
        Debris:AddItem(sound, math.max(1, sound.TimeLength + 0.2))
    end

    TweenService:Create(scale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
    TweenService:Create(popup, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        TextTransparency = 0,
        TextStrokeTransparency = 0.2,
        Rotation = 0,
    }):Play()
    if popupStroke then TweenService:Create(popupStroke, TweenInfo.new(0.22), { Transparency = 0 }):Play() end

    task.delay(1.45, function()
        if not popup.Parent then return end
        TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.72 }):Play()
        TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = popup.Position - UDim2.fromScale(0, 0.18),
            TextTransparency = 1,
            TextStrokeTransparency = 1,
            Rotation = 2,
        }):Play()
        if popupStroke then TweenService:Create(popupStroke, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
        task.delay(0.32, function() removePopup(popup) end)
    end)
end

remote.OnClientEvent:Connect(function(amount)
    script:SetAttribute("LastAmount", tonumber(amount) or 0)
    task.spawn(function()
        local ok, err = pcall(show, amount)
        if not ok then warn("[CashPopupClient]", err) end
    end)
end)
script:SetAttribute("Ready", true)

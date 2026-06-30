local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui       = playerGui:WaitForChild("GUI")
local notif     = gui:WaitForChild("Notif")
local template  = notif:WaitForChild("Template"):Clone() -- clone before destroying
notif:WaitForChild("Template"):Destroy() -- delete the original as requested
local listLayout = notif:FindFirstChildOfClass("UIListLayout")

local NotifRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notif")

local MAX_CARDS    = 3
local FADE_AFTER   = 2.5  -- seconds before a card starts fading
local FADE_TIME    = 0.4

-- track active cards
local activeCards = {}

local function removeCard(card)
    for i, c in ipairs(activeCards) do
        if c == card then table.remove(activeCards, i); break end
    end
    if card.Parent then
        local tw = TweenService:Create(card, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 })
        -- also fade the textlabel
        local tl = card:FindFirstChildOfClass("TextLabel") or card:FindFirstChild("TextLabel", true)
        local tw2 = tl and TweenService:Create(tl, TweenInfo.new(FADE_TIME), { TextTransparency = 1 })
        tw:Play()
        if tw2 then tw2:Play() end
        tw.Completed:Once(function()
            if card.Parent then card:Destroy() end
            if #activeCards == 0 then notif.Visible = false end
        end)
    end
end

local function showNotif(text, color)
    color = color or Color3.fromRGB(255, 255, 255)

    -- if already at max, remove the oldest
    if #activeCards >= MAX_CARDS then
        removeCard(activeCards[1])
    end

    notif.Visible = true

    local card = template:Clone()
    card.Name = "NotifCard"
    card.Visible = true
    card.BackgroundTransparency = 1  -- start transparent, tween in

    local tl = card:FindFirstChildOfClass("TextLabel") or card:FindFirstChild("TextLabel", true)
    if tl then
        tl.Text = text
        tl.TextColor3 = color
        tl.TextTransparency = 1
    end

    card.Parent = notif
    table.insert(activeCards, card)

    -- fade in
    TweenService:Create(card, TweenInfo.new(0.2), { BackgroundTransparency = card:GetAttribute("OrigBG") or 0 }):Play()
    if tl then
        TweenService:Create(tl, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
    end

    -- auto fade out after delay
    task.delay(FADE_AFTER, function()
        if card.Parent then removeCard(card) end
    end)
end

-- expose globally so BaseAndUnitUiClient can call it without a remote
_G.ShowNotif = showNotif

-- server-pushed notifications (stock refresh etc.)
NotifRemote.OnClientEvent:Connect(function(text, colorR, colorG, colorB)
    local color = Color3.fromRGB(colorR or 255, colorG or 255, colorB or 255)
    showNotif(text, color)
    if _G.PlaySound then _G.PlaySound("Notify") end
end)


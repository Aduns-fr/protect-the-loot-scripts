local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local transitionGui = script:WaitForChild("Transition"):Clone()
transitionGui.IgnoreGuiInset = true
transitionGui.ResetOnSpawn = false
transitionGui.Parent = playerGui

local stripes = {}
for i = 1, 4 do
    local frame = transitionGui:FindFirstChild(tostring(i))
    if frame then table.insert(stripes, frame) end
end

local originalLayouts = {}
if #originalLayouts == 0 then
    for i, frame in ipairs(stripes) do
        originalLayouts[i] = {
            Position = frame.Position,
            Size = frame.Size,
            AnchorPoint = frame.AnchorPoint,
        }
    end
end

-- init frames off-screen left
for i, frame in ipairs(stripes) do
    local layout = originalLayouts[i]
    frame.AnchorPoint = layout.AnchorPoint
    frame.Size = layout.Size
    frame.Position = UDim2.new(-1.6, 0, layout.Position.Y.Scale, layout.Position.Y.Offset)
end

local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local isTransitioning = false

local function playTransition(midCallback)
    if isTransitioning then return end
    isTransitioning = true

    -- slide in
    for i, frame in ipairs(stripes) do
        local targetPos = originalLayouts[i].Position
        frame.Position = UDim2.new(-1.6, 0, targetPos.Y.Scale, targetPos.Y.Offset)
        task.delay((i - 1) * 0.06, function()
            TweenService:Create(frame, tweenInfo, { Position = targetPos }):Play()
        end)
    end

    task.wait(0.65)

    if midCallback then
        pcall(midCallback)
    end

    task.wait(0.2)

    -- slide out
    for i = #stripes, 1, -1 do
        local frame = stripes[i]
        local exitPos = UDim2.new(1.6, 0, frame.Position.Y.Scale, frame.Position.Y.Offset)
        task.delay((#stripes - i) * 0.06, function()
            local tw = TweenService:Create(frame, tweenInfo, { Position = exitPos })
            tw:Play()
            tw.Completed:Once(function()
                frame.Position = UDim2.new(-1.6, 0, frame.Position.Y.Scale, frame.Position.Y.Offset)
            end)
        end)
    end

    task.wait(0.65 + (#stripes * 0.06))
    isTransitioning = false
end

-- expose globally so MapsClient can call it
_G.PlayTransition = playTransition

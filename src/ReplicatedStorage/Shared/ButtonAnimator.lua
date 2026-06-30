local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local ButtonAnimator = {}

local DEFAULTS = {
    HoverSizeScale = 1.045,
    PressSizeScale = 0.965,
    HoverRotation = -1.25,
    PressRotation = 1.25,
    HoverYOffset = -2,
    PressYOffset = 1,
    HoverInTime = 0.18,
    HoverSettleTime = 0.16,
    HoverOutTime = 0.2,
    PressTime = 0.075,
    ReleaseTime = 0.2,
    FrameHoverScale = 1.05,
    FramePressScale = 0.95,
    FrameTweenTime = 0.175,
}

local bound = setmetatable({}, { __mode = "k" })
local activeTweens = setmetatable({}, { __mode = "k" })
local settleTokens = setmetatable({}, { __mode = "k" })

local function merge(options)
    local out = {}
    for key, value in pairs(DEFAULTS) do out[key] = value end
    if options then
        for key, value in pairs(options) do out[key] = value end
    end
    return out
end

local function playSound(soundName)
    local sfx = SoundService:FindFirstChild("SFX")
    local ui = sfx and sfx:FindFirstChild("UI")
    local sound = ui and ui:FindFirstChild(soundName)
    if sound and sound:IsA("Sound") then
        sound.PlaybackSpeed = math.random(96, 104) / 100
        sound:Play()
    end
end

local function scaledSize(size, scale)
    return UDim2.new(size.X.Scale * scale, math.floor(size.X.Offset * scale + 0.5), size.Y.Scale * scale, math.floor(size.Y.Offset * scale + 0.5))
end

local function shiftedPosition(position, yOffset)
    return UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + yOffset)
end

local function getFrameButtonTarget(button)
    if button.Name == "Click" and button.Parent and button.Parent:IsA("GuiObject") then
        return button.Parent
    end
    return nil
end

local function stopTweens(button)
    local list = activeTweens[button]
    if not list then return end
    for _, tween in ipairs(list) do
        if tween.PlaybackState == Enum.PlaybackState.Playing then tween:Cancel() end
    end
    activeTweens[button] = nil
end

local function playTween(button, time, easingStyle, easingDirection, props)
    local tween = TweenService:Create(button, TweenInfo.new(time, easingStyle, easingDirection or Enum.EasingDirection.Out), props)
    activeTweens[button] = activeTweens[button] or {}
    table.insert(activeTweens[button], tween)
    tween.Completed:Once(function()
        local list = activeTweens[button]
        if not list then return end
        for i, item in ipairs(list) do
            if item == tween then table.remove(list, i); break end
        end
        if #list == 0 then activeTweens[button] = nil end
    end)
    tween:Play()
end

local function makeState(button)
    return { Size = button.Size, Position = button.Position, Rotation = button.Rotation }
end

local function bindFrameButton(button, target, opts)
    local scale = target:FindFirstChild("ButtonScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "ButtonScale"
        scale.Scale = 1
        scale.Parent = target
    end

    local tweenInfo = TweenInfo.new(opts.FrameTweenTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
    local hovering = false

    local function tweenScale(value)
        TweenService:Create(scale, tweenInfo, { Scale = value }):Play()
    end

    button.MouseEnter:Connect(function()
        hovering = true
        playSound("Hover")
        tweenScale(opts.FrameHoverScale)
    end)

    button.MouseLeave:Connect(function()
        hovering = false
        tweenScale(1)
    end)

    button.MouseButton1Down:Connect(function()
        playSound("Click")
        tweenScale(opts.FramePressScale)
    end)

    button.MouseButton1Up:Connect(function()
        tweenScale(hovering and opts.FrameHoverScale or 1)
    end)

    button.SelectionGained:Connect(function()
        hovering = true
        tweenScale(opts.FrameHoverScale)
    end)

    button.SelectionLost:Connect(function()
        hovering = false
        tweenScale(1)
    end)
end

function ButtonAnimator.Bind(button, options)
    if not button or not button:IsA("GuiButton") or bound[button] then return end
    bound[button] = true

    local opts = merge(options)
    local frameTarget = getFrameButtonTarget(button)
    if frameTarget then
        bindFrameButton(button, frameTarget, opts)
        return
    end

    local idle = makeState(button)
    local hovering = false
    local pressing = false

    local function refreshIdle()
        if not hovering and not pressing then idle = makeState(button) end
    end

    local function state(scaleBoost, yOffset, rotation)
        return {
            Size = scaledSize(idle.Size, scaleBoost),
            Position = shiftedPosition(idle.Position, yOffset),
            Rotation = idle.Rotation + rotation,
        }
    end

    local function tweenTo(target, time, style, direction)
        playTween(button, time, style, direction, target)
    end

    local function hoverIn()
        refreshIdle()
        hovering = true
        pressing = false
        playSound("Hover")
        stopTweens(button)
        local token = {}
        settleTokens[button] = token
        tweenTo(state(opts.HoverSizeScale + 0.012, opts.HoverYOffset - 1, opts.HoverRotation * 1.25), opts.HoverInTime, Enum.EasingStyle.Quint)
        task.delay(opts.HoverInTime * 0.72, function()
            if settleTokens[button] ~= token or not hovering or pressing or not button.Parent then return end
            stopTweens(button)
            tweenTo(state(opts.HoverSizeScale, opts.HoverYOffset, opts.HoverRotation), opts.HoverSettleTime, Enum.EasingStyle.Sine)
        end)
    end

    local function hoverOut()
        hovering = false
        pressing = false
        settleTokens[button] = nil
        stopTweens(button)
        tweenTo(idle, opts.HoverOutTime, Enum.EasingStyle.Quint)
    end

    local function press()
        pressing = true
        playSound("Click")
        settleTokens[button] = nil
        stopTweens(button)
        tweenTo(state(opts.PressSizeScale, opts.PressYOffset, opts.PressRotation), opts.PressTime, Enum.EasingStyle.Quad)
    end

    local function release()
        pressing = false
        stopTweens(button)
        if hovering then
            tweenTo(state(opts.HoverSizeScale + 0.006, opts.HoverYOffset - 0.5, opts.HoverRotation), opts.ReleaseTime * 0.55, Enum.EasingStyle.Back)
            task.delay(opts.ReleaseTime * 0.45, function()
                if not hovering or pressing or not button.Parent then return end
                stopTweens(button)
                tweenTo(state(opts.HoverSizeScale, opts.HoverYOffset, opts.HoverRotation), opts.ReleaseTime * 0.55, Enum.EasingStyle.Sine)
            end)
        else
            tweenTo(idle, opts.ReleaseTime, Enum.EasingStyle.Quint)
        end
    end

    button.MouseEnter:Connect(hoverIn)
    button.MouseLeave:Connect(hoverOut)
    button.MouseButton1Down:Connect(press)
    button.MouseButton1Up:Connect(release)
    button.SelectionGained:Connect(hoverIn)
    button.SelectionLost:Connect(hoverOut)
end

function ButtonAnimator.BindDescendants(root, options)
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("GuiButton") then ButtonAnimator.Bind(descendant, options) end
    end
    root.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("GuiButton") then ButtonAnimator.Bind(descendant, options) end
    end)
end

return ButtonAnimator

local Module = {}

local TweenService = game:GetService("TweenService")
local CustomPrompt = script:WaitForChild("CustomPrompt")
local TextModule = require(script.Parent.Parent.Modules.PromptText)

local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Module.activePrompts = {}

local function stopAllTweens(data)
    if data.holdTween then data.holdTween:Cancel() end
    if data.revertTween then data.revertTween:Cancel() end
end

function Module:onShown(prompt, inputType, player, target)
    local promptClone = CustomPrompt:Clone()
    local canvasGroup = promptClone.CanvasGroup
    local gui = canvasGroup.Frame
    local textFrame = gui.TextFrame
    local inputFrame = gui.InputFrame

    TextModule:SetText(prompt, inputType, textFrame, inputFrame)

    if inputType == Enum.ProximityPromptInputType.Touch or prompt.ClickablePrompt then
        local button = Instance.new("TextButton")
        button.BackgroundTransparency = 1
        button.TextTransparency = 1
        button.Size = UDim2.fromScale(1, 1)
        button.Parent = promptClone

        local buttonDown = false
        button.InputBegan:Connect(function(input)
            if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and input.UserInputState ~= Enum.UserInputState.Change then
                prompt:InputHoldBegin()
                buttonDown = true
            end
        end)
        button.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                if buttonDown then
                    buttonDown = false
                    prompt:InputHoldEnd()
                end
            end
        end)
    end

    local yOffset = 4.25
    local conf = prompt:FindFirstChild("CustomPromptConf")
    local yOffsetValue = conf and conf:FindFirstChild("YOffset")
    if yOffsetValue and yOffsetValue:IsA("NumberValue") then
        yOffset = yOffsetValue.Value
    end

    promptClone.Name = "CustomPrompt"
    promptClone.Enabled = true
    canvasGroup.GroupTransparency = 1
    promptClone.StudsOffsetWorldSpace = Vector3.new(0, yOffset, 0)
    promptClone.Adornee = target or prompt.Parent
    promptClone.Parent = player.PlayerGui:WaitForChild("CustomPrompts")

    local objectValue = conf and conf:FindFirstChild("ObjectValue")
    if objectValue and objectValue:IsA("ObjectValue") then
        objectValue.Value = promptClone
    end

    TweenService:Create(canvasGroup, tweenInfo, { GroupTransparency = 0 }):Play()
    Module.activePrompts[prompt] = { clone = promptClone, gui = gui }
end

function Module:onHidden(prompt)
    local data = Module.activePrompts[prompt]
    if not data or not data.clone then return end

    local canvasGroup = data.clone:FindFirstChild("CanvasGroup")
    if not canvasGroup then
        data.clone:Destroy()
        Module.activePrompts[prompt] = nil
        return
    end

    local disappearTween = TweenService:Create(canvasGroup, tweenInfo, { GroupTransparency = 1 })
    disappearTween:Play()
    disappearTween.Completed:Connect(function()
        if data.clone then data.clone:Destroy() end
    end)

    Module.activePrompts[prompt] = nil
end

function Module:onTriggered(prompt) end

function Module:onHoldStart(prompt)
    local data = Module.activePrompts[prompt]
    if not data then return end
    local textFrame = data.gui.TextFrame
    local holdBar = data.gui.InputFrame.Frame.ProgressBar.Bar
    if not holdBar then return end

    stopAllTweens(data)
    local duration = math.max(0.05, prompt.HoldDuration)
    TweenService:Create(textFrame, tweenInfo, { GroupTransparency = 1 }):Play()
    data.holdTween = TweenService:Create(holdBar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 1, 0) })
    data.holdTween:Play()
end

function Module:onHoldEnd(prompt)
    local data = Module.activePrompts[prompt]
    if not data then return end
    local textFrame = data.gui.TextFrame
    local holdBar = data.gui.InputFrame.Frame.ProgressBar.Bar
    if not holdBar then return end

    stopAllTweens(data)
    TweenService:Create(textFrame, tweenInfo, { GroupTransparency = 0 }):Play()
    data.revertTween = TweenService:Create(holdBar, TweenInfo.new(0.1, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 0, 0) })
    data.revertTween:Play()
end

return Module

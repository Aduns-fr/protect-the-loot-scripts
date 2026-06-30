local module = {}

local UserInputService = game:GetService("UserInputService")

local KeyCodeToTextMapping = {
    [Enum.KeyCode.LeftControl] = "Ctrl",
    [Enum.KeyCode.RightControl] = "Ctrl",
    [Enum.KeyCode.LeftAlt] = "Alt",
    [Enum.KeyCode.RightAlt] = "Alt",
    [Enum.KeyCode.Return] = "Enter",
    [Enum.KeyCode.Backspace] = "Backspace",
    [Enum.KeyCode.Space] = "Space",
}

function module:SetText(prompt, inputType, textFrame, inputFrame)
    textFrame.ActionText.Text = prompt.ActionText
    textFrame.ObjectText.Text = prompt.ObjectText

    local inputText = inputFrame.Frame.InputText
    local inputImage = inputFrame.Frame.InputImage
    inputImage.Visible = false
    inputText.Visible = true

    if inputType == Enum.ProximityPromptInputType.Touch then
        inputText.Text = "Tap"
        return
    end

    local keyCode = inputType == Enum.ProximityPromptInputType.Gamepad and prompt.GamepadKeyCode or prompt.KeyboardKeyCode
    local text = KeyCodeToTextMapping[keyCode] or UserInputService:GetStringForKeyCode(keyCode)
    if not text or text == "" then
        text = keyCode.Name
    end
    inputText.Text = text
end

return module

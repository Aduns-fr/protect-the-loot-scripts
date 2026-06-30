local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
player.CharacterAdded:Connect(function(char)
    character = char
end)

local PromptEffect = require(script.Modules.PromptEffect)
local PromptFolder = script.Prompts
local activeModules = {}

local function getPromptTarget(prompt)
    local parent = prompt.Parent
    if parent and parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
        return parent.Parent
    end
    if parent and parent:IsA("BasePart") then
        return parent
    end
    return nil
end

local function isCustom(prompt)
    if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return false end
    local conf = prompt:FindFirstChild("CustomPromptConf")
    local flag = conf and conf:FindFirstChild("CustomPrompt")
    return flag and flag:IsA("BoolValue") and flag.Value == true
end

local function getModule(prompt)
    local conf = prompt:FindFirstChild("CustomPromptConf")
    local custom = conf and conf:FindFirstChild("CustomPrompt")
    local promptName = custom and custom:FindFirstChild("PromptName")
    local moduleName = promptName and promptName.Value or "Prompt1"
    local moduleScript = PromptFolder:FindFirstChild(moduleName)
    if not moduleScript then
        warn("[CustomPrompt Handler] Prompt module not found:", moduleName)
        return nil
    end
    local module = activeModules[moduleName]
    if not module then
        module = require(moduleScript)
        activeModules[moduleName] = module
    end
    return module
end

local function handle(prompt, methodName, inputType)
    if not isCustom(prompt) then return end
    local module = getModule(prompt)
    if module and module[methodName] then
        module[methodName](module, prompt, inputType, player, getPromptTarget(prompt))
    end
end

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
    if isCustom(prompt) then
        local conf = prompt:FindFirstChild("CustomPromptConf")
        local target = getPromptTarget(prompt)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if target and root and conf and conf:FindFirstChild("Beam") and conf.Beam.Value then
            PromptEffect:CreateBeam(target, root, conf)
        end
        if target and conf and conf:FindFirstChild("Highlight") and conf.Highlight.Value then
            PromptEffect:CreateHighlight(target, conf)
        end
    end
    handle(prompt, "onShown", inputType)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt, inputType)
    if isCustom(prompt) then
        local conf = prompt:FindFirstChild("CustomPromptConf")
        local target = getPromptTarget(prompt)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if target and root and conf and conf:FindFirstChild("Beam") and conf.Beam.Value then
            PromptEffect:DestroyBeam(target, root)
        end
        if target and conf and conf:FindFirstChild("Highlight") and conf.Highlight.Value then
            PromptEffect:DestroyHighlight(target)
        end
    end
    handle(prompt, "onHidden", inputType)
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, inputType)
    handle(prompt, "onTriggered", inputType)
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, inputType)
    handle(prompt, "onHoldStart", inputType)
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, inputType)
    handle(prompt, "onHoldEnd", inputType)
end)

local screenGui = player.PlayerGui:FindFirstChild("CustomPrompts") or Instance.new("ScreenGui")
screenGui.Name = "CustomPrompts"
screenGui.ResetOnSpawn = false
screenGui.Parent = player.PlayerGui

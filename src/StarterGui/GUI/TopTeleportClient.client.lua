local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TopTeleport")
local top = script.Parent:WaitForChild("Top")

local function getClick(frameName, legacyName)
    local instance = top:FindFirstChild(frameName) or top:FindFirstChild(legacyName)
    if instance and instance:IsA("GuiButton") then
        return instance
    end

    local click = instance and instance:FindFirstChild("Click")
    if click and click:IsA("GuiButton") then
        return click
    end

    warn("[TopTeleportClient] Missing top button", frameName, legacyName)
    return nil
end

local baseButton = getClick("PlotButton", "Base")
local shopsButton = getClick("ShopsButton", "Shops")

if baseButton then
    baseButton.Activated:Connect(function()
        remote:FireServer("Base")
    end)
end

if shopsButton then
    shopsButton.Activated:Connect(function()
        remote:FireServer("Shops")
    end)
end

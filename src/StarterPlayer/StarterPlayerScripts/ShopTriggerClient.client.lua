local Players = game:GetService("Players")

local player = Players.LocalPlayer
local debounce = {}
local boundTriggers = {}

local function getRequest()
    local playerGui = player:WaitForChild("PlayerGui")
    local gui = playerGui:WaitForChild("GUI")
    return gui:WaitForChild("OpenFrameRequest")
end

local function findPlayerPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plotName = player:GetAttribute("PlotName")
    if plotName then
        local plot = plots:FindFirstChild(plotName)
        if plot then return plot end
    end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == player.UserId then
            return plot
        end
    end
    return nil
end

local function bindTrigger(shopFolder, modelName, frameName)
    local model = shopFolder and shopFolder:FindFirstChild(modelName)
    local trigger = model and model:FindFirstChild("Trigger")
    if not trigger or boundTriggers[trigger] then return end
    boundTriggers[trigger] = true
    trigger.Touched:Connect(function(hit)
        local character = player.Character
        if not character or not hit:IsDescendantOf(character) then return end
        local now = os.clock()
        if debounce[frameName] and now - debounce[frameName] < 1 then return end
        debounce[frameName] = now
        getRequest():Fire(frameName)
    end)
end

local function bindCurrentShop()
    local plot = findPlayerPlot()
    local shopFolder = plot and plot:FindFirstChild("Shop")
    if not shopFolder then return end
    bindTrigger(shopFolder, "Units", "Units")
    bindTrigger(shopFolder, "Crates", "Crates")
end

player:GetAttributeChangedSignal("PlotName"):Connect(bindCurrentShop)

local plots = workspace:WaitForChild("Plots")
plots.ChildAdded:Connect(function(plot)
    plot:GetAttributeChangedSignal("OwnerUserId"):Connect(bindCurrentShop)
    bindCurrentShop()
end)
for _, plot in ipairs(plots:GetChildren()) do
    plot:GetAttributeChangedSignal("OwnerUserId"):Connect(bindCurrentShop)
end

task.spawn(function()
    for _ = 1, 60 do
        bindCurrentShop()
        task.wait(1)
    end
end)

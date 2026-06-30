local Players = game:GetService("Players")

local player = Players.LocalPlayer
local shops = workspace:WaitForChild("Shops")
local debounce = {}

local function getRequest()
    local playerGui = player:WaitForChild("PlayerGui")
    local gui = playerGui:WaitForChild("GUI")
    return gui:WaitForChild("OpenFrameRequest")
end

local function bindTrigger(modelName, frameName)
    local model = shops:WaitForChild(modelName)
    local trigger = model:WaitForChild("Trigger")
    trigger.Touched:Connect(function(hit)
        local character = player.Character
        if not character or not hit:IsDescendantOf(character) then return end
        local now = os.clock()
        if debounce[frameName] and now - debounce[frameName] < 1 then return end
        debounce[frameName] = now
        getRequest():Fire(frameName)
    end)
end

bindTrigger("Units", "Units")
bindTrigger("Crates", "Crates")

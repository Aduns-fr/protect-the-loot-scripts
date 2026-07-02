local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local cashDisplay = gui:WaitForChild("CashDisplay")
local friendBoost = gui:WaitForChild("FriendBoost")
local boostDisplay = friendBoost:WaitForChild("BoostDisplay")
local inviteButton = friendBoost:WaitForChild("Invite")
local frames = gui:WaitForChild("Frames")
local openFrameRequest = gui:WaitForChild("OpenFrameRequest")
local closeFrameRequest = gui:WaitForChild("CloseFrameRequest")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local boostRemote = remotes:WaitForChild("FriendBoostUpdate")
local raidResultsRemote = remotes:WaitForChild("RaidResults")
local startRaidRemote = remotes:WaitForChild("StartRaid")
local raidRevivePurchaseRemote = remotes:WaitForChild("RaidRevivePurchase")

local displayedCash = 0
local cashTweenToken = 0
local lastRaidResult = nil

local function formatCash(value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    local text = tostring(value)
    local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if result:sub(1, 1) == "," then result = result:sub(2) end
    return "$" .. result
end

local function animateCash(target)
    target = math.max(0, math.floor(tonumber(target) or 0))
    cashTweenToken += 1
    local token = cashTweenToken
    local start = displayedCash
    local duration = math.clamp(math.abs(target - start) / 1500, 0.35, 1.15)
    local started = os.clock()

    task.spawn(function()
        while token == cashTweenToken do
            local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
            local eased = 1 - (1 - alpha) * (1 - alpha)
            local value = math.floor(start + (target - start) * eased)
            cashDisplay.Text = formatCash(value)
            if alpha >= 1 then break end
            task.wait(0.03)
        end
        if token == cashTweenToken then
            displayedCash = target
            cashDisplay.Text = formatCash(target)
        end
    end)
end

local function hookCash()
    local leaderstats = player:WaitForChild("leaderstats")
    local cash = leaderstats:WaitForChild("Cash")
    displayedCash = cash.Value
    cashDisplay.Text = formatCash(displayedCash)
    cash:GetPropertyChangedSignal("Value"):Connect(function()
        animateCash(cash.Value)
    end)
end

task.spawn(hookCash)

boostRemote.OnClientEvent:Connect(function(percent)
    percent = math.clamp(tonumber(percent) or 0, 0, 100)
    boostDisplay.Text = "Friend Boost: +" .. tostring(percent) .. "%"
end)

inviteButton.Activated:Connect(function()
    pcall(function()
        SocialService:PromptGameInvite(player)
    end)
end)

local function comma(value)
    value = math.floor(tonumber(value) or 0)
    local text = tostring(value)
    while true do
        local nextText, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = nextText
        if count == 0 then break end
    end
    return text
end

local function setResultValue(results, name, value)
    local holder = results:FindFirstChild("Holder")
    local row = holder and holder:FindFirstChild(name)
    local label = row and row:FindFirstChild("Value")
    if label and label:IsA("TextLabel") then label.Text = value end
end

local function setReviveVisible(results, visible)
    local revive = results and results:FindFirstChild("Revive")
    if revive and revive:IsA("GuiObject") then
        revive.Visible = visible == true
        if revive:IsA("GuiButton") then
            revive.Active = visible == true
            revive.AutoButtonColor = visible == true
        end
    end
end

raidResultsRemote.OnClientEvent:Connect(function(data)
    data = type(data) == "table" and data or {}
    lastRaidResult = data
    local results = frames:FindFirstChild("Results")
    if not results then return end
    setReviveVisible(results, data.reason == "Defeated")

    local status = results:FindFirstChild("Status")
    if status and status:IsA("TextLabel") then
        status.Text = tostring(data.status or "Defeat")
    end

    setResultValue(results, "Enemies", comma(data.enemiesDefeated or 0))
    setResultValue(results, "Waves", comma(data.wavesCleared or 0))
    setResultValue(results, "Cash", formatCash(data.cashEarned or 0))
    setResultValue(results, "Score", comma(data.score or 0))

    task.spawn(function()
        local started = os.clock()
        while gui:GetAttribute("RaidActive") == true and os.clock() - started < 3 do
            task.wait(0.05)
        end
        task.wait(0.15)
        openFrameRequest:Fire("Results")

        -- victory at wave 100: auto-close after 5s if player has auto on
        if data.reason == "Victory" then
            task.spawn(function()
                task.wait(5)
                -- only close if results is still the open frame
                if closeFrameRequest then
                    closeFrameRequest:Fire()
                end
            end)
        end
    end)
end)

local results = frames:FindFirstChild("Results")
if results then
    setReviveVisible(results, false)
    local done = results:FindFirstChild("Done")
    if done and done:IsA("GuiButton") then
        done.Activated:Connect(function()
            closeFrameRequest:Fire()
        end)
    end
    local restart = results:FindFirstChild("Restart")
    if restart and restart:IsA("GuiButton") then
        restart.Activated:Connect(function()
            closeFrameRequest:Fire()
            task.wait(0.2)
            startRaidRemote:FireServer()
        end)
    end
    local revive = results:FindFirstChild("Revive")
    if revive and revive:IsA("GuiButton") then
        revive.Activated:Connect(function()
            if not lastRaidResult or lastRaidResult.reason ~= "Defeated" then return end
            local ok, success, msg, productId = pcall(function()
                return raidRevivePurchaseRemote:InvokeServer()
            end)
            if ok and success and tonumber(productId) and tonumber(productId) > 0 then
                MarketplaceService:PromptProductPurchase(player, tonumber(productId))
            elseif _G.ShowNotif then
                _G.ShowNotif(tostring(ok and msg or success or "Revive unavailable"), Color3.fromRGB(255, 35, 35))
            end
        end)
    end
end

-- server fires AutoContinue when auto mode continues past wave 100
-- close the results frame so the next raid start feels seamless
local raidStatusRemote = remotes:WaitForChild("RaidStatus")
raidStatusRemote.OnClientEvent:Connect(function(action, data)
    if action == "AutoContinue" then
        closeFrameRequest:Fire()
    end
end)

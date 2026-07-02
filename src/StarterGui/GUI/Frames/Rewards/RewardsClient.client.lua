-- Daily Chests client. Each day the frame auto-opens with the Current chest;
-- clicking it opens the chest and reveals a rolled reward. ClaimNow purchases
-- tomorrow's chest early (dev product).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local frame = script.Parent
local openFrameRequest = gui:WaitForChild("OpenFrameRequest")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local dailyRewardRemote = remotes:WaitForChild("DailyReward")
local dailyRewardUpdate = remotes:WaitForChild("DailyRewardUpdate")

local currentButton = frame:WaitForChild("Current")
local claimNowButton = frame:WaitForChild("ClaimNow")
local infoLabel = frame:WaitForChild("Info")

local state = nil
local openedForReadyAt = nil
local revealUntil = 0
local opening = false

local function openRewards()
	task.spawn(function()
		for _ = 1, 5 do
			openFrameRequest:Fire("Rewards")
			task.wait(0.35)
			if frame.Visible then break end
		end
	end)
end

local function clickTarget(object)
	if object:IsA("GuiButton") then return object end
	local click = object:FindFirstChild("Click")
	if click and click:IsA("GuiButton") then return click end
	return object:FindFirstChildWhichIsA("GuiButton", true)
end

local function setTextWithChildren(object, text)
	if object and (object:IsA("TextLabel") or object:IsA("TextButton")) then
		object.Text = text
	end
	if object then
		for _, descendant in ipairs(object:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				descendant.Text = text
			end
		end
	end
end

local function setClaimed(button, visible)
	local claimed = button:FindFirstChild("Claimed", true)
	if claimed and claimed:IsA("GuiObject") then
		claimed.Visible = visible == true
	end
end

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function render()
	if type(state) ~= "table" then return end
	local day = (type(state.current) == "table" and state.current.day) or 1
	setTextWithChildren(currentButton:FindFirstChild("Day", true), "Day " .. tostring(day))
	local remaining = math.max(0, (tonumber(state.nextClaimAt) or 0) - os.time())
	if os.clock() < revealUntil then return end -- keep the reveal text on screen briefly
	if state.ready then
		setTextWithChildren(infoLabel, "Your daily chest is ready — open it!")
		setClaimed(currentButton, false)
	else
		setTextWithChildren(infoLabel, formatDuration(remaining) .. " until your next chest")
		setClaimed(currentButton, true)
	end
end

local function requestState(openAfter)
	local ok, success, _, payload = pcall(function()
		return dailyRewardRemote:InvokeServer("State")
	end)
	if ok and success and type(payload) == "table" then
		state = payload
		render()
		if openAfter then
			openRewards()
		end
	end
end

local function promptSkip()
	local ok, success, message, payload, productId = pcall(function()
		return dailyRewardRemote:InvokeServer("PromptSkip")
	end)
	if ok and success and tonumber(productId) and tonumber(productId) > 0 then
		state = type(payload) == "table" and payload or state
		render()
		MarketplaceService:PromptProductPurchase(player, tonumber(productId))
	elseif _G.ShowNotif then
		_G.ShowNotif(tostring(ok and message or success or "Daily chest unavailable"), Color3.fromRGB(255, 70, 70))
	end
end

local function claimCurrent()
	if opening then return end
	if not state or state.ready ~= true then
		if _G.ShowNotif then _G.ShowNotif("Your next chest isn't ready yet", Color3.fromRGB(255, 230, 90)) end
		return
	end
	opening = true
	local ok, success, rewardLabel, payload = pcall(function()
		return dailyRewardRemote:InvokeServer("Claim")
	end)
	if ok and success then
		-- the server fires the CrateOpened roulette; it takes over the screen from here
		state = type(payload) == "table" and payload or state
		revealUntil = os.clock() + 8
		setTextWithChildren(infoLabel, "You got: " .. tostring(rewardLabel or "a reward") .. "!")
		setClaimed(currentButton, true)
	elseif _G.ShowNotif then
		_G.ShowNotif(tostring(ok and rewardLabel or success or "Chest unavailable"), Color3.fromRGB(255, 70, 70))
	end
	opening = false
end

local currentClick = clickTarget(currentButton)
if currentClick then currentClick.Activated:Connect(claimCurrent) end
local claimClick = clickTarget(claimNowButton)
if claimClick then claimClick.Activated:Connect(promptSkip) end

dailyRewardUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then
		state = payload
		render()
		if state.ready then
			openRewards()
		end
	end
end)

task.spawn(function()
	task.wait(1)
	requestState(true)
	while true do
		if state then
			render()
			local readyAt = tonumber(state.nextClaimAt) or 0
			if not state.ready and readyAt > 0 and os.time() >= readyAt then
				state.ready = true
				if openedForReadyAt ~= readyAt then
					openedForReadyAt = readyAt
					openRewards()
				end
			end
		end
		task.wait(1)
	end
end)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Folder = ReplicatedStorage:WaitForChild("UltimateAdminAbusePack")
local Settings = require(Folder.Settings)

local AutoAAStore = DataStoreService:GetDataStore("AutoAA")
local BanStore = DataStoreService:GetDataStore("Banned")

Players.PlayerAdded:Connect(function(Player: Player)	
	if BanStore:GetAsync(Player.UserId) then
		Player:Kick(Settings.BanMessage)
	end
end)

script.Parent.BanUser.Event:Connect(function(UserID)
	BanStore:SetAsync(UserID, 1)
end)

script.Parent.UnbanUser.Event:Connect(function(UserID)
	BanStore:RemoveAsync(UserID)
end)

script.Parent.ChangeAA.Event:Connect(function(Time, Status, Weathers, Luck, UserId)
	AutoAAStore:SetAsync("Time", Time)
	AutoAAStore:SetAsync("Status", Status)
	if Weathers then
		AutoAAStore:SetAsync("Weather", Weathers)
	else
		AutoAAStore:RemoveAsync("Weather")
	end
	if Luck then
		AutoAAStore:SetAsync("Luck", Luck)
	else
		AutoAAStore:RemoveAsync("Luck")
	end
	if UserId then
		AutoAAStore:SetAsync("UserId", UserId)
	else
		AutoAAStore:RemoveAsync("UserId")
	end
end)

script.Parent.GetAA.OnInvoke = function()
	local Options = {}
	Options.Status = AutoAAStore:GetAsync("Status") or false
	Options.Weather = AutoAAStore:GetAsync("Weather")
	Options.Luck = AutoAAStore:GetAsync("Luck")
	Options.Time = AutoAAStore:GetAsync("Time")
	Options.UserId = AutoAAStore:GetAsync("UserId")
	return Options
end
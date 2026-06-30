local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

local Gui = PlayerGui:WaitForChild("Gui")
local OTHER = Gui:WaitForChild("OTHER")
local Announcement_UI = OTHER:WaitForChild("Announcement")
local Voting = OTHER:WaitForChild("Voting")

local Folder = ReplicatedStorage:WaitForChild("UltimateAdminAbusePack")

local InterfaceModule = require(Folder:WaitForChild("InterfaceModule"))
local Settings = require(Folder:WaitForChild("Settings"))

local Remotes = Folder:WaitForChild("Remotes")
local GlobalMessage_Remote = Remotes:WaitForChild("GlobalMessage")
local Vote_Remote = Remotes:WaitForChild("Vote")
local StartVoting_Remote = Remotes:WaitForChild("StartVoting")
local EndVoting_Remote = Remotes:WaitForChild("EndVoting")
local StartWeather_Remote = Remotes:WaitForChild("StartWeather")
local WeatherEffects_Remote = Remotes:WaitForChild("WeatherEffects")

local LastWeather = nil

Voting.Buttons.GreenButton.Click.MouseButton1Click:Connect(function()
	Vote_Remote:FireServer(1)
end)

Voting.Buttons.RedButton.Click.MouseButton1Click:Connect(function()
	Vote_Remote:FireServer(2)
end)

GlobalMessage_Remote.OnClientEvent:Connect(function(SenderId, Message)
	local Clone = Folder.Assets.AnnouncementTemplate:Clone()
	
	InterfaceModule.LoadText(Clone.Info, Message)
	
	Clone.Username.Text = Players:GetNameFromUserIdAsync(SenderId)
	Clone.UIScale.Scale = 0
	Clone.Parent = Announcement_UI
	
	local InTween = TweenService:Create(Clone.UIScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0), {Scale = 1})
	local OutTween = TweenService:Create(Clone.UIScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In, 0, false, 0), {Scale = 0})
	
	InTween:Play()
	task.wait(Settings.MessageTime)
	OutTween:Play()
	OutTween.Completed:Wait()
	Clone:Destroy()
end)

StartVoting_Remote.OnClientEvent:Connect(function(Text, Choises)
	local UIScale = Voting:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", Voting)
	UIScale.Scale = 0
	
	Voting.Buttons.GreenButton.TextLabel.Text = ""
	Voting.Buttons.RedButton.TextLabel.Text = ""
	
	Voting.Votes.Green.Text = 0
	Voting.Votes.Red.Text = 0
	
	Voting.VotingBar.Green.Size = UDim2.fromScale(0,1)
	Voting.VotingBar.Red.Size = UDim2.fromScale(0,1)
	
	Voting.VotingName.Text = ""
	
	Voting.Visible = true
	
	local Tween = TweenService:Create(UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	Tween:Play()
	
	Tween.Completed:Wait()
	InterfaceModule.LoadText(Voting.VotingName, Text)
	InterfaceModule.LoadText(Voting.Buttons.GreenButton.TextLabel, Choises[1])
	InterfaceModule.LoadText(Voting.Buttons.RedButton.TextLabel, Choises[2])
end)

EndVoting_Remote.OnClientEvent:Connect(function()
	local UIScale = Voting:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", Voting)
	UIScale.Scale = 1
	
	local Tween = TweenService:Create(UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 0})
	Tween:Play()
	
	Tween.Completed:Wait()
	
	Voting.Visible = false
end)

Vote_Remote.OnClientEvent:Connect(function(Votes, End)	
	local Choise1 = #Votes[1]
	local Choise2 = #Votes[2]
	
	local Max = Choise1 + Choise2
	
	Voting.Votes.Green.Text = Choise1
	Voting.Votes.Red.Text = Choise2
	
	local Procentage1 = 0.5
	local Procentage2 = 0.5
		
	local Procentage1 = (Choise1 == 0 and Choise2 == 0) and 0.5 or (Choise1 / Max)
	local Procentage2 = (Choise1 == 0 and Choise2 == 0) and 0.5 or (Choise2 / Max)
	
	local Tween1 = TweenService:Create(Voting.VotingBar.Green, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Size = UDim2.fromScale(Procentage1, 1)})
	local Tween2 = TweenService:Create(Voting.VotingBar.Red, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Size = UDim2.fromScale(Procentage2, 1)})
	
	Tween1:Play()
	Tween2:Play()
end)

StartWeather_Remote.OnClientEvent:Connect(function(WeatherConfig)
	InterfaceModule.WeatherTransition()
end)

WeatherEffects_Remote.OnClientEvent:Connect(function(WeatherSettings, Status)
	if not WeatherSettings then return end
	
	if Status == "Start" then
		SoundService.SFX.GameMusic:Stop()
		if WeatherSettings:FindFirstChildOfClass("Sound") then
			WeatherSettings:FindFirstChildOfClass("Sound"):Play()
		end
		if LastWeather ~= nil then
			LastWeather:FindFirstChildOfClass("Sound"):Stop()
		end
		LastWeather = WeatherSettings
	else
		if LastWeather ~= nil then
			LastWeather:FindFirstChildOfClass("Sound"):Stop()
		end
		if WeatherSettings:FindFirstChildOfClass("Sound") then
			WeatherSettings:FindFirstChildOfClass("Sound"):Stop()
		end
		SoundService.SFX.GameMusic:Play()
		LastWeather = WeatherSettings
	end
end)

task.delay(3, function()
	for _,Button:GuiObject in Gui:QueryDescendants(".Button, :has(TextButton)") do InterfaceModule.OnButton(Button) end

	Gui.DescendantAdded:Connect(function(Descendant)
		if Descendant:HasTag("Button") and Descendant:FindFirstChildOfClass("TextButton") then
			InterfaceModule.OnButton(Descendant)
		end
	end)
end)

SoundService.SFX.GameMusic:Play()
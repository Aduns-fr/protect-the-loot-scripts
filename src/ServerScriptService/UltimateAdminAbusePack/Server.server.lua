local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local AdminList = require(script.Parent:WaitForChild("AdminList"))

local Bindables = script.Parent.Bindables
local WeatherStart_Bindable = Bindables.WeatherStart
local WeatherEnd_Bindable = Bindables.WeatherEnd
local LuckStart_Bindable = Bindables.LuckStart
local LuckEnd_Bindable = Bindables.LuckEnd
local GiveItem_Bindable = Bindables.GiveItem
local VotingStart_Bindable = Bindables.VotingStart
local VotingEnd_Bindable = Bindables.VotingEnd

local Store = script.Parent.Store
local BanUser_Bindable = Store.BanUser
local UnbanUser_Bindable = Store.UnbanUser
local ChangeAA = Store.ChangeAA
local GetAA = Store.GetAA

local Folder = ReplicatedStorage:WaitForChild("UltimateAdminAbusePack")

local Settings = require(Folder.Settings)

local Remotes = Folder.Remotes
local GlobalMessage_Remote = Remotes.GlobalMessage
local StartWeather_Remote = Remotes.StartWeather
local StartLuck_Remote = Remotes.StartLuck
local BanUser_Remote = Remotes.BanUser
local UnbanUser_Remote = Remotes.UnbanUser
local GiveItem_Remote = Remotes.GiveItem
local StartVoting_Remote = Remotes.StartVoting
local EndVoting_Remote = Remotes.EndVoting
local Vote_Remote = Remotes.Vote
local StartAutoAA_Remote = Remotes.StartAutoAA
local EndAutoAA_Remote = Remotes.EndAutoAA
local WeatherEffects_Remote = Remotes.WeatherEffects

local Weathers = Folder.Weathers

local DefaultWeather = require(script.GetDefaultLighting)()
local WeatherCooldown = false
local WeatherID = 0
local LuckID = 0
local CurrentLuck = ""
local CurrentWeather = ""

local GlobalVotes = {[1] = {}, [2] = {}}
local ServerVotes = {[1] = {}, [2] = {}}
local Voting = false

local AutoAA = false

Players.PlayerAdded:Connect(function(Player: Player)
	if table.find(AdminList, Player.UserId) then
		local Panel = ServerStorage.UltimateAdminAbusePack.AdminAbusePanel:Clone()
		Panel.Visible = false
		Panel.Parent = Player.PlayerGui:WaitForChild("Gui"):WaitForChild("FRAMES")
		
		for _,LocalScript:LocalScript in Panel:QueryDescendants("LocalScript") do LocalScript.Enabled = true end
	end
end)

--<> { GLOBAL MESSAGES } <>--

local SendMessages = function(SenderId : number, Message : string, Times : number)
	for i = 1,Times,1 do
		GlobalMessage_Remote:FireAllClients(SenderId, Message)
		task.wait(Settings.MessageTime)
	end
end

GlobalMessage_Remote.OnServerEvent:Connect(function(Player : Player, Message : string, Times : number)
	Times = tonumber(Times)
	
	if typeof(Message) ~= "string" then
		warn("Message must be string!")
		return
	end
	if not Times or tonumber(Times) < 1 then
		warn("U must enter number between 1 - 100!")
		return
	end
	
	if table.find(AdminList, Player.UserId) then
		MessagingService:PublishAsync("GlobalMessage", {SenderId = Player.UserId, Message = Message, Times = Times})
	end
end)

MessagingService:SubscribeAsync("GlobalMessage", function(Packet)
	SendMessages(Packet.Data.SenderId, Packet.Data.Message, tonumber(Packet.Data.Times))
end)

--<> { WEATHER } <>--

local LoadLighting = function(WeatherSettings : Configuration)
	if not WeatherSettings:FindFirstChild("Lighting") then return end
	if not WeatherSettings:FindFirstChild("Model") then return end
	if not WeatherSettings:FindFirstChild("Objects") then return end
	
	StartWeather_Remote:FireAllClients()
	
	local Props = {}
	for _,Prop in WeatherSettings.Lighting:GetChildren() do
		Props[Prop.Name] = Prop.Value
	end
	
	local LightingTween = TweenService:Create(Lighting, TweenInfo.new(Settings.WeatherChangeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), Props)
	LightingTween:Play()
	
	task.wait(Settings.WeatherChangeTime / 2)
	
	Lighting:ClearAllChildren()
	for _,Object in WeatherSettings.Objects:GetChildren() do
		local Clone = Object:Clone()
		Clone.Parent = Lighting
	end
	
	if workspace:FindFirstChild("WeatherModel") then
		workspace["WeatherModel"]:Destroy()
	end
	
	local ModelClone = WeatherSettings.Model:Clone()
	ModelClone.Name = "WeatherModel"
	ModelClone.Parent = workspace
end

local ChangeWeather = function(Weather : string, Duration : number, UserId, Clear : boolean)
	if Clear then
		CurrentWeather = ""
	end
	
	if not Weather then return end
	
	if WeatherCooldown then return end
	
	local WeatherSettings = typeof(Weather) == "Instance" and Weather or Weathers:FindFirstChild(Weather)
	if not WeatherSettings then return end
	
	if Weather == CurrentWeather then
		if Duration ~= 1 then
			return
		end
	end
	
	WeatherCooldown = true
	WeatherID += 1
	CurrentWeather = Weather
	
	LoadLighting(WeatherSettings)
	WeatherStart_Bindable:Fire(Weather, Duration)
	WeatherEffects_Remote:FireAllClients(WeatherSettings, "Start")
	
	if UserId then GlobalMessage_Remote:FireAllClients(UserId, "started a " .. WeatherSettings.FullName.Value) end
	
	task.delay(3, function()
		WeatherCooldown = false
	end)
	
	local LastID = WeatherID
	task.delay(Duration, function()
		if WeatherID == LastID then
			LoadLighting(DefaultWeather)
			WeatherEnd_Bindable:Fire(Weather, Duration)
			WeatherEffects_Remote:FireAllClients(WeatherSettings, "End")
		end
	end)
end

StartWeather_Remote.OnServerEvent:Connect(function(Player : Player, Weather : string, Duration : number)
	Duration = Duration or Settings.WeatherTime
	
	if typeof(Weather) ~= "string" then
		warn("Weather must be string!")
		return
	end
	if not Duration or tonumber(Duration) < 1 then
		warn("U must enter number in seconds!")
		return
	end

	if table.find(AdminList, Player.UserId) then
		MessagingService:PublishAsync("ChangeWeather", {Weather = Weather, Duration = Duration, UserId = Player.UserId})
	end
end)

MessagingService:SubscribeAsync("ChangeWeather", function(Packet)
	ChangeWeather(Packet.Data.Weather, Packet.Data.Duration, Packet.Data.UserId)
end)

--<> { LUCK } <>--

local ChangeLuck = function(Luck : string, Duration : number, UserId)
	if Luck == CurrentLuck then
		if Duration ~= 1 then
			return
		end
	end
	
	LuckID += 1
	LuckStart_Bindable:Fire(Luck, Duration)
	if UserId and Luck then GlobalMessage_Remote:FireAllClients(UserId, "started a " .. Luck .. " luck") end
	CurrentLuck = Luck
	
	local LastID = LuckID
	task.delay(Duration, function()
		if LastID == LuckID then
			LuckEnd_Bindable:Fire(Luck, Duration)
		end
	end)
end

StartLuck_Remote.OnServerEvent:Connect(function(Player : Player, Luck : string, Duration : number)
	Duration = Duration or 120

	if typeof(Luck) ~= "string" then
		warn("Luck must be string!")
		return
	end
	if not Duration or tonumber(Duration) < 1 then
		warn("U must enter number in seconds!")
		return
	end

	if table.find(AdminList, Player.UserId) then
		MessagingService:PublishAsync("ChangeLuck", {Luck = Luck, Duration = Duration, UserId = Player.UserId})
	end
end)

MessagingService:SubscribeAsync("ChangeLuck", function(Packet)
	ChangeLuck(Packet.Data.Luck, Packet.Data.Duration, Packet.Data.UserId)
end)

--<> { BAN } <>--

local BanUser = function(UserID : number)
	local Player = Players:GetPlayerByUserId(UserID)
	if Player then
		Player:Kick(Settings.BanMessage)
	end
end

BanUser_Remote.OnServerEvent:Connect(function(Player : Player, Nickname : string)
	if typeof(Nickname) ~= "string" then
		warn("Nickname must be string!")
		return
	end
	
	local UserID = Players:GetUserIdFromNameAsync(Nickname)
	if not UserID then
		warn("Cannot find UserId!")
		return
	end
	
	if table.find(AdminList, Player.UserId) then
		BanUser_Bindable:Fire(UserID)
		MessagingService:PublishAsync("BanUser", {UserID = UserID})
	end
end)

MessagingService:SubscribeAsync("BanUser", function(Packet)
	BanUser(Packet.Data.UserID)
end)

UnbanUser_Remote.OnServerEvent:Connect(function(Player : Player, Nickname : string)
	if typeof(Nickname) ~= "string" then
		warn("Nickname must be string!")
		return
	end

	local UserID = Players:GetUserIdFromNameAsync(Nickname)
	if not UserID then
		warn("Cannot find UserId!")
		return
	end

	if table.find(AdminList, Player.UserId) then
		UnbanUser_Bindable:Fire(UserID)
	end
end)

--<> { GIVE } <>--

GiveItem_Remote.OnServerEvent:Connect(function(Player : Player, Nickname : string, Items, Brainrot)
	if typeof(Nickname) ~= "string" then
		warn("Nickname must be string!")
		return
	end
	
	local UserID = Players:GetUserIdFromNameAsync(Nickname)
	if not UserID then
		warn("Cannot find UserId!")
		return
	end
	
	if table.find(AdminList, Player.UserId) then
		GiveItem_Bindable:Fire(UserID, Items, Brainrot)
	end
end)

--<> { VOTING } <>--

local StartVoting = function(Text : string, Choises, Duration : number)
	if Voting then return end
	Voting = true
	
	ServerVotes = {[1] = {}, [2] = {}}
	GlobalVotes = {[1] = {}, [2] = {}}
	
	local Time = Duration
	
	StartVoting_Remote:FireAllClients(Text, Choises)
	VotingStart_Bindable:Fire(Text, Choises, Duration)
	
	repeat
		task.wait(2)
		if Time - 2 <= 0 then
			MessagingService:PublishAsync("NewVoting", ServerVotes)
			Vote_Remote:FireAllClients(GlobalVotes, true)
			task.delay(3, function()
				EndVoting_Remote:FireAllClients()
			end)
			VotingEnd_Bindable:Fire(Text, Choises, Duration, GlobalVotes)
			Voting = false
			break
		else
			Time -= 2
			MessagingService:PublishAsync("NewVoting", ServerVotes)
		end
		Vote_Remote:FireAllClients(GlobalVotes)
	until Time == 0
end

local ApplyChoiseVotes = function(Choise, Votes)
	local Negative = Choise == 1 and 2 or Choise == 2 and 1
	
	for i,Vote in Votes do
		if table.find(GlobalVotes[Negative], Vote) then
			table.remove(GlobalVotes[Negative], table.find(GlobalVotes[Negative], Vote))
		end
		
		if not table.find(GlobalVotes[Choise], Vote) then
			table.insert(GlobalVotes[Choise], Vote)
		end
	end
end

StartVoting_Remote.OnServerEvent:Connect(function(Player : Player, Global, Text : string, Choises, Duration : number)
	if typeof(Text) ~= "string" then
		warn("Nickname must be string!")
		return
	end
	
	if table.find(AdminList, Player.UserId) then
		if Global then
			MessagingService:PublishAsync("StartVoting", {Text = Text, Choises = Choises, Duration = Duration})
		else
			StartVoting(Text, Choises, Duration)
		end
	end
end)

MessagingService:SubscribeAsync("StartVoting", function(Packet)
	StartVoting(Packet.Data.Text, Packet.Data.Choises, Packet.Data.Duration)
end)

MessagingService:SubscribeAsync("NewVoting", function(Packet)
	if not Voting then return end
	
	ApplyChoiseVotes(1, Packet.Data[1])
	ApplyChoiseVotes(2, Packet.Data[2])
end)

Vote_Remote.OnServerEvent:Connect(function(Player : Player, Choise : number)
	if not Voting then return end
	if Choise == 1 or Choise == 2 then
		if table.find(ServerVotes[1], Player.UserId) then table.remove(ServerVotes[1], table.find(ServerVotes[1], Player.UserId)) end
		if table.find(ServerVotes[2], Player.UserId) then table.remove(ServerVotes[2], table.find(ServerVotes[2], Player.UserId)) end
		table.insert(ServerVotes[Choise], Player.UserId)
		
		if table.find(GlobalVotes[1], Player.UserId) then table.remove(GlobalVotes[1], table.find(GlobalVotes[1], Player.UserId)) end
		if table.find(GlobalVotes[2], Player.UserId) then table.remove(GlobalVotes[2], table.find(GlobalVotes[2], Player.UserId)) end
		table.insert(GlobalVotes[Choise], Player.UserId)
		
		Vote_Remote:FireAllClients(GlobalVotes)
	end
end)

--<> { AUTO AA } <>--

local GetOption = function(StartTime, ConfigTable)
	--print(ConfigTable)
	
	local Elapsed = os.time() - StartTime
	local CycleTime = 0
	
	for _, v in ConfigTable do 
		CycleTime += v.Duration 
	end
	
	if CycleTime == 0 then return nil end
	
	local Current = Elapsed % CycleTime
	local Acc = 0
	
	for _, v in ConfigTable do
		Acc += v.Duration
		if Current < Acc then
			return v.Value
		end
	end
end

local OnAutoAAStart = function(Time, Weather, Luck, UserId)
	--print(Time, Weather, Luck)
	AutoAA = true
	
	repeat
		local Weather = GetOption(Time, Weather, true)
		local Luck = GetOption(Time, Luck)
		
		ChangeWeather(Weather, 9999999999, UserId)
		ChangeLuck(Luck, 9999999999, UserId)
		
		task.wait(1)
	until not AutoAA
	
	repeat
		task.wait(0.1)
	until not WeatherCooldown
	
	ChangeWeather(DefaultWeather, 1)
	ChangeLuck(CurrentLuck, 1)
end

StartAutoAA_Remote.OnServerEvent:Connect(function(Player : Player, List)
	if table.find(AdminList, Player.UserId) then
		local Time = os.time()
		ChangeAA:Fire(Time, true, List.Weather, List.Luck, Player.UserId)
		List.Time = Time
		List.UserId = Player.UserId
		MessagingService:PublishAsync("AutoAAStart", List)
	end
end)

EndAutoAA_Remote.OnServerEvent:Connect(function(Player : Player)
	if table.find(AdminList, Player.UserId) then
		local Time = os.time()
		ChangeAA:Fire(Time, false)
		MessagingService:PublishAsync("AutoAAEnd", false)
	end
end)

MessagingService:SubscribeAsync("AutoAAStart", function(Packet)
	--print(Packet)
	OnAutoAAStart(Packet.Data.Time, Packet.Data.Weather, Packet.Data.Luck, Packet.Data.UserId)
end)

MessagingService:SubscribeAsync("AutoAAEnd", function(Packet)
	AutoAA = false
end)

local AAOpts = GetAA:Invoke()

if AAOpts.Status then
	--print(AAOpts)
	OnAutoAAStart(AAOpts.Time, AAOpts.Weather, AAOpts.Luck, AAOpts.UserId)
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Player = game.Players.LocalPlayer
local Mouse = Player:GetMouse()

local DraggingGui = Instance.new("ScreenGui", Player.PlayerGui)
DraggingGui.Name = "DraggingGui"

local Panel = script.Parent
local Main = Panel.Main
local Global = Main.Global
local Player_UI = Main.Player
local Voting = Main.Vote
local AutoAA = Main.AutoAA

local StarterMousePosition = Vector2.zero
local MouseOffset = Vector2.zero

local Hold = false
local Follow = false

local Selected = nil
local Draggable = nil

local Folder = ReplicatedStorage:WaitForChild("UltimateAdminAbusePack")

local InterfaceModule = require(Folder:WaitForChild("InterfaceModule"))
local Settings = require(Folder:WaitForChild("Settings"))

local Remotes = Folder:WaitForChild("Remotes")
local GlobalMessage_Remote = Remotes:WaitForChild("GlobalMessage")
local StartWeather_Remote = Remotes:WaitForChild("StartWeather")
local StartLuck_Remote = Remotes:WaitForChild("StartLuck")
local BanUser_Remote = Remotes:WaitForChild("BanUser")
local UnbanUser_Remote = Remotes:WaitForChild("UnbanUser")
local GiveItem_Remote = Remotes:WaitForChild("GiveItem")
local StartVoting_Remote = Remotes:WaitForChild("StartVoting")
local StartAutoAA_Remote = Remotes:WaitForChild("StartAutoAA")
local EndAutoAA_Remote = Remotes:WaitForChild("EndAutoAA")

local SelectedWeather = nil
local SelectedLuck = nil

local SelectedItems = {}

local SelectedAAWeather = {}
local SelectedAALuck = {}

--<> { TOGGLE } <>--

UserInputService.InputBegan:Connect(function(Input, GameProcessed)
	if GameProcessed then return end
	
	if Input.KeyCode.Name == Settings.Keybind then
		InterfaceModule.Switch(Panel)
	end
end)

Panel.CloseButton.Click.MouseButton1Click:Connect(function()
	InterfaceModule.Close(Panel)
end)

--<> { GLOBAL MESSAGES } <>--

Global.SendMessageButton.Click.MouseButton1Click:Connect(function()
	local Message = Global.WriteSomething.TextBox.Text
	local Times = Global.WriteSomething.Duration.Text
	
	if tonumber(Times) and tonumber(Times) > 0 and Message ~= "" then
		GlobalMessage_Remote:FireServer(Message, tonumber(Times))
	else
		GlobalMessage_Remote:FireServer(Message, 1)
	end
end)

--<> { WEATHER } <>--

local HandleWeather = function(Button : TextButton)
	Button.MouseButton1Click:Connect(function()
		local Started = SelectedWeather
		local Ended = Button.Parent
		
		if Ended == Started then return end
		
		SelectedWeather = Ended
		
		Ended.Selected.Visible = true
		if Started then
			if Started then Started.Selected.Visible = false end
		end
	end)
end

for _, Weather in Global.Weathers.Main.ScrollingFrame:GetChildren() do
	if Weather:FindFirstChildOfClass("TextButton") then
		HandleWeather(Weather:FindFirstChildOfClass("TextButton"))
	end
end

Global.Buttons.StartWeatherButton.Click.MouseButton1Click:Connect(function()
	local Duration = tonumber(Global.Weathers.Duration.Text) or Settings.WeatherTime
	if Duration and Duration > 0 then
		if SelectedWeather then StartWeather_Remote:FireServer(SelectedWeather.Name, Duration) end
	end
end)

--<> { LUCK } <>--

local HandleLuck = function(Button : TextButton)
	Button.MouseButton1Click:Connect(function()
		local Started = SelectedLuck
		local Ended = Button.Parent

		if Ended == Started then return end

		SelectedLuck = Ended

		Ended.Selected.Visible = true
		if Started then Started.Selected.Visible = false end
	end)
end

for _, Luck in Global.LuckEvents.Main.ScrollingFrame:GetChildren() do
	if Luck:FindFirstChildOfClass("TextButton") then
		HandleLuck(Luck:FindFirstChildOfClass("TextButton"))
	end
end

Global.Buttons.StartLuckEventButton.Click.MouseButton1Click:Connect(function()
	local Duration = tonumber(Global.LuckEvents.Duration.Text) or 120
	if Duration and Duration > 0 then
		if SelectedLuck then StartLuck_Remote:FireServer(SelectedLuck.Name, Duration) end
	end
end)

--<> { BAN } <>--

Player_UI.Buttons.BanPlayerButton.Click.MouseButton1Click:Connect(function()
	local Nickname = Player_UI.Username.TextBox.Text
	if Nickname == "" then return end
	BanUser_Remote:FireServer(Nickname)
end)

Player_UI.Buttons.UnbanPlayerButton.Click.MouseButton1Click:Connect(function()
	local Nickname = Player_UI.Username.TextBox.Text
	if Nickname == "" then return end
	UnbanUser_Remote:FireServer(Nickname)
end)

--<> { GIVE } <>--

local HandleItemButton = function(Item : Frame)
	Item.Click.MouseButton1Click:Connect(function()
		if not table.find(SelectedItems, Item.Name) then
			table.insert(SelectedItems, Item.Name)
			Item.Selected.Visible = true
		else
			table.remove(SelectedItems, table.find(SelectedItems, Item.Name))
			Item.Selected.Visible = false
		end
	end)
end

for _, Item : Frame in Player_UI.Items.Main.ScrollingFrame:GetChildren() do
	if Item:FindFirstChildOfClass("TextButton") then
		HandleItemButton(Item)
	end
end

Player_UI.SendItemButton.Click.MouseButton1Click:Connect(function()
	local Nickname = Player_UI.Username.TextBox.Text
	if Nickname == "" then return end
	
	local AmountOfItems = tonumber(Player_UI.Items.Amount.Text)
	if AmountOfItems == nil then AmountOfItems = 0 end
	
	local AmountOfBrainrots = tonumber(Player_UI.EnterBrainrotToolName.Amount.Text)
	if AmountOfBrainrots == nil then AmountOfBrainrots = 0 end
	
	local BrainrotName = Player_UI.EnterBrainrotToolName.TextBox.Text
	
	local Items = {
		List = SelectedItems,
		Amount = AmountOfItems
	}
	local Brainrot = {
		Name = BrainrotName,
		Amount = AmountOfBrainrots
	}
	
	GiveItem_Remote:FireServer(Nickname, Items, Brainrot)
end)

--<> { VOTING } <>--

local GetOptions = function()
	local Options = {}
	Options.Choices = {
		[1] = Voting.Buttons1.Choice1.TextBox.Text,
		[2] = Voting.Buttons1.Choice2.TextBox.Text
	}
	Options.Text = Voting.VoteName.TextBox.Text
	Options.Duration = tonumber(Voting.VoteName.Duration.Text) or 60
	return Options
end

Voting.Buttons2.GlobalButton.Click.MouseButton1Click:Connect(function()
	local Options = GetOptions()
	if Options.Choices[1] == "" or Options.Choices[2] == "" then return end
	if Options.Text == "" then return end
	StartVoting_Remote:FireServer(true, Options.Text, Options.Choices, Options.Duration)
end)

Voting.Buttons2.ServerButton.Click.MouseButton1Click:Connect(function()
	local Options = GetOptions()
	if Options.Choices[1] == "" or Options.Choices[2] == "" then return end
	if Options.Text == "" then return end
	StartVoting_Remote:FireServer(false, Options.Text, Options.Choices, Options.Duration)
end)

--<> { AUTO AA } <>--

local GetListOf = function(Parent)
	local List = {}
	for _,v in Parent:GetChildren() do
		if v:FindFirstChildOfClass("TextButton") then
			List[v.LayoutOrder] = {Value = v.Name, Duration = tonumber(v.Duration.Text) or Settings.WeatherTime}
		end
	end
	return List
end

AutoAA.Buttons.StartButton.Click.MouseButton1Click:Connect(function()
	local List = {
		Weather = GetListOf(AutoAA.Weathers.Main.ScrollingFrame),
		Luck = GetListOf(AutoAA.LuckEvents.Main.ScrollingFrame)
	}
	
	for _,v in List.Weather do
		if not table.find(SelectedAAWeather, v.Value) then
			v.Duration = 0
		end
	end
	for _,v in List.Luck do
		if not table.find(SelectedAALuck, v.Value) then
			v.Duration = 0
		end
	end
	
	StartAutoAA_Remote:FireServer(List)
end)

AutoAA.Buttons.StopButton.Click.MouseButton1Click:Connect(function()
	EndAutoAA_Remote:FireServer()
end)

local HandleWeatherAA = function(Button : TextButton)
	Button.MouseButton1Click:Connect(function()
		if table.find(SelectedAAWeather, Button.Parent.Name) then
			table.remove(SelectedAAWeather, table.find(SelectedAAWeather, Button.Parent.Name))
			Button.Parent.Selected.Visible = false
		else
			table.insert(SelectedAAWeather, Button.Parent.Name)
			Button.Parent.Selected.Visible = true
		end
	end)
end

for _, Weather in AutoAA.Weathers.Main.ScrollingFrame:GetChildren() do
	if Weather:FindFirstChildOfClass("TextButton") then
		HandleWeatherAA(Weather:FindFirstChildOfClass("TextButton"))
	end
end

local HandleLuckAA = function(Button : TextButton)
	Button.MouseButton1Click:Connect(function()
		if table.find(SelectedAALuck, Button.Parent.Name) then
			table.remove(SelectedAALuck, table.find(SelectedAALuck, Button.Parent.Name))
			Button.Parent.Selected.Visible = false
		else
			table.insert(SelectedAALuck, Button.Parent.Name)
			Button.Parent.Selected.Visible = true
		end
	end)
end

for _, Luck in AutoAA.LuckEvents.Main.ScrollingFrame:GetChildren() do
	if Luck:FindFirstChildOfClass("TextButton") then
		HandleLuckAA(Luck:FindFirstChildOfClass("TextButton"))
	end
end

--<> { OTHER } <>--

UserInputService.InputBegan:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 then
		for _, Object:GuiObject in Player.PlayerGui:GetGuiObjectsAtPosition(Mouse.X, Mouse.Y) do
			if Object.Parent == Main.AutoAA.Weathers.Main.ScrollingFrame and Object.LayoutOrder > 0 and Object.LayoutOrder < 100 then
				StarterMousePosition = Vector2.new(Mouse.X, Mouse.Y)
				Selected = Object
				MouseOffset = StarterMousePosition - Selected.AbsolutePosition
				Hold = true
				break
			end
		end
	end
end)

UserInputService.InputChanged:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseMovement then
		if Hold and not Follow and (Vector2.new(Mouse.X, Mouse.Y) - StarterMousePosition).Magnitude > 10 then
			Follow = true
			
			Draggable = Selected:Clone()
			Draggable.Size = UDim2.fromOffset(Selected.AbsoluteSize.X, Selected.AbsoluteSize.Y)
			Draggable.Parent = DraggingGui
			
			if Draggable:FindFirstChildOfClass("UIScale") then
				Draggable:FindFirstChildOfClass("UIScale").Scale = 1
				Draggable:FindFirstChildOfClass("UIScale"):Destroy()
			end
			
			Draggable.Position = UDim2.fromOffset(Mouse.X - MouseOffset.X, Mouse.Y - MouseOffset.Y)
			Selected.Visible = false
			
			for _,Object:Frame in Selected.Parent:GetChildren() do
				if Object:IsA("Frame") and Object.LayoutOrder > 0 and Object.LayoutOrder < 100  then
					if Object.LayoutOrder > Selected.LayoutOrder then
						Object.LayoutOrder -= 1
					end
				end
			end
			
		elseif Hold and Follow and Draggable then
			Draggable.Position = UDim2.fromOffset(Mouse.X - MouseOffset.X, Mouse.Y - MouseOffset.Y)
		end
	end
end)

UserInputService.InputEnded:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseButton1 then
		Hold = false
		
		if Follow then
			Follow = false
			
			Draggable:Destroy()
			Draggable = nil
			
			local ObjectAmount = 0
			
			for _,Object:Frame in Selected.Parent:GetChildren() do
				if Object:IsA("Frame") and Object.LayoutOrder > 0 and Object.LayoutOrder < 100 and Object.Visible then
					ObjectAmount += 1
				end
			end
			
			for _,Object:Frame in Selected.Parent:GetChildren() do
				if Object:IsA("Frame") and Object.LayoutOrder > 0 and Object.LayoutOrder < 100 and Object.Visible then
					local middle = Object.AbsolutePosition + (Object.AbsoluteSize/2)
					
					if Object.LayoutOrder == ObjectAmount then
						if Mouse.X >= middle.X then
							Selected.LayoutOrder = ObjectAmount + 1
							Selected.Visible = true
							break
						end
					else
						if Object.LayoutOrder == 1 then
							if Mouse.X <= middle.X then
								for _,AnotherObject:Frame in Selected.Parent:GetChildren() do
									if AnotherObject:IsA("Frame") and AnotherObject.LayoutOrder > 0 and AnotherObject.LayoutOrder < 100 and Object.Visible then
										AnotherObject.LayoutOrder += 1
									end
								end

								Selected.LayoutOrder = 1
								Selected.Visible = true
								break
							end
						end
						
						if Mouse.X >= middle.X then
							local SecondObject 

							task.wait()

							for _,NextObject:Frame in Selected.Parent:GetChildren() do
								if NextObject:IsA("Frame") and NextObject.LayoutOrder > 0 and NextObject.LayoutOrder < 100 and Object.Visible then
									if NextObject.LayoutOrder == Object.LayoutOrder + 1 then SecondObject = NextObject end
								end
							end

							if not SecondObject then
								Selected.LayoutOrder = ObjectAmount + 1
								Selected.Visible = true

							elseif Mouse.X >= middle.X and Mouse.X <= (SecondObject.AbsolutePosition + (SecondObject.AbsoluteSize/2)).X then
								for _,AnotherObject:Frame in Selected.Parent:GetChildren() do
									if AnotherObject:IsA("Frame") and AnotherObject.LayoutOrder > 0 and AnotherObject.LayoutOrder < 100 and Object.Visible then
										if AnotherObject.LayoutOrder > Object.LayoutOrder then
											AnotherObject.LayoutOrder += 1
										end
									end
								end 

								Selected.LayoutOrder = Object.LayoutOrder + 1
								Selected.Visible = true
								break
							end
						end
					end
				end
			end
		end
	end
end)


task.delay(3, InterfaceModule.NotifyAdmin)

for _,Button:GuiObject in Panel.Buttons.Main:GetChildren() do
	if Button:FindFirstChildOfClass("TextButton") then
		Button:FindFirstChildOfClass("TextButton").MouseButton1Click:Connect(function()
			for _,Container in Panel.Main:GetChildren() do
				if Container:IsA("Frame") then
					Container.Visible = false
				end
			end
			Panel.Main:FindFirstChild(Button.Name).Visible = true
		end)
	end
end
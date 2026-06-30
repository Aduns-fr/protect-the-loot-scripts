local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Folder = ReplicatedStorage:WaitForChild("UltimateAdminAbusePack")

local Module = {}

local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui

local Settings = require(Folder:WaitForChild("Settings"))

Module.Open = function(Frame: GuiObject)
	if Frame.Visible then return end
	
	local UIScale = Frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", Frame)
	local Tween = TweenService:Create(UIScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	
	UIScale.Scale = 0.6
	Frame.Visible = true
	
	Tween:Play()
	Tween.Completed:Wait()
end

Module.Close = function(Frame: GuiObject)
	if not Frame.Visible then return end
	
	local UIScale = Frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", Frame)
	local Tween = TweenService:Create(UIScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.4})
	
	UIScale.Scale = 1
	
	Tween:Play()
	Tween.Completed:Wait()
	
	Frame.Visible = false
end

Module.Switch = function(Frame: GuiObject)
	if Frame.Visible then
		Module.Close(Frame)
	else
		Module.Open(Frame)
	end
end

Module.LoadText = function(Frame: TextLabel|TextButton, Text: string)
	task.spawn(function()
		for i = 1, string.len(Text) do 
			Frame.Text = string.sub(Text, 1, i)
			task.wait(0.05)
		end
	end)
end

Module.OnButton = function(Button: GuiObject)
	task.spawn(function()		
		if not Button:FindFirstChildOfClass("TextButton") then return end

		local UIScale = Button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", Button)

		Button:FindFirstChildOfClass("TextButton").MouseButton1Down:Connect(function()
			TweenService:Create(UIScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Scale = 0.9}):Play()
		end)

		Button:FindFirstChildOfClass("TextButton").MouseButton1Up:Connect(function()
			TweenService:Create(UIScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Scale = 1.1}):Play()
			local sfx = SoundService:FindFirstChild("SFX"); local click = sfx and sfx:FindFirstChild("ClickSound"); if click then click:Play() end
		end)

		Button:FindFirstChildOfClass("TextButton").MouseEnter:Connect(function()
			TweenService:Create(UIScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Scale = 1.1}):Play()
		end)

		Button:FindFirstChildOfClass("TextButton").MouseLeave:Connect(function()
			TweenService:Create(UIScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Scale = 1}):Play()
		end)
	end)
end

Module.NotifyAdmin = function()
	local Text = "~ "..Settings.Keybind.." ~ Open Admin Abuse Panel"
	local Frame = PlayerGui:WaitForChild("Gui"):WaitForChild("OTHER"):WaitForChild("OpenAdminAbusePanelInfo")
	
	Frame.Position = UDim2.fromScale(0.5,1)
	Frame.Visible = true
	Frame.OpenAdminAbusePanelTemplate.Info.Text = ""
	
	TweenService:Create(Frame, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.5,0.95)}):Play()
	Module.LoadText(Frame.OpenAdminAbusePanelTemplate.Info, Text)
	task.wait(3)
	TweenService:Create(Frame, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Position = UDim2.fromScale(0.5,1)}):Play()
end

Module.WeatherTransition = function()
	local TransitionFrame = PlayerGui:QueryDescendants('.Transition')[1]
	if not TransitionFrame then return end
	
	local InTween = TweenService:Create(TransitionFrame, TweenInfo.new(Settings.WeatherChangeTime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {GroupTransparency = 0})
	local OutTween = TweenService:Create(TransitionFrame, TweenInfo.new(Settings.WeatherChangeTime / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {GroupTransparency = 1})
	
	local Connection : RBXScriptConnection
	Connection = RunService.Heartbeat:Connect(function()
		TransitionFrame.Shadow:FindFirstChildOfClass("UIGradient").Rotation += 5
	end)
	
	TransitionFrame.GroupTransparency = 1
	TransitionFrame.Visible = true
	
	InTween:Play()
	InTween.Completed:Wait()
	
	--task.wait(Settings.WeatherChangeTime / 2)
	
	OutTween:Play()
	OutTween.Completed:Wait()
	
	TransitionFrame.Visible = false
	
	Connection:Disconnect()
	Connection = nil
end

return RunService:IsClient() and Module or {}

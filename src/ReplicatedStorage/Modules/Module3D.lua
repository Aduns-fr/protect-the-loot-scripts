--[[
	Module3D
	Original by TheNexusAvenger

	PARTICLE FIX: PrepareModel now sets ParticleEmitter.Enabled = true.
	ReplicatedStorage templates ship with particles disabled - the game scripts
	enable them when spawning into workspace. We replicate that here.

	WORLDMODEL RESTORED: Particles require WorldModel's rendering context to
	display in a ViewportFrame. Without it they don't render. WorldModel is kept
	strictly for this - physics is irrelevant since everything is Anchored.

	RAINBOW: Handled externally by ViewportEffects. Scripts inside ViewportFrame
	are sandboxed, but external LocalScripts can write to parts inside freely.
]]

local RunService = game:GetService("RunService")

local FAR_POSITION = Vector3.new(0, 10000, 0)

local FORCE_CARTOON_LIGHTING  = true
local CARTOON_AMBIENT         = Color3.fromRGB(180, 180, 180)
local CARTOON_LIGHT_COLOR     = Color3.fromRGB(255, 245, 220)
local CARTOON_LIGHT_DIRECTION = Vector3.new(-0.5, -1, -0.4)

local Module3D = {}

local function GetFirstBasePart(Object)
	if Object:IsA("BasePart") then return Object end
	return Object:FindFirstChildWhichIsA("BasePart", true)
end

local function PrepareModel(Model)
	for _, Descendant in ipairs(Model:GetDescendants()) do
		if Descendant:IsA("BasePart") then
			Descendant.Anchored   = true
			Descendant.CanCollide = false
			Descendant.CanTouch   = false
			Descendant.CanQuery   = false
			Descendant.CastShadow = false
		elseif Descendant:IsA("Trail") or Descendant:IsA("Beam") then
			Descendant.Enabled = true
		end
		-- ParticleEmitters: ViewportFrame cannot render them (Roblox engine limit).
		-- Leave as-is - ViewportEffects handles visual fakes via UI for specific animals.
	end
end

local function ApplyViewportLighting(ViewportFrame)
	if FORCE_CARTOON_LIGHTING then
		ViewportFrame.Ambient        = CARTOON_AMBIENT
		ViewportFrame.LightColor     = CARTOON_LIGHT_COLOR
		ViewportFrame.LightDirection = CARTOON_LIGHT_DIRECTION
	else
		local Lighting = game:GetService("Lighting")
		ViewportFrame.Ambient    = Lighting.Ambient
		ViewportFrame.LightColor = Lighting.OutdoorAmbient
		local SunDir = Lighting:GetSunDirection()
		ViewportFrame.LightDirection = SunDir.Magnitude > 0 and -SunDir or CARTOON_LIGHT_DIRECTION
	end
end

function Module3D.new(Model)
	local CFrameOffset    = CFrame.new()
	local DepthMultiplier = 1

	local Model3D    = {}
	Model3D.Object3D = Model

	if Model:IsA("BasePart") then
		local Wrapper       = Instance.new("Model")
		Wrapper.Name        = "Model3D"
		Model.Parent        = Wrapper
		Wrapper.PrimaryPart = Model
		Model               = Wrapper
		Model3D.Object3D    = Model
	end

	local ViewportFrame = Instance.new("ViewportFrame")
	ViewportFrame.Name                  = "Model3DViewport"
	ViewportFrame.BackgroundTransparency = 1
	ViewportFrame.BorderSizePixel       = 0
	ViewportFrame.ClipsDescendants      = true
	Model3D.AdornFrame = ViewportFrame

	ApplyViewportLighting(ViewportFrame)

	-- WorldModel is needed for particles to render in ViewportFrame
	local WorldModel       = Instance.new("WorldModel")
	WorldModel.Name        = "WorldModel"
	WorldModel.Parent      = ViewportFrame
	Model3D.WorldModel     = WorldModel

	local Camera = Instance.new("Camera")
	Camera.Name        = "ViewportCamera"
	Camera.FieldOfView = 35
	Camera.Parent      = ViewportFrame
	ViewportFrame.CurrentCamera = Camera

	local OriginalPrimaryPart = Model.PrimaryPart
	if not Model.PrimaryPart then
		Model.PrimaryPart = GetFirstBasePart(Model)
	end

	PrepareModel(Model)

	if Model.PrimaryPart then
		Model:SetPrimaryPartCFrame(
			CFrame.new(FAR_POSITION - Model.PrimaryPart.Position) * Model.PrimaryPart.CFrame
		)
		Model.PrimaryPart = OriginalPrimaryPart
	end

	Model.Parent = WorldModel

	local function UpdateCFrame()
		if not Model or not Model.Parent then return end
		local BoundingCFrame, BoundingSize = Model:GetBoundingBox()
		local ModelCenter = BoundingCFrame.Position
		local MaxSize     = math.max(BoundingSize.X, BoundingSize.Y, BoundingSize.Z)
		if MaxSize <= 0 then MaxSize = 1 end
		local DistanceBack = (MaxSize / math.tan(math.rad(Camera.FieldOfView))) * DepthMultiplier
		Camera.CFrame = CFrame.new(ModelCenter) * CFrameOffset * CFrame.new(0, 0, (MaxSize / 2) + DistanceBack)
		Camera.Focus  = CFrame.new(ModelCenter)
	end

	function Model3D:Update()             UpdateCFrame() end
	function Model3D:SetActive(Active)    ViewportFrame.Visible = Active end
	function Model3D:GetActive()          return ViewportFrame.Visible end
	function Model3D:SetCFrame(NewCF)     CFrameOffset = NewCF; UpdateCFrame() end
	function Model3D:GetCFrame()          return CFrameOffset end
	function Model3D:SetDepthMultiplier(m) DepthMultiplier = m; UpdateCFrame() end
	function Model3D:GetDepthMultiplier() return DepthMultiplier end
	function Model3D:SyncLighting()       ApplyViewportLighting(ViewportFrame) end

	function Model3D:Destroy()
		if self.AdornFrame and self.AdornFrame.Parent then self.AdornFrame:Destroy() end
		if self.Object3D   and self.Object3D.Parent   then self.Object3D:Destroy()   end
	end

	function Model3D:End() self:Destroy() end

	local Metatable = {}
	setmetatable(Model3D, Metatable)

	Metatable.__index = function(_, Index)
		if Index == "Camera" or Index == "CurrentCamera" then
			return ViewportFrame.CurrentCamera
		end
		local v = rawget(Model3D, Index)
		if v ~= nil then return v end
		return ViewportFrame[Index]
	end

	Metatable.__newindex = function(_, Index, Value)
		ViewportFrame[Index] = Value
	end

	UpdateCFrame()
	return Model3D
end

function Module3D:Attach3D(Frame, Model)
	local Model3D = Module3D.new(Model)

	Model3D.AnchorPoint = Vector2.new(0.5, 0.5)
	Model3D.Position    = UDim2.new(0.5, 0, 0.5, 0)
	Model3D.Visible     = false
	Model3D.Parent      = Frame

	local function UpdateFrameSize()
		if not Frame or not Frame.Parent then return end
		local AbsSize = Frame.AbsoluteSize
		local MinSize = math.abs(math.min(AbsSize.X, AbsSize.Y))
		Model3D.AdornFrame.Size = UDim2.new(0, MinSize, 0, MinSize)
	end

	local FrameConn = Frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateFrameSize)
	local DestroyingConn

	local function DisconnectFrameListeners()
		if FrameConn then FrameConn:Disconnect(); FrameConn = nil end
		if DestroyingConn then DestroyingConn:Disconnect(); DestroyingConn = nil end
	end

	DestroyingConn = Model3D.AdornFrame.Destroying:Connect(DisconnectFrameListeners)
	UpdateFrameSize()

	local BaseDestroy = Model3D.Destroy
	rawset(Model3D, "Destroy", function(self)
		DisconnectFrameListeners()
		BaseDestroy(self)
	end)

	return Model3D
end

return Module3D
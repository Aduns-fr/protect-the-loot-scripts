--!strict
-- LMB drag to draw | RMB drag to move | E to delete | Q to toggle

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local ShapeDetector = require(script.Parent:WaitForChild("ShapeDetector"))
local Generator = require(script.Parent:WaitForChild("Generator"))
local Smoothing = require(script.Parent:WaitForChild("Smoothing"))
local Manipulator = require(script.Parent:WaitForChild("Manipulator"))

local SAMPLE_INTERVAL = 1.5
local MIN_DRAW_TIME = 0.1
local BUILDING_HEIGHT = 8

local Container = Workspace:FindFirstChild("ProceduralBuilds") or Instance.new("Folder")
Container.Name = "ProceduralBuilds"
Container.Parent = Workspace

local Preview = Workspace:FindFirstChild("_DrawPreview") or Instance.new("Folder")
Preview.Name = "_DrawPreview"
Preview.Parent = Workspace

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = {Container, Preview, character}
rayParams.IgnoreWater = false

LocalPlayer.CharacterAdded:Connect(function(c)
	rayParams.FilterDescendantsInstances = {Container, Preview, c}
end)

local function castMouse()
	local mp = UIS:GetMouseLocation()
	local r = Camera:ViewportPointToRay(mp.X, mp.Y)
	return Workspace:Raycast(r.Origin, r.Direction * 2000, rayParams)
end

local function groundY(x, z, fromY)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local excludes = {Container, Preview}
	local handles = Workspace:FindFirstChild("_Handles")
	if handles then table.insert(excludes, handles) end
	if LocalPlayer.Character then table.insert(excludes, LocalPlayer.Character) end
	rp.FilterDescendantsInstances = excludes
	rp.IgnoreWater = false
	local r = Workspace:Raycast(Vector3.new(x, fromY + 500, z), Vector3.new(0, -2000, 0), rp)
	return r and r.Position.Y or nil
end

-- Draw state
local drawMode = true
local drawing = false
local drawStart = 0
local points: {Vector3} = {}
local lastP: Vector3? = nil

local function clearPreview() Preview:ClearAllChildren() end

local function dot(pos)
	local d = Instance.new("Part")
	d.Anchored = true
	d.CanCollide = false
	d.Size = Vector3.new(0.6, 0.6, 0.6)
	d.Shape = Enum.PartType.Ball
	d.Color = Color3.fromRGB(255, 220, 0)
	d.Material = Enum.Material.Neon
	d.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0))
	d.Parent = Preview
end

-- Trace a fading neon line along the smoothed path
local function tracePath(points, closed)
	local lineFolder = Instance.new("Folder")
	lineFolder.Name = "_PathTrace"
	lineFolder.Parent = Preview

	local lastIdx = if closed then #points else #points - 1
	for i = 1, lastIdx do
		local a = points[i]
		local b = points[(i % #points) + 1]
		local mid = (a + b) / 2
		local diff = b - a
		local len = diff.Magnitude
		if len > 0.001 then
			local seg = Instance.new("Part")
			seg.Anchored = true
			seg.CanCollide = false
			seg.Material = Enum.Material.Neon
			seg.Color = Color3.fromRGB(80, 255, 180)
			seg.Size = Vector3.new(len, 0.25, 0.25)
			local horiz = Vector3.new(diff.X, 0, diff.Z)
			if horiz.Magnitude < 0.001 then horiz = Vector3.new(1,0,0) else horiz = horiz.Unit end
			local up = Vector3.new(0,1,0)
			local fwd = up:Cross(horiz).Unit
			seg.CFrame = CFrame.fromMatrix(mid + Vector3.new(0, 0.5, 0), horiz, up, -fwd)
			seg.Parent = lineFolder
		end
	end

	task.spawn(function()
		local steps = 12
		for i = 1, steps do
			local t = i / steps
			for _, part in lineFolder:GetChildren() do
				if part:IsA("BasePart") then
					part.Transparency = t
				end
			end
			task.wait(0.8 / steps)
		end
		lineFolder:Destroy()
	end)
end

-- Per-model state: mutable params + setter API used by Manipulator
type ModelParams = {
	path: {Vector3}?,       -- world-space path; walls only (after yaw applied)
	size: Vector3?,         -- buildings (Y mutable via setHeight)
	radius: number?,        -- circles
	height: number?,        -- walls (default Generator.WALL_DEFAULT_HEIGHT)
	center: Vector3,        -- world anchor (model center on ground)
	controlPoints: {Vector3}?, -- sparse editable wall curve controls (in REST orientation, yaw=0)
	yaw: number,            -- radians, rotation around vertical axis through center
}
type ModelState = {
	shapeType: string,
	params: ModelParams,
	-- For Manipulator (compat with Wall via .path passthrough)
	path: {Vector3}?,
	setHeight: (number) -> (),
	setRadius: ((number) -> ())?,
	setSize: ((Vector3) -> ())?,
	setCenter: (Vector3) -> (),
	setPathPoint: (number, Vector3) -> (),
	setYaw: (number) -> (),
	addPathPoint: ((Vector3) -> ())?,
	removePathPoint: ((number) -> ())?,
}
local state: {[Instance]: ModelState} = {}

-- Build wall parts in the container. Path is in world coords; we translate to
-- local space by subtracting `origin`, then offset each built part by `origin`.
local function buildWall(model, container, path, origin)
	container:ClearAllChildren()
	Generator.OnGenerate({
		Size = Vector3.zero,
		ShapeType = "Wall",
		Path = path,
		Origin = origin,
	}, container)
	for _, p in container:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = CFrame.new(origin) * p.CFrame
		end
	end
end

local function buildBuilding(model, container, worldCF, size)
	container:ClearAllChildren()
	Generator.OnGenerate({
		Size = size,
		ShapeType = "Building",
		FloorOffsets = model:GetAttribute("FloorOffsets"),
		Thickness = model:GetAttribute("Thickness"),
	}, container)
	for _, p in container:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = worldCF * p.CFrame
		end
	end
end

local function conformBuilding(model, worldCF, size)
	local hx, hz = size.X/2, size.Z/2
	local baseY = worldCF.Position.Y - size.Y/2
	local corners = {
		worldCF:PointToWorldSpace(Vector3.new(-hx, -size.Y/2,  hz)),
		worldCF:PointToWorldSpace(Vector3.new( hx, -size.Y/2,  hz)),
		worldCF:PointToWorldSpace(Vector3.new(-hx, -size.Y/2, -hz)),
		worldCF:PointToWorldSpace(Vector3.new( hx, -size.Y/2, -hz)),
	}
	local strs = {}
	for _, c in corners do
		local gy = groundY(c.X, c.Z, c.Y + 100)
		local off = gy and (gy - baseY) or 0
		table.insert(strs, string.format("%.2f", off))
	end
	model:SetAttribute("FloorOffsets", table.concat(strs, ","))
end

local function buildWallWithHeight(container, path, height)
	container:ClearAllChildren()
	Generator.OnGenerate({
		Size = Vector3.zero,
		ShapeType = "Wall",
		Path = path,
		Origin = Vector3.zero,
		Height = height,
	}, container)
end

-- Rotate a list of points around `pivot` by `yaw` radians (around vertical axis).
local function rotatePointsYaw(points: {Vector3}, pivot: Vector3, yaw: number): {Vector3}
	if math.abs(yaw) < 1e-5 then return points end
	local cs = math.cos(yaw)
	local sn = math.sin(yaw)
	local out = {}
	for _, p in points do
		local dx = p.X - pivot.X
		local dz = p.Z - pivot.Z
		table.insert(out, Vector3.new(
			pivot.X + dx * cs - dz * sn,
			p.Y,
			pivot.Z + dx * sn + dz * cs
		))
	end
	return out
end

local function buildCurveFromControls(controlPoints: {Vector3})
	local path = {}
	if #controlPoints < 2 then return controlPoints end
	for i = 1, #controlPoints - 1 do
		local p0 = controlPoints[math.max(1, i - 1)]
		local p1 = controlPoints[i]
		local p2 = controlPoints[i + 1]
		local p3 = controlPoints[math.min(#controlPoints, i + 2)]
		local segLen = (p2 - p1).Magnitude
		local steps = math.clamp(math.floor(segLen / 2), 3, 10)
		for j = 0, steps - 1 do
			local t = j / steps
			local t2 = t * t
			local t3 = t2 * t
			local point = (p1 * 2
				+ (p2 - p0) * t
				+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
				+ (-p0 + p1 * 3 - p2 * 3 + p3) * t3) * 0.5
			table.insert(path, point)
		end
	end
	table.insert(path, controlPoints[#controlPoints])
	return path
end

local function makeControlPointsFromPath(path: {Vector3})
	local controls = {}
	local count = #path
	local maxControls = 9
	local step = math.max(1, math.floor(count / (maxControls - 1)))
	for i = 1, count, step do
		table.insert(controls, path[i])
	end
	if controls[#controls] ~= path[count] then
		table.insert(controls, path[count])
	end
	return controls
end

local function pathCenter(path: {Vector3})
	local minV, maxV = path[1], path[1]
	for i = 2, #path do
		local p = path[i]
		minV = Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
		maxV = Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
	end
	return (minV + maxV) / 2
end

local function spawnWall(result, rawPath)
	local groundedPath: {Vector3} = {}
	for _, p in rawPath do
		local gy = groundY(p.X, p.Z, p.Y + 100) or p.Y
		table.insert(groundedPath, Vector3.new(p.X, gy, p.Z))
	end

	local model = Instance.new("Model")
	model.Name = "Wall_" .. tostring(os.time())
	model:SetAttribute("ShapeType", "Wall")

	local container = Instance.new("Folder")
	container.Name = "GeneratedFolder"
	container.Parent = model
	model.Parent = Container

	-- Initial control points: take the smoothed/grounded path and resample at
	-- ~4-stud arc-length intervals, so the user starts with a manageable number
	-- of handles. They can add more or remove freely afterward.
	local function thin(pathPts, interval)
		local out = {pathPts[1]}
		local last = pathPts[1]
		for i = 2, #pathPts - 1 do
			if (pathPts[i] - last).Magnitude >= interval then
				table.insert(out, pathPts[i])
				last = pathPts[i]
			end
		end
		if #pathPts > 1 then
			if (pathPts[#pathPts] - out[#out]).Magnitude > 0.001 then
				table.insert(out, pathPts[#pathPts])
			end
		end
		return out
	end
	local controls = thin(groundedPath, 8)
	local smoothPath = buildCurveFromControls(controls)

	local params: ModelParams = {
		path = smoothPath,
		size = nil,
		radius = nil,
		height = Generator.WALL_DEFAULT_HEIGHT,
		center = pathCenter(smoothPath),
		controlPoints = controls,
		yaw = 0,
	}

	local function rebuild()
		-- Yaw is a LIVE offset: controlPoints stay in rest pose, path = rotated.
		local restPath = buildCurveFromControls(params.controlPoints)
		local restCenter = pathCenter(restPath)
		params.center = if math.abs(params.yaw) < 1e-5 then restCenter
			else rotatePointsYaw({restCenter}, restCenter, params.yaw)[1]
		params.path = if math.abs(params.yaw) < 1e-5 then restPath
			else rotatePointsYaw(restPath, restCenter, params.yaw)
		buildWallWithHeight(container, params.path, params.height)
	end

	local s: ModelState
	s = {
		shapeType = "Wall",
		params = params,
		path = smoothPath,
		setHeight = function(h)
			params.height = h
			rebuild()
		end,
		setCenter = function(newCenter)
			if not params.controlPoints or #params.controlPoints < 2 then return end
			local delta = Vector3.new(newCenter.X - params.center.X, 0, newCenter.Z - params.center.Z)
			if delta.Magnitude < 0.001 then return end
			for i, p in params.controlPoints do
				local np = p + delta
				local gy = groundY(np.X, np.Z, np.Y + 100) or np.Y
				params.controlPoints[i] = Vector3.new(np.X, gy, np.Z)
			end
			rebuild()
			s.path = params.path
		end,
		setPathPoint = function(idx, newPoint)
			if not params.controlPoints or not params.controlPoints[idx] then return end
			-- newPoint comes from manipulator in ROTATED world coords. Un-rotate to rest pose.
			local restCenter = pathCenter(buildCurveFromControls(params.controlPoints))
			local unrotated = rotatePointsYaw({newPoint}, restCenter, -params.yaw)[1]
			local gy = groundY(unrotated.X, unrotated.Z, unrotated.Y + 100) or unrotated.Y
			params.controlPoints[idx] = Vector3.new(unrotated.X, gy, unrotated.Z)
			rebuild()
			s.path = params.path
		end,
		setYaw = function(y)
			-- Keep yaw as a live offset.  ControlPoints stay in rest pose.  Path + handles get rotated on rebuild.
			params.yaw = y
			rebuild()
			s.path = params.path
		end,
		addPathPoint = function(worldPos)
			local cps = params.controlPoints
			if not cps or #cps < 2 then return end
			-- worldPos in ROTATED coords; un-rotate to rest pose.
			local restCenter = pathCenter(buildCurveFromControls(cps))
			local unrotated = rotatePointsYaw({worldPos}, restCenter, -params.yaw)[1]
			local bestIdx = 1
			local bestDist = math.huge
			for i = 1, #cps - 1 do
				local a, b = cps[i], cps[i+1]
				local abx, abz = b.X - a.X, b.Z - a.Z
				local apx, apz = unrotated.X - a.X, unrotated.Z - a.Z
				local abLen2 = abx*abx + abz*abz
				local t = if abLen2 > 0.001 then math.clamp((apx*abx + apz*abz) / abLen2, 0, 1) else 0
				local cx = a.X + abx * t
				local cz = a.Z + abz * t
				local dx = unrotated.X - cx
				local dz = unrotated.Z - cz
				local d = dx*dx + dz*dz
				if d < bestDist then
					bestDist = d
					bestIdx = i
				end
			end
			local gy = groundY(unrotated.X, unrotated.Z, unrotated.Y + 100) or unrotated.Y
			table.insert(params.controlPoints, bestIdx + 1, Vector3.new(unrotated.X, gy, unrotated.Z))
			rebuild()
			s.path = params.path
		end,
		removePathPoint = function(idx)
			local cps = params.controlPoints
			if not cps or #cps <= 2 then return end
			if idx < 1 or idx > #cps then return end
			table.remove(cps, idx)
			rebuild()
			s.path = params.path
		end,
	}
	state[model] = s

	model.Destroying:Connect(function() state[model] = nil end)

	rebuild()

	print(string.format("[RobloxProceduralModel] Spawned Wall  bricks=%d  pathPoints=%d",
		#container:GetChildren(), #groundedPath))
end

local function spawnBuilding(result)
	local sx = math.max(2, result.bboxSize.X)
	local sz = math.max(2, result.bboxSize.Z)
	local cgy = groundY(result.bboxCenter.X, result.bboxCenter.Z, result.bboxCenter.Y + 100)
		or result.bboxCenter.Y

	local model = Instance.new("Model")
	model.Name = "Building_" .. tostring(os.time())
	model:SetAttribute("ShapeType", "Building")
	model:SetAttribute("Thickness", 1)
	model:SetAttribute("FloorOffsets", "0,0,0,0")

	local container = Instance.new("Folder")
	container.Name = "GeneratedFolder"
	container.Parent = model
	model.Parent = Container

	local params: ModelParams = {
		path = nil,
		size = Vector3.new(sx, BUILDING_HEIGHT, sz),
		radius = nil,
		height = BUILDING_HEIGHT,
		center = Vector3.new(result.bboxCenter.X, cgy, result.bboxCenter.Z),
		yaw = 0,
	}

	local function makeCF()
		return CFrame.new(params.center.X, params.center.Y + params.size.Y/2, params.center.Z)
			* CFrame.Angles(0, params.yaw, 0)
	end

	local rebuilding = false
	local function rebuild()
		rebuilding = true
		local cf = makeCF()
		buildBuilding(model, container, cf, params.size)
		conformBuilding(model, cf, params.size)
		rebuilding = false
	end

	model.AttributeChanged:Connect(function()
		if rebuilding then return end
		rebuilding = true
		buildBuilding(model, container, makeCF(), params.size)
		rebuilding = false
	end)

	local s: ModelState = {
		shapeType = "Building",
		params = params,
		path = nil,
		setHeight = function(h)
			params.size = Vector3.new(params.size.X, math.max(1, h), params.size.Z)
			params.height = h
			rebuild()
		end,
		setSize = function(newSize)
			params.size = Vector3.new(math.clamp(newSize.X, 4, 80), params.size.Y, math.clamp(newSize.Z, 4, 80))
			rebuild()
		end,
		setCenter = function(newCenter)
			local cgy2 = groundY(newCenter.X, newCenter.Z, newCenter.Y + 100) or newCenter.Y
			params.center = Vector3.new(newCenter.X, cgy2, newCenter.Z)
			rebuild()
		end,
		setPathPoint = function() end,
		setYaw = function(y)
			params.yaw = y
			rebuild()
		end,
	}
	state[model] = s

	model.Destroying:Connect(function() state[model] = nil end)

	rebuild()

	print(string.format("[RobloxProceduralModel] Spawned Building  size=(%.1f, %.1f, %.1f)  parts=%d",
		params.size.X, params.size.Y, params.size.Z, #container:GetChildren()))
end

local function spawnFlowerPot(result)
	local radius = math.clamp(result.radius or math.max(2, (result.bboxSize.X + result.bboxSize.Z) / 4), 1.5, 16)
	local cgy = groundY(result.bboxCenter.X, result.bboxCenter.Z, result.bboxCenter.Y + 100)
		or result.bboxCenter.Y

	local model = Instance.new("Model")
	model.Name = "FlowerPot_" .. tostring(os.time())
	model:SetAttribute("ShapeType", "Circle")
	model:SetAttribute("Radius", radius)

	local container = Instance.new("Folder")
	container.Name = "GeneratedFolder"
	container.Parent = model
	model.Parent = Container

	local params: ModelParams = {
		path = nil,
		size = nil,
		radius = radius,
		height = 2,
		center = Vector3.new(result.bboxCenter.X, cgy, result.bboxCenter.Z),
		yaw = 0,
	}

	local function rebuild()
		container:ClearAllChildren()
		Generator.OnGenerate({
			Size = Vector3.new(params.radius, params.height or (params.radius * 1.4), 0),
			ShapeType = "Circle",
		}, container)
		local cf = CFrame.new(params.center) * CFrame.Angles(0, params.yaw, 0)
		for _, p in container:GetChildren() do
			if p:IsA("BasePart") then
				p.CFrame = cf * p.CFrame
			end
		end
	end

	local s: ModelState = {
		shapeType = "Circle",
		params = params,
		path = nil,
		setHeight = function(h)
			params.height = math.max(1, h)
			rebuild()
		end,
		setRadius = function(r)
			params.radius = math.clamp(r, 1.5, 16)
			model:SetAttribute("Radius", params.radius)
			rebuild()
		end,
		setCenter = function(newCenter)
			local cgy2 = groundY(newCenter.X, newCenter.Z, newCenter.Y + 100) or newCenter.Y
			params.center = Vector3.new(newCenter.X, cgy2, newCenter.Z)
			rebuild()
		end,
		setPathPoint = function() end,
		setYaw = function(y)
			params.yaw = y
			rebuild()
		end,
	}
	state[model] = s

	model.Destroying:Connect(function() state[model] = nil end)

	rebuild()

	print(string.format("[RobloxProceduralModel] Spawned FlowerPot  radius=%.1f  parts=%d",
		radius, #container:GetChildren()))
end

-- Draw handlers
local function beginDraw()
	if not drawMode then return end
	local h = castMouse()
	if not h then return end
	drawing = true
	drawStart = os.clock()
	points = {h.Position}
	lastP = h.Position
	clearPreview()
	dot(h.Position)
end

local function updateDraw()
	if not drawing then return end
	local h = castMouse()
	if not h then return end
	local p = h.Position
	if lastP and (p - lastP).Magnitude < SAMPLE_INTERVAL then return end
	table.insert(points, p)
	lastP = p
	dot(p)
end

local function endDraw()
	if not drawing then return end
	drawing = false
	if os.clock() - drawStart < MIN_DRAW_TIME or #points < 2 then
		clearPreview()
		return
	end
	local r = ShapeDetector.Detect(points)
	local previewPoints
	local previewClosed = false

	if r.shapeType == "Building" then
		-- Clean rectangle along the bbox so trace matches what spawns
		local mn, mx = r.bboxMin, r.bboxMax
		local cgy = (groundY(r.bboxCenter.X, r.bboxCenter.Z, r.bboxCenter.Y + 100)) or r.bboxCenter.Y
		previewPoints = {
			Vector3.new(mn.X, cgy, mn.Z),
			Vector3.new(mx.X, cgy, mn.Z),
			Vector3.new(mx.X, cgy, mx.Z),
			Vector3.new(mn.X, cgy, mx.Z),
		}
		previewClosed = true
	elseif r.shapeType == "Circle" then
		-- Clean ring along the detected center + radius
		local cgy = (groundY(r.bboxCenter.X, r.bboxCenter.Z, r.bboxCenter.Y + 100)) or r.bboxCenter.Y
		local segments = 32
		previewPoints = {}
		for i = 0, segments - 1 do
			local a = (i / segments) * math.pi * 2
			table.insert(previewPoints, Vector3.new(
				r.bboxCenter.X + math.cos(a) * (r.radius or 4),
				cgy,
				r.bboxCenter.Z + math.sin(a) * (r.radius or 4)
			))
		end
		previewClosed = true
	else
		-- Wall: smoothed open path
		previewPoints = Smoothing.Chaikin(points, 3, false)
		previewClosed = false
	end

	tracePath(previewPoints, previewClosed)

	task.delay(0.35, function()
		if r.shapeType == "Building" then
			spawnBuilding(r)
		elseif r.shapeType == "Circle" then
			spawnFlowerPot(r)
		else
			spawnWall(r, previewPoints)
		end
	end)
	task.delay(0.9, clearPreview)
end

local function findContainerModel(inst)
	while inst and inst.Parent ~= Container do
		inst = inst.Parent
	end
	return inst
end

local function castMouseForModel()
	local mp = UIS:GetMouseLocation()
	local r = Camera:ViewportPointToRay(mp.X, mp.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local excludes = {Preview}
	if LocalPlayer.Character then table.insert(excludes, LocalPlayer.Character) end
	rp.FilterDescendantsInstances = excludes
	rp.IgnoreWater = false
	return Workspace:Raycast(r.Origin, r.Direction * 2000, rp)
end

local function tryDelete()
	local h = castMouseForModel()
	if not h or not h.Instance then return end
	local m = findContainerModel(h.Instance)
	if m then
		Manipulator.Deselect()
		m:Destroy()
	end
end

-- Initialize manipulator now that state map is alive
Manipulator.Init({
	Container = Container,
	StateMap = state,
	Generator = Generator,
})

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Manipulator gets first crack: handles, model selection, deselect.
		-- If it consumed the click, don't draw.
		local consumed = Manipulator.OnMouseDown()
		if consumed then return end
		beginDraw()
	elseif input.KeyCode == Enum.KeyCode.Q then
		drawMode = not drawMode
		print("[RobloxProceduralModel] Draw mode:", drawMode and "ON" or "OFF")
	elseif input.KeyCode == Enum.KeyCode.E then
		tryDelete()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		Manipulator.Deselect()
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		Manipulator.OnMouseUp()
		endDraw()
	end
end)

RunService.RenderStepped:Connect(function()
	updateDraw()
end)

-- HUD
local pg = LocalPlayer:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "ProceduralBuildHUD"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 360, 0, 130)
frame.Position = UDim2.new(0, 12, 0, 12)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Parent = gui
local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0, 8) uc.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -56, 0, 24)
title.Position = UDim2.new(0, 8, 0, 6)
title.BackgroundTransparency = 1
title.Text = "RobloxProceduralModel"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 220, 80)
title.Parent = frame

local menuButton = Instance.new("TextButton")
menuButton.Name = "InstructionToggle"
menuButton.Size = UDim2.new(0, 32, 0, 24)
menuButton.Position = UDim2.new(1, -40, 0, 6)
menuButton.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
menuButton.BackgroundTransparency = 0.1
menuButton.BorderSizePixel = 0
menuButton.Text = "..."
menuButton.Font = Enum.Font.GothamBold
menuButton.TextSize = 18
menuButton.TextColor3 = Color3.fromRGB(255, 220, 80)
menuButton.Parent = frame
local menuCorner = Instance.new("UICorner") menuCorner.CornerRadius = UDim.new(0, 6) menuCorner.Parent = menuButton

local body = Instance.new("TextLabel")
body.Size = UDim2.new(1, -16, 1, -34)
body.Position = UDim2.new(0, 8, 0, 30)
body.BackgroundTransparency = 1
body.Text = "LMB - draw / select model / drag handles\nClosed shape = Building (rect) or Flower Pot (round)\nHeight: wall <3 = fence | pot >=4 = tree | building >=8 = mall\nYellow arrows = pot/building size | building size >=18 = multiple\nE - delete | Esc - deselect | Q - toggle draw"
body.Font = Enum.Font.Gotham
body.TextSize = 13
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true
body.TextColor3 = Color3.fromRGB(220, 220, 230)
body.Parent = frame

local instructionsVisible = true
menuButton.MouseButton1Click:Connect(function()
	instructionsVisible = not instructionsVisible
	body.Visible = instructionsVisible
	frame.Size = instructionsVisible and UDim2.new(0, 360, 0, 130) or UDim2.new(0, 360, 0, 36)
end)

print("[RobloxProceduralModel] Loaded. LMB draw/select/drag handles | E delete | Esc deselect | Q toggle")

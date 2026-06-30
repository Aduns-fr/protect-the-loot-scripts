--!strict
-- Manipulator: hover highlight + selection + 3D handles for moving / resizing /
-- adjusting curve points on spawned models.

local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Camera = Workspace.CurrentCamera

local Manipulator = {}

-- ---------------------------------------------------------------
-- Wired by ClientController.Init(...)
-- ---------------------------------------------------------------
local Container: Folder
local stateMap: {[Instance]: any}
local Generator

-- ---------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------
local HandlesFolder: Folder
local hoverModel: Model? = nil
local selectedModel: Model? = nil
local hoverHL: Highlight? = nil
local selectHL: Highlight? = nil
local handles: {[BasePart]: {kind: string, axis: Vector3?, idx: number?}} = {}
local activeDrag: any = nil

local HANDLE_COLOR_MOVE = Color3.fromRGB(255, 255, 255)
local HANDLE_COLOR_HEIGHT = Color3.fromRGB(255, 255, 255)
local HANDLE_COLOR_POINT = Color3.fromRGB(255, 255, 255)
local HANDLE_COLOR_RAIL = Color3.fromRGB(255, 255, 255)
local HANDLE_COLOR_ROTATE = Color3.fromRGB(120, 200, 255)
local HANDLE_COLOR_INSERT = Color3.fromRGB(255, 230, 100)

-- Which side the rotate arc is currently rendered on ("front"|"back"|"left"|"right"|nil)
local currentRotateSide: string? = nil

-- Persistent preview dot for "insert new curve point here"
local insertPreview: Part? = nil
local insertPreviewWorldPos: Vector3? = nil  -- where a click would insert

-- ---------------------------------------------------------------
-- Raycasting that ignores handles + the local character
-- ---------------------------------------------------------------
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function buildRayParams()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local excludes = {HandlesFolder}
	if LocalPlayer.Character then table.insert(excludes, LocalPlayer.Character) end
	rp.FilterDescendantsInstances = excludes
	return rp
end

local function castMouseFull()
	local mp = UIS:GetMouseLocation()
	local r = Camera:ViewportPointToRay(mp.X, mp.Y)
	local hit = Workspace:Raycast(r.Origin, r.Direction * 2000, buildRayParams())
	return hit, r.Origin, r.Direction.Unit
end

local function findContainerModel(inst: Instance?): Model?
	local cur = inst
	while cur and cur.Parent ~= Container do
		cur = cur.Parent
	end
	return cur and cur:IsA("Model") and cur or nil
end

local function findHandleHit()
	local mp = UIS:GetMouseLocation()
	local r = Camera:ViewportPointToRay(mp.X, mp.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = {HandlesFolder}
	local hit = Workspace:Raycast(r.Origin, r.Direction * 2000, rp)
	if hit and handles[hit.Instance] and handles[hit.Instance].kind ~= "rail" then
		return hit
	end

	local bestPart = nil
	local bestDist = math.huge
	for part, info in handles do
		if part.Parent and info.kind ~= "rail" then
			local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
			if onScreen then
				local dx = screenPos.X - mp.X
				local dy = screenPos.Y - mp.Y
				local dist = math.sqrt(dx * dx + dy * dy)
				local threshold = 28
				if info.kind == "height" then
					threshold = 76
				elseif info.kind == "movePlane" then
					threshold = 48
				elseif info.kind == "size" then
					threshold = 48
				elseif info.kind == "point" then
					threshold = 36
				elseif info.kind == "rotate" then
					threshold = 34
				end
				if string.find(part.Name, "EasyGrab") then
					threshold = 96
				end
				if dist <= threshold and dist < bestDist then
					bestDist = dist
					bestPart = part
				end
			end
		end
	end
	if bestPart then
		return {Instance = bestPart}
	end
	return nil
end

-- ---------------------------------------------------------------
-- Highlight helpers
-- ---------------------------------------------------------------
local function ensureHover()
	if hoverHL then return end
	hoverHL = Instance.new("Highlight")
	hoverHL.Name = "HoverHL"
	hoverHL.FillColor = Color3.fromRGB(255, 255, 255)
	hoverHL.FillTransparency = 0.95
	hoverHL.OutlineColor = Color3.fromRGB(255, 230, 100)
	hoverHL.OutlineTransparency = 0
	hoverHL.DepthMode = Enum.HighlightDepthMode.Occluded
	hoverHL.Parent = HandlesFolder
end

local function ensureSelect()
	if selectHL then return end
	selectHL = Instance.new("Highlight")
	selectHL.Name = "SelectHL"
	selectHL.FillColor = Color3.fromRGB(120, 255, 200)
	selectHL.FillTransparency = 0.85  -- subtler fill so disc handles inside the bbox stay visible
	selectHL.OutlineColor = Color3.fromRGB(80, 255, 180)
	selectHL.OutlineTransparency = 0
	-- Occluded (not AlwaysOnTop) so the highlight doesn't paint over disc handle
	-- adornments that sit along the wall's path.
	selectHL.DepthMode = Enum.HighlightDepthMode.Occluded
	selectHL.Parent = HandlesFolder
end

local function setHover(model: Model?)
	if hoverModel == model then return end
	hoverModel = model
	if hoverHL then
		hoverHL.Adornee = (model and model ~= selectedModel) and model or nil
	end
end

-- ---------------------------------------------------------------
-- Handle factory
-- ---------------------------------------------------------------
local function makeHandle(name: string, size: Vector3, cf: CFrame, color: Color3, kind: string, axis: Vector3?, idx: number?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = 1
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = HandlesFolder

	local adorn = Instance.new("BoxHandleAdornment")
	adorn.Name = name .. "Adornment"
	adorn.Adornee = p
	adorn.AlwaysOnTop = true
	adorn.ZIndex = 10
	adorn.Size = size
	adorn.Color3 = color
	adorn.Transparency = 0
	adorn.Parent = p

	handles[p] = {kind = kind, axis = axis, idx = idx}
	return p
end

local function makeHitHandle(name: string, size: Vector3, cf: CFrame, kind: string, axis: Vector3?, idx: number?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.Transparency = 1
	p.Parent = HandlesFolder
	handles[p] = {kind = kind, axis = axis, idx = idx}
	return p
end

local function makeArrowHandle(name, basePos, axis, length, color, kind)
	local up = Vector3.new(0, 1, 0)
	local right = if math.abs(axis.Y) > 0.99 then Vector3.new(1,0,0) else axis:Cross(up).Unit
	local trueUp = if math.abs(axis.Y) > 0.99 then Vector3.new(0,0,1) else up
	local mid = basePos + axis * (length * 0.5)
	local cf = CFrame.fromMatrix(mid, axis, trueUp, right)
	return makeHandle(name .. "Shaft", Vector3.new(length, 0.28, 0.28), cf, color, kind, axis, nil)
end

local function makeRailSegment(name, a, b, yOffset, sideOffset)
	local diff = b - a
	local len = diff.Magnitude
	if len < 0.05 then return end
	local horiz = Vector3.new(diff.X, 0, diff.Z)
	if horiz.Magnitude < 0.001 then horiz = Vector3.new(1,0,0) else horiz = horiz.Unit end
	local up = Vector3.new(0, 1, 0)
	local fwd = up:Cross(horiz).Unit
	local mid = (a + b) / 2 + Vector3.new(0, yOffset, 0) + fwd * (sideOffset or 0)
	makeHandle(name, Vector3.new(len, 0.2, 0.2), CFrame.fromMatrix(mid, horiz, up, -fwd), HANDLE_COLOR_RAIL, "rail", nil, nil)
end

local function makeDiscNode(name, pos, kind, idx)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(1.15, 1.15, 1.15)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = HANDLE_COLOR_POINT
	p.Transparency = 1
	p.CFrame = CFrame.new(pos)
	p.Parent = HandlesFolder

	local adorn = Instance.new("SphereHandleAdornment")
	adorn.Name = name .. "Adornment"
	adorn.Adornee = p
	adorn.AlwaysOnTop = true
	adorn.ZIndex = 12
	adorn.Radius = 0.575
	adorn.Color3 = HANDLE_COLOR_POINT
	adorn.Transparency = 0
	adorn.Parent = p

	handles[p] = {kind = kind, idx = idx}
	return p
end

-- Build a quarter-circle arc of small segments lying flat on the ground,
-- centered on `center`, in the horizontal plane, spanning [startAngle, startAngle+arcSpan].
-- All segments share kind="rotate" so any click on the arc starts the rotate drag.
local function makeArcRotateHandle(center: Vector3, radius: number, startAngle: number, yawOffset: number)
	local arc = math.pi / 4  -- 45 degrees, shorter than before
	local segments = 8
	for i = 0, segments - 1 do
		local t0 = i / segments
		local t1 = (i + 1) / segments
		local a0 = startAngle + arc * t0
		local a1 = startAngle + arc * t1
		local p0 = center + Vector3.new(math.cos(a0), 0, math.sin(a0)) * radius
		local p1 = center + Vector3.new(math.cos(a1), 0, math.sin(a1)) * radius
		local mid = (p0 + p1) / 2
		local diff = p1 - p0
		local len = diff.Magnitude
		if len > 0.001 then
			local horiz = Vector3.new(diff.X, 0, diff.Z).Unit
			local up = Vector3.new(0, 1, 0)
			local fwd = up:Cross(horiz).Unit
			local cf = CFrame.fromMatrix(mid + Vector3.new(0, 0.05, 0), horiz, up, -fwd)
			makeHandle("RotateArc" .. i, Vector3.new(len * 1.05, 0.18, 0.32), cf, HANDLE_COLOR_ROTATE, "rotate", nil, nil)
		end
	end
end

-- ---------------------------------------------------------------
-- Compute model bounding box from generated parts
-- ---------------------------------------------------------------
local function modelBounds(model: Model)
	local container = model:FindFirstChild("GeneratedFolder")
	if not container then return nil end
	local minV, maxV
	for _, p in container:GetDescendants() do
		if p:IsA("BasePart") then
			local s, c = p.Size, p.CFrame
			local corners = {
				c * Vector3.new( s.X/2,  s.Y/2,  s.Z/2),
				c * Vector3.new(-s.X/2,  s.Y/2,  s.Z/2),
				c * Vector3.new( s.X/2, -s.Y/2,  s.Z/2),
				c * Vector3.new(-s.X/2, -s.Y/2,  s.Z/2),
				c * Vector3.new( s.X/2,  s.Y/2, -s.Z/2),
				c * Vector3.new(-s.X/2,  s.Y/2, -s.Z/2),
				c * Vector3.new( s.X/2, -s.Y/2, -s.Z/2),
				c * Vector3.new(-s.X/2, -s.Y/2, -s.Z/2),
			}
			for _, v in corners do
				if not minV then minV, maxV = v, v
				else
					minV = Vector3.new(math.min(minV.X,v.X), math.min(minV.Y,v.Y), math.min(minV.Z,v.Z))
					maxV = Vector3.new(math.max(maxV.X,v.X), math.max(maxV.Y,v.Y), math.max(maxV.Z,v.Z))
				end
			end
		end
	end
	return minV, maxV
end

-- ---------------------------------------------------------------
-- Build manipulator handles around the selected model
-- ---------------------------------------------------------------
-- Persistent insert-preview dot. Created on demand, hidden when not relevant.
local function ensureInsertPreview()
	if insertPreview then return end
	local p = Instance.new("Part")
	p.Name = "InsertPreview"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(1.0, 1.0, 1.0)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = HANDLE_COLOR_INSERT
	p.Transparency = 0.35
	p.Parent = HandlesFolder
	insertPreview = p
end

local function hideInsertPreview()
	if insertPreview then
		insertPreview.Transparency = 1
	end
	insertPreviewWorldPos = nil
end

local function showInsertPreviewAt(worldPos: Vector3)
	ensureInsertPreview()
	assert(insertPreview)
	insertPreview.CFrame = CFrame.new(worldPos + Vector3.new(0, 0.5, 0))
	insertPreview.Transparency = 0.35
	insertPreviewWorldPos = worldPos
end

-- Find the closest point on the wall's smooth path to a target world position (XZ).
-- Returns (closestPoint, segmentIndex, distance).
local function closestPointOnPath(path: {Vector3}, target: Vector3): (Vector3?, number?, number?)
	if not path or #path < 2 then return nil end
	local best, bestIdx, bestDist = nil, 1, math.huge
	for i = 1, #path - 1 do
		local a, b = path[i], path[i+1]
		local abx, abz = b.X - a.X, b.Z - a.Z
		local apx, apz = target.X - a.X, target.Z - a.Z
		local abLen2 = abx*abx + abz*abz
		local t = if abLen2 > 0.001 then math.clamp((apx*abx + apz*abz) / abLen2, 0, 1) else 0
		local cx = a.X + abx * t
		local cz = a.Z + abz * t
		local dx = target.X - cx
		local dz = target.Z - cz
		local d = math.sqrt(dx*dx + dz*dz)
		if d < bestDist then
			bestDist = d
			bestIdx = i
			local cy = a.Y + (b.Y - a.Y) * t
			best = Vector3.new(cx, cy, cz)
		end
	end
	return best, bestIdx, bestDist
end

-- Update the insert preview based on mouse position. Only shown when:
--   * a Wall is selected,
--   * mouse is hovering near the wall but NOT on a handle/disc,
--   * mouse ground-projection is within `insertHoverThreshold` of the wall path,
--   * no drag is active.
local INSERT_HOVER_THRESHOLD = 4  -- studs
local function refreshInsertPreview()
	if activeDrag then hideInsertPreview() return end
	if not selectedModel then hideInsertPreview() return end
	local s = stateMap[selectedModel]
	if not s or s.shapeType ~= "Wall" then hideInsertPreview() return end

	-- Mouse over a handle? Don't show insert preview.
	local handleHit = findHandleHit()
	if handleHit and handles[handleHit.Instance] then hideInsertPreview() return end

	local _, rayOrigin, rayDir = castMouseFull()
	local mn, mx = modelBounds(selectedModel)
	if not mn then hideInsertPreview() return end
	local t = if math.abs(rayDir.Y) > 1e-4 then (mn.Y - rayOrigin.Y) / rayDir.Y else -1
	if t < 0 then hideInsertPreview() return end
	local groundHit = rayOrigin + rayDir * t

	local closestPt, _, dist = closestPointOnPath(s.params.path, groundHit)
	if not closestPt or not dist then hideInsertPreview() return end
	if dist > INSERT_HOVER_THRESHOLD then hideInsertPreview() return end

	showInsertPreviewAt(Vector3.new(closestPt.X, mn.Y + 0.4, closestPt.Z))
end

local function clearHandles()
	for h in handles do h:Destroy() end
	handles = {}
end

-- Pick which side of the selected model (front/back/left/right) the mouse is
-- closest to, in world-XZ. Uses the model's bbox extents.
-- Returns one of "front" | "back" | "left" | "right", and the angle at which
-- the quarter arc should start (so the arc is centered on that side).
--   front = +Z, back = -Z, right = +X, left = -X.
local function pickNearSide(selModel: Model): (string?, number?, Vector3?, number?)
	local mn, mx = modelBounds(selModel)
	if not mn then return nil end
	local center = Vector3.new((mn.X + mx.X) / 2, mn.Y, (mn.Z + mx.Z) / 2)
	local halfX = (mx.X - mn.X) / 2
	local halfZ = (mx.Z - mn.Z) / 2

	local _, rayOrigin, rayDir = castMouseFull()
	-- Project the mouse ray onto ground Y
	local t = if math.abs(rayDir.Y) > 1e-4 then (center.Y - rayOrigin.Y) / rayDir.Y else -1
	if t < 0 then return nil end
	local hit = rayOrigin + rayDir * t

	local dx = hit.X - center.X
	local dz = hit.Z - center.Z

	-- Normalized signed distances past each side
	local sxRight = (dx - halfX)
	local sxLeft  = (-dx - halfX)
	local szFront = (dz - halfZ)
	local szBack  = (-dz - halfZ)

	-- Pick the side whose outward signed distance is largest (mouse beyond that face)
	-- and within a reasonable hover band.
	local best = math.max(sxRight, sxLeft, szFront, szBack)
	local hoverBand = math.max(halfX, halfZ) * 1.5 + 6
	if best > hoverBand or best < -math.max(halfX, halfZ) * 0.3 then
		return nil
	end

	local side, startAngle, radius
	if best == sxRight then
		side = "right"
		startAngle = -math.pi/4              -- arc spans -45 to +45 around +X
		radius = halfX + 2.5
	elseif best == sxLeft then
		side = "left"
		startAngle = math.pi * 3/4           -- arc around -X
		radius = halfX + 2.5
	elseif best == szFront then
		side = "front"
		startAngle = math.pi/4               -- arc around +Z
		radius = halfZ + 2.5
	else
		side = "back"
		startAngle = -math.pi * 3/4          -- arc around -Z
		radius = halfZ + 2.5
	end
	return side, startAngle, center, radius
end

local function rebuildHandles()
	clearHandles()
	currentRotateSide = nil
	if not selectedModel then return end
	local s = stateMap[selectedModel]
	if not s then return end

	local mn, mx = modelBounds(selectedModel)
	if not mn then return end
	local center = (mn + mx) / 2
	local topY = mx.Y
	local botY = mn.Y
	local halfX = (mx.X - mn.X) / 2
	local halfZ = (mx.Z - mn.Z) / 2

	if s.shapeType == "Wall" and s.params.path then
		local height = math.max(1, topY - botY)
		local railBottom = 0.75
		local railTop = height + 0.25
		local railSide = 0.65
		local railPath = s.params.path
		local controlPoints = s.params.controlPoints or s.path or railPath

		-- Control points live in REST POSE; rotate them to match the wall's current yaw
		-- so disc handles sit on the rotated geometry like the rails do.
		local yaw = s.params.yaw or 0
		local restCenterForRot
		if math.abs(yaw) > 1e-5 then
			-- Compute rest center as bbox of un-rotated controlPoints
			local mnP, mxP = controlPoints[1], controlPoints[1]
			for _, p in controlPoints do
				mnP = Vector3.new(math.min(mnP.X,p.X), math.min(mnP.Y,p.Y), math.min(mnP.Z,p.Z))
				mxP = Vector3.new(math.max(mxP.X,p.X), math.max(mxP.Y,p.Y), math.max(mxP.Z,p.Z))
			end
			restCenterForRot = (mnP + mxP) / 2
		end

		-- White outline rails follow the smooth generated (rotated) wall curve.
		for i = 1, #railPath - 1 do
			makeRailSegment("BottomRail" .. i, railPath[i], railPath[i+1], railBottom, railSide)
			makeRailSegment("TopRail" .. i, railPath[i], railPath[i+1], railTop, railSide)
		end

		-- Disc nodes at control points, rotated by yaw to align with rails.
		local cs = math.cos(yaw)
		local sn = math.sin(yaw)
		for i, p in controlPoints do
			local dispPos
			if math.abs(yaw) > 1e-5 and restCenterForRot then
				local dx = p.X - restCenterForRot.X
				local dz = p.Z - restCenterForRot.Z
				dispPos = Vector3.new(
					restCenterForRot.X + dx * cs - dz * sn,
					p.Y,
					restCenterForRot.Z + dx * sn + dz * cs
				)
			else
				dispPos = p
			end
			makeDiscNode("PathPoint" .. i, dispPos + Vector3.new(0, railBottom + 0.45, 0), "point", i)
		end

		-- Central four-way move gizmo at bottom/front center.
		local moveBase = Vector3.new(center.X, botY + 0.8, center.Z)
		makeArrowHandle("MoveRight", moveBase, Vector3.new(1, 0, 0), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveLeft", moveBase, Vector3.new(-1, 0, 0), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveForward", moveBase, Vector3.new(0, 0, 1), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveBack", moveBase, Vector3.new(0, 0, -1), 1.4, HANDLE_COLOR_MOVE, "move")
		makeHandle("MoveCenter", Vector3.new(0.75, 0.75, 0.75), CFrame.new(moveBase), HANDLE_COLOR_MOVE, "movePlane", nil, nil)

		-- Up/down height handle centered above wall.
		local heightBase = Vector3.new(center.X, topY + 0.35, center.Z)
		makeArrowHandle("HeightUp", heightBase, Vector3.new(0, 1, 0), 2.0, HANDLE_COLOR_HEIGHT, "height")
		makeArrowHandle("HeightDown", heightBase, Vector3.new(0, -1, 0), 1.2, HANDLE_COLOR_HEIGHT, "height")
		makeHandle("HeightCenter", Vector3.new(0.65, 0.65, 0.65), CFrame.new(heightBase), HANDLE_COLOR_HEIGHT, "height", Vector3.new(0, 1, 0), nil)
	elseif s.shapeType ~= "Circle" then
		-- Buildings keep a simpler height + move gizmo.
		local moveBase = Vector3.new(center.X, botY + 0.8, center.Z)
		makeArrowHandle("MoveRight", moveBase, Vector3.new(1, 0, 0), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveLeft", moveBase, Vector3.new(-1, 0, 0), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveForward", moveBase, Vector3.new(0, 0, 1), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveBack", moveBase, Vector3.new(0, 0, -1), 1.4, HANDLE_COLOR_MOVE, "move")
		makeHandle("MoveCenter", Vector3.new(0.75, 0.75, 0.75), CFrame.new(moveBase), HANDLE_COLOR_MOVE, "movePlane", nil, nil)

		local heightBase = Vector3.new(center.X, topY + 0.35, center.Z)
		makeArrowHandle("HeightUp", heightBase, Vector3.new(0, 1, 0), 2.0, HANDLE_COLOR_HEIGHT, "height")
		makeArrowHandle("HeightDown", heightBase, Vector3.new(0, -1, 0), 1.2, HANDLE_COLOR_HEIGHT, "height")
		makeHandle("HeightCenter", Vector3.new(0.65, 0.65, 0.65), CFrame.new(heightBase), HANDLE_COLOR_HEIGHT, "height", Vector3.new(0, 1, 0), nil)

		local sizeY = botY + 0.35
		makeArrowHandle("SizeRight", Vector3.new(center.X + halfX + 0.45, sizeY, center.Z), Vector3.new(1, 0, 0), 1.6, HANDLE_COLOR_INSERT, "size")
		makeArrowHandle("SizeLeft", Vector3.new(center.X - halfX - 0.45, sizeY, center.Z), Vector3.new(-1, 0, 0), 1.6, HANDLE_COLOR_INSERT, "size")
		makeArrowHandle("SizeForward", Vector3.new(center.X, sizeY, center.Z + halfZ + 0.45), Vector3.new(0, 0, 1), 1.6, HANDLE_COLOR_INSERT, "size")
		makeArrowHandle("SizeBack", Vector3.new(center.X, sizeY, center.Z - halfZ - 0.45), Vector3.new(0, 0, -1), 1.6, HANDLE_COLOR_INSERT, "size")
	else
		-- Flower pots/trees: move gizmo + height gizmo for pot/tree morphing.
		local moveBase = Vector3.new(center.X, botY + 0.8, center.Z)
		makeArrowHandle("MoveRight", moveBase, Vector3.new(1, 0, 0), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveLeft", moveBase, Vector3.new(-1, 0, 0), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveForward", moveBase, Vector3.new(0, 0, 1), 1.4, HANDLE_COLOR_MOVE, "move")
		makeArrowHandle("MoveBack", moveBase, Vector3.new(0, 0, -1), 1.4, HANDLE_COLOR_MOVE, "move")
		makeHandle("MoveCenter", Vector3.new(0.75, 0.75, 0.75), CFrame.new(moveBase), HANDLE_COLOR_MOVE, "movePlane", nil, nil)

		local heightBase = Vector3.new(center.X, topY + 0.35, center.Z)
		makeArrowHandle("HeightUp", heightBase, Vector3.new(0, 1, 0), 2.0, HANDLE_COLOR_HEIGHT, "height")
		makeArrowHandle("HeightDown", heightBase, Vector3.new(0, -1, 0), 1.2, HANDLE_COLOR_HEIGHT, "height")
		makeHandle("HeightCenter", Vector3.new(0.65, 0.65, 0.65), CFrame.new(heightBase), HANDLE_COLOR_HEIGHT, "height", Vector3.new(0, 1, 0), nil)

		local radius = math.max(1.5, s.params.radius or math.max(halfX, halfZ))
		local sizeY = botY + 0.35
		makeArrowHandle("SizeRight", Vector3.new(center.X + radius + 0.45, sizeY, center.Z), Vector3.new(1, 0, 0), 1.6, HANDLE_COLOR_INSERT, "size")
		makeArrowHandle("SizeLeft", Vector3.new(center.X - radius - 0.45, sizeY, center.Z), Vector3.new(-1, 0, 0), 1.6, HANDLE_COLOR_INSERT, "size")
		makeArrowHandle("SizeForward", Vector3.new(center.X, sizeY, center.Z + radius + 0.45), Vector3.new(0, 0, 1), 1.6, HANDLE_COLOR_INSERT, "size")
		makeArrowHandle("SizeBack", Vector3.new(center.X, sizeY, center.Z - radius - 0.45), Vector3.new(0, 0, -1), 1.6, HANDLE_COLOR_INSERT, "size")
	end
end

-- Lightweight rotate-arc updater: only rebuilds the rotate arc when the mouse
-- moves to a different side. Avoids rebuilding the whole gizmo every frame.
local function refreshRotateArcOnHover()
	if not selectedModel then return end
	if activeDrag then return end  -- don't switch sides mid-rotate
	local s = stateMap[selectedModel]
	if not s or s.shapeType == "Circle" then return end  -- flower pots don't get a rotate handle

	local side, startAngle, center, radius = pickNearSide(selectedModel)
	if side == currentRotateSide then return end

	-- Drop existing rotate handles
	for h, info in handles do
		if info.kind == "rotate" then
			h:Destroy()
			handles[h] = nil
		end
	end
	currentRotateSide = side
	if side and center and startAngle and radius then
		-- Center the 45-degree arc on the side direction by offsetting -22.5 degrees
		makeArcRotateHandle(center, radius, startAngle + math.pi/8, 0)
	end
end

local function refreshHandles()
	rebuildHandles()
end

-- ---------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------
local function selectModel(model: Model?)
	if selectedModel == model then return end
	selectedModel = model
	if selectHL then
		selectHL.Adornee = model
	end
	if hoverHL then
		hoverHL.Adornee = (hoverModel and hoverModel ~= selectedModel) and hoverModel or nil
	end
	if not model then hideInsertPreview() end
	rebuildHandles()
end

function Manipulator.Refresh()
	if selectedModel and not selectedModel.Parent then
		selectModel(nil)
		return
	end
	rebuildHandles()
end

-- ---------------------------------------------------------------
-- Drag math
-- ---------------------------------------------------------------
-- Project mouse ray onto a horizontal plane at given Y; returns Vector3 hit
local function rayToPlaneY(rayOrigin, rayDir, planeY)
	if math.abs(rayDir.Y) < 0.0001 then return nil end
	local t = (planeY - rayOrigin.Y) / rayDir.Y
	if t < 0 then return nil end
	return rayOrigin + rayDir * t
end

-- Project mouse ray onto a vertical plane that contains the world line
-- through (x,?,z) and faces the camera. Returns the Y of the intersection.
local function rayToVerticalAt(rayOrigin, rayDir, x, z)
	-- Plane normal: horizontal direction toward the camera (negated ray direction, flat-Y)
	local flat = Vector3.new(rayDir.X, 0, rayDir.Z)
	if flat.Magnitude < 0.0001 then return nil end
	local n = -flat.Unit
	local planePoint = Vector3.new(x, rayOrigin.Y, z)
	local denom = n:Dot(rayDir)
	if math.abs(denom) < 0.0001 then return nil end
	local t = n:Dot(planePoint - rayOrigin) / denom
	if t < 0 then return nil end
	local hit = rayOrigin + rayDir * t
	return hit.Y
end

-- ---------------------------------------------------------------
-- Drag handlers
-- ---------------------------------------------------------------
local function startHandleDrag(handlePart: BasePart)
	local info = handles[handlePart]
	if not info or not selectedModel then return end
	local s = stateMap[selectedModel]
	if not s then return end

	local _, rayOrigin, rayDir = castMouseFull()
	local mn, mx = modelBounds(selectedModel)
	if not mn then return end
	local center = (mn + mx) / 2

	if info.kind == "height" then
		local startY = rayToVerticalAt(rayOrigin, rayDir, center.X, center.Z) or center.Y
		activeDrag = {
			kind = "height",
			startMouseY = startY,
			startHeight = s.params.height or 8,
		}
	elseif info.kind == "rotate" then
		-- Use ground-plane intersection at the model's base Y.
		local planeHit = rayToPlaneY(rayOrigin, rayDir, mn.Y)
		if not planeHit then return end
		local pivot = s.params.center or Vector3.new(center.X, mn.Y, center.Z)
		local dx = planeHit.X - pivot.X
		local dz = planeHit.Z - pivot.Z
		local startAngle = math.atan2(dz, dx)
		activeDrag = {
			kind = "rotate",
			pivot = pivot,
			startMouseAngle = startAngle,
			startYaw = s.params.yaw or 0,
		}
	elseif info.kind == "move" or info.kind == "movePlane" then
		local axis = info.axis or Vector3.zero
		local startHit = rayToPlaneY(rayOrigin, rayDir, mn.Y) or center
		activeDrag = {
			kind = info.kind,
			axis = axis,
			startHit = startHit,
			startCenter = (s.params.center or Vector3.new(center.X, mn.Y, center.Z)),
		}
	elseif info.kind == "size" then
		if not s.setRadius and not s.setSize then return end
		local axis = info.axis or Vector3.new(1, 0, 0)
		local startHit = rayToPlaneY(rayOrigin, rayDir, mn.Y) or center
		activeDrag = {
			kind = "size",
			axis = axis,
			startHit = startHit,
			startRadius = s.params.radius or math.max((mx.X - mn.X) / 2, (mx.Z - mn.Z) / 2),
			startSize = s.params.size,
		}
	elseif info.kind == "point" then
		local startHit = rayToPlaneY(rayOrigin, rayDir, mn.Y) or center
		local controls = s.params.controlPoints or s.path or s.params.path
		if not controls or not controls[info.idx] then return end
		-- Convert the rest-pose control point to its rotated world position so
		-- it matches the disc's rendered location. Both the disc and the mouse
		-- live in rotated world space; rest-pose mixing would push the drag off.
		local yaw = s.params.yaw or 0
		local restPt = controls[info.idx]
		local rotatedStartPoint = restPt
		if math.abs(yaw) > 1e-5 then
			local mnP, mxP = controls[1], controls[1]
			for _, p in controls do
				mnP = Vector3.new(math.min(mnP.X,p.X), math.min(mnP.Y,p.Y), math.min(mnP.Z,p.Z))
				mxP = Vector3.new(math.max(mxP.X,p.X), math.max(mxP.Y,p.Y), math.max(mxP.Z,p.Z))
			end
			local restCenter = (mnP + mxP) / 2
			local dx = restPt.X - restCenter.X
			local dz = restPt.Z - restCenter.Z
			local cs = math.cos(yaw)
			local sn = math.sin(yaw)
			rotatedStartPoint = Vector3.new(
				restCenter.X + dx * cs - dz * sn,
				restPt.Y,
				restCenter.Z + dx * sn + dz * cs
			)
		end
		activeDrag = {
			kind = "point",
			idx = info.idx,
			startHit = startHit,
			startPoint = rotatedStartPoint,
			lastUpdate = 0,
		}
	end
end

local function updateDrag()
	if not activeDrag or not selectedModel then return end
	local s = stateMap[selectedModel]
	if not s then return end

	local _, rayOrigin, rayDir = castMouseFull()

	if activeDrag.kind == "height" then
		local mn, mx = modelBounds(selectedModel)
		if not mn then return end
		local cur = rayToVerticalAt(rayOrigin, rayDir, (mn.X+mx.X)/2, (mn.Z+mx.Z)/2)
		if not cur then return end
		local delta = cur - activeDrag.startMouseY
		local newH = math.clamp(activeDrag.startHeight + delta, 1, 60)
		s.setHeight(newH)
		rebuildHandles()
	elseif activeDrag.kind == "rotate" then
		local mn, _ = modelBounds(selectedModel)
		if not mn then return end
		local hit = rayToPlaneY(rayOrigin, rayDir, mn.Y)
		if not hit then return end
		local dx = hit.X - activeDrag.pivot.X
		local dz = hit.Z - activeDrag.pivot.Z
		local curAngle = math.atan2(dz, dx)
		-- We want the model to follow the mouse: yaw delta is the angular delta in -Y direction.
		-- atan2 increases CCW in (X,Z). CFrame.Angles(0, yaw, 0) is CCW around +Y, which in (X,Z)
		-- shows up as CW. So we negate to align mouse motion with visible rotation.
		local angleDelta = curAngle - activeDrag.startMouseAngle
		local newYaw = activeDrag.startYaw + angleDelta
		if s.setYaw then
			s.setYaw(newYaw)
		end
		rebuildHandles()
	elseif activeDrag.kind == "move" or activeDrag.kind == "movePlane" then
		local mn, _ = modelBounds(selectedModel)
		if not mn then return end
		local hit = rayToPlaneY(rayOrigin, rayDir, mn.Y)
		if not hit then return end
		local delta = hit - activeDrag.startHit
		local projected
		if activeDrag.kind == "movePlane" then
			projected = Vector3.new(delta.X, 0, delta.Z)
		else
			local axis = activeDrag.axis
			projected = axis * delta:Dot(axis)
		end
		local newCenter = activeDrag.startCenter + projected
		s.setCenter(newCenter)
		rebuildHandles()
	elseif activeDrag.kind == "size" then
		local mn, _ = modelBounds(selectedModel)
		if not mn then return end
		local hit = rayToPlaneY(rayOrigin, rayDir, mn.Y)
		if not hit then return end
		local delta = hit - activeDrag.startHit
		local amount = delta:Dot(activeDrag.axis)
		if s.setRadius then
			local newRadius = math.clamp(activeDrag.startRadius + amount, 1.5, 16)
			s.setRadius(newRadius)
		elseif s.setSize and activeDrag.startSize then
			local startSize = activeDrag.startSize
			local newSize = startSize
			if math.abs(activeDrag.axis.X) > 0.5 then
				newSize = Vector3.new(math.clamp(startSize.X + amount * 2, 4, 80), startSize.Y, startSize.Z)
			else
				newSize = Vector3.new(startSize.X, startSize.Y, math.clamp(startSize.Z + amount * 2, 4, 80))
			end
			s.setSize(newSize)
		end
		rebuildHandles()
	elseif activeDrag.kind == "point" then
		local now = os.clock()
		if now - (activeDrag.lastUpdate or 0) < 0.08 then return end
		activeDrag.lastUpdate = now
		local mn, _ = modelBounds(selectedModel)
		if not mn then return end
		local hit = rayToPlaneY(rayOrigin, rayDir, mn.Y)
		if not hit then return end
		local delta = hit - activeDrag.startHit
		local newPoint = activeDrag.startPoint + Vector3.new(delta.X, 0, delta.Z)
		s.setPathPoint(activeDrag.idx, newPoint)
		rebuildHandles()
	end
end

local function endDrag()
	activeDrag = nil
end

-- ---------------------------------------------------------------
-- Public API: returns true if input was consumed by manipulator
-- ---------------------------------------------------------------
function Manipulator.OnMouseDown(): boolean
	-- 0) If insert preview is visible, decide between INSERT and SELECT-NEAR-POINT.
	--    If the click is near an existing control point, snap to dragging that point
	--    instead of creating a new one.
	local handleHit = findHandleHit()
	if insertPreviewWorldPos and not (handleHit and handles[handleHit.Instance]) and selectedModel then
		local s = stateMap[selectedModel]
		if s and s.shapeType == "Wall" then
			-- Look for an existing PathPoint handle within snap distance of the click.
			local SNAP_DIST = 2.0  -- studs in XZ; tweak as needed
			local nearest, nearestDist = nil, math.huge
			for h, info in handles do
				if info.kind == "point" then
					local dx = h.Position.X - insertPreviewWorldPos.X
					local dz = h.Position.Z - insertPreviewWorldPos.Z
					local d = math.sqrt(dx*dx + dz*dz)
					if d < nearestDist then
						nearestDist = d
						nearest = h
					end
				end
			end
			if nearest and nearestDist <= SNAP_DIST then
				-- Treat as a drag-start on that point instead of inserting
				startHandleDrag(nearest)
				return true
			end
			if s.addPathPoint then
				s.addPathPoint(insertPreviewWorldPos)
				rebuildHandles()
				return true
			end
		end
	end

	-- 1) Click on a handle => start drag (no delete; users adjust by dragging only)
	if handleHit and handles[handleHit.Instance] then
		startHandleDrag(handleHit.Instance)
		return true
	end

	-- 2) Click on a spawned model => select
	local hit = castMouseFull()
	if hit and hit.Instance then
		local model = findContainerModel(hit.Instance)
		if model then
			selectModel(model)
			return true
		end
	end

	-- 3) Click on empty space while something selected => deselect (and let LMB pass through)
	if selectedModel then
		selectModel(nil)
		return true
	end

	return false
end

function Manipulator.OnMouseUp()
	if activeDrag then
		endDrag()
	end
end

function Manipulator.IsDragging(): boolean
	return activeDrag ~= nil
end

function Manipulator.IsHoveringInteractive(): boolean
	-- True when LMB should NOT be used to start drawing
	if activeDrag then return true end
	if insertPreviewWorldPos then return true end
	local handleHit = findHandleHit()
	if handleHit and handles[handleHit.Instance] then return true end
	local hit = castMouseFull()
	if hit and hit.Instance then
		local model = findContainerModel(hit.Instance)
		if model then return true end
	end
	return selectedModel ~= nil
end

function Manipulator.Deselect()
	selectModel(nil)
end

-- ---------------------------------------------------------------
-- Init from ClientController
-- ---------------------------------------------------------------
function Manipulator.Init(opts: {Container: Folder, StateMap: any, Generator: any})
	Container = opts.Container
	stateMap = opts.StateMap
	Generator = opts.Generator

	HandlesFolder = Workspace:FindFirstChild("_Handles") or Instance.new("Folder")
	HandlesFolder.Name = "_Handles"
	HandlesFolder.Parent = Workspace

	ensureHover()
	ensureSelect()

	-- Hover loop: update hover highlight every frame (and keep handles fresh on drag)
	RunService.RenderStepped:Connect(function()
		if activeDrag then
			updateDrag()
			return
		end
		local handleHit = findHandleHit()
		if handleHit and handles[handleHit.Instance] then
			-- Hovering a handle: keep current state
			hideInsertPreview()
			return
		end
		local hit = castMouseFull()
		local model = hit and hit.Instance and findContainerModel(hit.Instance) or nil
		setHover(model)
		-- When a model is selected, also refresh the rotate arc based on mouse proximity
		refreshRotateArcOnHover()
		-- And the insert preview (only meaningful for walls)
		refreshInsertPreview()
	end)
end

return Manipulator

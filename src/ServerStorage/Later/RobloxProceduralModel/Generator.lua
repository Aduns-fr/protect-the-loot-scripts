--!strict
-- Generator: builds parts at LOCAL coordinates around origin.
-- The caller offsets them into world space afterwards.

local Generator = {}

local BRICK_LEN = 0.5          -- studs along the wall
local WALL_HEIGHT = 8
local WALL_THICKNESS = 1
local BRICK_COLOR = Color3.fromRGB(170, 90, 70)
local FENCE_HEIGHT_THRESHOLD = 3   -- Wall with Height < this becomes a fence
local FENCE_POST_SPACING = 2.5
local FENCE_POST_THICKNESS = 0.35
local FENCE_RAIL_THICKNESS = 0.28
local FENCE_COLOR = Color3.fromRGB(120, 80, 50)
local TREE_HEIGHT_THRESHOLD = 4
local MALL_SHOP_HEIGHT_THRESHOLD = 8
local BUILDING_CLUSTER_SIZE_THRESHOLD = 18

Generator.FENCE_HEIGHT_THRESHOLD = FENCE_HEIGHT_THRESHOLD
Generator.WALL_DEFAULT_HEIGHT = WALL_HEIGHT
Generator.TREE_HEIGHT_THRESHOLD = TREE_HEIGHT_THRESHOLD
Generator.MALL_SHOP_HEIGHT_THRESHOLD = MALL_SHOP_HEIGHT_THRESHOLD
Generator.BUILDING_CLUSTER_SIZE_THRESHOLD = BUILDING_CLUSTER_SIZE_THRESHOLD

export type Params = {
	Size: Vector3,
	ShapeType: string?,
	FloorOffsets: string?,
	Thickness: number?,
	Path: {Vector3}?,         -- world-space points; used for Wall
	Origin: Vector3?,         -- world origin the parts will be offset to (so we can build in local space)
	Height: number?,          -- Wall height; < FENCE_HEIGHT_THRESHOLD => fence
}

local function makePart(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color or Color3.fromRGB(180, 170, 150)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decodeOffsets(s)
	if not s or s == "" then return {0,0,0,0} end
	local out = {}
	for chunk in string.gmatch(s, "[^,]+") do
		table.insert(out, tonumber(chunk) or 0)
	end
	while #out < 4 do table.insert(out, 0) end
	return out
end

-- WALL: chain of bricks along the path. Uses arc-length sampling so
-- segment boundaries don't introduce gaps. Each brick is oriented to the
-- average of the incoming/outgoing tangents at its position to minimize
-- gaps at bends.
local function genWall(path, origin, parent, height)
	if not path or #path < 2 then return end
	height = height or WALL_HEIGHT

	-- Convert path to local space (subtract origin) and compute per-segment
	-- lengths + cumulative arc length.
	local local_path = {}
	for _, p in path do
		table.insert(local_path, p - origin)
	end

	local segLens = {}
	local cumLen = {0}
	local totalLen = 0
	for i = 1, #local_path - 1 do
		local d = (local_path[i+1] - local_path[i]).Magnitude
		segLens[i] = d
		totalLen += d
		cumLen[i+1] = totalLen
	end

	if totalLen < BRICK_LEN * 0.5 then return end

	-- Number of bricks: fit as many full bricks as the path allows.
	-- Use ceil so very short paths still get at least one brick.
	local numBricks = math.max(1, math.floor(totalLen / BRICK_LEN))
	-- Stretch brick spacing slightly so the last brick lands exactly at the end
	local spacing = totalLen / numBricks

	-- Helper: at arc distance d along the path, return (position, tangentDir)
	-- segHint is the segment index to start scanning from (for forward iteration).
	local function sampleAt(d, segHint)
		segHint = segHint or 1
		-- Find segment i such that cumLen[i] <= d <= cumLen[i+1]
		local i = segHint
		while i < #local_path - 1 and cumLen[i+1] < d do
			i += 1
		end
		local segStart = cumLen[i]
		local segLen = segLens[i]
		local t = if segLen > 0.001 then (d - segStart) / segLen else 0
		local a = local_path[i]
		local b = local_path[i+1]
		local pos = a + (b - a) * t
		local tangent = b - a
		if tangent.Magnitude < 0.001 then
			tangent = Vector3.new(1, 0, 0)
		else
			tangent = tangent.Unit
		end
		return pos, tangent, i
	end

	-- Place each brick at arc distance (k + 0.5) * spacing for k = 0..numBricks-1,
	-- so bricks are centered within their slot.
	local segHint = 1
	for k = 0, numBricks - 1 do
		local d = (k + 0.5) * spacing
		local pos, tangent, hint = sampleAt(d, segHint)
		segHint = hint

		-- For bend-smoothing, average the tangent at +/- spacing/2 (the brick's
		-- endpoints), so corners orient to the bisector.
		local _, tBack = sampleAt(math.max(0, d - spacing * 0.5), 1)
		local _, tFwd  = sampleAt(math.min(totalLen, d + spacing * 0.5), segHint)
		local avgTangent = (tBack + tFwd)
		if avgTangent.Magnitude < 0.001 then
			avgTangent = tangent
		else
			avgTangent = avgTangent.Unit
		end

		-- Flatten to horizontal so bricks stand upright even if path Y wobbles
		local horizDir = Vector3.new(avgTangent.X, 0, avgTangent.Z)
		if horizDir.Magnitude < 0.001 then
			horizDir = Vector3.new(1, 0, 0)
		else
			horizDir = horizDir.Unit
		end

		local up = Vector3.new(0, 1, 0)
		local fwd = up:Cross(horizDir).Unit  -- -Z
		local centerPos = Vector3.new(pos.X, pos.Y + height/2, pos.Z)
		-- Brick length matches spacing so they butt-join cleanly.
		local cf = CFrame.fromMatrix(centerPos, horizDir, up, -fwd)
		makePart(parent, "Brick" .. k,
			Vector3.new(spacing, height, WALL_THICKNESS),
			cf, BRICK_COLOR, Enum.Material.Brick)
	end
end

-- FENCE: posts every FENCE_POST_SPACING studs along path, with top + middle rails.
local function genFence(path, origin, parent, height)
	if not path or #path < 2 then return end
	height = math.max(1, height or 2.5)

	local local_path = {}
	for _, p in path do
		table.insert(local_path, p - origin)
	end

	local segLens, cumLen = {}, {0}
	local totalLen = 0
	for i = 1, #local_path - 1 do
		local d = (local_path[i+1] - local_path[i]).Magnitude
		segLens[i] = d
		totalLen += d
		cumLen[i+1] = totalLen
	end

	if totalLen < FENCE_POST_SPACING * 0.5 then return end

	local function sampleAt(d)
		local i = 1
		while i < #local_path - 1 and cumLen[i+1] < d do i += 1 end
		local segStart = cumLen[i]
		local segLen = segLens[i]
		local t = if segLen > 0.001 then (d - segStart) / segLen else 0
		local a = local_path[i]
		local b = local_path[i+1]
		return a + (b - a) * t
	end

	local numPosts = math.max(2, math.floor(totalLen / FENCE_POST_SPACING) + 1)
	local postSpacing = totalLen / (numPosts - 1)
	local posts = {}
	for k = 0, numPosts - 1 do
		local d = math.min(k * postSpacing, totalLen)
		local pos = sampleAt(d)
		local centerPos = Vector3.new(pos.X, pos.Y + height/2, pos.Z)
		makePart(parent, "Post" .. k,
			Vector3.new(FENCE_POST_THICKNESS, height, FENCE_POST_THICKNESS),
			CFrame.new(centerPos), FENCE_COLOR, Enum.Material.Wood)
		posts[k] = pos
	end

	for k = 0, numPosts - 2 do
		local a, b = posts[k], posts[k+1]
		local mid = (a + b) / 2
		local diff = b - a
		local len = diff.Magnitude
		if len > 0.001 then
			local horiz = Vector3.new(diff.X, 0, diff.Z)
			if horiz.Magnitude < 0.001 then horiz = Vector3.new(1,0,0) else horiz = horiz.Unit end
			local up = Vector3.new(0, 1, 0)
			local fwd = up:Cross(horiz).Unit
			local topY = mid.Y + height - FENCE_RAIL_THICKNESS
			local botY = mid.Y + height * 0.4
			makePart(parent, "RailTop" .. k,
				Vector3.new(len, FENCE_RAIL_THICKNESS, FENCE_RAIL_THICKNESS),
				CFrame.fromMatrix(Vector3.new(mid.X, topY, mid.Z), horiz, up, -fwd),
				FENCE_COLOR, Enum.Material.Wood)
			makePart(parent, "RailBot" .. k,
				Vector3.new(len, FENCE_RAIL_THICKNESS, FENCE_RAIL_THICKNESS),
				CFrame.fromMatrix(Vector3.new(mid.X, botY, mid.Z), horiz, up, -fwd),
				FENCE_COLOR, Enum.Material.Wood)
		end
	end
end

local function genBuilding(size, offsets, thickness, color, parent, offset, suffix)
	offset = offset or Vector3.zero
	suffix = suffix or ""
	local fl, fr, bl, br = offsets[1], offsets[2], offsets[3], offsets[4]
	local hx, hz = size.X/2, size.Z/2
	local pillarW = thickness
	local function part(name, sz, cf, c, material)
		return makePart(parent, name .. suffix, sz, CFrame.new(offset) * cf, c, material)
	end

	local corners = {
		{x=-hx, z= hz, off=fl, name="PillarFL"},
		{x= hx, z= hz, off=fr, name="PillarFR"},
		{x=-hx, z=-hz, off=bl, name="PillarBL"},
		{x= hx, z=-hz, off=br, name="PillarBR"},
	}
	for _, c in corners do
		local foundationDepth = math.max(0, -c.off)
		part(c.name,
			Vector3.new(pillarW, size.Y + foundationDepth, pillarW),
			CFrame.new(c.x, -foundationDepth/2, c.z),
			color)
	end

	part("WallFront", Vector3.new(size.X - pillarW, size.Y, thickness), CFrame.new(0, 0,  hz), color)
	part("WallBack",  Vector3.new(size.X - pillarW, size.Y, thickness), CFrame.new(0, 0, -hz), color)
	part("WallLeft",  Vector3.new(thickness, size.Y, size.Z - pillarW), CFrame.new(-hx, 0, 0), color)
	part("WallRight", Vector3.new(thickness, size.Y, size.Z - pillarW), CFrame.new( hx, 0, 0), color)

	local doorW = math.min(size.X * 0.25, 3)
	local doorH = math.min(size.Y * 0.55, 4)
	part("DoorFrame", Vector3.new(doorW + 0.35, doorH + 0.35, thickness * 0.35),
		CFrame.new(0, -size.Y/2 + doorH/2 + 0.18, hz + thickness * 0.55),
		Color3.fromRGB(70, 55, 45))
	part("Door", Vector3.new(doorW, doorH, thickness * 0.45),
		CFrame.new(0, -size.Y/2 + doorH/2, hz + thickness * 0.75),
		Color3.fromRGB(55, 35, 25), Enum.Material.Wood)

	part("Roof",
		Vector3.new(size.X, 0.5, size.Z),
		CFrame.new(0, size.Y/2 + 0.25, 0),
		Color3.fromRGB(120, 80, 60))
	part("Floor",
		Vector3.new(size.X - pillarW, 0.3, size.Z - pillarW),
		CFrame.new(0, -size.Y/2 + 0.15, 0),
		Color3.fromRGB(140, 100, 70))
end

-- FLOWER POT: cylindrical terracotta pot + soil + leaves + flowers.
-- Built in local space centered on origin.  Radius drives all sub-dimensions.
local function genSingleFlowerPot(radius, height, parent, offset, suffix)
	local r = math.max(0.9, radius)
	local potHeight = math.clamp(height or 2, 2, TREE_HEIGHT_THRESHOLD - 0.1)
	local growth = math.clamp(potHeight / 2, 0.8, 1.9)
	local soilThickness = 0.4

	-- Pot body: cylinder
	local pot = Instance.new("Part")
	pot.Name = "Pot" .. suffix
	pot.Shape = Enum.PartType.Cylinder
	pot.Anchored = true
	pot.Size = Vector3.new(potHeight, r * 2, r * 2)  -- X is cylinder's axis
	-- Lay cylinder on its side so axis points up: rotate 0,0,90
	pot.CFrame = CFrame.new(offset + Vector3.new(0, potHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pot.Material = Enum.Material.Slate
	pot.Color = Color3.fromRGB(180, 90, 50)  -- terracotta
	pot.TopSurface = Enum.SurfaceType.Smooth
	pot.BottomSurface = Enum.SurfaceType.Smooth
	pot.Parent = parent

	-- Pot rim (slightly wider band near the top, looks more like a real pot)
	local rim = Instance.new("Part")
	rim.Name = "Rim" .. suffix
	rim.Shape = Enum.PartType.Cylinder
	rim.Anchored = true
	rim.Size = Vector3.new(0.3, r * 2.15, r * 2.15)
	rim.CFrame = CFrame.new(offset + Vector3.new(0, potHeight - 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	rim.Material = Enum.Material.Slate
	rim.Color = Color3.fromRGB(160, 75, 40)
	rim.Parent = parent

	-- Soil: dark disc just below the rim
	local soil = Instance.new("Part")
	soil.Name = "Soil" .. suffix
	soil.Shape = Enum.PartType.Cylinder
	soil.Anchored = true
	soil.Size = Vector3.new(soilThickness, r * 1.95, r * 1.95)
	soil.CFrame = CFrame.new(offset + Vector3.new(0, potHeight - 0.3 - soilThickness / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	soil.Material = Enum.Material.Ground
	soil.Color = Color3.fromRGB(60, 40, 30)
	soil.Parent = parent

	local soilTopY = potHeight - 0.3

	-- Leaves: 5 small slanted parts radiating outward from center
	local numLeaves = 5
	for i = 1, numLeaves do
		local angle = (i / numLeaves) * math.pi * 2
		local lx = math.cos(angle) * r * 0.55
		local lz = math.sin(angle) * r * 0.55
		local leaf = Instance.new("Part")
		leaf.Name = "Leaf" .. i .. suffix
		leaf.Anchored = true
		leaf.Size = Vector3.new(0.3, r * 0.8 * growth, r * 0.45)
		-- Tilt outward: lookAt away from pot center, then tilt up
		local up = Vector3.new(0, 1, 0)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local cf = CFrame.new(offset + Vector3.new(lx, soilTopY + r * 0.35 * growth, lz))
			* CFrame.fromAxisAngle(up:Cross(outward).Unit, math.rad(-25))
		leaf.CFrame = cf
		leaf.Material = Enum.Material.Grass
		leaf.Color = Color3.fromRGB(60, 130, 50)
		leaf.Parent = parent
	end

	-- Flowers: 3 stems with colored ball blossoms
	local flowerColors = {
		Color3.fromRGB(230, 100, 160),  -- pink
		Color3.fromRGB(240, 210, 60),   -- yellow
		Color3.fromRGB(220, 60, 60),    -- red
	}
	for i = 1, 3 do
		local angle = (i / 3) * math.pi * 2 + math.pi / 6
		local fx = math.cos(angle) * r * 0.3
		local fz = math.sin(angle) * r * 0.3
		local stemHeight = (r * 0.9 + (i % 2) * 0.3) * growth

		local stem = Instance.new("Part")
		stem.Name = "Stem" .. i .. suffix
		stem.Anchored = true
		stem.Size = Vector3.new(0.18, stemHeight, 0.18)
		stem.CFrame = CFrame.new(offset + Vector3.new(fx, soilTopY + stemHeight / 2, fz))
		stem.Material = Enum.Material.Grass
		stem.Color = Color3.fromRGB(50, 110, 45)
		stem.Parent = parent

		local blossom = Instance.new("Part")
		blossom.Name = "Flower" .. i .. suffix
		blossom.Shape = Enum.PartType.Ball
		blossom.Anchored = true
		blossom.Size = Vector3.new(r * 0.55, r * 0.55, r * 0.55)
		blossom.CFrame = CFrame.new(offset + Vector3.new(fx, soilTopY + stemHeight + r * 0.2, fz))
		blossom.Material = Enum.Material.Neon
		blossom.Color = flowerColors[i]
		blossom.Parent = parent
	end
end

local function genFlowerPot(radius, height, parent)
	local clusterRadius = math.max(1.5, radius)
	local count = math.clamp(math.floor((clusterRadius - 1.5) / 1.8) + 1, 1, 8)
	local potRadius = math.clamp(clusterRadius / 4, 0.9, 1.6)
	if count == 1 then
		genSingleFlowerPot(potRadius, height, parent, Vector3.zero, "")
		return
	end
	local ringCount = count
	local startIndex = 1
	if count > 4 then
		genSingleFlowerPot(potRadius, height, parent, Vector3.zero, "1")
		ringCount = count - 1
		startIndex = 2
	end
	local ringRadius = clusterRadius * 0.45
	for i = 1, ringCount do
		local potIndex = startIndex + i - 1
		local angle = ((i - 1) / ringCount) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius)
		local r = potRadius * (0.92 + (potIndex % 2) * 0.12)
		genSingleFlowerPot(r, height, parent, offset, tostring(potIndex))
	end
end

-- TREE: trunk + foliage clusters. Radius from caller, total height drives crown size.
local function genSingleTree(radius: number, height: number, parent: Instance, offset: Vector3, suffix: string)
	local r = math.max(1.2, radius)
	local trunkRadius = math.max(0.45, r * 0.3)
	local trunkHeight = height * 0.55
	local crownBase = trunkHeight
	local crownHeight = height - trunkHeight

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk" .. suffix
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Anchored = true
	trunk.Size = Vector3.new(trunkHeight, trunkRadius * 2, trunkRadius * 2)
	trunk.CFrame = CFrame.new(offset + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Material = Enum.Material.Wood
	trunk.Color = Color3.fromRGB(95, 60, 35)
	trunk.TopSurface = Enum.SurfaceType.Smooth
	trunk.BottomSurface = Enum.SurfaceType.Smooth
	trunk.Parent = parent

	local crownCenter = offset + Vector3.new(0, crownBase + crownHeight * 0.55, 0)
	local crownRadius = math.max(r * 1.35, crownHeight * 0.42)
	local clumpColors = {
		Color3.fromRGB(60, 130, 50),
		Color3.fromRGB(50, 115, 45),
		Color3.fromRGB(70, 140, 55),
	}
	local mainBlob = Instance.new("Part")
	mainBlob.Name = "Foliage1" .. suffix
	mainBlob.Shape = Enum.PartType.Ball
	mainBlob.Anchored = true
	mainBlob.Size = Vector3.new(crownRadius * 2, crownRadius * 2, crownRadius * 2)
	mainBlob.CFrame = CFrame.new(crownCenter)
	mainBlob.Material = Enum.Material.Grass
	mainBlob.Color = clumpColors[1]
	mainBlob.Parent = parent

	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2
		local offsetXZ = crownRadius * 0.55
		local offsetY = (i % 2 == 0) and crownRadius * 0.35 or -crownRadius * 0.2
		local blobR = crownRadius * (0.65 + (i % 2) * 0.1)
		local blob = Instance.new("Part")
		blob.Name = "Foliage" .. (i + 1) .. suffix
		blob.Shape = Enum.PartType.Ball
		blob.Anchored = true
		blob.Size = Vector3.new(blobR * 2, blobR * 2, blobR * 2)
		blob.CFrame = CFrame.new(
			crownCenter.X + math.cos(angle) * offsetXZ,
			crownCenter.Y + offsetY,
			crownCenter.Z + math.sin(angle) * offsetXZ
		)
		blob.Material = Enum.Material.Grass
		blob.Color = clumpColors[(i % #clumpColors) + 1]
		blob.Parent = parent
	end
end

local function genTree(radius: number, height: number, parent: Instance)
	local clusterRadius = math.max(1.5, radius)
	local count = math.clamp(math.floor((clusterRadius - 1.5) / 1.8) + 1, 1, 8)
	local treeRadius = math.clamp(clusterRadius / 4, 1.2, 2.4)
	if count == 1 then
		genSingleTree(treeRadius, height, parent, Vector3.zero, "")
		return
	end
	local ringCount = count
	local startIndex = 1
	if count > 4 then
		genSingleTree(treeRadius, height, parent, Vector3.zero, "1")
		ringCount = count - 1
		startIndex = 2
	end
	local ringRadius = clusterRadius * 0.45
	for i = 1, ringCount do
		local treeIndex = startIndex + i - 1
		local angle = ((i - 1) / ringCount) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius)
		local h = height * (0.9 + (treeIndex % 3) * 0.05)
		local r = treeRadius * (0.92 + (treeIndex % 2) * 0.12)
		genSingleTree(r, h, parent, offset, tostring(treeIndex))
	end
end

-- MALL SHOP: 4-wall box with storefront glass strip, sign, and entrance.
local function genMallShop(size: Vector3, parent: Instance, offset: Vector3?, suffix: string?)
	offset = offset or Vector3.zero
	suffix = suffix or ""
	local hx, hz = size.X / 2, size.Z / 2
	local h = size.Y
	local wallThickness = 0.6

	local beigeColor = Color3.fromRGB(220, 210, 190)
	local accentColor = Color3.fromRGB(180, 60, 60)
	local glassColor = Color3.fromRGB(120, 180, 220)
	local trimColor = Color3.fromRGB(80, 80, 90)

	-- Storefront window strip dimensions (front face only)
	local windowHeight = math.min(h * 0.45, 14)
	local windowSillY = h * 0.25
	local signHeight = math.min(h * 0.15, 5)
	local signY = h - signHeight / 2 - 0.4

	local function part(name, sz, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name .. suffix
		p.Anchored = true
		p.Size = sz
		p.CFrame = CFrame.new(offset) * cf
		p.Material = material or Enum.Material.SmoothPlastic
		p.Color = color
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end

	-- Side walls (left/right) — full height
	part("WallLeft", Vector3.new(wallThickness, h, size.Z), CFrame.new(-hx, 0, 0), beigeColor)
	part("WallRight", Vector3.new(wallThickness, h, size.Z), CFrame.new(hx, 0, 0), beigeColor)
	-- Back wall — full height
	part("WallBack", Vector3.new(size.X, h, wallThickness), CFrame.new(0, 0, -hz), beigeColor)

	-- Front face: split into bottom strip, window band, and upper wall + sign overlay
	-- Bottom strip below windows
	if windowSillY > 0 then
		part("FrontBottom", Vector3.new(size.X, windowSillY, wallThickness),
			CFrame.new(0, -h/2 + windowSillY/2, hz), trimColor, Enum.Material.Concrete)
	end
	-- Window band (storefront glass)
	part("Window", Vector3.new(size.X - 1.0, windowHeight, wallThickness * 0.4),
		CFrame.new(0, -h/2 + windowSillY + windowHeight/2, hz - wallThickness * 0.3),
		glassColor, Enum.Material.Glass)
	-- Window frame trim (a thin border that wraps around the glass)
	part("WindowFrame", Vector3.new(size.X, windowHeight + 0.4, wallThickness * 0.6),
		CFrame.new(0, -h/2 + windowSillY + windowHeight/2, hz - wallThickness * 0.6),
		trimColor)
	-- Re-place the glass IN FRONT of the frame so it stays visible
	part("Glass", Vector3.new(size.X - 0.8, windowHeight - 0.1, 0.15),
		CFrame.new(0, -h/2 + windowSillY + windowHeight/2, hz - 0.05),
		glassColor, Enum.Material.Glass)

	-- Upper wall (above windows, up to sign band)
	local upperWallStart = -h/2 + windowSillY + windowHeight
	local upperWallTop = h/2 - signHeight
	local upperWallH = upperWallTop - upperWallStart
	if upperWallH > 0 then
		part("FrontUpper", Vector3.new(size.X, upperWallH, wallThickness),
			CFrame.new(0, (upperWallStart + upperWallTop)/2, hz), beigeColor)
	end

	-- Sign band across the top of the front facade
	part("Sign", Vector3.new(size.X - 0.3, signHeight, wallThickness * 0.5),
		CFrame.new(0, h/2 - signHeight/2, hz + wallThickness * 0.3),
		accentColor, Enum.Material.SmoothPlastic)
	-- Three glowing rectangles on the sign suggesting MALL letters
	local letterCount = 4
	local letterSpacing = (size.X - 2) / letterCount
	for i = 1, letterCount do
		local lx = -size.X/2 + 1 + (i - 0.5) * letterSpacing
		part("SignLetter" .. i, Vector3.new(letterSpacing * 0.45, signHeight * 0.55, 0.3),
			CFrame.new(lx, h/2 - signHeight/2, hz + wallThickness * 0.6),
			Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
	end

	-- Entrance: a darker doorway recessed into the bottom-center of the front
	local doorW = math.min(size.X * 0.25, 6)
	local doorH = math.min(windowSillY + windowHeight * 0.5, h * 0.4)
	part("Doorway", Vector3.new(doorW, doorH, wallThickness * 1.2),
		CFrame.new(0, -h/2 + doorH/2, hz + 0.01),
		Color3.fromRGB(40, 40, 50), Enum.Material.SmoothPlastic)
	part("DoorTrim", Vector3.new(doorW + 0.6, doorH + 0.6, wallThickness * 0.4),
		CFrame.new(0, -h/2 + doorH/2 + 0.3, hz + wallThickness * 0.5),
		Color3.fromRGB(60, 50, 50))

	-- Roof (flat with a slight overhang)
	part("Roof", Vector3.new(size.X + 0.6, 0.6, size.Z + 0.6),
		CFrame.new(0, h/2 + 0.3, 0), Color3.fromRGB(60, 60, 70), Enum.Material.Concrete)

	-- Floor inside
	part("Floor", Vector3.new(size.X - wallThickness, 0.3, size.Z - wallThickness),
		CFrame.new(0, -h/2 + 0.15, 0), Color3.fromRGB(180, 170, 160), Enum.Material.Concrete)
end

local function buildingClusterCount(size: Vector3): number
	local footprint = math.max(size.X, size.Z)
	if footprint < BUILDING_CLUSTER_SIZE_THRESHOLD then
		return 1
	end
	return math.clamp(math.floor((footprint - BUILDING_CLUSTER_SIZE_THRESHOLD) / BUILDING_CLUSTER_SIZE_THRESHOLD) + 2, 2, 6)
end

local function genBuildingCluster(size: Vector3, offsets, thickness: number, color: Color3, parent: Instance)
	local count = buildingClusterCount(size)
	if count == 1 then
		genBuilding(size, offsets, thickness, color, parent)
		return
	end
	local cols = math.ceil(math.sqrt(count))
	local rows = math.ceil(count / cols)
	local cellX = size.X / cols
	local cellZ = size.Z / rows
	local singleSize = Vector3.new(math.max(4, cellX * 0.78), size.Y, math.max(4, cellZ * 0.78))
	for i = 1, count do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local ox = (col - (cols - 1) / 2) * cellX
		local oz = (row - (rows - 1) / 2) * cellZ
		genBuilding(singleSize, {0,0,0,0}, thickness, color, parent, Vector3.new(ox, 0, oz), tostring(i))
	end
end

local function genMallShopCluster(size: Vector3, parent: Instance)
	local count = buildingClusterCount(size)
	if count == 1 then
		genMallShop(size, parent)
		return
	end
	local cols = math.ceil(math.sqrt(count))
	local rows = math.ceil(count / cols)
	local cellX = size.X / cols
	local cellZ = size.Z / rows
	local singleSize = Vector3.new(math.max(5, cellX * 0.8), size.Y, math.max(5, cellZ * 0.8))
	for i = 1, count do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local ox = (col - (cols - 1) / 2) * cellX
		local oz = (row - (rows - 1) / 2) * cellZ
		genMallShop(singleSize, parent, Vector3.new(ox, 0, oz), tostring(i))
	end
end

function Generator.OnGenerate(params: Params, target: Instance)
	local shape = params.ShapeType or "Wall"
	if shape == "Building" then
		local offsets = decodeOffsets(params.FloorOffsets)
		local thickness = params.Thickness or 1
		-- Building → MallShop morph at height ≥ MALL_SHOP_HEIGHT_THRESHOLD
		if params.Size and params.Size.Y >= MALL_SHOP_HEIGHT_THRESHOLD then
			genMallShopCluster(params.Size, target)
		else
			genBuildingCluster(params.Size, offsets, thickness, Color3.fromRGB(200,190,170), target)
		end
	elseif shape == "Circle" then
		-- Radius in params.Size.X, height in params.Size.Y
		-- FlowerPot → Tree morph at height ≥ TREE_HEIGHT_THRESHOLD
		local h = params.Size and params.Size.Y or 0
		if h >= TREE_HEIGHT_THRESHOLD then
			genTree(params.Size.X, h, target)
		else
			genFlowerPot(params.Size.X, h, target)
		end
	else
		-- Wall (path-following) — switch to fence below threshold height
		local h = params.Height or WALL_HEIGHT
		local origin = params.Origin or Vector3.zero
		if h < FENCE_HEIGHT_THRESHOLD then
			genFence(params.Path, origin, target, h)
		else
			genWall(params.Path, origin, target, h)
		end
	end
end

return Generator

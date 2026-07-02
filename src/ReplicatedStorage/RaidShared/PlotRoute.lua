--!strict
local RouteMover = require(script.Parent:WaitForChild("RouteMover"))

local PlotRoute = {}

local EDGE_PADDING = 6
local SURFACE_OFFSET = 0.15
local BASE_PADDING = 4

local function getPlotPart(plot: Instance?): BasePart?
	if not plot then return nil end
	local part = plot:FindFirstChild("Part")
	return if part and part:IsA("BasePart") then part else nil
end

local function getBasePart(plot: Instance?): BasePart?
	if not plot then return nil end
	local direct = plot:FindFirstChild("Base")
	if direct and direct:IsA("BasePart") then return direct end
	local nested = plot:FindFirstChild("Base", true)
	return if nested and nested:IsA("BasePart") then nested else nil
end

-- Fallback surface height (world Y) from the island geometry, used when a
-- downward raycast finds nothing under a route point.
local function islandTopY(plot: Instance?, fallback: number): number
	if plot then
		local island = plot:FindFirstChild("Island")
		if island and island:IsA("Model") then
			local ok, cf, size = pcall(function()
				return island:GetBoundingBox()
			end)
			if ok and cf and size then
				return cf.Position.Y + size.Y * 0.5
			end
		end
	end
	return fallback
end

-- Raycast params limited to the walkable surfaces of this plot (Island/Docks/Base),
-- so enemies follow the ground rather than the tall invisible "Part" hitbox.
local function buildRayParams(plot: Instance?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.IgnoreWater = true
	local includes = {}
	if plot then
		for _, name in ipairs({ "Island", "Docks", "Base" }) do
			local c = plot:FindFirstChild(name)
			if c then includes[#includes + 1] = c end
		end
	end
	params.FilterDescendantsInstances = includes
	return params
end

local function clampLocal(point: Vector3, half: Vector3): Vector3
	return Vector3.new(
		math.clamp(point.X, -half.X + EDGE_PADDING, half.X - EDGE_PADDING),
		0,
		math.clamp(point.Z, -half.Z + EDGE_PADDING, half.Z - EDGE_PADDING)
	)
end

local SHORE_INSET = 3

local function groundHit(x: number, z: number, plotPart: BasePart, half: Vector3, params: RaycastParams): RaycastResult?
	local origin = Vector3.new(x, plotPart.Position.Y + half.Y + 60, z)
	return workspace:Raycast(origin, Vector3.new(0, -(half.Y * 2 + 120), 0), params)
end

-- The plot "Part" is a big rectangle; the island inside it is not. A point picked
-- on the Part edge can hang over open water. Pull such points along the line
-- toward the anchor (the stash, always on land) until the raycast finds ground,
-- binary-refine to the shoreline, then step slightly inland.
local function snapToLand(world: Vector3, anchor: Vector3, plotPart: BasePart, half: Vector3, params: RaycastParams): RaycastResult?
	local hit = groundHit(world.X, world.Z, plotPart, half, params)
	if hit then return hit end
	local delta = anchor - world
	local dist = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if dist < 1 then return nil end
	local steps = math.clamp(math.floor(dist / 6), 8, 60)
	local lastMissT, firstHitT, firstHit = 0, nil, nil
	for i = 1, steps do
		local t = i / steps
		local p = world:Lerp(anchor, t)
		local h = groundHit(p.X, p.Z, plotPart, half, params)
		if h then firstHitT, firstHit = t, h break end
		lastMissT = t
	end
	if not firstHitT then return nil end
	for _ = 1, 8 do
		local midT = (lastMissT + firstHitT) / 2
		local p = world:Lerp(anchor, midT)
		local h = groundHit(p.X, p.Z, plotPart, half, params)
		if h then firstHitT, firstHit = midT, h else lastMissT = midT end
	end
	local insetT = math.min(1, firstHitT + SHORE_INSET / dist)
	local p = world:Lerp(anchor, insetT)
	return groundHit(p.X, p.Z, plotPart, half, params) or firstHit
end

-- Converts local X/Z route points to world space, snapping each onto actual
-- walkable ground (island/docks/base) so no route point floats over water.
local function toWorldPoints(plot: Instance?, plotPart: BasePart, half: Vector3, localPoints: { Vector3 })
	local params = buildRayParams(plot)
	local fallbackY = islandTopY(plot, plotPart.Position.Y + half.Y)
	local points = table.create(#localPoints)
	-- the route's final point is the stash/Base, which is always over land
	local lastFlat = clampLocal(localPoints[#localPoints], half)
	local anchorWorld = plotPart.CFrame:PointToWorldSpace(lastFlat)
	for i, point in ipairs(localPoints) do
		local flat = clampLocal(point, half)
		local world = plotPart.CFrame:PointToWorldSpace(flat)
		local hit = snapToLand(world, anchorWorld, plotPart, half, params)
		if hit then
			points[i] = hit.Position + Vector3.new(0, SURFACE_OFFSET, 0)
		else
			points[i] = Vector3.new(world.X, fallbackY + SURFACE_OFFSET, world.Z)
		end
	end
	return points
end

function PlotRoute.BuildRoutePoints(plot: Instance?)
	local plotPart = getPlotPart(plot)
	if not plotPart then return {} end

	local half = plotPart.Size * 0.5
	local base = getBasePart(plot)
	local baseLocal = base and plotPart.CFrame:PointToObjectSpace(base.Position) or Vector3.zero
	local finish = Vector3.new(
		math.clamp(baseLocal.X, -half.X + BASE_PADDING, half.X - BASE_PADDING),
		0,
		math.clamp(baseLocal.Z, -half.Z + BASE_PADDING, half.Z - BASE_PADDING)
	)

	local xMin, xMax = -half.X + EDGE_PADDING, half.X - EDGE_PADDING
	local zMin, zMax = -half.Z + EDGE_PADDING, half.Z - EDGE_PADDING
	local xWide, zWide = (xMax - xMin), (zMax - zMin)
	local xL, xR = xMin + xWide * 0.22, xMax - xWide * 0.22
	local zB, zT = zMin + zWide * 0.22, zMax - zWide * 0.22

	local routes = {
		{ Vector3.new(xL, 0, zMin), Vector3.new(xL, 0, zB), Vector3.new(finish.X - xWide * 0.18, 0, finish.Z - zWide * 0.08), finish },
		{ Vector3.new(xR, 0, zMax), Vector3.new(xR, 0, zT), Vector3.new(finish.X + xWide * 0.18, 0, finish.Z + zWide * 0.08), finish },
		{ Vector3.new(xMin, 0, zB), Vector3.new(xL, 0, zB), Vector3.new(finish.X - xWide * 0.10, 0, finish.Z + zWide * 0.18), finish },
		{ Vector3.new(xMax, 0, zT), Vector3.new(xR, 0, zT), Vector3.new(finish.X + xWide * 0.10, 0, finish.Z - zWide * 0.18), finish },
		{ Vector3.new(xMin, 0, zMin), Vector3.new(xL, 0, zMin + zWide * 0.34), Vector3.new(finish.X - xWide * 0.24, 0, finish.Z - zWide * 0.16), finish },
		{ Vector3.new(xMax, 0, zMin), Vector3.new(xR, 0, zMin + zWide * 0.34), Vector3.new(finish.X + xWide * 0.24, 0, finish.Z - zWide * 0.16), finish },
		{ Vector3.new(xMin, 0, zMax), Vector3.new(xMin + xWide * 0.34, 0, zT), Vector3.new(finish.X - xWide * 0.24, 0, finish.Z + zWide * 0.16), finish },
		{ Vector3.new(xMax, 0, zMax), Vector3.new(xMax - xWide * 0.34, 0, zT), Vector3.new(finish.X + xWide * 0.24, 0, finish.Z + zWide * 0.16), finish },
	}

	local worldRoutes = table.create(#routes)
	for i, route in ipairs(routes) do
		worldRoutes[i] = toWorldPoints(plot, plotPart, half, route)
	end
	return worldRoutes
end

function PlotRoute.BuildRoutes(plot: Instance?)
	local routePoints = PlotRoute.BuildRoutePoints(plot)
	local routes = table.create(#routePoints)
	for i, points in ipairs(routePoints) do
		routes[i] = RouteMover.new(points)
	end
	return routes
end

function PlotRoute.BuildRoute(plot: Instance?, seed: number?)
	local plotPart = getPlotPart(plot)
	if not plotPart then return nil end

	local half = plotPart.Size * 0.5
	local base = getBasePart(plot)
	local baseLocal = base and plotPart.CFrame:PointToObjectSpace(base.Position) or Vector3.zero
	local finish = Vector3.new(
		math.clamp(baseLocal.X, -half.X + BASE_PADDING, half.X - BASE_PADDING),
		0,
		math.clamp(baseLocal.Z, -half.Z + BASE_PADDING, half.Z - BASE_PADDING)
	)
	local rng = Random.new(math.floor(tonumber(seed) or os.clock() * 100000))
	local side = rng:NextInteger(1, 4)
	local t = rng:NextNumber(-0.92, 0.92)
	local start
	if side == 1 then
		start = Vector3.new(t * (half.X - EDGE_PADDING), 0, -half.Z + EDGE_PADDING)
	elseif side == 2 then
		start = Vector3.new(half.X - EDGE_PADDING, 0, t * (half.Z - EDGE_PADDING))
	elseif side == 3 then
		start = Vector3.new(t * (half.X - EDGE_PADDING), 0, half.Z - EDGE_PADDING)
	else
		start = Vector3.new(-half.X + EDGE_PADDING, 0, t * (half.Z - EDGE_PADDING))
	end

	local mid = start:Lerp(finish, rng:NextNumber(0.42, 0.62))
	local sideBias = Vector3.new(-start.Z, 0, start.X)
	if sideBias.Magnitude > 0.01 then
		sideBias = sideBias.Unit * rng:NextNumber(-10, 10)
	end
	mid += sideBias

	local approach = toWorldPoints(plot, plotPart, half, { start, mid, finish })
	return RouteMover.new(approach)
end

function PlotRoute.ReverseMover(mover)
	if not mover or type(mover.points) ~= "table" then return nil end
	local points = table.create(#mover.points)
	for i = #mover.points, 1, -1 do
		table.insert(points, mover.points[i])
	end
	return RouteMover.new(points)
end

function PlotRoute.Build(plot: Instance?)
	return PlotRoute.BuildRoute(plot, 1)
end

function PlotRoute.GetBasePart(plot: Instance?): BasePart?
	return getBasePart(plot)
end

return PlotRoute

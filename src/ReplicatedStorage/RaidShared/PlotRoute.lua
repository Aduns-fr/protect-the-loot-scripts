--!strict
local RouteMover = require(script.Parent:WaitForChild("RouteMover"))

local PlotRoute = {}

local EDGE_PADDING = 6
local SURFACE_OFFSET = 0.15

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

function PlotRoute.Build(plot: Instance?)
	local plotPart = getPlotPart(plot)
	if not plotPart then return nil end

	local half = plotPart.Size * 0.5
	local base = getBasePart(plot)
	local baseLocal = base and plotPart.CFrame:PointToObjectSpace(base.Position) or Vector3.zero
	local x = math.clamp(baseLocal.X, -half.X + EDGE_PADDING, half.X - EDGE_PADDING)
	local z = math.clamp(baseLocal.Z, -half.Z + EDGE_PADDING, half.Z - EDGE_PADDING)
	local y = half.Y + SURFACE_OFFSET

	local startZ = -half.Z + EDGE_PADDING
	if math.abs(z - startZ) < 12 then
		startZ = half.Z - EDGE_PADDING
	end

	local start = plotPart.CFrame:PointToWorldSpace(Vector3.new(x, y, startZ))
	local finish = plotPart.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
	return RouteMover.new({ start, finish })
end

function PlotRoute.GetBasePart(plot: Instance?): BasePart?
	return getBasePart(plot)
end

return PlotRoute

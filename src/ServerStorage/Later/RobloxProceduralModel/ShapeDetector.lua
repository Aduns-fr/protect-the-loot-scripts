--!strict
-- Wall = open path.  Building = rectangular closed loop.  Circle = round closed loop.

local ShapeDetector = {}

export type ShapeResult = {
	shapeType: string,
	bboxMin: Vector3,
	bboxMax: Vector3,
	bboxCenter: Vector3,
	bboxSize: Vector3,
	pathLength: number,
	radius: number?,        -- for Circle
}

local function pathLength(points)
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i-1]).Magnitude
	end
	return total
end

local function bbox(points)
	local minV, maxV = points[1], points[1]
	for i = 2, #points do
		local p = points[i]
		minV = Vector3.new(math.min(minV.X,p.X), math.min(minV.Y,p.Y), math.min(minV.Z,p.Z))
		maxV = Vector3.new(math.max(maxV.X,p.X), math.max(maxV.Y,p.Y), math.max(maxV.Z,p.Z))
	end
	return minV, maxV
end

-- Shoelace formula in XZ plane.  Returns absolute area.
local function polygonAreaXZ(points)
	local n = #points
	if n < 3 then return 0 end
	local sum = 0
	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		sum += (a.X * b.Z) - (b.X * a.Z)
	end
	return math.abs(sum) * 0.5
end

function ShapeDetector.Detect(points: {Vector3}): ShapeResult
	assert(#points >= 2, "Need at least 2 points")

	local minV, maxV = bbox(points)
	local size = maxV - minV
	local center = (minV + maxV) / 2
	local plen = pathLength(points)
	local diagXZ = math.sqrt(size.X^2 + size.Z^2)

	local startEndDist = (points[#points] - points[1]).Magnitude
	local closeThreshold = math.max(diagXZ * 0.22, 0.75)
	local isClosed = startEndDist <= closeThreshold and #points >= 5
	local hasArea = size.X >= 1.8 and size.Z >= 1.8

	local shapeType
	local radius

	if isClosed and hasArea then
		-- Distinguish Circle from Building via isoperimetric ratio.
		-- Perfect circle: 4*pi*A / P^2 = 1.0.  Square: ~0.785.
		-- Threshold at 0.85: rounder than a square => Circle.
		local area = polygonAreaXZ(points)
		local ratio = (4 * math.pi * area) / (plen * plen)
		if ratio >= 0.85 then
			shapeType = "Circle"
			-- Radius: average of horizontal bbox half-extents
			radius = (size.X + size.Z) / 4
		else
			shapeType = "Building"
		end
	else
		shapeType = "Wall"
	end

	return {
		shapeType = shapeType,
		bboxMin = minV,
		bboxMax = maxV,
		bboxCenter = center,
		bboxSize = size,
		pathLength = plen,
		radius = radius,
	}
end

return ShapeDetector

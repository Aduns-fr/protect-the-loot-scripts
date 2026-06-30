--!strict
-- Chaikin's corner-cutting algorithm.
-- Each iteration replaces every interior edge AB with two points at
-- A + 0.25*(B-A) and A + 0.75*(B-A). The first and last points are kept
-- (open path) so endpoints don't drift. For closed paths the loop wraps.

local Smoothing = {}

local function chaikinOnce(points: {Vector3}, closed: boolean): {Vector3}
	local n = #points
	if n < 3 then return points end
	local out: {Vector3} = {}
	if not closed then
		table.insert(out, points[1])
	end
	local last = if closed then n else n - 1
	for i = 1, last do
		local a = points[i]
		local b = points[(i % n) + 1]
		table.insert(out, a + (b - a) * 0.25)
		table.insert(out, a + (b - a) * 0.75)
	end
	if not closed then
		table.insert(out, points[n])
	end
	return out
end

function Smoothing.Chaikin(points: {Vector3}, iterations: number?, closed: boolean?): {Vector3}
	local iters = iterations or 3
	local closedFlag = closed == true
	local result = points
	for _ = 1, iters do
		result = chaikinOnce(result, closedFlag)
	end
	return result
end

return Smoothing

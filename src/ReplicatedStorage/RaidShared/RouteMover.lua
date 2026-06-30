--!strict
-- RouteMover maps scalar travel distance along generated route points to a
-- world position and facing. Server and client use the same math.
local RouteMover = {}
RouteMover.__index = RouteMover

function RouteMover.new(points)
	local self = setmetatable({}, RouteMover)
	self.points = points
	local cum = table.create(#points)
	cum[1] = 0
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
		cum[i] = total
	end
	self.cum = cum
	self.length = total
	return self
end

function RouteMover:At(distance)
	local pts = self.points
	local n = #pts
	if n == 0 then return Vector3.zero, CFrame.identity, true end
	if n == 1 then return pts[1], CFrame.new(pts[1]), true end
	if distance <= 0 then
		return pts[1], CFrame.lookAt(pts[1], pts[2]), false
	end
	if distance >= self.length then
		local dir = pts[n] - pts[n - 1]
		dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(0, 0, -1)
		return pts[n], CFrame.lookAt(pts[n], pts[n] + dir), true
	end
	for i = 2, n do
		if distance <= self.cum[i] then
			local segLen = self.cum[i] - self.cum[i - 1]
			local t = segLen > 0 and (distance - self.cum[i - 1]) / segLen or 0
			local a, b = pts[i - 1], pts[i]
			local pos = a:Lerp(b, t)
			local dir = b - a
			dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(0, 0, -1)
			return pos, CFrame.lookAt(pos, pos + dir), false
		end
	end
	return pts[n], CFrame.new(pts[n]), true
end

return RouteMover

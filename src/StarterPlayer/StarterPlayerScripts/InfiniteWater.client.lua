local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local waterFolder = ReplicatedStorage:WaitForChild("WaterSystem")
local waterTemplate = waterFolder:WaitForChild("WaterTile")
local WaterConfig = require(waterFolder:WaitForChild("WaterConfig"))

local TILE_SIZE = WaterConfig.TileSize
local GRID_RADIUS = 2
local WATER_Y_LEVEL = WaterConfig.TileCenterY
local UPDATE_INTERVAL = 1 / 20
local SPEED_U = WaterConfig.ScrollU
local SPEED_V = WaterConfig.ScrollV

local activeTiles = {}
local lastPlayerGridX
local lastPlayerGridZ

for x = -GRID_RADIUS, GRID_RADIUS do
	for z = -GRID_RADIUS, GRID_RADIUS do
		local clone = waterTemplate:Clone()
		local legacyAnimator = clone:FindFirstChildWhichIsA("Script", true)
		if legacyAnimator then
			legacyAnimator.Disabled = true
		end
		clone.Parent = workspace
		table.insert(activeTiles, {
			part = clone,
			texture = clone:FindFirstChildWhichIsA("Texture", true),
			gridX = x,
			gridZ = z,
		})
	end
end

local accumulator = UPDATE_INTERVAL
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < UPDATE_INTERVAL then return end
	local step = accumulator
	accumulator = 0

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local playerPos = root.Position
		local playerGridX = math.floor((playerPos.X + TILE_SIZE / 2) / TILE_SIZE)
		local playerGridZ = math.floor((playerPos.Z + TILE_SIZE / 2) / TILE_SIZE)
		if playerGridX ~= lastPlayerGridX or playerGridZ ~= lastPlayerGridZ then
			lastPlayerGridX = playerGridX
			lastPlayerGridZ = playerGridZ
			for _, tile in ipairs(activeTiles) do
				tile.part.Position = Vector3.new(
					(playerGridX + tile.gridX) * TILE_SIZE,
					WATER_Y_LEVEL,
					(playerGridZ + tile.gridZ) * TILE_SIZE
				)
			end
		end
	end

	for _, tile in ipairs(activeTiles) do
		local texture = tile.texture
		if texture and texture.Parent then
			texture.OffsetStudsU += SPEED_U * step
			texture.OffsetStudsV += SPEED_V * step
		end
	end
end)

local texture = script.Parent
local runService = game:GetService("RunService")

-- Adjust these numbers to change the speed and direction of the water
local speedX = 0.05
local speedY = 0.02

-- This loop runs every frame to smoothly move the texture
runService.Heartbeat:Connect(function(deltaTime)
	-- deltaTime ensures the water moves at the same speed regardless of lag
	texture.OffsetStudsU = texture.OffsetStudsU + (speedX * deltaTime * 10)
	texture.OffsetStudsV = texture.OffsetStudsV + (speedY * deltaTime * 10)
end)
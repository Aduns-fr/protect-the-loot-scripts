local conveyor = script.Parent

-- Keep this as a positive number here...
local speed = 25 

-- ...and add a minus sign here to flip it to the Left (Negative X)
conveyor.AssemblyLinearVelocity = -conveyor.CFrame.RightVector * speed
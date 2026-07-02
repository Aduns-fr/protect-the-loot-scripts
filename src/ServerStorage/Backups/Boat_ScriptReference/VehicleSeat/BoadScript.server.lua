local Engine = script.Parent.Parent.Engine.BodyThrust --The Force making the boat move
local SForce = script.Parent.Parent.Steer.BodyAngularVelocity -- The force making the boat turn
local DSeat = script.Parent -- The driver seat
local Base = script.Parent.Parent.Base -- The base part of the boat

speed = 5000 -- The force of 'Engine'
SteerSpeed = 25 -- The force of SForce
BaseDensity = .1 -- Lower this is your boat can't float, make it higher to make it go more in the water

DSeat.Changed:Connect(function(p)
	if p == "ThrottleFloat"then
		Engine.Force = Vector3.new(0,0,speed * DSeat.ThrottleFloat)
	end
	if p == "SteerFloat"then
		SForce.AngularVelocity = Vector3.new(0,-SteerSpeed*DSeat.SteerFloat,0)
	end
end)

Base.CustomPhysicalProperties = PhysicalProperties.new(BaseDensity,0,0)
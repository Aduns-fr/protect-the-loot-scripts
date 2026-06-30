local Lighting = game:GetService("Lighting")

local PropsList = {
	"Ambient";
	"Brightness";
	"ClockTime";
	"ColorShift_Bottom";
	"ColorShift_Top";
	"EnvironmentDiffuseScale";
	"EnvironmentSpecularScale";
	"ExposureCompensation";
	"FogColor";
	"FogEnd";
	"FogStart";
	"GeographicLatitude";
	"GlobalShadows";
	"OutdoorAmbient";
	"ShadowSoftness";
}

local CreateValue = function(name, value, parent)
	local valueType = typeof(value)
	local instance

	if valueType == "string" then
		instance = Instance.new("StringValue")
	elseif valueType == "number" then
		instance = Instance.new("NumberValue")
	elseif valueType == "boolean" then
		instance = Instance.new("BoolValue")
	elseif valueType == "Color3" then
		instance = Instance.new("Color3Value")
	elseif valueType == "Vector3" then
		instance = Instance.new("Vector3Value")
	elseif valueType == "CFrame" then
		instance = Instance.new("CFrameValue")
	elseif valueType == "BrickColor" then
		instance = Instance.new("BrickColorValue")
	elseif valueType == "Object" then
		instance = Instance.new("ObjectValue")
	else
		return
	end

	instance.Name = name or "Value"
	instance.Value = value

	if parent then
		instance.Parent = parent
	end

	return instance
end

local GetObjectProps = function()
	local Props = {}

	for _,prop in PropsList do
		Props[prop] = Lighting[prop]
	end

	return Props
end

return function()
	local MainConfig = Instance.new("Configuration")
	MainConfig.Name = "CurrentLighting"

	local LightingObject = Instance.new("Configuration")
	LightingObject.Name = "Lighting"
	LightingObject.Parent = MainConfig

	local Objects = Instance.new("Folder")
	Objects.Name = "Objects"
	Objects.Parent = MainConfig

	local Model = Instance.new("Model")
	Model.Name = "Model"
	Model.Parent = MainConfig

	local LightingProps = GetObjectProps()
	for Prop, Value in LightingProps do
		CreateValue(Prop, Value, LightingObject)
	end

	for _,Obj in Lighting:GetChildren() do
		local Clone = Obj:Clone()
		Clone.Parent = Objects
	end
	
	return MainConfig
end
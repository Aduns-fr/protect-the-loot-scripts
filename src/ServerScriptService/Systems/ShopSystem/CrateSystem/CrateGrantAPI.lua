local CrateGrantAPI = {}

-- set by server.server.lua once its local placeChest/getFreeSlot functions exist
CrateGrantAPI.Handler = nil

function CrateGrantAPI.Grant(player, crateId)
	if not CrateGrantAPI.Handler then return false, "Not ready" end
	return CrateGrantAPI.Handler(player, crateId)
end

return CrateGrantAPI

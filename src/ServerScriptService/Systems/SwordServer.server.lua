local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SwordsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SwordsConfig"))
local PlayerDataService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("DataSystem"):WaitForChild("Modules"):WaitForChild("PlayerDataService"))
local EnemyCore = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("RaidSystem"):WaitForChild("Modules"):WaitForChild("EnemyCore"))

local swordsFolder = ReplicatedStorage:WaitForChild("Swords")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local equipRemote = remotes:WaitForChild("EquipSword")
local swordHitRemote = remotes:WaitForChild("SwordHit")
local swordsUpdateRemote = remotes:WaitForChild("SwordsUpdate")

local equippedSword = {}
local lastSwing = {}
local SWING_COOLDOWN = 0.32
local MAX_HIT_DISTANCE = 10
local MAX_TARGETS_PER_SWING = 5

local function getOwnedSwords(player)
	local data = PlayerDataService.GetData(player)
	if not data then return {} end
	local owned = {}
	local weapons = data.Weapons or data.Swords or {}
	for weaponId, amount in pairs(weapons) do
		if (tonumber(amount) or 0) > 0 and SwordsConfig.Swords[weaponId] then
			table.insert(owned, weaponId)
		end
	end
	return owned
end

local function sendSwordsUpdate(player)
	swordsUpdateRemote:FireClient(player, getOwnedSwords(player))
end

local function clearSwordsFromChar(player)
	local character = player.Character
	if not character then return end
	local backpack = player:FindFirstChild("Backpack")
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("IsSword") then
			if backpack then
				-- reparent to backpack first so tool.Unequipped fires on the client
				-- (Destroy() alone doesn't reliably fire Unequipped)
				item.Parent = backpack
				local ref = item
				task.defer(function()
					if ref.Parent then ref:Destroy() end
				end)
			else
				item:Destroy()
			end
		end
	end
end

-- equip a sword by parenting the tool directly to the character (auto-holds it)
-- called only when the player picks one from the swords frame
local function equipSword(player, swordId)
	swordId = tostring(swordId or "")
	local cfg = SwordsConfig.Swords[swordId]
	if not cfg then return false, "Unknown sword" end

	if swordId ~= "WoodenSword" then
		local data = PlayerDataService.GetData(player)
		local weapons = data and (data.Weapons or data.Swords) or {}
		if (tonumber(weapons[swordId]) or 0) <= 0 then
			return false, "You don't own that sword"
		end
	end

	local character = player.Character
	if not character then return false, "Not ready" end

	-- remove any sword already held
	clearSwordsFromChar(player)
	-- also clear backpack so old clones don't stack
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:GetAttribute("IsSword") then item:Destroy() end
		end
	end

	local template = swordsFolder:FindFirstChild("WoodenSword")
	if not template then return false, "Sword model missing" end

	local tool = template:Clone()
	tool.Name = cfg.DisplayName or swordId
	tool:SetAttribute("IsSword", true)
	tool:SetAttribute("SwordId", swordId)
	-- parent to character = immediately held, no hotbar needed
	tool.Parent = character

	equippedSword[player] = swordId
	return true, "Equipped"
end

swordHitRemote.OnServerEvent:Connect(function(player)
	local character = player.Character
	local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not characterRoot or not equippedSword[player] then return end

	local now = os.clock()
	if (lastSwing[player] or 0) + SWING_COOLDOWN > now then return end
	lastSwing[player] = now

	-- enemies are data in EnemyCore now; query authoritatively around the player
	local cfg = SwordsConfig.Swords[equippedSword[player]]
	local damage = cfg and cfg.Damage or 10
	local origin = characterRoot.Position
	local look = characterRoot.CFrame.LookVector
	local hits = EnemyCore.QueryInRange(player, origin, MAX_HIT_DISTANCE)
	table.sort(hits, function(a, b) return a.distSq < b.distSq end)
	local accepted = 0
	for _, info in ipairs(hits) do
		if accepted >= MAX_TARGETS_PER_SWING then break end
		local offset = info.pos - origin
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= 0.1 or look:Dot(flat.Unit) >= -0.15 then
			EnemyCore.Damage(player, info.id, damage)
			accepted += 1
		end
	end
end)

equipRemote.OnServerInvoke = function(player, swordId)
	-- nil means unequip
	if swordId == nil then
		clearSwordsFromChar(player)
		equippedSword[player] = nil
		return true, "Unequipped"
	end
	return equipSword(player, swordId)
end

-- send owned swords list once data is loaded, no auto-equip
Players.PlayerAdded:Connect(function(player)
	task.delay(3, function()
		if player.Parent then sendSwordsUpdate(player) end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	equippedSword[player] = nil
	lastSwing[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.delay(3, function()
		if player.Parent then sendSwordsUpdate(player) end
	end)
end

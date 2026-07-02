local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("BadgeConfig"))

local BadgeProgressService = {}

local ownershipCache = {}
local lastCheck = {}
local started = false

local remotes
local stateRemote
local updateRemote

local function ensureRemotes()
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	stateRemote = remotes:FindFirstChild("BadgeState")
	if not stateRemote then
		stateRemote = Instance.new("RemoteFunction")
		stateRemote.Name = "BadgeState"
		stateRemote.Parent = remotes
	end

	updateRemote = remotes:FindFirstChild("BadgeUpdate")
	if not updateRemote then
		updateRemote = Instance.new("RemoteEvent")
		updateRemote.Name = "BadgeUpdate"
		updateRemote.Parent = remotes
	end
end

local function playerCache(player)
	local cache = ownershipCache[player]
	if not cache then
		cache = {}
		ownershipCache[player] = cache
	end
	return cache
end

local function configuredBadgeId(badgeKey)
	local config = BadgeConfig.Badges[badgeKey]
	local badgeId = config and tonumber(config.BadgeId) or 0
	if badgeId and badgeId > 0 then
		return badgeId
	end
	return nil
end

local function userHasBadge(player, badgeKey)
	local badgeId = configuredBadgeId(badgeKey)
	if not badgeId then
		return false
	end

	local cache = playerCache(player)
	if cache[badgeKey] ~= nil then
		return cache[badgeKey]
	end

	local throttleKey = tostring(player.UserId) .. ":" .. badgeKey
	local now = os.clock()
	if lastCheck[throttleKey] and now - lastCheck[throttleKey] < 10 then
		return false
	end
	lastCheck[throttleKey] = now

	local ok, owns = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
	end)
	if not ok then
		warn("[BadgeProgressService] UserHasBadgeAsync failed", player.Name, badgeKey, owns)
		return false
	end

	cache[badgeKey] = owns == true
	return cache[badgeKey]
end

local function payloadFor(player)
	local ownedCount = 0
	local badges = {}
	for _, badgeKey in ipairs(BadgeConfig.Order) do
		local config = BadgeConfig.Badges[badgeKey]
		local unlocked = userHasBadge(player, badgeKey)
		if unlocked then
			ownedCount += 1
		end
		badges[#badges + 1] = {
			Key = badgeKey,
			BadgeId = tonumber(config.BadgeId) or 0,
			Title = config.Title,
			How = config.How,
			Tip = config.Tip,
			Icon = config.Icon,
			Unlocked = unlocked,
		}
	end
	return {
		Owned = ownedCount,
		Total = #BadgeConfig.Order,
		Badges = badges,
	}
end

function BadgeProgressService.GetState(player)
	return payloadFor(player)
end

function BadgeProgressService.Award(player, badgeKey)
	if not player or not player.Parent then
		return false
	end

	local badgeId = configuredBadgeId(badgeKey)
	if not badgeId then
		return false
	end

	if userHasBadge(player, badgeKey) then
		return true
	end

	local ok, err = pcall(function()
		BadgeService:AwardBadge(player.UserId, badgeId)
	end)
	if not ok then
		warn("[BadgeProgressService] AwardBadge failed", player.Name, badgeKey, err)
		return false
	end

	playerCache(player)[badgeKey] = true
	if updateRemote then
		updateRemote:FireClient(player, payloadFor(player))
	end
	return true
end

function BadgeProgressService.Start()
	if started then
		return
	end
	started = true
	ensureRemotes()
	stateRemote.OnServerInvoke = function(player)
		return payloadFor(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ownershipCache[player] = nil
	end)
end

return BadgeProgressService

--[[
	VoxelManager (ModuleScript - ServerScriptService.Modules)

	PHYSICS FIX:
	  VoxBreaker's CopyProperties copies Anchored = true from every source part
	  (map parts must be anchored). All resulting voxels were therefore anchored
	  and just hung in the air. After CreateHitbox returns, we iterate the result
	  parts, unanchor them, and throw them outward from the impact point.

	SOUND FIX:
	  Plays rbxassetid://1476374050 (block breaking sound) at the impact position
	  each time breakAt is called. A brief invisible Part is used as the anchor
	  for 3D audio rolloff so it sounds like it's coming from the wall/floor.

	CLIENT -> SERVER FLOW:
	  AnimalController detects collision with a Destroyable part (Attribute
	  "Destroyable = true") and fires VoxelRemote:FireServer(hitPosition).
	  Server validates (in round, distance check) then calls breakAt.
	  VoxelManager.breakAt is also called directly from server code
	  (e.g. charge collision in AnimalController triggers it server-side too).

	VOXEL PERSISTENCE FIX:
	  VoxBreaker parents VoxelHolder models to workspace root, which means
	  clearMapDecorations() never touches them. They accumulate across rounds,
	  and their parts stay stuck in cache.InUse forever once destroyed without
	  going through ReturnPart - eventually starving the PartCache so nothing
	  can break. flushVoxels() re-parents each part to workspace BEFORE calling
	  ReturnPart, so the subsequent obj:Destroy() cannot destroy the now-detached
	  parts. They survive in cache.Open and are ready for the next round.

	  A currentGeneration counter invalidates any in-flight cleanup coroutines
	  so they don't attempt to double-return parts after a flush.

	  Call VoxelManager.flushVoxels() from RoundManager just before
	  MapVotingManager.loadMap() at the start of each new round.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local VoxBreaker = require(script.Parent:WaitForChild("VoxBreaker"))

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local VoxelRemote  = RemoteEvents:FindFirstChild("VoxelRemote")
if not VoxelRemote then
	VoxelRemote        = Instance.new("RemoteEvent")
	VoxelRemote.Name   = "VoxelRemote"
	VoxelRemote.Parent = RemoteEvents
end

local BREAK_SIZE        = Vector3.new(10, 10, 10)
local MIN_VOXEL_SIZE    = 3
local RESET_TIME        = -1
local MAX_VALID_DIST    = 24
local VERIFY_RADIUS     = 7
local REQUEST_COOLDOWN  = 0.25
local BREAK_SOUND_ID    = "rbxassetid://1476374050"

local SCATTER_SPEED_MIN = 10
local SCATTER_SPEED_MAX = 26
local SCATTER_UP_MIN    = 4
local SCATTER_UP_MAX    = 16
local SCATTER_SPIN_MAX  = 20

local VOXEL_LIFETIME    = 1.75
local VOXEL_FADE_TIME   = 0.55

local fadeInfo = TweenInfo.new(VOXEL_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local currentGeneration = 0

local cooldowns = {}

local PlayerManager
local AnimalManager

local VoxelManager = {}

-- Sound

local function playBreakSound(position)
	local anchor = Instance.new("Part")
	anchor.Size              = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored          = true
	anchor.CanCollide        = false
	anchor.Transparency      = 1
	anchor.CFrame            = CFrame.new(position)
	anchor.Parent            = workspace

	local sound = Instance.new("Sound")
	sound.SoundId            = BREAK_SOUND_ID
	sound.Volume             = 0.9
	sound.RollOffMaxDistance = 120
	-- route through the SFX group so each client's SFX mute setting applies
	local sfxGroup = game:GetService("SoundService"):FindFirstChild("SFX")
	if sfxGroup and sfxGroup:IsA("SoundGroup") then sound.SoundGroup = sfxGroup end
	sound.Parent             = anchor
	sound:Play()

	Debris:AddItem(anchor, 4)
end

-- Voxel cleanup

local function scheduleVoxelCleanup(part, generation)
	local returned = false
	local destroyingConnection
	destroyingConnection = part.Destroying:Connect(function()
		if returned then return end
		returned = true
		VoxBreaker:DiscardPart(part)
	end)

	task.delay(VOXEL_LIFETIME, function()
		if generation ~= currentGeneration then
			destroyingConnection:Disconnect()
			return
		end
		if not part or not part.Parent then return end

		part.Anchored = true

		local tween = TweenService:Create(part, fadeInfo, { Transparency = 1 })
		tween:Play()
		tween.Completed:Wait()

		if generation ~= currentGeneration then
			destroyingConnection:Disconnect()
			return
		end

		returned = true
		destroyingConnection:Disconnect()
		pcall(function()
			VoxBreaker:ReturnPart(part)
		end)
	end)
end

-- Core break function

function VoxelManager.breakAt(position, size, timeToReset)
	size        = size        or BREAK_SIZE
	timeToReset = timeToReset or RESET_TIME

	local generation = currentGeneration

	task.spawn(function()
		local ok, resultParts = pcall(function()
			return VoxBreaker:CreateHitbox(
				size,
				CFrame.new(position),
				Enum.PartType.Block,
				MIN_VOXEL_SIZE,
				timeToReset
			)
		end)

		if not ok then
			warn("[VoxelManager] Failed to break voxels:", resultParts)
			return
		end

		if not resultParts or #resultParts == 0 then return end

		playBreakSound(position)

		for _, part in ipairs(resultParts) do
			if not part or not part.Parent then continue end
			pcall(function()
				part.Anchored = false

				local towardPart = part.Position - position
				local dist       = towardPart.Magnitude

				local outDir
				if dist > 0.01 then
					outDir = towardPart.Unit
				else
					outDir = Vector3.new(
						(math.random() - 0.5) * 2,
						0.8,
						(math.random() - 0.5) * 2
					).Unit
				end

				local speed   = math.random(SCATTER_SPEED_MIN, SCATTER_SPEED_MAX)
				local upBoost = math.random(SCATTER_UP_MIN,    SCATTER_UP_MAX)

				part.AssemblyLinearVelocity = outDir * speed + Vector3.new(0, upBoost, 0)

				local spin = SCATTER_SPIN_MAX
				part.AssemblyAngularVelocity = Vector3.new(
					(math.random() - 0.5) * spin * 2,
					(math.random() - 0.5) * spin * 2,
					(math.random() - 0.5) * spin * 2
				)

				scheduleVoxelCleanup(part, generation)
			end)
		end
	end)
end

-- Flush function

function VoxelManager.flushVoxels()
	currentGeneration += 1

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("VoxelHolder") then
			for _, part in ipairs(obj:GetChildren()) do
				if part:IsA("BasePart") then
					-- Detach from the model BEFORE returning to cache so that
					-- obj:Destroy() below cannot destroy the now-reparented part.
					-- ReturnPart checks InUse by reference so parent doesn't matter.
					part.Parent = workspace
					pcall(function() VoxBreaker:ReturnPart(part) end)
				end
			end
			obj:Destroy()
		end
	end
end

-- Client request handler

local function findDestroyableNear(position)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local nearest, nearestDistance = nil, math.huge
	for _, part in ipairs(workspace:GetPartBoundsInRadius(position, VERIFY_RADIUS, overlap)) do
		if part:IsA("BasePart") and part.Name ~= "Floor" and part:GetAttribute("Destroyable") == true then
			local distance = (part.Position - position).Magnitude
			if distance < nearestDistance then
				nearest, nearestDistance = part, distance
			end
		end
	end
	return nearest
end

local function onClientRequest(player, position)
	if typeof(position) ~= "Vector3" then return end

	if not PlayerManager.isInRound(player) then return end
	if not PlayerManager.isAlive(player)   then return end

	local now = tick()
	if cooldowns[player] and (now - cooldowns[player]) < REQUEST_COOLDOWN then return end
	cooldowns[player] = now

	local data = AnimalManager.getAnimalData(player)
	if not data or not data.model then return end
	local animalRoot = data.model:FindFirstChild("HumanoidRootPart")
	if not animalRoot then return end
	if (animalRoot.Position - position).Magnitude > MAX_VALID_DIST then return end

	-- Never trust an arbitrary client position. Resolve it back to real,
	-- currently destroyable geometry before creating the voxel hitbox.
	local target = findDestroyableNear(position)
	if not target then return end
	VoxelManager.breakAt(target:GetClosestPointOnSurface(position))
end

-- Init

function VoxelManager.init(playerMgr, animalMgr)
	PlayerManager = playerMgr
	AnimalManager = animalMgr

	VoxelRemote.OnServerEvent:Connect(onClientRequest)

	Players.PlayerRemoving:Connect(function(p)
		cooldowns[p] = nil
	end)

end

return VoxelManager

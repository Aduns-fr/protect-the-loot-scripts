--[[
	RoundManager (ModuleScript - ServerScriptService.Modules)

	DROP-IN DEATHMATCH: continuous loop, intermission (35s) then round (300s,
	entry OPEN via Trigger). Knocked off = back to spawn, re-touch to rejoin.
	Win = most elims when time runs out.

	BOT INTEGRATION (AIManager v2):
	  - registerBotAttacker: a bot hit a player -> if that player falls within
	    the window, the bot's display name shows in the feed and the bot scores.
	  - creditElim: a player knocked a bot off -> full elim credit + cash + feed.
	  - recordBotElim: bot-on-bot kill -> feed entry only.
	  - Standings include bot rows (kind="bot", userId=0 so the client skips
	    the avatar thumbnail).
	  - Bots can show as the in-round elim leader, but a bot can NEVER take the
	    round win - resolveWinner only considers real players.

	LEADER HIGHLIGHT: one Highlight controlled via .Enabled. NEVER hide it by
	only setting Adornee=nil - a workspace-parented Highlight with a nil Adornee
	adorns the entire workspace (the whole-map-red bug).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService  = game:GetService("AnalyticsService")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local ServerStorage     = game:GetService("ServerStorage")
local Debris            = game:GetService("Debris")

local RemoteEvents      = ReplicatedStorage:WaitForChild("RemoteEvents")
local HudRemote         = RemoteEvents:WaitForChild("HudRemote")
local RoundRemote       = RemoteEvents:WaitForChild("RoundRemote")
local EliminationRemote = RemoteEvents:WaitForChild("EliminationRemote")
local CashUpdate        = RemoteEvents:WaitForChild("CashUpdate")

local AntiCheat    = require(script.Parent:WaitForChild("AntiCheat"))
local VoxelManager = require(script.Parent:WaitForChild("VoxelManager"))

local INTERMISSION_DURATION  = 35
local ROUND_DURATION         = 300
local SERVER_CHECK_INTERVAL  = 0.2
local KB_OOB_GRACE           = 1.0
local WINNER_DISPLAY_TIME    = 4
local BLACKSCREEN_COVER_WAIT = 0.85
local BOT_CREDIT_WINDOW      = 5    -- seconds a bot hit stays valid for kill credit

local ELIM_CASH = 10
local WIN_CASH  = 50

-- BOUNTY: knocking off the current sole elim leader (the red-highlighted one)
-- pays double. CHAOS: final 30s of the round, all elim cash doubles and the
-- music speeds up client-side (via the workspace ChaosMode attribute).
local BOUNTY_MULT  = 2
local CHAOS_WINDOW = 30
local chaosActive  = false

local function setChaos(on)
	chaosActive = on
	pcall(function() workspace:SetAttribute("ChaosMode", on) end)
end

-- parked shrink feature, not wired in yet
local SHRINK_START_TIME     = 60
local SHRINK_FINAL_FRACTION = 0.22
local SHRINK_TWEEN_TIME     = 55

local MAP_NAMES = { "Farm", "Baseplate", "Snow", "Lava", "Desert" }

local elimTagTemplate = ServerStorage:FindFirstChild("Elim")

local floor               = nil
local originalFloorSize   = nil
local originalFloorCFrame = nil
local floorShrinkTween    = nil

local RoundManager = {}

local currentPhase      = "intermission"
local currentTimer      = 0
local entryOpen         = false
local roundConns        = {}
local floorCheckThread  = nil
local knockbackGrace    = {}
local roundElims        = {}
local roundParticipants = {}
local elimConns         = {}
local roundCounter      = 0

-- [victim] = { botId, name, time } - set when a bot knocks a player
local botAttacker = {}

local _abortRound = false
function RoundManager.forceEnd() _abortRound = true end

local PlayerManager, AnimalManager, DataManager, CombatManager
local MultiplierManager, RewardsManager, TitleManager, MapVotingManager
local AIManager

-- Leader highlight

local leaderHighlight = nil

local function ensureLeaderHighlight()
	if leaderHighlight and leaderHighlight.Parent then return leaderHighlight end
	leaderHighlight = Instance.new("Highlight")
	leaderHighlight.Name = "KillLeader"
	leaderHighlight.FillColor = Color3.fromRGB(220, 30, 30)
	leaderHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	leaderHighlight.FillTransparency = 0.55
	leaderHighlight.OutlineTransparency = 0
	leaderHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	leaderHighlight.Enabled = false
	leaderHighlight.Parent = workspace
	return leaderHighlight
end

local function updateLeaderHighlight()
	local h = ensureLeaderHighlight()
	if currentPhase ~= "round" then
		h.Enabled = false
		h.Adornee = nil
		return
	end

	-- Only active arena combatants are eligible. Eliminated players may keep their
	-- score for results, but the lobby should never wear the in-round crown.
	local bestAdornee, bestElims = nil, 0
	local tiedCount = 0
	for p, elims in pairs(roundElims) do
		if p.Parent and elims > 0 and PlayerManager.isInRound(p) and PlayerManager.isAlive(p) then
			local character = p.Character
			if character and character.Parent then
				if elims > bestElims then
					bestElims = elims
					bestAdornee = character
					tiedCount = 1
				elseif elims == bestElims then
					tiedCount += 1
				end
			end
		end
	end

	-- A living bot can outscore players and wear the crown mid-round.
	if AIManager and AIManager.getLeader then
		local okB, _, botElims, botMount = pcall(AIManager.getLeader)
		if okB and botMount and botMount.Parent and botElims > 0 then
			if botElims > bestElims then
				bestElims = botElims
				bestAdornee = botMount
				tiedCount = 1
			elseif botElims == bestElims then
				tiedCount += 1
			end
		end
	end

	if bestAdornee and tiedCount == 1 and bestElims > 0 then
		h.Adornee = bestAdornee
		h.Enabled = true
	else
		h.Enabled = false
		h.Adornee = nil
	end
end

local function clearLeaderHighlight()
	if leaderHighlight then
		leaderHighlight.Enabled = false
		leaderHighlight.Adornee = nil
	end
end

local function getTitleManager()
	if TitleManager then return TitleManager end
	local ok, tm = pcall(function()
		return require(game:GetService("ServerScriptService")
			:WaitForChild("Modules"):WaitForChild("TitleManager"))
	end)
	if ok then TitleManager = tm end
	return TitleManager
end

local function getCurrentMapName()
	if not MapVotingManager then return "ARENA" end
	local ok, idx = pcall(function() return MapVotingManager.getCurrentMapIndex() end)
	if ok and idx then return MAP_NAMES[idx] or "ARENA" end
	return "ARENA"
end

local function calcDisplayCash(player, raw)
	local bm = MultiplierManager and MultiplierManager.get(player) or 1
	local tm = RewardsManager and RewardsManager.getCashMultiplier(player) or 1
	return math.floor(raw * bm * tm)
end

local function refreshFloor()
	floor = MapVotingManager and MapVotingManager.getFloor() or nil
	if floor then
		originalFloorSize   = floor.Size
		originalFloorCFrame = floor.CFrame
	else
		originalFloorSize, originalFloorCFrame = nil, nil
	end
end

local function assignLobbyTeam(p)   if _G.setLobbyTeam   then pcall(_G.setLobbyTeam,   p) end end
local function assignPlayingTeam(p) if _G.setPlayingTeam then pcall(_G.setPlayingTeam, p) end end

local function analyticsCustom(p, e, v)
	pcall(function() AnalyticsService:LogCustomEvent(p, e, v or 1) end)
end
local function analyticsEconomy(p, flow, amt, total, tx, sku)
	pcall(function() AnalyticsService:LogEconomyEvent(p, flow, "Cash", amt, total, tx, sku) end)
end

local function formatTime(s)
	return ("%02d:%02d"):format(math.floor(s / 60), s % 60)
end

local function sendCashUpdate(p)
	CashUpdate:FireClient(p, DataManager.getCash(p), DataManager.getWins(p))
end

-- Standings: players + bots, sorted by elims (players win ties for the sort)

local function getBotStandings()
	if not (AIManager and AIManager.getStandings) then return {} end
	local ok, standings = pcall(AIManager.getStandings)
	if ok and type(standings) == "table" then return standings end
	return {}
end

local function buildRoundStandings()
	local rows = {}
	for p in pairs(roundParticipants) do
		if p.Parent then
			table.insert(rows, {
				kind   = "player",
				name   = p.Name,
				userId = p.UserId,
				elims  = roundElims[p] or 0,
			})
		end
	end
	for _, bot in ipairs(getBotStandings()) do
		table.insert(rows, {
			kind   = "bot",
			name   = tostring(bot.name or "Bot"),
			userId = tonumber(bot.userId) or 0,
			elims  = tonumber(bot.elims) or 0,
		})
	end
	table.sort(rows, function(a, b)
		if a.elims ~= b.elims then return a.elims > b.elims end
		if a.kind ~= b.kind then return a.kind == "player" end
		return a.name:lower() < b.name:lower()
	end)
	for i, row in ipairs(rows) do row.pos = i end
	return rows
end

local function getSingleLeader()
	local rows = buildRoundStandings()
	local first = rows[1]
	if not first or first.elims <= 0 then return nil, rows, "empty", 0, 0 end
	local tied = 0
	for _, row in ipairs(rows) do
		if row.elims == first.elims then tied += 1 else break end
	end
	if tied == 1 then return first, rows, "leader", first.elims, 1 end
	return nil, rows, "tie", first.elims, tied
end

local function broadcastMostElims()
	if currentPhase ~= "round" then return end
	local leader, _, status, topElims, tiedCount = getSingleLeader()
	for _, p in ipairs(Players:GetPlayers()) do
		if leader then
			RoundRemote:FireClient(p, "mostElims", leader.name, leader.userId, leader.elims, status)
		elseif status == "tie" then
			RoundRemote:FireClient(p, "mostElims", tiedCount, 0, topElims, status)
		else
			RoundRemote:FireClient(p, "mostElims", nil, 0, 0, status)
		end
	end
	updateLeaderHighlight()
end

local function sendRoundResults()
	local rows = buildRoundStandings()
	for _, p in ipairs(Players:GetPlayers()) do
		RoundRemote:FireClient(p, "roundResults", rows)
	end
end

local fireElimSFX

local function broadcastElim(victim, attacker, botKillerName, botKillerUserId)
	if attacker then
		for _, p in ipairs(Players:GetPlayers()) do
			RoundRemote:FireClient(p, "elimFeed",
				attacker.Name, attacker.UserId, victim.Name, victim.UserId)
		end
	elseif botKillerName then
		for _, p in ipairs(Players:GetPlayers()) do
			RoundRemote:FireClient(p, "elimFeed",
				botKillerName, tonumber(botKillerUserId) or 0, victim.Name, victim.UserId)
		end
	else
		for _, p in ipairs(Players:GetPlayers()) do
			RoundRemote:FireClient(p, "elimFeed",
				victim.Name, victim.UserId, victim.Name, victim.UserId)
		end
	end
end

-- Head elim tags

local function getHead(player)
	local char = player.Character
	return char and char:FindFirstChild("Head")
end

local function ensureHeadTag(player)
	local head = getHead(player)
	if not head then return nil end
	local tag = head:FindFirstChild("ElimTag")
	if not tag then
		if not elimTagTemplate then return nil end
		tag = elimTagTemplate:Clone()
		tag.Name = "ElimTag"
		tag.Parent = head
	end
	return tag
end

local function updateHeadTag(player)
	local tag = ensureHeadTag(player)
	if not tag then return end
	local label = tag:FindFirstChildWhichIsA("TextLabel")
	local score = roundElims[player] or 0
	if label then label.Text = tostring(score) end
	tag.Enabled = PlayerManager.isInRound(player) and PlayerManager.isAlive(player)
end

function RoundManager.refreshHeadTag(player)
	updateHeadTag(player)
end

-- parked shrink helpers, not called yet

local function resetFloor()
	if floorShrinkTween then floorShrinkTween:Cancel(); floorShrinkTween = nil end
	if not floor or not floor.Parent or not originalFloorSize then return end
	floor.Size   = originalFloorSize
	floor.CFrame = originalFloorCFrame
end

local function clearMapDecorations()
	if not floor or not floor.Parent then return end
	local gameMapFolder = floor.Parent
	for _, child in ipairs(gameMapFolder:GetChildren()) do
		if child ~= floor then child:Destroy() end
	end
end

local function startFloorShrink()
	if not floor or not floor.Parent or not originalFloorSize then return end
	if floorShrinkTween then floorShrinkTween:Cancel() end
	local targetSize = Vector3.new(
		originalFloorSize.X * SHRINK_FINAL_FRACTION,
		originalFloorSize.Y,
		originalFloorSize.Z * SHRINK_FINAL_FRACTION
	)
	floorShrinkTween = TweenService:Create(
		floor,
		TweenInfo.new(SHRINK_TWEEN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ Size = targetSize }
	)
	floorShrinkTween:Play()
end

-- Bounds checking

local function isPositionInBounds(pos)
	if not floor or not floor.Parent then return true end
	local fp, fs = floor.Position, floor.Size
	if math.abs(pos.X - fp.X) > fs.X * 0.5 + 4 then return false end
	if math.abs(pos.Z - fp.Z) > fs.Z * 0.5 + 4 then return false end
	local topY = fp.Y + fs.Y * 0.5
	return pos.Y >= topY - 20 and pos.Y <= topY + 300
end

local function isPlayerInBounds(p)
	local char = p.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and not isPositionInBounds(hrp.Position) then return false end
	end
	local ad = AnimalManager.getAnimalData(p)
	if ad and ad.model then
		local ar = ad.model:FindFirstChild("HumanoidRootPart")
		if ar and not isPositionInBounds(ar.Position) then return false end
	end
	return true
end

local function startFloorChecking(delay)
	floorCheckThread = task.spawn(function()
		task.wait(delay or 0)
		local hardKillY = floor and (floor.Position.Y - 200) or -1000
		while currentPhase == "round" do
			for _, p in ipairs(PlayerManager.getAlivePlayers()) do
				local char = p.Character
				if char then
					local hrp = char:FindFirstChild("HumanoidRootPart")
					if hrp and hrp.Position.Y < hardKillY then
						RoundManager.eliminatePlayer(p)
						continue
					end
				end
				local ad = AnimalManager.getAnimalData(p)
				if ad and ad.model then
					local ar = ad.model:FindFirstChild("HumanoidRootPart")
					if ar and ar.Position.Y < hardKillY then
						RoundManager.eliminatePlayer(p)
						continue
					end
				end
				local grace = knockbackGrace[p]
				if grace and tick() < grace then continue end
				if not isPlayerInBounds(p) then RoundManager.eliminatePlayer(p) end
			end
			task.wait(SERVER_CHECK_INTERVAL)
		end
	end)
end

local function stopFloorChecking()
	if floorCheckThread then task.cancel(floorCheckThread); floorCheckThread = nil end
end

local function cleanupRoundConns()
	for _, c in ipairs(roundConns) do c:Disconnect() end
	table.clear(roundConns)
end

local function zeroPlayerVelocities(p)
	local char = p.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			pcall(function()
				hrp.AssemblyLinearVelocity  = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end
	local ad = AnimalManager.getAnimalData(p)
	if ad and ad.model then
		for _, part in ipairs(ad.model:GetDescendants()) do
			if part:IsA("BasePart") then
				pcall(function()
					part.AssemblyLinearVelocity  = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
				end)
			end
		end
	end
end

local function unhookElim(player)
	local c = elimConns[player]
	if c then c:Disconnect(); elimConns[player] = nil end
end

local function hookElim(player)
	unhookElim(player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	elimConns[player] = hum.Died:Connect(function()
		RoundManager.eliminatePlayer(player)
	end)
end

local function teleportPlayerIntoArena(player)
	local floorPart = (MapVotingManager and MapVotingManager.getFloor()) or floor
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	AntiCheat.grantTeleportGrace(player)
	zeroPlayerVelocities(player)

	if floorPart then
		local topY = floorPart.Position.Y + floorPart.Size.Y * 0.5 + 5
		local maxR = math.min(floorPart.Size.X, floorPart.Size.Z) * 0.40
		local ang  = math.random() * 2 * math.pi
		local r    = maxR * (0.4 + math.random() * 0.6)
		local x    = floorPart.Position.X + math.cos(ang) * r
		local z    = floorPart.Position.Z + math.sin(ang) * r
		pcall(function()
			hrp.CFrame = CFrame.lookAt(
				Vector3.new(x, topY, z),
				Vector3.new(floorPart.Position.X, topY, floorPart.Position.Z)
			)
		end)
	else
		PlayerManager.teleportToArena(player)
	end

	task.defer(function() zeroPlayerVelocities(player) end)
end

local function spawnWinVFX(winner)
	local char = winner.Character
	if not char then return end
	local effectParent = char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("HumanoidRootPart")
	if not effectParent then return end
	local vfx = ServerStorage:FindFirstChild("VFX")
	if not vfx then return end
	local win = vfx:FindFirstChild("Win")
	if not win then return end
	local att = win:FindFirstChild("Attachment")
	if not att then return end
	local clone = att:Clone()
	clone.Parent = effectParent
	Debris:AddItem(clone, 3)
end

-- Public API

function RoundManager.getCurrentPhase() return currentPhase end
function RoundManager.isEntryOpen()     return entryOpen    end

function RoundManager.getElims(player)
	return roundElims[player] or 0
end

function RoundManager.setAIManager(ai)
	AIManager = ai
end

-- A bot landed a hit on this player. If they fall within the window and no
-- real player has fresher credit, the bot gets the elim + the feed entry.
function RoundManager.registerBotAttacker(victim, botId, displayName, avatarUserId)
	if victim then
		botAttacker[victim] = {
			botId = botId,
			name = displayName,
			userId = tonumber(avatarUserId) or 0,
			time = os.clock(),
		}
	end
end

function RoundManager.sendHudToPlayer(p)
	if currentPhase == "intermission" then
		HudRemote:FireClient(p, formatTime(currentTimer), "INTERMISSION")
	elseif currentPhase == "round" then
		HudRemote:FireClient(p, formatTime(currentTimer), getCurrentMapName())
	end
end

function RoundManager.registerKnockback(victim)
	knockbackGrace[victim] = tick() + KB_OOB_GRACE
	AntiCheat.grantKnockbackGrace(victim)
end

function RoundManager.requestJoin(player)
	if currentPhase ~= "round" or not entryOpen then
		RoundRemote:FireClient(player, "entryClosed")
		return
	end
	if PlayerManager.isInRound(player) and PlayerManager.isAlive(player) then return end
	if PlayerManager.isAFK(player) then
		RoundRemote:FireClient(player, "afkBlocked")
		return
	end

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end

	PlayerManager.setInRound(player, true)
	assignPlayingTeam(player)
	if roundElims[player] == nil then roundElims[player] = 0 end
	roundParticipants[player] = true
	broadcastMostElims()

	teleportPlayerIntoArena(player)

	if AnimalManager.hasAnimal(player) then
		AnimalManager.switchMode(player, "mount")
	else
		AnimalManager.spawnAnimal(player, AnimalManager.getDefaultAnimalName(), "mount")
	end

	hookElim(player)
	updateHeadTag(player)
	RoundManager.sendHudToPlayer(player)

	analyticsCustom(player, "round_joined", 1)
	RoundRemote:FireClient(player, "joinedRound")
end

local function fireElimSFXImpl(victim)
	local sfx = SoundService:FindFirstChild("SFX")
	local effects = sfx and sfx:FindFirstChild("Effects")
	if not effects then return end
	local sounds = {}
	for _, s in ipairs(effects:GetChildren()) do
		if s:IsA("Sound") then table.insert(sounds, s) end
	end
	if #sounds == 0 then return end
	local soundId = sounds[math.random(#sounds)].SoundId
	for _, p in ipairs(Players:GetPlayers()) do
		RoundRemote:FireClient(p, "playElimSFX", soundId)
	end
end
fireElimSFX = fireElimSFXImpl

function RoundManager.eliminatePlayer(victim)
	local state = PlayerManager.getState(victim)
	if not state or not state.inRound or not state.alive then return end

	if CombatManager and CombatManager.tryConsumeRebirth(victim) then
		knockbackGrace[victim] = tick() + 2
		botAttacker[victim] = nil
		CombatManager.clearAttacker(victim)
		teleportPlayerIntoArena(victim)
		if AnimalManager.hasAnimal(victim) then AnimalManager.switchMode(victim, "mount") end
		RoundRemote:FireClient(victim, "rebirthSaved")
		return
	end

	-- Bounty check before scoring mutates the standings.
	local leaderBefore = getSingleLeader()
	local victimWasLeader = leaderBefore ~= nil
		and leaderBefore.kind == "player"
		and leaderBefore.name == victim.Name

	fireElimSFX(victim)
	PlayerManager.setAlive(victim, false)
	PlayerManager.setInRound(victim, false)
	knockbackGrace[victim] = nil
	unhookElim(victim)
	assignLobbyTeam(victim)

	local attacker = nil
	if DataManager and CombatManager then
		local candidate = CombatManager.getLastAttacker(victim)
		if candidate and candidate ~= victim
			and candidate.Parent
			and roundParticipants[candidate] then
			attacker = candidate
			DataManager.addElim(attacker)
			roundElims[attacker] = (roundElims[attacker] or 0) + 1
			roundParticipants[attacker] = true
			updateHeadTag(attacker)

			local cashReward = ELIM_CASH
			if victimWasLeader then cashReward *= BOUNTY_MULT end
			if chaosActive then cashReward *= 2 end
			if CombatManager.consumeCashBonus then
				cashReward *= CombatManager.consumeCashBonus(attacker)
			end

			local display = calcDisplayCash(attacker, cashReward)
			DataManager.addCash(attacker, cashReward)
			sendCashUpdate(attacker)
			RoundRemote:FireClient(attacker, "earnedCash", display)
			analyticsEconomy(attacker, Enum.AnalyticsEconomyFlowType.Source,
				cashReward, DataManager.getCash(attacker), "Gameplay", "elim_reward")
			analyticsCustom(attacker, "player_eliminated_enemy", 1)
			if victimWasLeader then analyticsCustom(attacker, "bounty_claimed", 1) end
			local tm = getTitleManager()
			if tm then pcall(tm.onElim, attacker, victim) end
		end
		CombatManager.clearAttacker(victim)
	end

	-- no player credit? check whether a bot's hit is fresh enough to claim it
	local botKillerName = nil
	local botKillerUserId = 0
	local ba = botAttacker[victim]
	botAttacker[victim] = nil
	if not attacker and ba and (os.clock() - ba.time) <= BOT_CREDIT_WINDOW then
		botKillerName = ba.name
		botKillerUserId = tonumber(ba.userId) or 0
		if AIManager and AIManager.creditBotElim then
			pcall(AIManager.creditBotElim, ba.botId)
		end
	end

	analyticsCustom(victim, "player_eliminated", 1)
	broadcastElim(victim, attacker, botKillerName, botKillerUserId)
	broadcastMostElims()

	updateHeadTag(victim)

	if AnimalManager.hasAnimal(victim) then AnimalManager.switchMode(victim, "follow") end
	PlayerManager.teleportToSpawn(victim)
	RoundManager.sendHudToPlayer(victim)
	RoundRemote:FireClient(victim, "eliminated")
end

-- A player knocked a bot off the map. Mirrors the PvP attacker reward path.
-- victimElims comes from AIManager (the bot is already flagged dead, so it no
-- longer appears in standings - we can't look its score up here).
function RoundManager.creditElim(attacker, botDisplayName, botAvatarUserId, victimElims)
	if not attacker or not attacker.Parent then return end
	if currentPhase ~= "round" or not roundParticipants[attacker] then return end

	-- bounty: the dead bot was the sole leader iff its score beats everyone
	-- still on the board
	victimElims = tonumber(victimElims) or 0
	local rows = buildRoundStandings()
	local topRemaining = (rows[1] and rows[1].elims) or 0
	local victimWasLeader = victimElims > 0 and victimElims > topRemaining

	DataManager.addElim(attacker)
	roundElims[attacker] = (roundElims[attacker] or 0) + 1
	roundParticipants[attacker] = true
	updateHeadTag(attacker)

	local cashReward = ELIM_CASH
	if victimWasLeader then cashReward *= BOUNTY_MULT end
	if chaosActive then cashReward *= 2 end
	if CombatManager and CombatManager.consumeCashBonus then
		cashReward *= CombatManager.consumeCashBonus(attacker)
	end

	local display = calcDisplayCash(attacker, cashReward)
	DataManager.addCash(attacker, cashReward)
	sendCashUpdate(attacker)
	RoundRemote:FireClient(attacker, "earnedCash", display)
	analyticsCustom(attacker, "ai_eliminated", 1)
	if victimWasLeader then analyticsCustom(attacker, "bounty_claimed", 1) end
	fireElimSFX(nil)

	for _, p in ipairs(Players:GetPlayers()) do
		RoundRemote:FireClient(p, "elimFeed",
			attacker.Name, attacker.UserId, botDisplayName or "Bot", tonumber(botAvatarUserId) or 0)
	end
	broadcastMostElims()
end

-- Bot killed a bot (or fell off): feed entry, no cash, no player stats.
function RoundManager.recordBotElim(killerName, killerUserId, victimName, victimUserId)
	if currentPhase ~= "round" then return end
	fireElimSFX(nil)
	killerName = tostring(killerName or "Bot")
	victimName = tostring(victimName or "Bot")
	for _, p in ipairs(Players:GetPlayers()) do
		RoundRemote:FireClient(p, "elimFeed", killerName, tonumber(killerUserId) or 0, victimName, tonumber(victimUserId) or 0)
	end
	broadcastMostElims()
end

function RoundManager.cleanupPlayer(player)
	unhookElim(player)
	roundElims[player]        = nil
	roundParticipants[player] = nil
	knockbackGrace[player]    = nil
	botAttacker[player]       = nil
end

local function isActuallyOutOfBounds(player)
	local floor = PlayerManager.getFloor()
	if not floor or not floor:IsA("BasePart") then return false end

	local data = AnimalManager.getAnimalData(player)
	local model = data and data.model
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then
		local character = player.Character
		root = character and character:FindFirstChild("HumanoidRootPart")
	end
	if not root or not root:IsA("BasePart") then return false end

	local position = root.Position
	local floorPosition = floor.Position
	local floorSize = floor.Size
	local floorTop = floorPosition.Y + floorSize.Y * 0.5
	return math.abs(position.X - floorPosition.X) > floorSize.X * 0.5 + 3
		or math.abs(position.Z - floorPosition.Z) > floorSize.Z * 0.5 + 3
		or position.Y < floorTop - 25
		or position.Y > floorTop + 300
end

function RoundManager.init(playerMgr, animalMgr, dataMgr, combatMgr, multiplierMgr, rewardsMgr, mapVotingMgr)
	PlayerManager, AnimalManager, DataManager, CombatManager =
		playerMgr, animalMgr, dataMgr, combatMgr
	MultiplierManager, RewardsManager, MapVotingManager =
		multiplierMgr, rewardsMgr, mapVotingMgr

	if not elimTagTemplate then
		warn("[RoundManager] ServerStorage.Elim not found — head elim tags disabled")
	end

	EliminationRemote.OnServerEvent:Connect(function(reporter, reason)
		if typeof(reason) ~= "string" or reason ~= "outOfBounds" then return end
		if currentPhase ~= "round" then return end
		if not PlayerManager.isInRound(reporter) then return end
		if not PlayerManager.isAlive(reporter)   then return end
		local grace = knockbackGrace[reporter]
		if grace and tick() < grace then return end
		if not isActuallyOutOfBounds(reporter) then return end
		RoundManager.eliminatePlayer(reporter)
	end)
end

local function resetEveryoneToLobby(announce)
	clearLeaderHighlight()
	for _, p in ipairs(Players:GetPlayers()) do
		PlayerManager.setInRound(p, false)
		PlayerManager.setAlive(p, false)
		assignLobbyTeam(p)
		unhookElim(p)
		if AnimalManager.hasAnimal(p) then AnimalManager.switchMode(p, "follow") end
		PlayerManager.teleportToSpawn(p)
		updateHeadTag(p)
		if announce then RoundRemote:FireClient(p, "intermission") end
	end
end

-- Only real players can win the round - bots show in standings but never
-- take the W. If a bot tops the board, the best PLAYER still gets the win.
local function resolveWinner()
	sendRoundResults()
	local topScore, winners = 0, {}
	for p, score in pairs(roundElims) do
		if p.Parent and score > 0 then
			if score > topScore then
				topScore = score
				winners = { p }
			elseif score == topScore then
				table.insert(winners, p)
			end
		end
	end

	if topScore > 0 and #winners == 1 then
		local winner = winners[1]
		DataManager.addWin(winner)
		DataManager.addCash(winner, WIN_CASH)
		sendCashUpdate(winner)
		RoundRemote:FireClient(winner, "earnedCash", calcDisplayCash(winner, WIN_CASH))
		analyticsEconomy(winner, Enum.AnalyticsEconomyFlowType.Source,
			WIN_CASH, DataManager.getCash(winner), "Gameplay", "win_reward")
		local tm = getTitleManager()
		if tm then pcall(tm.onDataChanged, winner) end
		spawnWinVFX(winner)
		for _, p in ipairs(Players:GetPlayers()) do
			RoundRemote:FireClient(p, "roundWinner", winner.Name, winner.UserId, topScore)
		end

	elseif topScore > 0 and #winners > 1 then
		for _, w in ipairs(winners) do
			DataManager.addCash(w, WIN_CASH)
			sendCashUpdate(w)
			RoundRemote:FireClient(w, "earnedCash", calcDisplayCash(w, WIN_CASH))
		end
		for _, p in ipairs(Players:GetPlayers()) do
			RoundRemote:FireClient(p, "noWinner")
		end

	else
		for _, p in ipairs(Players:GetPlayers()) do
			RoundRemote:FireClient(p, "noWinner")
		end
	end
end

function RoundManager.startLoop()
	PlayerManager.startElimListener(function(p)
		if currentPhase == "round" and PlayerManager.isInRound(p) and PlayerManager.isAlive(p) then
			RoundManager.eliminatePlayer(p)
		else
			PlayerManager.teleportToSpawn(p)
		end
	end)

	while true do
		currentPhase = "intermission"
		entryOpen    = false
		cleanupRoundConns()
		stopFloorChecking()
		table.clear(knockbackGrace)
		table.clear(roundElims)
		table.clear(roundParticipants)
		table.clear(botAttacker)

		if roundCounter > 0 then
			for _, p in ipairs(Players:GetPlayers()) do
				RoundRemote:FireClient(p, "blackScreenCover")
			end
			task.wait(BLACKSCREEN_COVER_WAIT)
			resetEveryoneToLobby(true)
			for _, p in ipairs(Players:GetPlayers()) do
				RoundRemote:FireClient(p, "blackScreenReveal")
			end
		else
			resetEveryoneToLobby(true)
		end

		if MapVotingManager then MapVotingManager.startVoting() end

		for i = INTERMISSION_DURATION, 1, -1 do
			currentTimer = i
			for _, p in ipairs(Players:GetPlayers()) do
				HudRemote:FireClient(p, formatTime(i), "INTERMISSION")
			end
			task.wait(1)
		end

		VoxelManager.flushVoxels()
		if MapVotingManager then
			MapVotingManager.loadMap(MapVotingManager.getWinningMapIndex())
		end
		refreshFloor()

		roundCounter += 1
		currentPhase  = "round"
		currentTimer  = ROUND_DURATION
		entryOpen     = true
		if CombatManager and CombatManager.onRoundStart then
			CombatManager.onRoundStart()
		end

		local mapName = getCurrentMapName()
		for _, p in ipairs(Players:GetPlayers()) do
			HudRemote:FireClient(p, formatTime(ROUND_DURATION), mapName)
			RoundRemote:FireClient(p, "roundOpen")
		end
		broadcastMostElims()

		startFloorChecking(0.5)
		if AIManager then task.spawn(AIManager.spawnForRound) end

		for i = ROUND_DURATION, 1, -1 do
			if _abortRound then _abortRound = false; break end
			currentTimer = i
			-- final-30s chaos: double elim cash + faster music on every client
			if i == CHAOS_WINDOW and not chaosActive then setChaos(true) end
			for _, p in ipairs(Players:GetPlayers()) do
				HudRemote:FireClient(p, formatTime(i), mapName)
			end
			task.wait(1)
		end

		entryOpen = false
		setChaos(false)
		stopFloorChecking()
		cleanupRoundConns()
		table.clear(knockbackGrace)
		clearLeaderHighlight()

		if AIManager then AIManager.clearAll() end
		resolveWinner()
		task.wait(WINNER_DISPLAY_TIME)
	end
end

return RoundManager

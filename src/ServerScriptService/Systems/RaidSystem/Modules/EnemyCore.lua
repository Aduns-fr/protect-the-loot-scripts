--!nonstrict
-- EnemyCore: data-driven enemy/wave system. Server holds enemies as pure data
-- (no models/Humanoids); clients render rigs via EnemyController. Movement is math
-- from island edges to the stash, then back out if they steal loot.
-- Current raid runtime; preserves RaidConfig tuning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local PlotService = require(ServerScriptService.Systems.PlotSystem.Modules.PlotService)
local RaidConfig = require(ReplicatedStorage.Configs.RaidConfig)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local MonetizationAnalytics = require(ServerScriptService.Systems.DataSystem.Modules.MonetizationAnalytics)
local GamePassService = require(ServerScriptService.Systems.DataSystem.Modules.GamePassService)
local BadgeProgressService = require(ServerScriptService.Systems.DataSystem.Modules.BadgeProgressService)
local GamePassConfig = require(ReplicatedStorage.Configs.GamePassConfig)
local DeveloperProductsConfig = require(ReplicatedStorage.Configs.DeveloperProductsConfig)
local PlotRoute = require(ReplicatedStorage.RaidShared.PlotRoute)

local EnemyCore = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartRaidRemote = Remotes:WaitForChild("StartRaid")
local RaidStatusRemote = Remotes:WaitForChild("RaidStatus")
local RaidControlRemote = Remotes:WaitForChild("RaidControl")
local RaidResultsRemote = Remotes:WaitForChild("RaidResults")
local CashPopupRemote = Remotes:WaitForChild("CashPopup")
local EnemyStreamRemote = Remotes:WaitForChild("EnemyStream")

local STREAM_INTERVAL = 0.1

local activeRaids, playerState, lastStarted, beyondHundred = {}, {}, {}, {}
local sessions = {} -- player -> { enemies = {id->e}, nextId, alive, carriedLoot, drops }
local raidAnalyticsSessions = {}
local reviveState, pendingReviveStarts = {}, {}
local REVIVE_WINDOW_SECONDS = 120

local finish, runWave -- forward declarations

-- ===== pure tuning helpers =====
local function waveSpawnInterval(wave)
	local t = RaidConfig.Timing
	local lo, hi = t.SpawnInterval or 0.5, t.SpawnIntervalEarly or 1.2
	local ramp = t.SpawnIntervalRampWaves or 40
	local alpha = math.clamp((wave - 1) / (ramp - 1), 0, 1)
	return hi + (lo - hi) * alpha
end
local function waveBetweenDelay(wave)
	local t = RaidConfig.Timing
	local lo, hi = t.BetweenWaves or 2.5, t.BetweenWavesEarly or 9.0
	local ramp = t.BetweenWavesRampWaves or 50
	local alpha = math.clamp((wave - 1) / (ramp - 1), 0, 1)
	return hi + (lo - hi) * alpha
end
local function waveHealthMultiplier(wave)
	local w = math.max(1, tonumber(wave) or 1)
	local waves = RaidConfig.Waves or {}
	return (1 + (w - 1) * (waves.HealthLinear or 0.035)) * ((waves.HealthExpo or 1.045) ^ (w - 1))
end
local function rewardMultiplier(wave)
	local w = math.max(1, tonumber(wave) or 1)
	return 1 + (w - 1) * ((RaidConfig.Waves and RaidConfig.Waves.CashWaveBonus) or 0.045)
end
local function chooseMob(wave)
	local total = 0
	for _, id in ipairs(RaidConfig.MobOrder) do
		local cfg = RaidConfig.MobStats[id]
		if cfg and wave >= (cfg.UnlockWave or 1) then total += cfg.Weight or 1 end
	end
	if total <= 0 then local id = RaidConfig.MobOrder[1]; return id, RaidConfig.MobStats[id] end
	local r = Random.new(os.clock() * 1000 + wave):NextNumber(0, total)
	local acc = 0
	for _, id in ipairs(RaidConfig.MobOrder) do
		local cfg = RaidConfig.MobStats[id]
		if cfg and wave >= (cfg.UnlockWave or 1) then
			acc += cfg.Weight or 1
			if r <= acc then return id, cfg end
		end
	end
	local id = RaidConfig.MobOrder[1]; return id, RaidConfig.MobStats[id]
end
local function chooseBoss(wave)
	local pick = RaidConfig.BossOrder[1]
	for _, id in ipairs(RaidConfig.BossOrder or {}) do
		local cfg = RaidConfig.MobStats[id]
		if cfg and wave >= (cfg.BossWave or 10) then pick = id end
	end
	return pick, RaidConfig.MobStats[pick]
end

-- ===== state / session =====
local function state(p)
	local s = playerState[p]
	if not s then
		s = { speed = 1, auto = false, stopping = false, wave = 0, loot = 500, maxLoot = 500,
			stats = { enemiesDefeated = 0, wavesCleared = 0, cashEarned = 0, score = 0, lootStolen = 0, lootRecovered = 0 },
			waveStats = { spawned = 0, finished = 0, killed = 0 } }
		playerState[p] = s
	end
	return s
end
local function getSession(p)
	local s = sessions[p]
	if not s then s = { enemies = {}, nextId = 1, alive = 0, carriedLoot = 0, drops = {} }; sessions[p] = s end
	return s
end
local function buildRoute(plot, seed)
	return PlotRoute.BuildRoute(plot, seed)
end

local function send(p, a, d) if p and p.Parent then RaidStatusRemote:FireClient(p, a, d or {}) end end
local function clampReviveTier(tier)
	local tiers = DeveloperProductsConfig.ReviveTiers or {}
	if #tiers <= 0 then return 1 end
	return math.clamp(math.floor(tonumber(tier) or 1), 1, #tiers)
end
local function openReviveOffer(p, diedWave)
	local info = reviveState[p] or { tier = 1 }
	info.tier = clampReviveTier(info.tier)
	info.available = true
	info.nextWave = math.max(1, math.floor(tonumber(diedWave) or 1) + 1)
	info.expiresAt = os.clock() + REVIVE_WINDOW_SECONDS
	reviveState[p] = info
end
local function clearReviveOffer(p)
	reviveState[p] = nil
	pendingReviveStarts[p] = nil
end
local function scaledWait(p, sec)
	local e = 0
	while e < sec do
		local st = state(p)
		local step = math.min(0.1, sec - e)
		task.wait(step / math.max(1, st.speed or 1))
		e += step
		if st.stopping or not activeRaids[p] or not p.Parent then break end
	end
end

local function waveProgress(p)
	local st = state(p); local ws = st.waveStats
	local total = math.max(1, ws.spawned or 0)
	send(p, "WaveProgress", { wave = st.wave, progress = (ws.killed or 0) / total, killed = ws.killed or 0, total = total })
end
local function sendLoot(p)
	local st = state(p)
	local sess = getSession(p)
	send(p, "Loot", { loot = st.loot, maxLoot = st.maxLoot, carriers = sess.carriedLoot or 0, stolen = st.stats.lootStolen or 0, recovered = st.stats.lootRecovered or 0 })
end
local function stealLoot(p, amount)
	local st = state(p)
	amount = math.min(math.max(1, math.floor(tonumber(amount) or 1)), st.loot)
	if amount <= 0 then return 0 end
	st.loot -= amount
	sendLoot(p)
	return amount
end
local function loseLoot(p, amount)
	local st = state(p)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	st.stats.lootStolen += amount
	sendLoot(p)
	local sess = getSession(p)
	-- Defeat only when the stash is empty AND nothing recoverable remains (no carriers, no ground drops)
	if st.loot <= 0 and (sess.carriedLoot or 0) <= 0 and next(sess.drops) == nil then st.stopping = true end
end
local function recoverLoot(p, amount)
	local st = state(p)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	st.loot = math.min(st.maxLoot, st.loot + amount)
	st.stats.lootRecovered += amount
	st.stats.score += amount * 30
	sendLoot(p)
end
local function updateHighestWave(p, wave)
	local leaderstats = p:FindFirstChild("leaderstats")
	local hw = leaderstats and leaderstats:FindFirstChild("Highest Wave")
	wave = math.max(0, math.floor(tonumber(wave) or 0))
	if hw and wave > hw.Value then hw.Value = wave end
	local data = PlayerDataService.GetData(p)
	local mapId = PlayerDataService.GetActiveMap and PlayerDataService.GetActiveMap(p) or 1
	if data and data.Maps and data.Maps[mapId] then
		local md = data.Maps[mapId]
		md.HighestWave = math.max(tonumber(md.HighestWave) or 0, wave)
	end
end

local droppedFolder = workspace:FindFirstChild("DroppedLoot") or Instance.new("Folder")
droppedFolder.Name = "DroppedLoot"
droppedFolder.Parent = workspace

local function dropLoot(p, position, amount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount <= 0 then return end
	local sess = getSession(p)
	local part = Instance.new("Part")
	part.Name = "DroppedLoot"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.4, 2.4, 2.4)
	part.Color = Color3.fromRGB(255, 210, 70)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = false
	part.Position = position + Vector3.new(0, 2.5, 0)
	part:SetAttribute("OwnerUserId", p.UserId)
	part:SetAttribute("LootAmount", amount)
	part.Parent = droppedFolder
	sess.drops[part] = amount
	local collected = false
	part.Touched:Connect(function(hit)
		if collected then return end
		local character = p.Character
		if not character or not hit:IsDescendantOf(character) then return end
		collected = true
		sess.drops[part] = nil
		recoverLoot(p, amount)
		part:Destroy()
	end)
	task.delay(25, function()
		if part.Parent and not collected then
			collected = true
			sess.drops[part] = nil
			part:Destroy()
			-- Unrecovered loot counts as stolen; may end the raid in defeat
			if p.Parent then loseLoot(p, amount) end
		end
	end)
end

-- ===== enemy lifecycle =====
local function removeEnemy(p, e, reason)
	local sess = sessions[p]
	if not sess or not sess.enemies[e.id] then return end
	sess.enemies[e.id] = nil
	sess.alive = math.max(0, sess.alive - 1)
	EnemyStreamRemote:FireClient(p, "despawn", { id = e.id, reason = reason })
end
local function award(p, e)
	if e.awarded then return end
	e.awarded = true
	if (e.carrying or 0) > 0 then
		local sess = getSession(p)
		sess.carriedLoot = math.max(0, (sess.carriedLoot or 0) - e.carrying)
		local pos = e.mover and e.mover:At(e.distance) or Vector3.zero
		dropLoot(p, pos, e.carrying)
		e.carrying = 0
		sendLoot(p)
	end
	local st = state(p)
	local reward = e.cashReward or 0
	if e.isBoss then reward += math.floor(150 + st.wave * 8) end
	st.stats.enemiesDefeated += 1
	st.stats.cashEarned += reward
	st.stats.score += reward * 10 + st.wave * (e.isBoss and 60 or 15) + (e.isBoss and 1000 or 0)
	st.waveStats.killed += 1
	st.waveStats.finished += 1
	CashPopupRemote:FireClient(p, reward)
	waveProgress(p)
	local _d = PlayerDataService.GetData(p)
	local _mid = PlayerDataService.GetActiveMap and PlayerDataService.GetActiveMap(p) or 1
	local _m = _d and _d.Maps and _d.Maps[_mid]
	if _m then _m.EnemiesDefeated = (_m.EnemiesDefeated or 0) + 1 end
end
local function spawnEnemy(p, wave, isBoss)
	local id, cfg
	if isBoss then id, cfg = chooseBoss(wave) else id, cfg = chooseMob(wave) end
	if not cfg then return false end
	local sess = getSession(p)
	local maxHealth = math.floor((cfg.MaxHealth or 100) * waveHealthMultiplier(wave))
	local eid = sess.nextId; sess.nextId += 1
	local routeSeed = p.UserId + wave * 1009 + eid * 9176 + (isBoss and 41 or 0)
	local mover = buildRoute(PlotService.GetPlayerPlot(p), routeSeed)
	if not mover then return false end
	local stealAmount = isBoss and math.max(8, math.floor(maxHealth / 250)) or math.max(1, math.floor((cfg.CoreDamage or 10) / 4))
	local e = {
		id = eid, name = id, isBoss = isBoss == true,
		routeSeed = routeSeed, mover = mover,
		distance = 0,
		speed = cfg.Speed or RaidConfig.MobWalkSpeed or 11,
		slowMult = 1, slowUntil = 0,
		health = maxHealth, maxHealth = maxHealth,
		cashReward = math.floor((cfg.CashReward or 8) * rewardMultiplier(wave)),
		stealAmount = stealAmount,
		carrying = 0,
		phase = "approach",
		scale = cfg.Scale or 1,
		awarded = false, finished = false, dead = false,
	}
	sess.enemies[eid] = e
	sess.alive += 1
	state(p).waveStats.spawned += 1
	EnemyStreamRemote:FireClient(p, "spawn", {
		id = eid, name = id, isBoss = e.isBoss, maxHealth = maxHealth, scale = e.scale, speed = e.speed,
		routePoints = mover.points,
	})
	if e.isBoss then send(p, "Boss", { wave = wave, health = maxHealth, maxHealth = maxHealth }) end
	return true
end
local function clearEnemies(p)
	local sess = sessions[p]
	if not sess then return end
	table.clear(sess.enemies)
	sess.alive = 0
	sess.carriedLoot = 0
	for drop in pairs(sess.drops or {}) do
		if drop and drop.Parent then drop:Destroy() end
	end
	table.clear(sess.drops)
	if p and p.Parent then EnemyStreamRemote:FireClient(p, "clear", {}) end
end

-- ===== movement + streaming (single Heartbeat for all players) =====
local streamAccum = 0
local function step(dt)
	streamAccum += dt
	local doStream = false
	if streamAccum >= STREAM_INTERVAL then streamAccum -= STREAM_INTERVAL; doStream = true end
	for p, sess in pairs(sessions) do
		if activeRaids[p] then
			local st = playerState[p]
			local gspeed = (st and st.speed) or 1
			local now = os.clock()
			local syncList = doStream and {} or nil
			for id, e in pairs(sess.enemies) do
				if e.slowUntil > 0 and now >= e.slowUntil then e.slowMult = 1; e.slowUntil = 0 end
				local v = e.speed * e.slowMult * gspeed
				e.distance += v * dt
				local mover = e.mover
				if not mover then
					removeEnemy(p, e, "end")
				elseif e.distance >= mover.length then
					if e.phase == "approach" then
						local taken = stealLoot(p, e.stealAmount or 1)
						if taken > 0 then
							e.phase = "escape"
							e.carrying = taken
							e.mover = PlotRoute.ReverseMover(e.mover)
							e.distance = 0
							e.speed *= e.isBoss and 0.82 or 0.74
							sess.carriedLoot = (sess.carriedLoot or 0) + taken
							EnemyStreamRemote:FireClient(p, "carry", { id = e.id, carrying = taken, routePoints = e.mover and e.mover.points })
							sendLoot(p)
						else
							if st then st.waveStats.finished += 1 end
							removeEnemy(p, e, "empty")
						end
					else
						if not e.finished then
							e.finished = true
							if st then st.waveStats.finished += 1 end
							sess.carriedLoot = math.max(0, (sess.carriedLoot or 0) - (e.carrying or 0))
							loseLoot(p, e.carrying or 0)
						end
						removeEnemy(p, e, "escaped")
					end
				elseif syncList then
					syncList[#syncList + 1] = { e.id, math.floor(e.distance * 10) / 10, math.floor(e.health), math.floor(v * 10) / 10 }
				end
			end
			if syncList and #syncList > 0 then EnemyStreamRemote:FireClient(p, "sync", syncList) end
		end
	end
end

-- ===== wave orchestration =====
function runWave(p, plot, wave)
	local st = state(p)
	st.wave = wave
	local waves = RaidConfig.Waves or {}
	local boss = wave % (waves.BossEvery or 10) == 0
	local rawCount = (waves.BaseCount or 4) + math.floor(math.max(0, wave - 1) / (waves.AddEvery or 6)) * (waves.AddAmount or 1)
	local count = boss and 1 or math.min(waves.MaxRegularCount or 18, rawCount)
	st.waveStats = { spawned = 0, finished = 0, killed = 0 }
	send(p, "Wave", { wave = wave, progress = 0, total = count, killed = 0 })
	waveProgress(p)
	local sess = getSession(p)
	local cap = (RaidConfig.Performance and RaidConfig.Performance.MaxActiveMobsPerPlayer) or 18
	for _ = 1, count do
		if st.stopping or not activeRaids[p] then break end
		while activeRaids[p] and p.Parent and not st.stopping and sess.alive >= cap do scaledWait(p, 0.35) end
		if st.stopping or not activeRaids[p] then break end
		spawnEnemy(p, wave, boss)
		waveProgress(p)
		scaledWait(p, waveSpawnInterval(wave))
	end
	-- Wave ends when every enemy is gone (killed, escaped, or emptied) — carriers walking
	-- loot back out keep the wave open. The timeout is a stuck-enemy safety net sized to the
	-- slowest possible round trip, and it cleans up survivors instead of abandoning them.
	local function stuckTimeout()
		local longest, slowest = 0, math.huge
		for _, e in pairs(sess.enemies) do
			if e.mover then longest = math.max(longest, e.mover.length) end
			if (e.speed or 0) > 0 then slowest = math.min(slowest, e.speed) end
		end
		if longest <= 0 or slowest == math.huge then return 60 end
		return math.max(60, (2 * longest) / slowest + 45)
	end
	local started = os.clock()
	while activeRaids[p] and p.Parent and not st.stopping and sess.alive > 0 do
		if os.clock() - started > stuckTimeout() then
			for _, e in pairs(sess.enemies) do
				if (e.carrying or 0) > 0 then
					sess.carriedLoot = math.max(0, (sess.carriedLoot or 0) - e.carrying)
					recoverLoot(p, e.carrying)
					e.carrying = 0
				end
				removeEnemy(p, e, "end")
			end
			break
		end
		scaledWait(p, 0.25)
	end
	st.waveStats.finished = st.waveStats.spawned
	waveProgress(p)
	if not st.stopping then
		st.stats.wavesCleared = math.max(st.stats.wavesCleared, wave)
		updateHighestWave(p, st.stats.wavesCleared)
		if wave >= 5 then BadgeProgressService.Award(p, "TreasureGuard") end
		if wave % 5 == 0 then PlayerDataService.SetRaidCheckpoint(p, wave) end
		st.stats.score += wave * 100
	end
end

local function statusText(reason)
	if reason == "Completed" then return "Victory"
	elseif reason == "Stopped" then return "Game Over"
	else return "Defeat" end
end
function finish(p, reason)
	local st = state(p)
	activeRaids[p] = nil
	p:SetAttribute("RaidActive", false)
	clearEnemies(p)
	updateHighestWave(p, st.stats.wavesCleared or 0)
	st.stats.score = math.floor(st.stats.score + (st.stats.wavesCleared or 0) * 25 + st.loot)
	if st.stats.cashEarned > 0 then
		local reward = math.floor(st.stats.cashEarned * GamePassService.GetCashMultiplier(p))
		local ok, endingBalance = PlayerDataService.AddCash(p, reward)
		if ok then
			MonetizationAnalytics.LogCashSource(p, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, reward, endingBalance, "RaidReward", "Raid")
		end
	end
	MonetizationAnalytics.LogRaidStep(p, 3, "Raid Ended", raidAnalyticsSessions[p])
	MonetizationAnalytics.LogRaidResult(p, st.stats.wavesCleared or 0, reason, st.loot or 0)
	raidAnalyticsSessions[p] = nil
	local skip = st.auto and reason == "Defeated"
	if reason == "Defeated" then
		openReviveOffer(p, st.wave or st.stats.wavesCleared or 1)
	else
		clearReviveOffer(p)
	end
	if not skip then
		RaidResultsRemote:FireClient(p, {
			status = statusText(reason), enemiesDefeated = st.stats.enemiesDefeated,
			wavesCleared = st.stats.wavesCleared, cashEarned = st.stats.cashEarned,
			score = st.stats.score, reason = reason, lootProtected = st.loot,
			lootStolen = st.stats.lootStolen, lootRecovered = st.stats.lootRecovered,
		})
	end
	send(p, "End", { reason = reason, skipResults = skip })
end

function EnemyCore.StartRaid(p)
	local st = state(p)
	if activeRaids[p] then return false end
	if lastStarted[p] and os.clock() - lastStarted[p] < 1 then return false end
	lastStarted[p] = os.clock()
	local plot = PlotService.GetPlayerPlot(p) or PlotService.AssignPlayer(p)
	if not plot or not buildRoute(plot, p.UserId + os.clock() * 1000) then warn("[EnemyCore] missing plot route", p.Name); return false end
	local sess = getSession(p)
	sess.carriedLoot = 0
	local checkpoint = PlayerDataService.GetRaidCheckpoint(p)
	local reviveStart = pendingReviveStarts[p]
	pendingReviveStarts[p] = nil
	local startWave
	if reviveStart then
		startWave = math.max(1, math.floor(tonumber(reviveStart.wave) or 1))
		reviveState[p] = { tier = clampReviveTier(reviveStart.nextTier), available = false }
	elseif beyondHundred[p] then startWave = beyondHundred[p]; beyondHundred[p] = nil
	else startWave = checkpoint > 0 and checkpoint or 1 end
	if not reviveStart then
		reviveState[p] = nil
	end
	st.stopping = false
	st.wave = startWave
	st.stats = { enemiesDefeated = 0, wavesCleared = math.max(0, startWave - 1), cashEarned = 0, score = 0, lootStolen = 0, lootRecovered = 0 }
	st.maxLoot = PlayerDataService.GetBaseMaxHealth(p)
	st.loot = st.maxLoot
	activeRaids[p] = true
	raidAnalyticsSessions[p] = MonetizationAnalytics.LogRaidStep(p, 1, "Raid Started")
	BadgeProgressService.Award(p, "RaidCaller")
	p:SetAttribute("RaidActive", true)
	clearEnemies(p)
	send(p, "Start", { loot = st.loot, maxLoot = st.maxLoot, startWave = startWave, checkpoint = checkpoint })
	send(p, "Speed", { speed = st.speed })
	send(p, "Auto", { enabled = st.auto })
	task.spawn(function()
		local w = startWave
		while true do
			if not activeRaids[p] or not p.Parent then finish(p, "Stopped"); return end
			if st.stopping then finish(p, st.loot <= 0 and "Defeated" or "Stopped"); return end
			local _rwok, _rwerr = pcall(runWave, p, plot, w)
			if not _rwok then warn("[EnemyCore] runWave error wave " .. tostring(w) .. ": " .. tostring(_rwerr)) end
			if st.stopping then finish(p, st.loot <= 0 and "Defeated" or "Stopped"); return end
			if w == 100 then
				updateHighestWave(p, 100)
				PlayerDataService.SetRaidCheckpoint(p, 100)
				if st.stats.cashEarned > 0 then
					local reward = math.floor(st.stats.cashEarned * GamePassService.GetCashMultiplier(p))
					local ok, endingBalance = PlayerDataService.AddCash(p, reward)
					if ok then
						MonetizationAnalytics.LogCashSource(p, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, reward, endingBalance, "RaidReward", "Raid")
					end
					st.stats.cashEarned = 0
				end
				MonetizationAnalytics.LogRaidStep(p, 3, "Raid Ended", raidAnalyticsSessions[p])
				MonetizationAnalytics.LogRaidResult(p, 100, "Victory", st.loot or 0)
				raidAnalyticsSessions[p] = nil
				activeRaids[p] = nil
				p:SetAttribute("RaidActive", false)
				clearEnemies(p)
				RaidResultsRemote:FireClient(p, {
					status = "Victory", enemiesDefeated = st.stats.enemiesDefeated, wavesCleared = 100,
					cashEarned = 0, score = math.floor(st.stats.score + 100 * 25 + st.loot + 10000), reason = "Victory",
					lootProtected = st.loot, lootStolen = st.stats.lootStolen, lootRecovered = st.stats.lootRecovered,
				})
				send(p, "End", { reason = "Victory", skipResults = false })
				if st.auto then
					task.wait(5)
					if p.Parent and st.auto then
						send(p, "AutoContinue", { wave = 101 })
						beyondHundred[p] = 101
						EnemyCore.StartRaid(p)
					end
				else
					beyondHundred[p] = 101
				end
				return
			end
			scaledWait(p, waveBetweenDelay(w))
			w += 1
		end
	end)
	return true
end

function EnemyCore.StopRaid(p)
	state(p).stopping = true
	activeRaids[p] = nil
	p:SetAttribute("RaidActive", false)
	clearEnemies(p)
	MonetizationAnalytics.LogRaidStep(p, 2, "Raid Stop Requested", raidAnalyticsSessions[p])
	return true
end
function EnemyCore.SetAuto(p, en)
	local st = state(p); st.auto = en == true
	send(p, "Auto", { enabled = st.auto })
end
function EnemyCore.SetSpeed(p, s)
	local st = state(p); s = tonumber(s) or 1
	if s == 3 then
		if not GamePassService.HasPass(p, GamePassConfig.TripleSpeed) then s = st.speed or 1 end
	elseif s ~= 2 then s = 1 end
	st.speed = s
	send(p, "Speed", { speed = s })
end

function EnemyCore.GetRevivePromptProduct(p)
	local info = reviveState[p]
	if not info or info.available ~= true then
		return false, "No revive available"
	end
	if (tonumber(info.expiresAt) or 0) < os.clock() then
		clearReviveOffer(p)
		return false, "Revive expired"
	end
	local tier = clampReviveTier(info.tier)
	local config = DeveloperProductsConfig.ReviveTiers and DeveloperProductsConfig.ReviveTiers[tier]
	local productId = config and tonumber(config.ProductId) or 0
	if productId <= 0 then
		return false, "Revive product is not configured"
	end
	return true, "Prompt", productId, tier
end

function EnemyCore.GrantRevive(p, tier)
	local info = reviveState[p]
	if activeRaids[p] or not info or info.available ~= true then
		return false
	end
	if (tonumber(info.expiresAt) or 0) < os.clock() then
		clearReviveOffer(p)
		return false
	end
	local currentTier = clampReviveTier(info.tier)
	if tonumber(tier) and clampReviveTier(tier) ~= currentTier then
		return false
	end
	pendingReviveStarts[p] = {
		wave = info.nextWave,
		nextTier = clampReviveTier(currentTier + 1),
	}
	info.available = false
	task.defer(function()
		if p.Parent then
			EnemyCore.StartRaid(p)
		end
	end)
	return true
end

-- ===== targeting API (used by PlacementServer towers + SwordServer melee) =====
function EnemyCore.QueryInRange(p, pos, radius)
	local sess = sessions[p]
	if not sess then return {} end
	local out, r2 = {}, radius * radius
	for id, e in pairs(sess.enemies) do
		if not e.dead and e.mover then
			local epos = e.mover:At(e.distance)
			local d2 = (epos - pos).Magnitude
			d2 = d2 * d2
			if d2 <= r2 then
				out[#out + 1] = { id = id, pos = epos, distSq = d2, travelled = e.distance, health = e.health, maxHealth = e.maxHealth, carrying = e.carrying or 0, phase = e.phase }
			end
		end
	end
	return out
end
function EnemyCore.GetPos(p, enemyId)
	local sess = sessions[p]
	if not sess then return nil end
	local e = sess.enemies[enemyId]
	if not e or e.dead or not e.mover then return nil end
	return e.mover:At(e.distance)
end
function EnemyCore.IsAlive(p, enemyId)
	local sess = sessions[p]
	local e = sess and sess.enemies[enemyId]
	return e ~= nil and not e.dead
end
function EnemyCore.Damage(p, enemyId, amount)
	local sess = sessions[p]
	if not sess then return false end
	local e = sess.enemies[enemyId]
	if not e or e.dead then return false end
	e.health -= (tonumber(amount) or 0)
	if e.isBoss then send(p, "Boss", { wave = state(p).wave, health = math.max(0, e.health), maxHealth = e.maxHealth }) end
	if e.health <= 0 then
		e.dead = true
		award(p, e)
		removeEnemy(p, e, "death")
	end
	return true
end
function EnemyCore.ApplySlow(p, enemyId, mult, dur)
	local sess = sessions[p]
	if not sess then return end
	local e = sess.enemies[enemyId]
	if not e or e.dead then return end
	mult = math.clamp(tonumber(mult) or 1, 0.05, 1)
	local now = os.clock()
	if e.slowUntil <= now or mult < e.slowMult then e.slowMult = mult end
	e.slowUntil = math.max(e.slowUntil, now + (tonumber(dur) or 1))
end

function EnemyCore.Debug(p)
	local sess = sessions[p]
	local st = playerState[p]
	local n = 0
	if sess then for _ in pairs(sess.enemies) do n += 1 end end
	return { active = activeRaids[p] == true, hasSession = sess ~= nil, enemyCount = n, alive = sess and sess.alive, carriedLoot = sess and sess.carriedLoot or 0, wave = st and st.wave, spawned = st and st.waveStats and st.waveStats.spawned, loot = st and st.loot, maxLoot = st and st.maxLoot }
end

function EnemyCore.Start()
	_G.MyEvilLairRaidRevive = {
		GetPromptProduct = function(player)
			return EnemyCore.GetRevivePromptProduct(player)
		end,
		Grant = function(player, tier)
			return EnemyCore.GrantRevive(player, tier)
		end,
	}
	StartRaidRemote.OnServerEvent:Connect(function(p) EnemyCore.StartRaid(p) end)
	RaidControlRemote.OnServerEvent:Connect(function(p, a, v)
		if a == "Stop" then EnemyCore.StopRaid(p)
		elseif a == "Auto" then EnemyCore.SetAuto(p, v)
		elseif a == "Speed" then EnemyCore.SetSpeed(p, v) end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastStarted[p] = nil; activeRaids[p] = nil; playerState[p] = nil; beyondHundred[p] = nil; sessions[p] = nil; raidAnalyticsSessions[p] = nil; clearReviveOffer(p)
	end)
	RunService.Heartbeat:Connect(step)
end

return EnemyCore

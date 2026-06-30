--!nonstrict
-- EnemyCore: data-driven enemy/wave system. Server holds enemies as pure data
-- (no models/Humanoids); clients render rigs via EnemyController. Movement is math
-- along a generated route from the plot edge to its Base part.
-- Current raid runtime; preserves RaidConfig tuning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local PlotService = require(ServerScriptService.Systems.PlotSystem.Modules.PlotService)
local RaidConfig = require(ReplicatedStorage.Configs.RaidConfig)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local BaseUpgradesConfig = require(ReplicatedStorage.Configs.BaseUpgradesConfig)
local PlotRoute = require(ReplicatedStorage.RaidShared.PlotRoute)

local function getLeaderboardManager()
	local ok, lm = pcall(require, ServerScriptService.Systems.LeaderboardSystem.LeaderboardManager)
	return ok and lm or nil
end

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
local sessions = {} -- player -> { enemies = {id->e}, mover, nextId, alive }

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
		s = { speed = 1, auto = false, stopping = false, wave = 0, baseHealth = 500, baseMaxHealth = 500,
			stats = { enemiesDefeated = 0, wavesCleared = 0, cashEarned = 0, score = 0 },
			waveStats = { spawned = 0, finished = 0, killed = 0 } }
		playerState[p] = s
	end
	return s
end
local function getSession(p)
	local s = sessions[p]
	if not s then s = { enemies = {}, nextId = 1, alive = 0, mover = nil }; sessions[p] = s end
	return s
end
local function buildMover(plot)
	return PlotRoute.Build(plot)
end

local function send(p, a, d) if p and p.Parent then RaidStatusRemote:FireClient(p, a, d or {}) end end
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
local function damageBase(p, amount)
	local st = state(p)
	st.baseHealth = math.max(0, st.baseHealth - amount)
	send(p, "Base", { health = st.baseHealth, maxHealth = st.baseMaxHealth })
	if st.baseHealth <= 0 then st.stopping = true end
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
	local e = {
		id = eid, name = id, isBoss = isBoss == true,
		distance = 0,
		speed = cfg.Speed or RaidConfig.MobWalkSpeed or 11,
		slowMult = 1, slowUntil = 0,
		health = maxHealth, maxHealth = maxHealth,
		cashReward = math.floor((cfg.CashReward or 8) * rewardMultiplier(wave)),
		coreDamage = cfg.CoreDamage or 10,
		scale = cfg.Scale or 1,
		awarded = false, finished = false, dead = false,
	}
	sess.enemies[eid] = e
	sess.alive += 1
	state(p).waveStats.spawned += 1
	EnemyStreamRemote:FireClient(p, "spawn", {
		id = eid, name = id, isBoss = e.isBoss, maxHealth = maxHealth, scale = e.scale, speed = e.speed,
	})
	if e.isBoss then send(p, "Boss", { wave = wave, health = maxHealth, maxHealth = maxHealth }) end
	return true
end
local function clearEnemies(p)
	local sess = sessions[p]
	if not sess then return end
	table.clear(sess.enemies)
	sess.alive = 0
	if p and p.Parent then EnemyStreamRemote:FireClient(p, "clear", {}) end
end

-- ===== movement + streaming (single Heartbeat for all players) =====
local streamAccum = 0
local function step(dt)
	streamAccum += dt
	local doStream = false
	if streamAccum >= STREAM_INTERVAL then streamAccum -= STREAM_INTERVAL; doStream = true end
	for p, sess in pairs(sessions) do
		if activeRaids[p] and sess.mover then
			local st = playerState[p]
			local gspeed = (st and st.speed) or 1
			local now = os.clock()
			local syncList = doStream and {} or nil
			for id, e in pairs(sess.enemies) do
				if e.slowUntil > 0 and now >= e.slowUntil then e.slowMult = 1; e.slowUntil = 0 end
				local v = e.speed * e.slowMult * gspeed
				e.distance += v * dt
				if e.distance >= sess.mover.length then
					if not e.finished then
						e.finished = true
						if st then st.waveStats.finished += 1 end
						damageBase(p, e.coreDamage)
					end
					removeEnemy(p, e, "end")
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
	local started = os.clock()
	local timeout = math.max(20, (st.waveStats.spawned or count) * 7)
	while activeRaids[p] and p.Parent and not st.stopping and st.waveStats.finished < st.waveStats.spawned do
		if sess.alive <= 0 and st.waveStats.spawned > 0 then
			st.waveStats.finished = st.waveStats.spawned; waveProgress(p); break
		end
		if os.clock() - started > timeout then
			st.waveStats.finished = st.waveStats.spawned; waveProgress(p); break
		end
		scaledWait(p, 0.25)
	end
	if not st.stopping then
		st.stats.wavesCleared = math.max(st.stats.wavesCleared, wave)
		updateHighestWave(p, st.stats.wavesCleared)
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
	st.stats.score = math.floor(st.stats.score + (st.stats.wavesCleared or 0) * 25 + st.baseHealth)
	if st.stats.cashEarned > 0 then PlayerDataService.AddCash(p, st.stats.cashEarned) end
	local skip = st.auto and reason == "Defeated"
	if not skip then
		RaidResultsRemote:FireClient(p, {
			status = statusText(reason), enemiesDefeated = st.stats.enemiesDefeated,
			wavesCleared = st.stats.wavesCleared, cashEarned = st.stats.cashEarned,
			score = st.stats.score, reason = reason,
		})
	end
	send(p, "End", { reason = reason, skipResults = skip })
	local lb = getLeaderboardManager()
	if lb then task.defer(function() pcall(lb.submitPlayer, p) end) end
end

function EnemyCore.StartRaid(p)
	local st = state(p)
	if activeRaids[p] then return false end
	if lastStarted[p] and os.clock() - lastStarted[p] < 1 then return false end
	lastStarted[p] = os.clock()
	local plot = PlotService.GetPlayerPlot(p) or PlotService.AssignPlayer(p)
	local mover = plot and buildMover(plot)
	if not plot or not mover then warn("[EnemyCore] missing plot route", p.Name); return false end
	local sess = getSession(p)
	sess.mover = mover
	local checkpoint = PlayerDataService.GetRaidCheckpoint(p)
	local startWave
	if beyondHundred[p] then startWave = beyondHundred[p]; beyondHundred[p] = nil
	else startWave = checkpoint > 0 and checkpoint or 1 end
	st.stopping = false
	st.wave = startWave
	st.stats = { enemiesDefeated = 0, wavesCleared = math.max(0, startWave - 1), cashEarned = 0, score = 0 }
	st.baseMaxHealth = PlayerDataService.GetBaseMaxHealth(p)
	st.baseHealth = st.baseMaxHealth
	activeRaids[p] = true
	p:SetAttribute("RaidActive", true)
	clearEnemies(p)
	send(p, "Start", { baseHealth = st.baseHealth, baseMaxHealth = st.baseMaxHealth, startWave = startWave, checkpoint = checkpoint })
	send(p, "Speed", { speed = st.speed })
	send(p, "Auto", { enabled = st.auto })
	task.spawn(function()
		local w = startWave
		while true do
			if not activeRaids[p] or not p.Parent then finish(p, "Stopped"); return end
			if st.stopping then finish(p, st.baseHealth <= 0 and "Defeated" or "Stopped"); return end
			local _rwok, _rwerr = pcall(runWave, p, plot, w)
			if not _rwok then warn("[EnemyCore] runWave error wave " .. tostring(w) .. ": " .. tostring(_rwerr)) end
			if st.stopping then finish(p, st.baseHealth <= 0 and "Defeated" or "Stopped"); return end
			if w == 100 then
				updateHighestWave(p, 100)
				PlayerDataService.SetRaidCheckpoint(p, 100)
				if st.stats.cashEarned > 0 then PlayerDataService.AddCash(p, st.stats.cashEarned); st.stats.cashEarned = 0 end
				activeRaids[p] = nil
				p:SetAttribute("RaidActive", false)
				clearEnemies(p)
				RaidResultsRemote:FireClient(p, {
					status = "Victory", enemiesDefeated = st.stats.enemiesDefeated, wavesCleared = 100,
					cashEarned = 0, score = math.floor(st.stats.score + 100 * 25 + st.baseHealth + 10000), reason = "Victory",
				})
				send(p, "End", { reason = "Victory", skipResults = false })
				local lb = getLeaderboardManager()
				if lb then task.defer(function() pcall(lb.submitPlayer, p) end) end
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
	return true
end
function EnemyCore.SetAuto(p, en)
	local st = state(p); st.auto = en == true
	send(p, "Auto", { enabled = st.auto })
end
function EnemyCore.SetSpeed(p, s)
	local st = state(p); s = tonumber(s) or 1
	if s == 3 then
		local productId = (BaseUpgradesConfig.RaidSpeed or {}).Speed3ProductId or 0
		if productId <= 0 then s = st.speed or 1 end
	elseif s ~= 2 then s = 1 end
	st.speed = s
	send(p, "Speed", { speed = s })
end

-- ===== targeting API (used by PlacementServer towers + SwordServer melee) =====
function EnemyCore.QueryInRange(p, pos, radius)
	local sess = sessions[p]
	if not sess or not sess.mover then return {} end
	local out, r2 = {}, radius * radius
	for id, e in pairs(sess.enemies) do
		if not e.dead then
			local epos = sess.mover:At(e.distance)
			local d2 = (epos - pos).Magnitude
			d2 = d2 * d2
			if d2 <= r2 then
				out[#out + 1] = { id = id, pos = epos, distSq = d2, travelled = e.distance, health = e.health, maxHealth = e.maxHealth }
			end
		end
	end
	return out
end
function EnemyCore.GetPos(p, enemyId)
	local sess = sessions[p]
	if not sess or not sess.mover then return nil end
	local e = sess.enemies[enemyId]
	if not e or e.dead then return nil end
	return sess.mover:At(e.distance)
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
	return { active = activeRaids[p] == true, hasSession = sess ~= nil, hasMover = sess and sess.mover ~= nil, enemyCount = n, alive = sess and sess.alive, wave = st and st.wave, spawned = st and st.waveStats and st.waveStats.spawned, baseHealth = st and st.baseHealth }
end

function EnemyCore.Start()
	StartRaidRemote.OnServerEvent:Connect(function(p) EnemyCore.StartRaid(p) end)
	RaidControlRemote.OnServerEvent:Connect(function(p, a, v)
		if a == "Stop" then EnemyCore.StopRaid(p)
		elseif a == "Auto" then EnemyCore.SetAuto(p, v)
		elseif a == "Speed" then EnemyCore.SetSpeed(p, v) end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastStarted[p] = nil; activeRaids[p] = nil; playerState[p] = nil; beyondHundred[p] = nil; sessions[p] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return EnemyCore

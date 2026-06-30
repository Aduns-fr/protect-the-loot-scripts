local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local MarketplaceService = game:GetService("MarketplaceService")
local Debris = game:GetService("Debris")

local PlotService = require(ServerScriptService.Systems.PlotSystem.Modules.PlotService)
local RaidConfig = require(ReplicatedStorage.Configs.RaidConfig)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)
local BaseUpgradesConfig = require(ReplicatedStorage.Configs.BaseUpgradesConfig)
local LeaderboardManager = require(ServerScriptService.Systems.LeaderboardSystem.LeaderboardManager)

local RaidService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartRaidRemote = Remotes:WaitForChild("StartRaid")
local RaidStatusRemote = Remotes:WaitForChild("RaidStatus")
local RaidControlRemote = Remotes:WaitForChild("RaidControl")
local RaidResultsRemote = Remotes:WaitForChild("RaidResults")
local CashPopupRemote = Remotes:WaitForChild("CashPopup")

-- eggs are regular mobs, bosses are the voxel birds
local EggsFolder = ReplicatedStorage:WaitForChild("Eggs")
local BossesFolder = ReplicatedStorage:WaitForChild("Bosses")
local HpGui = ReplicatedStorage:FindFirstChild("HP")

local ACTIVE_FOLDER_NAME = "ActiveMobs"
local MOB_GROUP = "Mobs"
local PLAYER_GROUP = "Players"

local lastStarted, activeRaids, playerState = {}, {}, {}

local function waveSpawnInterval(wave)
    local t = RaidConfig.Timing
    local lo  = t.SpawnInterval      or 0.5
    local hi  = t.SpawnIntervalEarly or 1.2
    local ramp = t.SpawnIntervalRampWaves or 40
    local alpha = math.clamp((wave - 1) / (ramp - 1), 0, 1)
    return hi + (lo - hi) * alpha
end

local function waveBetweenDelay(wave)
    local t = RaidConfig.Timing
    local lo  = t.BetweenWaves      or 2.5
    local hi  = t.BetweenWavesEarly or 9.0
    local ramp = t.BetweenWavesRampWaves or 50
    local alpha = math.clamp((wave - 1) / (ramp - 1), 0, 1)
    return hi + (lo - hi) * alpha
end

local function state(player)
    local s = playerState[player]
    if not s then
        s = {
            speed = 1, auto = false, stopping = false, wave = 0,
            baseHealth = 500, baseMaxHealth = 500,
            stats = { enemiesDefeated = 0, wavesCleared = 0, cashEarned = 0, score = 0 },
            waveStats = { spawned = 0, finished = 0, killed = 0 },
        }
        playerState[player] = s
    end
    return s
end

local function folder()
    local f = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME) or Instance.new("Folder")
    f.Name = ACTIVE_FOLDER_NAME
    f.Parent = Workspace
    return f
end

local function send(p, a, d)
    if p and p.Parent then RaidStatusRemote:FireClient(p, a, d or {}) end
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

local function points(plot)
    local pf = plot and plot:FindFirstChild("Points")
    if not pf then return nil end
    local t = {}
    for _, pt in ipairs(pf:GetChildren()) do
        local n = tonumber(pt.Name)
        if n and pt:IsA("BasePart") then table.insert(t, { n = n, p = pt }) end
    end
    table.sort(t, function(a, b) return a.n < b.n end)
    local out = {}
    for _, e in ipairs(t) do table.insert(out, e.p) end
    return out
end

local function setChar(char)
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then d.CollisionGroup = PLAYER_GROUP end
    end
    char.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then d.CollisionGroup = PLAYER_GROUP end
    end)
end

local function setMobParts(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanTouch = false
            d.Massless = true
            d.CastShadow = false
            d.CollisionGroup = MOB_GROUP
            pcall(function() d:SetNetworkOwner(nil) end)
        end
    end
end

local function configureHumanoid(hum)
    hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    hum.AutoJumpEnabled = false
    hum.RequiresNeck = false
end

-- launches a single voxel part with velocity + spin, fades and cleans up
local function launchVoxel(part, velocity, spin, delay)
    -- detach from model by reparenting to workspace before unanchoring
    local cf = part.CFrame
    part.Parent = Workspace
    part.Anchored = false
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = true
    part.CFrame = cf

    local att = Instance.new("Attachment", part)

    local lv = Instance.new("LinearVelocity")
    lv.VectorVelocity = velocity
    lv.MaxForce = math.huge
    lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.Attachment0 = att
    lv.Parent = part

    local av = Instance.new("AngularVelocity")
    av.AngularVelocity = spin
    av.MaxTorque = math.huge
    av.RelativeTo = Enum.ActuatorRelativeTo.World
    av.Attachment0 = att
    av.Parent = part

    -- after the burst window, kill constraints so gravity takes over, then fade
    task.spawn(function()
        task.wait(delay or 0.1)
        if lv.Parent then lv:Destroy() end
        if av.Parent then av:Destroy() end
        task.wait(0.5)
        for i = 1, 10 do
            task.wait(0.045)
            if part.Parent then
                part.Transparency = i / 10
            else
                return
            end
        end
        if part.Parent then part:Destroy() end
    end)

    Debris:AddItem(part, 3)
end

-- explodes the actual EggVoxel parts outward from their positions
-- capped at MAX_VOXELS to keep perf sane — picks a spread sample
local MAX_VOXELS = 30
local function shatterEgg(hero)
    task.spawn(function()
        local hitbox = hero:FindFirstChild("Hitbox") or hero.PrimaryPart
        if not hitbox then hero:Destroy(); return end

        local center = hitbox.CFrame.Position
        local rng = Random.new()

        local soundAnchor = Instance.new("Part")
        soundAnchor.Name = "EggShatterSound"
        soundAnchor.Size = Vector3.one
        soundAnchor.Transparency = 1
        soundAnchor.Anchored = true
        soundAnchor.CanCollide = false
        soundAnchor.CanTouch = false
        soundAnchor.CanQuery = false
        soundAnchor.Position = center
        soundAnchor.Parent = Workspace
        local eggSounds = game:GetService("SoundService"):FindFirstChild("SFX")
        eggSounds = eggSounds and eggSounds:FindFirstChild("Egg")
        for index, soundName in ipairs({ "Crack", "Crack2" }) do
            local source = eggSounds and eggSounds:FindFirstChild(soundName)
            if source then
                local sound = source:Clone()
                sound.PlaybackSpeed = rng:NextNumber(0.92, 1.08)
                sound.Volume = math.min(1, source.Volume + 0.15)
                sound.Parent = soundAnchor
                task.delay((index - 1) * 0.045, function() if sound.Parent then sound:Play() end end)
            end
        end
        Debris:AddItem(soundAnchor, 3)

        -- collect all EggVoxel parts
        local voxels = {}
        for _, p in ipairs(hero:GetChildren()) do
            if p.Name == "EggVoxel" and p:IsA("BasePart") then
                table.insert(voxels, p)
            end
        end

        -- if there are more than our cap, pick a random spread rather than
        -- just the first N — looks much better, covers the whole egg shape
        local toExplode = {}
        if #voxels <= MAX_VOXELS then
            toExplode = voxels
        else
            -- shuffle and take first MAX_VOXELS
            for i = #voxels, 2, -1 do
                local j = rng:NextInteger(1, i)
                voxels[i], voxels[j] = voxels[j], voxels[i]
            end
            for i = 1, MAX_VOXELS do
                table.insert(toExplode, voxels[i])
            end
        end

        -- hide voxels we're NOT exploding immediately
        for _, p in ipairs(voxels) do
            p.Transparency = 1
        end
        hitbox.Transparency = 1

        -- explode the selected voxels
        for _, p in ipairs(toExplode) do
            p.Transparency = 0

            -- direction from egg center to this voxel — so pieces fly away from
            -- where they actually sat on the egg, looks totally natural
            local dir = (p.Position - center)
            local dist = dir.Magnitude
            if dist < 0.01 then
                dir = Vector3.new(rng:NextNumber(-1,1), rng:NextNumber(0.5,1), rng:NextNumber(-1,1))
            else
                dir = dir.Unit
            end

            -- outer voxels fly faster/further, inner ones pop less
            local speed = rng:NextNumber(18, 34) * (0.55 + dist * 0.2)
            speed = math.clamp(speed, 14, 42)

            -- strong upward pop keeps the voxel breakup readable
            local upBias = rng:NextNumber(8, 18)
            local vel = Vector3.new(dir.X * speed, dir.Y * speed + upBias, dir.Z * speed)

            local spin = Vector3.new(
                rng:NextNumber(-12, 12),
                rng:NextNumber(-8, 8),
                rng:NextNumber(-12, 12)
            )

            -- stagger slightly so it looks like a crack propagating, not all at once
            local stagger = rng:NextNumber(0, 0.08)
            task.delay(stagger, function()
                if p.Parent then
                    launchVoxel(p, vel, spin, 0.16)
                end
            end)
        end

        -- destroy the model shell after the voxels have flown off
        task.wait(0.2)
        if hero.Parent then hero:Destroy() end
    end)
end

-- boss death: parts scatter and shrink out
local function fadeMob(hero)
    task.spawn(function()
        for step = 1, 12 do
            local alpha = step / 12
            for _, part in ipairs(hero:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Anchored = true
                    part.CanCollide = false
                    part.Transparency = math.clamp(alpha, part.Transparency, 1)
                    part.Size = part.Size:Lerp(Vector3.new(0.15, 0.15, 0.15), 0.18)
                end
            end
            task.wait(0.03)
        end
        if hero.Parent then hero:Destroy() end
    end)
end

local function updateHp(hero, hum)
    local gui = hero:FindFirstChild("HP", true)
    if not gui then return end
    local cg = gui:FindFirstChildWhichIsA("CanvasGroup", true)
    local fill = cg and cg:FindFirstChild("Fill") or gui:FindFirstChild("Fill", true)
    local txt = gui:FindFirstChild("Text", true)
    local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
    if fill then
        fill.AnchorPoint = Vector2.new(0, 0)
        fill.Position = UDim2.fromScale(0, 0)
        fill.Size = UDim2.fromScale(ratio, 1)
    end
    if txt then txt.Text = tostring(math.max(0, math.floor(hum.Health))) end
end

local function addHp(hero, hum)
    local part = hero:FindFirstChild("Body") or hero.PrimaryPart or hero:FindFirstChild("HumanoidRootPart")
    if HpGui and part then
        local g = HpGui:Clone()
        g.Name = "HP"
        g.Adornee = part
        g.Parent = part
        local pending = false
        updateHp(hero, hum)
        hum.HealthChanged:Connect(function()
            if pending then return end
            pending = true
            task.delay((RaidConfig.Performance and RaidConfig.Performance.HpUpdateInterval) or 0.1, function()
                pending = false
                if hero.Parent and hum.Parent then updateHp(hero, hum) end
            end)
        end)
    end
end

local function waveProgress(p)
    local st = state(p)
    local ws = st.waveStats
    local total = math.max(1, ws.spawned or 0)
    send(p, "WaveProgress", { wave = st.wave, progress = (ws.killed or 0) / total, killed = ws.killed or 0, total = total })
end

local function award(p, hero, cfg, isBoss)
    local st = state(p)
    if hero:GetAttribute("Awarded") then return end
    hero:SetAttribute("Awarded", true)
    local reward = hero:GetAttribute("CashReward") or cfg.CashReward or 0
    if isBoss then reward += math.floor(150 + st.wave * 8) end
    st.stats.enemiesDefeated += 1
    st.stats.cashEarned += reward
    st.stats.score += reward * 10 + st.wave * (isBoss and 60 or 15) + (isBoss and 1000 or 0)
    st.waveStats.killed += 1
    st.waveStats.finished += 1
    CashPopupRemote:FireClient(p, reward)
    waveProgress(p)
    -- persist elims per map so leaderboard reads live data
    local _d = PlayerDataService.GetData(p)
    local _mid = PlayerDataService.GetActiveMap and PlayerDataService.GetActiveMap(p) or 1
    local _m = _d and _d.Maps and _d.Maps[_mid]
    if _m then _m.EnemiesDefeated = (_m.EnemiesDefeated or 0) + 1 end
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
    -- write into the active map's slot, not the root data
    local data = PlayerDataService.GetData(p)
    local mapId = PlayerDataService.GetActiveMap and PlayerDataService.GetActiveMap(p) or 1
    if data and data.Maps and data.Maps[mapId] then
        local md = data.Maps[mapId]
        md.HighestWave = math.max(tonumber(md.HighestWave) or 0, wave)
    end
end

local function getMobRoot(mob)
    return mob and (mob.PrimaryPart or mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChildWhichIsA("BasePart", true))
end

local function cleanupBrokenMobs(p)
    local removed = 0
    for _, mob in ipairs(folder():GetChildren()) do
        if mob:GetAttribute("OwnerUserId") == p.UserId and not getMobRoot(mob) then
            mob:Destroy()
            removed += 1
        end
    end
    return removed
end

local function activeMobCount(p)
    local n = 0
    for _, h in ipairs(folder():GetChildren()) do
        if h:GetAttribute("OwnerUserId") == p.UserId and getMobRoot(h) then n += 1 end
    end
    return n
end

local function applyRaidSpeed(p, hum)
    local st = state(p)
    local speed = (RaidConfig.MobWalkSpeed or 12) * math.max(1, st.speed or 1)
    if math.abs((hum.WalkSpeed or 0) - speed) > 0.05 then hum.WalkSpeed = speed end
    return speed
end

local function mobGroundOffset(root)
    return ((root and root.Size and root.Size.Y) or 4) * 0.5 + 0.05
end

-- weld all EggVoxels to the Hitbox so physics carries them along
-- then kick them with a random torque for cartoony tumbling
local function setupEggPhysics(model, root)
    local att0 = Instance.new("Attachment")
    att0.Position = Vector3.new(0, 0, 0)
    att0.Parent = root

    for _, part in ipairs(model:GetChildren()) do
        if part.Name ~= "EggVoxel" then continue end

        -- weld to root so it follows movement
        local wc = Instance.new("WeldConstraint")
        wc.Part0 = root
        wc.Part1 = part
        wc.Parent = model

        -- unanchor so physics can rotate it
        part.Anchored = false
        part.Massless = true
        part.CanCollide = false
        part.CanTouch = false
    end

    -- angular velocity constraint for cartoony spin
    -- each egg gets a random axis and speed so they all tumble differently
    local rng = Random.new()
    local att = Instance.new("Attachment")
    att.Parent = root

    local av = Instance.new("AngularVelocity")
    av.AngularVelocity = Vector3.new(
        rng:NextNumber(-6, 6),
        rng:NextNumber(-3, 3),
        rng:NextNumber(-6, 6)
    )
    av.MaxTorque = 500  -- not infinite — lets it slow/shift naturally
    av.RelativeTo = Enum.ActuatorRelativeTo.World
    av.Attachment0 = att
    av.Parent = root
end

local function waitMove(p, hum, root, pos, isEgg)
    local model = root and root.Parent
    if not model then return end
    local target = Vector3.new(pos.X, pos.Y + mobGroundOffset(root), pos.Z)

    while model.Parent and hum.Parent and hum.Health > 0 do
        local st = state(p)
        if st.stopping or not activeRaids[p] then break end
        local current = root.Position
        local delta   = target - current
        local dist    = delta.Magnitude
        if dist < 0.75 then break end

        local speed = applyRaidSpeed(p, hum)
        local dt    = task.wait(0.06)
        local step  = math.min(dist, speed * math.max(dt, 0.016))
        local nextPos    = current + delta.Unit * step
        local flatTarget = Vector3.new(target.X, nextPos.Y, target.Z)

        -- plain movement for all mobs — eggs tumble via physics/welds
        if (flatTarget - nextPos).Magnitude < 0.05 then
            model:PivotTo(CFrame.new(nextPos))
        else
            model:PivotTo(CFrame.lookAt(nextPos, flatTarget))
        end
    end
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
    if total <= 0 then
        local id = RaidConfig.MobOrder[1]
        return id, RaidConfig.MobStats[id]
    end
    local r = Random.new(os.clock() * 1000 + wave):NextNumber(0, total)
    local acc = 0
    for _, id in ipairs(RaidConfig.MobOrder) do
        local cfg = RaidConfig.MobStats[id]
        if cfg and wave >= (cfg.UnlockWave or 1) then
            acc += cfg.Weight or 1
            if r <= acc then return id, cfg end
        end
    end
    local id = RaidConfig.MobOrder[1]
    return id, RaidConfig.MobStats[id]
end

local function chooseBoss(wave)
    local pick = RaidConfig.BossOrder[1]
    for _, id in ipairs(RaidConfig.BossOrder or {}) do
        local cfg = RaidConfig.MobStats[id]
        if cfg and wave >= (cfg.BossWave or 10) then pick = id end
    end
    return pick, RaidConfig.MobStats[pick]
end

-- inject a Humanoid into a model that doesn't have one
-- eggs have a part named Hitbox as PrimaryPart — we rename it to HumanoidRootPart
-- on the clone (not the template) so Roblox's Humanoid system works correctly
local function injectHumanoid(model, maxHealth)
    local existing = model:FindFirstChildOfClass("Humanoid")
    if existing then return existing, model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") end

    local root = model:FindFirstChild("Hitbox") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not root then
        warn("[RaidService] no primary part on", model.Name)
        return nil, nil
    end

    -- rename to HumanoidRootPart so Roblox's Humanoid registers it properly
    -- (TakeDamage and health work without it, but targeting in PlacementServer
    --  does hero:FindFirstChild("HumanoidRootPart") so this also fixes unit targeting)
    root.Name = "HumanoidRootPart"
    model.PrimaryPart = root

    local hum = Instance.new("Humanoid")
    hum.MaxHealth = maxHealth
    hum.Health = maxHealth
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    hum.BreakJointsOnDeath = false
    -- RequiresNeck must be false BEFORE parenting, otherwise Roblox kills
    -- the humanoid immediately on parent since there's no Neck joint
    hum.RequiresNeck = false
    -- disable states before parenting too so none fire on insertion
    hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    hum.AutoJumpEnabled = false
    hum.Parent = model
    -- re-affirm health after parenting in case Roblox reset it
    hum.MaxHealth = maxHealth
    hum.Health = maxHealth

    return hum, root
end

local function spawnMob(p, plot, pts, wave, index, isBoss)
    local id, cfg
    if isBoss then
        id, cfg = chooseBoss(wave)
    else
        id, cfg = chooseMob(wave)
    end

    -- bosses come from Bosses folder, eggs from Eggs folder
    local sourceFolder = isBoss and BossesFolder or EggsFolder
    local template = sourceFolder:FindFirstChild(cfg.Template)
    if not template then
        warn("[RaidService] missing template", cfg.Template, "in", sourceFolder.Name)
        return nil
    end

    -- if the template is a bare Part (e.g. placeholder boss), wrap it in a Model
    local hero
    if template:IsA("BasePart") then
        local clonedPart = template:Clone()
        clonedPart.Name = "Body"
        hero = Instance.new("Model")
        hero.Name = id .. "_W" .. wave .. "_" .. index
        clonedPart.Parent = hero
        hero.PrimaryPart = clonedPart
    else
        hero = template:Clone()
        hero.Name = id .. "_W" .. wave .. "_" .. index
    end
    hero:SetAttribute("OwnerUserId", p.UserId)
    hero:SetAttribute("Wave", wave)
    hero:SetAttribute("IsBoss", isBoss == true)
    hero:SetAttribute("IsEgg", not isBoss) -- used later for death effect choice

    local baseMaxHealth = math.floor((cfg.MaxHealth or 100) * waveHealthMultiplier(wave))
    local hum, root = injectHumanoid(hero, baseMaxHealth)

    if not hum or not root then
        warn("[RaidService] failed to set up humanoid for", id)
        hero:Destroy()
        return nil
    end

    configureHumanoid(hum)
    hum.WalkSpeed = RaidConfig.MobWalkSpeed or 12
    hum:SetAttribute("BaseWalkSpeed", RaidConfig.MobWalkSpeed or 12)
    hero:SetAttribute("CashReward", math.floor((cfg.CashReward or 8) * rewardMultiplier(wave)))

    if cfg.Scale then hero:ScaleTo(cfg.Scale) end
    if cfg.Speed then hum.WalkSpeed = cfg.Speed end

    hero.PrimaryPart = root
    setMobParts(hero)
    if not isBoss then setupEggPhysics(hero, root) end
    root.Anchored = true
    hero.Parent = folder()
    hero:PivotTo(CFrame.lookAt(pts[1].Position + Vector3.new(0, mobGroundOffset(root), 0), pts[2].Position))
    pcall(function() root:SetNetworkOwner(nil) end)
    addHp(hero, hum)

    if isBoss then
        send(p, "Boss", { wave = wave, health = hum.Health, maxHealth = hum.MaxHealth })
        hum.HealthChanged:Connect(function()
            send(p, "Boss", { wave = wave, health = hum.Health, maxHealth = hum.MaxHealth })
        end)
    end

    hum.Died:Once(function()
        award(p, hero, cfg, isBoss)
        if isBoss then send(p, "Boss", { wave = wave, health = 0, maxHealth = hum.MaxHealth }) end
        -- eggs shatter, bosses fade
        if isBoss then
            fadeMob(hero)
        else
            shatterEgg(hero)
        end
    end)

    task.spawn(function()
        local isEgg = not isBoss
        for i = 2, #pts do
            if not hero.Parent or hum.Health <= 0 or state(p).stopping or not activeRaids[p] then break end
            waitMove(p, hum, root, pts[i].Position, isEgg)
        end
        if hero.Parent and hum.Health > 0 and activeRaids[p] then
            state(p).waveStats.finished += 1
            damageBase(p, cfg.CoreDamage or 10)
        end
        if hero.Parent and hum.Health > 0 then hero:Destroy() end
    end)

    return hero
end

local function clearMobs(p)
    for _, h in ipairs(folder():GetChildren()) do
        if h:GetAttribute("OwnerUserId") == p.UserId then h:Destroy() end
    end
end

local function runWave(p, plot, pts, wave)
    local st = state(p)
    st.wave = wave
    local waves = RaidConfig.Waves or {}
    local boss = wave % (waves.BossEvery or 10) == 0
    local rawCount = (waves.BaseCount or 4) + math.floor(math.max(0, wave - 1) / (waves.AddEvery or 6)) * (waves.AddAmount or 1)
    local count = boss and 1 or math.min(waves.MaxRegularCount or 18, rawCount)
    st.waveStats = { spawned = 0, finished = 0, killed = 0 }
    send(p, "Wave", { wave = wave, progress = 0, total = count, killed = 0 })
    waveProgress(p)

    for i = 1, count do
        if st.stopping or not activeRaids[p] then break end
        while activeRaids[p] and p.Parent and not st.stopping
            and activeMobCount(p) >= ((RaidConfig.Performance and RaidConfig.Performance.MaxActiveMobsPerPlayer) or 24) do
            scaledWait(p, 0.35)
        end
        if st.stopping or not activeRaids[p] then break end
        local mob = spawnMob(p, plot, pts, wave, i, boss)
        if mob then st.waveStats.spawned += 1; waveProgress(p) end
        scaledWait(p, waveSpawnInterval(wave))
    end

    local started = os.clock()
    local timeout = math.max(20, (st.waveStats.spawned or count) * 7)
    while activeRaids[p] and p.Parent and not st.stopping and st.waveStats.finished < st.waveStats.spawned do
        local removed = cleanupBrokenMobs(p)
        if removed > 0 then
            st.waveStats.finished = math.min(st.waveStats.spawned, st.waveStats.finished + removed)
            waveProgress(p)
        end
        if activeMobCount(p) <= 0 and st.waveStats.spawned > 0 then
            st.waveStats.finished = st.waveStats.spawned
            waveProgress(p)
            break
        end
        if os.clock() - started > timeout then
            warn("[RaidService] wave timeout", p.Name, wave, st.waveStats.finished, st.waveStats.spawned)
            st.waveStats.finished = st.waveStats.spawned
            waveProgress(p)
            break
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

local function finish(p, reason)
    local st = state(p)
    activeRaids[p] = nil
    p:SetAttribute("RaidActive", false)
    clearMobs(p)
    updateHighestWave(p, st.stats.wavesCleared or 0)
    st.stats.score = math.floor(st.stats.score + (st.stats.wavesCleared or 0) * 25 + st.baseHealth)
    if st.stats.cashEarned > 0 then PlayerDataService.AddCash(p, st.stats.cashEarned) end
    local skip = st.auto and reason == "Defeated"
    if not skip then
        RaidResultsRemote:FireClient(p, {
            status = statusText(reason),
            enemiesDefeated = st.stats.enemiesDefeated,
            wavesCleared = st.stats.wavesCleared,
            cashEarned = st.stats.cashEarned,
            score = st.stats.score,
            reason = reason,
        })
    end
    send(p, "End", { reason = reason, skipResults = skip })
    task.defer(function() pcall(LeaderboardManager.submitPlayer, p) end)
end

local beyondHundred = {} -- tracks players who've cleared 100 and can continue from 101

function RaidService.StartRaid(p)
    local st = state(p)
    if activeRaids[p] then return false end
    if lastStarted[p] and os.clock() - lastStarted[p] < 1 then return false end
    lastStarted[p] = os.clock()

    local plot = PlotService.GetPlayerPlot(p) or PlotService.AssignPlayer(p)
    local pts = points(plot)
    if not plot or not pts or #pts < 2 then warn("[RaidService] missing points", p.Name); return false end

    local checkpoint = PlayerDataService.GetRaidCheckpoint(p)
    -- if player has cleared 100 before and is restarting, pick up from 101
    local startWave
    if beyondHundred[p] then
        startWave = beyondHundred[p]
        beyondHundred[p] = nil
    else
        startWave = checkpoint > 0 and checkpoint or 1
    end

    st.stopping = false
    st.wave = startWave
    st.stats = { enemiesDefeated = 0, wavesCleared = math.max(0, startWave - 1), cashEarned = 0, score = 0 }
    st.baseMaxHealth = PlayerDataService.GetBaseMaxHealth(p)
    st.baseHealth = st.baseMaxHealth
    activeRaids[p] = true
    p:SetAttribute("RaidActive", true)
    clearMobs(p)

    send(p, "Start", { baseHealth = st.baseHealth, baseMaxHealth = st.baseMaxHealth, startWave = startWave, checkpoint = checkpoint })
    send(p, "Speed", { speed = st.speed })
    send(p, "Auto", { enabled = st.auto })

    task.spawn(function()
        local w = startWave
        while true do
            if not activeRaids[p] or not p.Parent then
                finish(p, "Stopped")
                return
            end
            if st.stopping then
                finish(p, st.baseHealth <= 0 and "Defeated" or "Stopped")
                return
            end

            runWave(p, plot, pts, w)

            if st.stopping then
                finish(p, st.baseHealth <= 0 and "Defeated" or "Stopped")
                return
            end

            -- wave 100 milestone: show victory results, then handle auto vs manual
            if w == 100 then
                -- award cash and save progress before showing results
                updateHighestWave(p, 100)
                PlayerDataService.SetRaidCheckpoint(p, 100)
                if st.stats.cashEarned > 0 then
                    PlayerDataService.AddCash(p, st.stats.cashEarned)
                    st.stats.cashEarned = 0
                end

                -- stop the raid state so HUD clears
                activeRaids[p] = nil
                p:SetAttribute("RaidActive", false)
                clearMobs(p)

                -- show victory results screen
                RaidResultsRemote:FireClient(p, {
                    status = "Victory",
                    enemiesDefeated = st.stats.enemiesDefeated,
                    wavesCleared = 100,
                    cashEarned = 0,
                    score = math.floor(st.stats.score + 100 * 25 + st.baseHealth + 10000),
                    reason = "Victory",
                })
                send(p, "End", { reason = "Victory", skipResults = false })
                task.defer(function() pcall(LeaderboardManager.submitPlayer, p) end)

                if st.auto then
                    -- auto: wait 5s then continue from 101 automatically
                    task.wait(5)
                    if p.Parent and st.auto then
                        -- close results on client and restart
                        send(p, "AutoContinue", { wave = 101 })
                        beyondHundred[p] = 101
                        RaidService.StartRaid(p)
                    end
                else
                    -- manual: just park here, next StartRaid press will continue from 101
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

function RaidService.StopRaid(p)
    local st = state(p)
    st.stopping = true
    clearMobs(p)
    return true
end

function RaidService.SetAuto(p, en)
    local st = state(p)
    st.auto = en == true
    send(p, "Auto", { enabled = st.auto })
end

function RaidService.SetSpeed(p, s)
    local st = state(p)
    s = tonumber(s) or 1
    if s == 3 then
        local productId = (BaseUpgradesConfig.RaidSpeed or {}).Speed3ProductId or 0
        if productId <= 0 then s = st.speed or 1 end
    elseif s ~= 2 then
        s = 1
    end
    st.speed = s
    send(p, "Speed", { speed = s })
end

function RaidService.Start()
    pcall(function() PhysicsService:RegisterCollisionGroup(MOB_GROUP) end)
    pcall(function() PhysicsService:RegisterCollisionGroup(PLAYER_GROUP) end)
    PhysicsService:CollisionGroupSetCollidable(MOB_GROUP, MOB_GROUP, false)
    PhysicsService:CollisionGroupSetCollidable(MOB_GROUP, PLAYER_GROUP, false)
    folder():ClearAllChildren()

    StartRaidRemote.OnServerEvent:Connect(function(p) RaidService.StartRaid(p) end)
    RaidControlRemote.OnServerEvent:Connect(function(p, a, v)
        if a == "Stop" then RaidService.StopRaid(p)
        elseif a == "Auto" then RaidService.SetAuto(p, v)
        elseif a == "Speed" then RaidService.SetSpeed(p, v)
        end
    end)

    Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(setChar)
        if p.Character then setChar(p.Character) end
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        p.CharacterAdded:Connect(setChar)
        if p.Character then setChar(p.Character) end
    end
    Players.PlayerRemoving:Connect(function(p)
        lastStarted[p] = nil
        activeRaids[p] = nil
        playerState[p] = nil
        beyondHundred[p] = nil
    end)
end

return RaidService

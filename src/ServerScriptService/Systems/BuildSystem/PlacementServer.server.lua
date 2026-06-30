local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buildRemote = remotes:WaitForChild("BuildAction")
local shotVisualRemote = remotes:WaitForChild("UnitShotVisual")
local unitModels = ReplicatedStorage:WaitForChild("UnitModels")
local UnitsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UnitsConfig"))
local LEGACY_UNIT_ALIASES = {
    ScrapTurret="BlockTower", SlimeSprayer="RapidBlock", BoneLauncher="HeavyBlock", ZapCoil="RangeBlock", GooCannon="SplashBlock",
    SpikeThrower="PulseBlock", LaserEye="SniperBlock", MiniMech="BeamBlock", DoomSpeaker="FrostBlock", AcidBarrel="GoldBlock",
    MeteorMortar="MegaBlock", ShadowOrb="OrbitBlock", FreezeRay="ChainBlock", SawDrone="SpikeBlock", VolcanoVent="NovaBlock",
    VoidPylon="VoidBlock", GoldGatling="HyperBlock", MoonLaser="LunarBlock", RealityRipper="PrismBlock", DoomCore="CoreBlock",
}
local function resolveUnitId(unitId)
    unitId = tostring(unitId or "")
    return UnitsConfig.Units[unitId] and unitId or LEGACY_UNIT_ALIASES[unitId]
end
local PlayerDataService = require(game.ServerScriptService:WaitForChild("Systems"):WaitForChild("DataSystem"):WaitForChild("Modules"):WaitForChild("PlayerDataService"))
local PlotService = require(game.ServerScriptService:WaitForChild("Systems"):WaitForChild("PlotSystem"):WaitForChild("Modules"):WaitForChild("PlotService"))
local EnemyCore = require(game.ServerScriptService:WaitForChild("Systems"):WaitForChild("RaidSystem"):WaitForChild("Modules"):WaitForChild("EnemyCore"))
local DEBUG_PLACEMENT = false

local placedFolder = Workspace:FindFirstChild("PlacedUnits") or Instance.new("Folder")
placedFolder.Name = "PlacedUnits"
placedFolder.Parent = Workspace
local ACTIVE_HEROES_NAME = "ActiveMobs"
local TARGET_RESCAN_INTERVAL = 0.6
local beamPool = {}
local startAttackLoop

local function getPlayerPlot(player)
    local plot = PlotService.GetPlayerPlot(player)
    if plot then return plot end

    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, candidate in ipairs(plots:GetChildren()) do
        if candidate:GetAttribute("OwnerUserId") == player.UserId then
            return candidate
        end
    end
    return PlotService.AssignPlayer(player)
end

local function getPlotPart(player)
    local plot = getPlayerPlot(player)
    if not plot then return nil, nil end
    local part = plot:FindFirstChild("Part")
    if part and part:IsA("BasePart") and part.Name == "Part" then
        return plot, part
    end
    return plot, nil
end

local function cframeToArray(cf)
    return { cf:GetComponents() }
end

local function arrayToCFrame(values)
    if type(values) ~= "table" or #values < 12 then return nil end
    return CFrame.new(table.unpack(values, 1, 12))
end

local function ownedUnitsFolder(player)
    local folder = placedFolder:FindFirstChild(tostring(player.UserId))
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = tostring(player.UserId)
        folder.Parent = placedFolder
    end
    return folder
end

local function modelBounds(model)
    local boxCf, boxSize = model:GetBoundingBox()
    local pivotToBox = model:GetPivot():ToObjectSpace(boxCf)
    return boxSize, pivotToBox
end

local function makeUnitModel(unitId)
    local template = unitModels:FindFirstChild(unitId)
    local model
    if template and template:IsA("Model") then
        model = template:Clone()
    else
        model = Instance.new("Model")
        local base = Instance.new("Part")
        base.Name = "Base"
        base.Size = Vector3.new(4, 1, 4)
        base.Anchored = true
        base.Color = Color3.fromRGB(110, 110, 120)
        base.Parent = model
        local head = Instance.new("Part")
        head.Name = "Head"
        head.Size = Vector3.new(2.4, 2, 2.4)
        head.Anchored = true
        head.Color = Color3.fromRGB(255, 244, 126)
        head.CFrame = base.CFrame + Vector3.new(0, 1.5, 0)
        head.Parent = model
        model.PrimaryPart = base
    end

    model.Name = unitId
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = true
        end
    end
    if not model.PrimaryPart then
        local first = model:FindFirstChildWhichIsA("BasePart", true)
        if first then model.PrimaryPart = first end
    end
    return model
end

local function pointInsidePart(part, worldPos, radius)
    local localPos = part.CFrame:PointToObjectSpace(worldPos)
    local half = part.Size * 0.5
    radius = radius or 2
    return math.abs(localPos.X) <= half.X - radius and math.abs(localPos.Z) <= half.Z - radius
end

local function placementCFrame(plotPart, model, worldPos, rotation)
    local boxSize, pivotToBox = modelBounds(model)
    local localPos = plotPart.CFrame:PointToObjectSpace(worldPos)
    local half = plotPart.Size * 0.5
    local radius = math.max(2, math.min(boxSize.X, boxSize.Z) * 0.5)
    local x = math.clamp(localPos.X, -half.X + radius, half.X - radius)
    local z = math.clamp(localPos.Z, -half.Z + radius, half.Z - radius)
    local targetBoxCf = plotPart.CFrame * CFrame.new(x, half.Y + boxSize.Y * 0.5, z) * CFrame.Angles(0, math.rad(tonumber(rotation) or 0), 0)
    local cf = targetBoxCf * pivotToBox:Inverse()
    return cf, boxSize, targetBoxCf
end

local function isValidTopHit(plotPart, hitPart, hitNormal)
    if hitPart ~= plotPart then return false end
    if typeof(hitNormal) ~= "Vector3" then return false end
    return hitNormal:Dot(plotPart.CFrame.UpVector) >= 0.97
end

local function topSurfaceIsPlotPart(player, plotPart, worldPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = player.Character and { player.Character } or {}
    local up = plotPart.CFrame.UpVector
    local result = Workspace:Raycast(worldPos + up * 200, -up * 400, params)
    return result and result.Instance == plotPart and result.Normal:Dot(up) >= 0.97, result
end

local function hasBlockingOverlap(player, plotPart, boxSize, boxCf)
    local extents = boxSize - Vector3.new(0.15, 0.15, 0.15)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = player.Character and { player.Character } or {}

    for _, part in ipairs(Workspace:GetPartBoundsInBox(boxCf, extents, params)) do
        if part ~= plotPart then
            return true, part:GetFullName()
        end
    end

    local folder = placedFolder:FindFirstChild(tostring(player.UserId))
    if folder then
        local localCenter = plotPart.CFrame:PointToObjectSpace(boxCf.Position)
        local radiusX = boxSize.X * 0.5
        local radiusZ = boxSize.Z * 0.5
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                local otherBoxCf, otherSize = model:GetBoundingBox()
                local otherCenter = plotPart.CFrame:PointToObjectSpace(otherBoxCf.Position)
                local closeX = math.abs(localCenter.X - otherCenter.X) < (radiusX + otherSize.X * 0.5)
                local closeZ = math.abs(localCenter.Z - otherCenter.Z) < (radiusZ + otherSize.Z * 0.5)
                if closeX and closeZ then
                    return true, model:GetFullName()
                end
            end
        end
    end
    return false
end

local function serializePlaced(player)
    local _, plotPart = getPlotPart(player)
    if not plotPart then return end

    local saved = {}
    local folder = placedFolder:FindFirstChild(tostring(player.UserId))
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                table.insert(saved, {
                    UnitId = model:GetAttribute("UnitId") or model.Name,
                    CFrame = cframeToArray(plotPart.CFrame:ToObjectSpace(model:GetPivot())),
                })
            end
        end
    end
    PlayerDataService.SetPlacedUnits(player, saved)
end

local function place(player, unitId, worldPos, rotation, hitPart, hitNormal, restoring)
    local ownedUnitId = tostring(unitId or "")
    local resolvedUnitId = resolveUnitId(ownedUnitId)
    if not resolvedUnitId or not UnitsConfig.Units[resolvedUnitId] then return false, "Unknown unit" end
    if typeof(worldPos) ~= "Vector3" then return false, "Bad position" end

    local _, plotPart = getPlotPart(player)
    if not plotPart then return false, "Plot not ready" end
    if not restoring and not isValidTopHit(plotPart, hitPart, hitNormal) then
        return false, "Place on your plot floor"
    end
    if not pointInsidePart(plotPart, worldPos, 2) then
        return false, "Out of bounds"
    end

    local model = makeUnitModel(resolvedUnitId)
    local cf, boxSize, boxCf = placementCFrame(plotPart, model, worldPos, rotation)
    if DEBUG_PLACEMENT then
        print(string.format("[PlacementDebug][ServerPlace] player=%s unit=%s hit=%s topDot=%s world=(%.1f, %.1f, %.1f) pivot=(%.1f, %.1f, %.1f) box=(%.1f, %.1f, %.1f)", player.Name, unitId, hitPart and hitPart:GetFullName() or "nil", typeof(hitNormal) == "Vector3" and string.format("%.3f", hitNormal:Dot(plotPart.CFrame.UpVector)) or "nil", worldPos.X, worldPos.Y, worldPos.Z, cf.Position.X, cf.Position.Y, cf.Position.Z, boxSize.X, boxSize.Y, boxSize.Z))
    end
    local blocked, blocker = hasBlockingOverlap(player, plotPart, boxSize, boxCf)
    if blocked then
        if DEBUG_PLACEMENT then print("[PlacementDebug][ServerResult] success=false reason=Blocked by " .. tostring(blocker)) end
        model:Destroy()
        return false, "Blocked by " .. tostring(blocker)
    end

    if not restoring then
        local removed = PlayerDataService.RemoveUnit(player, ownedUnitId, 1)
        if not removed then
            if DEBUG_PLACEMENT then print("[PlacementDebug][ServerResult] success=false reason=No unit owned") end
            model:Destroy()
            return false, "No unit owned"
        end
    end

    model:SetAttribute("OwnerUserId", player.UserId)
    model:SetAttribute("UnitId", ownedUnitId)
    model:SetAttribute("ResolvedUnitId", resolvedUnitId)
    model:PivotTo(cf)
    model.Parent = ownedUnitsFolder(player)
    startAttackLoop(player, model, resolvedUnitId)

    serializePlaced(player)
    if DEBUG_PLACEMENT then print("[PlacementDebug][ServerResult] success=true") end
    return true
end

local function getAimPart(model)
    return model:FindFirstChild("Head", true) or model:FindFirstChild("Barrel", true) or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getBeam()
    local item = table.remove(beamPool)
    if item and item.part and item.part.Parent then return item end
    local part = Instance.new("Part")
    part.Name = "UnitShotBeam"
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Transparency = 1
    part.Size = Vector3.new(0.1,0.1,0.1)
    part.Parent = Workspace
    local a0 = Instance.new("Attachment")
    a0.Name = "A0"
    a0.Parent = part
    local a1 = Instance.new("Attachment")
    a1.Name = "A1"
    a1.Parent = part
    local beam = Instance.new("Beam")
    beam.Name = "Flash"
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.Color = ColorSequence.new(Color3.fromRGB(255,245,120))
    beam.Width0 = 0.18
    beam.Width1 = 0.04
    beam.FaceCamera = true
    beam.LightEmission = 1
    beam.Enabled = false
    beam.Parent = part
    return {part=part,a0=a0,a1=a1,beam=beam}
end

local function flashShot(player,from,to)
    if player and player.Parent then
        shotVisualRemote:FireClient(player, from, to)
    end
end

-- ===== data-driven targeting: enemies live in EnemyCore, not workspace =====
-- pick the enemy furthest along the route (closest to base) within range
local function acquireTarget(player, origin, range)
    local best, bestScore = nil, -math.huge
    for _, info in ipairs(EnemyCore.QueryInRange(player, origin, range)) do
        local score = (tonumber(info.travelled) or 0) + ((tonumber(info.carrying) or 0) > 0 and 100000 or 0)
        if score > bestScore then best, bestScore = info, score end
    end
    return best
end

local function damageSplash(player, center, radius, damage)
    for _, info in ipairs(EnemyCore.QueryInRange(player, center, radius)) do
        EnemyCore.Damage(player, info.id, damage)
    end
end

local function damagePierce(player, origin, dir, range, width, damage)
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.01 then return end
    flat = flat.Unit
    for _, info in ipairs(EnemyCore.QueryInRange(player, origin, range)) do
        local rel = info.pos - origin
        local along = rel.X * flat.X + rel.Z * flat.Z
        if along >= 0 and math.abs(rel.X * flat.Z - rel.Z * flat.X) <= width then
            EnemyCore.Damage(player, info.id, damage)
        end
    end
end

local function damageChain(player, firstId, firstPos, damage, count, chainRange, falloff)
    EnemyCore.Damage(player, firstId, damage)
    local hit = { [firstId] = true }
    local lastPos, dmg = firstPos, damage
    for _ = 2, count do
        dmg = dmg * falloff
        local best, bestD2, bestPos = nil, math.huge, nil
        for _, info in ipairs(EnemyCore.QueryInRange(player, lastPos, chainRange)) do
            if not hit[info.id] and info.distSq < bestD2 then best, bestD2, bestPos = info.id, info.distSq, info.pos end
        end
        if not best then break end
        hit[best] = true
        EnemyCore.Damage(player, best, dmg)
        lastPos = bestPos
    end
end

function startAttackLoop(player, model, unitId)
    local cfg = UnitsConfig.Units[unitId]
    if not cfg or model:GetAttribute("AttackLoopStarted") then return end
    model:SetAttribute("AttackLoopStarted", true)
    task.spawn(function()
        local range = tonumber(cfg.Range) or 30
        local damage = tonumber(cfg.Damage) or 5
        local fireRate = math.max(0.1, tonumber(cfg.FireRate) or 1)
        local shotDelay = math.max(1 / fireRate, 0.18)
        local mechanic = cfg.Mechanic or "single"
        local targetId = nil
        while model.Parent and player.Parent do
            local origin = (model:GetBoundingBox()).Position
            if mechanic == "crush" then
                -- AoE melee: hit everything in range every tick, no aim needed
                for _, info in ipairs(EnemyCore.QueryInRange(player, origin, range)) do
                    EnemyCore.Damage(player, info.id, damage)
                end
            else
                local tpos = targetId and EnemyCore.GetPos(player, targetId)
                if tpos and (tpos - origin).Magnitude > range then tpos = nil end
                if not tpos then
                    local t = acquireTarget(player, origin, range)
                    targetId = t and t.id or nil
                    tpos = t and t.pos or nil
                end
                if targetId and tpos then
                    local aim = getAimPart(model)
                    if aim and aim:IsA("BasePart") then
                        local from = aim.Position
                        aim.CFrame = aim.CFrame:Lerp(CFrame.lookAt(from, Vector3.new(tpos.X, from.Y, tpos.Z)), 0.35)
                    end
                    local muzzle = getAimPart(model)
                    local from = muzzle and muzzle.Position or origin
                    if mechanic == "splash" then
                        damageSplash(player, tpos, tonumber(cfg.SplashRadius) or 10, damage)
                    elseif mechanic == "pierce" then
                        damagePierce(player, origin, tpos - origin, range, tonumber(cfg.PierceWidth) or 4, damage)
                    elseif mechanic == "chain" then
                        damageChain(player, targetId, tpos, damage, tonumber(cfg.ChainCount) or 3, tonumber(cfg.ChainRange) or 16, tonumber(cfg.ChainFalloff) or 0.75)
                    elseif mechanic == "slow" then
                        EnemyCore.Damage(player, targetId, damage)
                        EnemyCore.ApplySlow(player, targetId, tonumber(cfg.SlowMult) or 0.5, tonumber(cfg.SlowDuration) or 1.5)
                    else
                        EnemyCore.Damage(player, targetId, damage)
                    end
                    flashShot(player, from, tpos)
                end
            end
            task.wait(shotDelay)
        end
    end)
end

local function deleteUnit(player, model)
    if typeof(model) ~= "Instance" or not model:IsA("Model") then return false, "Pick a unit" end
    if model:GetAttribute("OwnerUserId") ~= player.UserId then return false, "Not yours" end
    if not model:IsDescendantOf(placedFolder) then return false, "Not placed" end

    local unitId = model:GetAttribute("UnitId") or model.Name
    model:Destroy()
    PlayerDataService.AddUnit(player, unitId, 1)
    serializePlaced(player)
    return true
end

local function loadPlaced(player)
    for _ = 1, 100 do
        if PlayerDataService.GetData(player) then break end
        task.wait(0.1)
    end
    if not PlayerDataService.GetData(player) then return end

    local _, plotPart = getPlotPart(player)
    if not plotPart then return end

    local folder = ownedUnitsFolder(player)
    folder:ClearAllChildren()

    for _, saved in ipairs(PlayerDataService.GetPlacedUnits(player)) do
        if type(saved) == "table" and saved.UnitId and saved.CFrame then
            local relative = arrayToCFrame(saved.CFrame)
            if relative then
                local worldCf = plotPart.CFrame * relative
                place(player, saved.UnitId, worldCf.Position, 0, plotPart, plotPart.CFrame.UpVector, true)
                local newest = folder:GetChildren()[#folder:GetChildren()]
                if newest and newest:IsA("Model") then newest:PivotTo(worldCf) end
            end
        end
    end
    serializePlaced(player)
end

local function bindRemote()
    buildRemote.OnServerInvoke = function(player, action, ...)
        if action == "Place" then
            return place(player, ...)
        elseif action == "Delete" then
            return deleteUnit(player, ...)
        end
        return false, "Unknown build action"
    end
end

task.delay(1, bindRemote)

-- expose serialize/load via bindables for future systems that need to reload placed units
local bindables = game.ServerScriptService:WaitForChild("Bindables")
bindables:WaitForChild("SavePlacedUnits").OnInvoke = function(player)
    serializePlaced(player)
end
bindables:WaitForChild("LoadPlacedUnits").OnInvoke = function(player)
    loadPlaced(player)
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(loadPlaced, player)
end)
Players.PlayerRemoving:Connect(function(player)
    serializePlaced(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(loadPlaced, player)
end

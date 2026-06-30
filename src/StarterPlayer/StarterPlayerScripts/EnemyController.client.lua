--!nonstrict
-- EnemyController: renders this player's enemies (data streamed from EnemyCore).
-- Clones the workspace Rig per enemy, interpolates along the shared PathMover path
-- (dead-reckon + gentle correction to the server's authoritative distance), shows
-- an HP bar, plays a walk anim, and runs a death pop. Pure client visual.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PathMover = require(ReplicatedStorage:WaitForChild("RaidShared"):WaitForChild("PathMover"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EnemyStream = Remotes:WaitForChild("EnemyStream")
local HpGui = ReplicatedStorage:FindFirstChild("HP")
local rigTemplate = Workspace:WaitForChild("Rig")
local WALK_ANIM_ID = "rbxassetid://180426354"

local folder = Workspace:FindFirstChild("ClientEnemies") or Instance.new("Folder")
folder.Name = "ClientEnemies"; folder.Parent = Workspace

local enemies = {} -- id -> { model, hrp, offset, distance, target, speed, health, maxHealth, fill, txt }
local mover = nil

local function locatePlot()
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then return plot end
	end
	return nil
end
local function rebuildMover()
	mover = nil
	local plot = locatePlot()
	local pf = plot and plot:FindFirstChild("Points")
	if not pf then return end
	local ordered = {}
	for _, pt in ipairs(pf:GetChildren()) do
		local n = tonumber(pt.Name)
		if n and pt:IsA("BasePart") then table.insert(ordered, { n = n, p = pt }) end
	end
	table.sort(ordered, function(a, b) return a.n < b.n end)
	if #ordered < 2 then return end
	local pts = {}
	for _, e in ipairs(ordered) do table.insert(pts, e.p.Position) end
	mover = PathMover.new(pts)
end

local function rigGroundOffset(model, hrp)
	local cf, size = model:GetBoundingBox()
	return hrp.Position.Y - (cf.Position.Y - size.Y / 2)
end
local function makeRig(scale)
	local m = rigTemplate:Clone()
	local animate = m:FindFirstChild("Animate"); if animate then animate:Destroy() end
	local hum = m:FindFirstChildOfClass("Humanoid")
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
		for _, s in ipairs({ Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Flying, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Freefall }) do
			pcall(function() hum:SetStateEnabled(s, false) end)
		end
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true; d.CastShadow = false; d.Anchored = false
		end
	end
	if scale and scale ~= 1 then pcall(function() m:ScaleTo(scale) end) end
	if hrp then hrp.Anchored = true end
	local offset = hrp and rigGroundOffset(m, hrp) or 3
	if hum then
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		pcall(function()
			local anim = Instance.new("Animation"); anim.AnimationId = WALK_ANIM_ID
			local track = animator:LoadAnimation(anim)
			track.Looped = true; track.Priority = Enum.AnimationPriority.Movement; track:Play()
		end)
	end
	return m, hrp, offset
end

local function onSpawn(info)
	if not mover then rebuildMover() end
	local model, hrp, offset = makeRig(info.scale)
	model.Name = tostring(info.id)
	local fill, txt
	if HpGui and hrp then
		local g = HpGui:Clone(); g.Name = "HP"; g.Adornee = hrp; g.Parent = hrp
		local cg = g:FindFirstChildWhichIsA("CanvasGroup", true)
		fill = (cg and cg:FindFirstChild("Fill")) or g:FindFirstChild("Fill", true)
		txt = g:FindFirstChild("Text", true)
	end
	model.Parent = folder
	enemies[info.id] = { model = model, hrp = hrp, offset = offset or 3, distance = 0, target = 0,
		speed = info.speed or 11, health = info.maxHealth, maxHealth = math.max(1, info.maxHealth or 1), fill = fill, txt = txt }
	if mover and hrp then local _, cf = mover:At(0); hrp.CFrame = cf + Vector3.new(0, offset or 3, 0) end
end
local function onSync(list)
	for _, entry in ipairs(list) do
		local e = enemies[entry[1]]
		if e then
			e.target = entry[2]; e.health = entry[3]; e.speed = entry[4]
			if math.abs(e.distance - e.target) > 12 then e.distance = e.target end
		end
	end
end
local function deathFX(model)
	task.spawn(function()
		for i = 1, 8 do
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.Transparency = math.clamp(i / 8, d.Transparency, 1); d.Size = d.Size * 0.88 end
				if d:IsA("Decal") then d.Transparency = i / 8 end
			end
			task.wait(0.03)
		end
		model:Destroy()
	end)
end
local function onDespawn(info)
	local e = enemies[info.id]; if not e then return end
	enemies[info.id] = nil
	if info.reason == "death" then deathFX(e.model) else e.model:Destroy() end
end
local function onClear()
	for _, e in pairs(enemies) do if e.model then e.model:Destroy() end end
	table.clear(enemies)
	rebuildMover()
end

RunService.RenderStepped:Connect(function(dt)
	if not mover then return end
	for _, e in pairs(enemies) do
		e.target += (e.speed or 0) * dt
		e.distance += (e.target - e.distance) * math.clamp(dt * 8, 0, 1)
		local _, cf = mover:At(e.distance)
		if e.hrp then e.hrp.CFrame = cf + Vector3.new(0, e.offset, 0) end
		if e.fill then e.fill.Size = UDim2.fromScale(math.clamp((e.health or 0) / e.maxHealth, 0, 1), 1) end
		if e.txt then e.txt.Text = tostring(math.max(0, math.floor(e.health or 0))) end
	end
end)

EnemyStream.OnClientEvent:Connect(function(action, data)
	if action == "spawn" then onSpawn(data)
	elseif action == "sync" then onSync(data)
	elseif action == "despawn" then onDespawn(data)
	elseif action == "clear" then onClear() end
end)

rebuildMover()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local slashSound = handle:FindFirstChild("SwordSlash")
local unsheathSound = handle:FindFirstChild("Unsheath")

local swordHitRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SwordHit")
local SwordsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SwordsConfig"))

local player = Players.LocalPlayer

local swinging = false
local SWING_COOLDOWN = 0.38
local lastSwingTime = 0
local HITBOX_SIZE = Vector3.new(7, 6, 8)
local HITBOX_FORWARD = 4

local slashAnim = Instance.new("Animation")
slashAnim.AnimationId = SwordsConfig.SlashAnimationId

local character, animator, slashTrack
local cleanedUp = false  -- guard so double-cleanup (Unequipped + AncestryChanged) is safe

local function cleanupSword()
	if cleanedUp then return end
	cleanedUp = true

	swinging = false

	if slashTrack and slashTrack.IsPlaying then
		slashTrack:Stop(0.15)
	end

	-- nil everything so stale callbacks can't fire on a dead character
	animator = nil
	slashTrack = nil
	character = nil
end

tool.Equipped:Connect(function()
	cleanedUp = false  -- arm cleanup for this equip session
	character = player.Character
	if not character then return end

	local hum = character:WaitForChild("Humanoid")
	animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)

	slashTrack = animator:LoadAnimation(slashAnim)
	slashTrack.Priority = Enum.AnimationPriority.Action

	if unsheathSound then unsheathSound:Play() end
end)

tool.Unequipped:Connect(cleanupSword)

-- backup: catches cases where the server destroys/reparents the tool
-- without going through the normal unequip path
tool.AncestryChanged:Connect(function()
	local char = player.Character
	if char and not tool:IsDescendantOf(char) then
		cleanupSword()
	end
end)

local function flashHit(model)
	if not model or not model.Parent then return end
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 30, 30)
	hl.FillTransparency = 0.3
	hl.OutlineTransparency = 1
	hl.Adornee = model
	hl.Parent = model
	task.delay(0.18, function()
		if hl and hl.Parent then hl:Destroy() end
	end)
end

local function collectTargets()
	if not character then return {} end
	local root = character:FindFirstChild("HumanoidRootPart")
	local clientEnemies = Workspace:FindFirstChild("ClientEnemies")
	if not root or not clientEnemies then return {} end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { clientEnemies }
	params.MaxParts = 80
	local hitbox = root.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD)
	local targets = {}
	local seen = {}
	for _, part in ipairs(Workspace:GetPartBoundsInBox(hitbox, HITBOX_SIZE, params)) do
		local mob = part:FindFirstAncestorOfClass("Model")
		if mob and mob.Parent == clientEnemies and not seen[mob] then
			seen[mob] = true
			table.insert(targets, mob)
			flashHit(mob)
			if #targets >= 5 then break end
		end
	end
	return targets
end

local function doSwing()
	if swinging or not animator or not character then return end
	local now = os.clock()
	if now - lastSwingTime < SWING_COOLDOWN then return end
	lastSwingTime = now
	swinging = true

	if slashSound then slashSound:Play() end
	if slashTrack then slashTrack:Play(0.04, 1, 1.12) end
	local targets = collectTargets()
	if #targets > 0 then swordHitRemote:FireServer() end

	task.delay(SWING_COOLDOWN, function()
		swinging = false
	end)
end

tool.Activated:Connect(doSwing)

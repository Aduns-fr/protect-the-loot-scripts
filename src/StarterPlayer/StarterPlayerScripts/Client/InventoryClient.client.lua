--[[
	InventoryClient (LocalScript)

	EQUIP PANEL CHANGE: Migrated from a single ImageButton that swapped text/image
	to two separate TextButtons (Equip and Unequip) that are shown/hidden based
	on state. Removed IMG_* constants, setEquipBtnText, setEquipBtnImage helpers.

	SOUNDS: setupGridButton plays UIManager hover/click sounds.
	Grid buttons use UIScale for visual bounce (UIGridLayout controls Size).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules          = ReplicatedStorage:WaitForChild("Modules")
local AnimalConfig     = require(Modules:WaitForChild("AnimalConfig"))
local AbilityConfig    = require(Modules:WaitForChild("AbilityConfig"))
local Module3D         = require(Modules:WaitForChild("Module3D"))
local ViewportEffects  = require(Modules:WaitForChild("ViewportEffects"))

local InventoryRemotes = ReplicatedStorage:WaitForChild("InventoryRemotes")
local GetInventory     = InventoryRemotes:WaitForChild("GetInventory")
local EquipAnimal      = InventoryRemotes:WaitForChild("EquipAnimal")
local UnequipAnimal    = InventoryRemotes:WaitForChild("UnequipAnimal")
local InventoryUpdate  = InventoryRemotes:WaitForChild("InventoryUpdate")

local interface      = playerGui:WaitForChild("Interface", 30)
local framesFolder   = interface:WaitForChild("Frames")
local inventoryFrame = framesFolder:WaitForChild("Inventory")

local holder         = inventoryFrame:WaitForChild("ScrollingFrame")
local template       = holder:WaitForChild("Template")
local equipFrame     = inventoryFrame:WaitForChild("Equip")
local imageLabel     = equipFrame:WaitForChild("ImageLabel")
local equipDisplay   = imageLabel:WaitForChild("Display")
local equipNameLabel = equipFrame:WaitForChild("Name")
local buffLabel      = equipFrame:FindFirstChild("Buff")

-- Two separate buttons instead of one that swaps text/image
local equipBtn   = equipFrame:FindFirstChild("Equip")    -- TextButton: shown when can equip
local unequipBtn = equipFrame:FindFirstChild("Unequip")  -- TextButton: shown when can unequip

template.Visible = false

local COLUMNS  = 4
local CELL_GAP = 10

local ownedAnimals   = {}
local equippedAnimal = nil
local selectedAnimal = nil
local isRequesting   = false
local renderConns    = {}
local gridLayoutConn = nil
local cellSizeConn   = nil
local equipPanelConn  = nil
local equipEffectConn = nil  -- viewport effect for the equip panel display (e.g. rainbow)

local function playUISound(name)
	local um = _G.UIManager
	if um and um.playSound then um.playSound(name) end
end

local function setupGridButton(btn)
	local function getScale()
		local s = btn:FindFirstChildOfClass("UIScale")
		if not s then s = Instance.new("UIScale"); s.Parent = btn end
		return s
	end

	btn.MouseEnter:Connect(function()
		playUISound("hover")
		TweenService:Create(getScale(), TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1.08 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(getScale(), TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		playUISound("click")
		TweenService:Create(getScale(), TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = 0.92 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(getScale(), TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
end

local SOURCE_RANK = {
	Free        = 0,
	Egg1        = 1, Egg2 = 2, Egg3 = 3, Egg4 = 4, Egg5 = 5,
	Pack        = 6,
	VIP         = 7,
	DailyReward = 8,
	WeeklyWins  = 9,
	WeeklyElims = 10,
}

local function getChanceRank(chance)
	if not chance or chance >= 0.50 then return 0
	elseif chance >= 0.20            then return 1
	elseif chance >= 0.03            then return 2
	else                                  return 3 end
end

local function sortKey(animalName)
	local cfg = AnimalConfig.getConfig(animalName); if not cfg then return 999 end
	local sr = SOURCE_RANK[cfg.Obtainability.Source] or 0
	local cr = getChanceRank(cfg.Obtainability.Chance)
	return sr * 10 + cr
end

local function sortedOwned(list)
	local copy = {}
	for _, v in ipairs(list) do table.insert(copy, v) end
	table.sort(copy, function(a, b) return sortKey(a) < sortKey(b) end)
	local snailIdx = nil
	for i, name in ipairs(copy) do if name == "Snail" then snailIdx = i; break end end
	if snailIdx then table.remove(copy, snailIdx) end
	table.insert(copy, 1, "Snail")
	local seen, deduped = {}, {}
	for _, v in ipairs(copy) do
		if not seen[v] then seen[v] = true; table.insert(deduped, v) end
	end
	return deduped
end

local function clearDisplay(displayFrame)
	for _, v in ipairs(displayFrame:GetChildren()) do
		if v:IsA("ViewportFrame") then v:Destroy() end
	end
end

local function attach3D(displayFrame, modelName)
	clearDisplay(displayFrame)
	local Animals = ReplicatedStorage:FindFirstChild("Animals")
	if not Animals then warn("[INV] ReplicatedStorage.Animals not found"); return nil, nil end
	local model = Animals:FindFirstChild(modelName)
	if not model then warn("[INV] Model not found:", modelName); return nil, nil end
	local petModel = Module3D.new(model:Clone())
	petModel.AdornFrame.Size        = UDim2.new(1, 0, 1, 0)
	petModel.AdornFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	petModel.AdornFrame.Position    = UDim2.new(0.5, 0, 0.5, 0)
	petModel.AdornFrame.Parent      = displayFrame
	petModel:SetDepthMultiplier(1.2)
	petModel.Camera.FieldOfView = 5
	petModel.Visible = true
	petModel:Update()
	-- Heartbeat is lower priority than RenderStepped, good enough for rotation
	local rotConn = RunService.Heartbeat:Connect(function()
		if not petModel or not petModel.Visible then return end
		petModel:SetCFrame(
			CFrame.Angles(0, tick() % (math.pi * 2), 0) * CFrame.Angles(math.rad(-10), 0, 0)
		)
	end)
	-- ViewportEffects: pass displayFrame so UI-based effects (Phoenix fire) can overlay it
	local effectConn = ViewportEffects.apply(modelName, petModel.Object3D, displayFrame)
	return rotConn, effectConn
end

-- Shows/hides Equip and Unequip buttons based on current selection state.
local function refreshEquipPanel()
	if not selectedAnimal then selectedAnimal = equippedAnimal end

	-- always hide both first so we start from a clean slate
	if equipBtn   then equipBtn.Visible   = false end
	if unequipBtn then unequipBtn.Visible = false end

	if not selectedAnimal then
		equipNameLabel.Text = "Select an animal"
		if buffLabel then buffLabel.Text = "" end
		clearDisplay(equipDisplay)
		if equipPanelConn  then equipPanelConn:Disconnect();  equipPanelConn  = nil end
		if equipEffectConn then equipEffectConn:Disconnect(); equipEffectConn = nil end
		return
	end

	local cfg = AnimalConfig.getConfig(selectedAnimal)
	equipNameLabel.Text = cfg and cfg.DisplayName or selectedAnimal
	if buffLabel then
		local ability, resolvedName = AbilityConfig.getFor(selectedAnimal)
		buffLabel.Text = ability and ability.buffText or ""
		buffLabel.Visible = resolvedName ~= nil
	end

	if equipPanelConn  then equipPanelConn:Disconnect();  equipPanelConn  = nil end
	if equipEffectConn then equipEffectConn:Disconnect(); equipEffectConn = nil end
	local modelName = cfg and cfg.ModelName or selectedAnimal
	equipPanelConn, equipEffectConn = attach3D(equipDisplay, modelName)

	if selectedAnimal == equippedAnimal then
		-- already wearing this one - show Unequip unless it's the default Snail
		if selectedAnimal ~= "Snail" then
			if unequipBtn then unequipBtn.Visible = true end
		end
		-- Snail equipped: show nothing (can't unequip the default)
	else
		-- different animal selected - show Equip
		if equipBtn then equipBtn.Visible = true end
	end
end

local COL_STROKE_EQUIPPED   = Color3.fromRGB(61, 141, 47)
local COL_STROKE_DEFAULT    = Color3.fromRGB(0, 0, 0)
local STROKE_THICK_EQUIPPED = 2
local STROKE_THICK_DEFAULT  = 2

local function updateTemplateOutlines()
	for _, child in ipairs(holder:GetChildren()) do
		if not child:IsA("GuiButton") or child == template then continue end
		local stroke = child:FindFirstChildOfClass("UIStroke"); if not stroke then continue end
		local name = child:GetAttribute("AnimalName")
		if name == equippedAnimal then
			stroke.Color = COL_STROKE_EQUIPPED; stroke.Thickness = STROKE_THICK_EQUIPPED
		else
			stroke.Color = COL_STROKE_DEFAULT; stroke.Thickness = STROKE_THICK_DEFAULT
		end
	end
end

local function clearTemplates()
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("GuiButton") and child ~= template then child:Destroy() end
	end
	for _, conn in ipairs(renderConns) do conn:Disconnect() end
	table.clear(renderConns)
	if gridLayoutConn then gridLayoutConn:Disconnect(); gridLayoutConn = nil end
	if cellSizeConn   then cellSizeConn:Disconnect();   cellSizeConn   = nil end
end

local function populateTemplates()
	clearTemplates()
	local sorted = sortedOwned(ownedAnimals)

	for _, animalName in ipairs(sorted) do
		local cfg = AnimalConfig.getConfig(animalName)
		if not cfg then warn("[INV] no config for:", animalName); continue end

		local btn = template:Clone()
		btn.Name    = animalName
		btn.Visible = true
		btn:SetAttribute("AnimalName", animalName)
		btn.Parent  = holder

		local nameLabel = btn:FindFirstChild("Name")
		if nameLabel then nameLabel.Text = cfg.DisplayName end

		local display = btn:FindFirstChild("Display")
		if display then
			local rotConn, effectConn = attach3D(display, cfg.ModelName)
			if rotConn then table.insert(renderConns, rotConn) end
			if effectConn then table.insert(renderConns, effectConn) end
		else
			warn("[INV] no Display child on btn for", animalName)
		end

		setupGridButton(btn)

		btn.MouseButton1Click:Connect(function()
			selectedAnimal = animalName
			refreshEquipPanel()
		end)
	end

	local gridLayout = holder:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then
		local function updateCellSize()
			local w = holder.AbsoluteSize.X
			local uiPad = holder:FindFirstChildOfClass("UIPadding")
			if uiPad then
				w = w
				- (uiPad.PaddingLeft.Offset  + uiPad.PaddingLeft.Scale  * w)
				- (uiPad.PaddingRight.Offset + uiPad.PaddingRight.Scale * w)
			end
			local totalGap = CELL_GAP * (COLUMNS + 1)
			local cellW    = math.floor((w - totalGap) / COLUMNS)
			gridLayout.CellPadding = UDim2.new(0, CELL_GAP, 0, CELL_GAP)
			gridLayout.CellSize    = UDim2.new(0, cellW, 0, cellW)
		end

		local function updateCanvas()
			holder.CanvasSize = UDim2.new(0, 0, 0, gridLayout.AbsoluteContentSize.Y + 8)
		end

		task.defer(function() updateCellSize(); updateCanvas() end)
		cellSizeConn   = holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
		gridLayoutConn = gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
	end

	updateTemplateOutlines()
end

local function refreshInventory()
	local ok, data = pcall(function() return GetInventory:InvokeServer() end)
	if ok and type(data) == "table" then
		ownedAnimals   = data.owned   or {}
		equippedAnimal = data.equipped
	else
		warn("[INV] GetInventory failed:", tostring(data))
	end
	local hasSnail = false
	for _, name in ipairs(ownedAnimals) do if name == "Snail" then hasSnail = true; break end end
	if not hasSnail then table.insert(ownedAnimals, "Snail") end
	selectedAnimal = equippedAnimal
	populateTemplates()
	refreshEquipPanel()
end

-- Equip / Unequip button clicks

if equipBtn then
	equipBtn.MouseButton1Click:Connect(function()
		if isRequesting or not selectedAnimal then return end
		if selectedAnimal == equippedAnimal then return end
		isRequesting = true
		local ok, result = pcall(function() return EquipAnimal:InvokeServer(selectedAnimal) end)
		if ok and result then equippedAnimal = selectedAnimal end
		if not ok then warn("[INV] Equip error:", result) end
		refreshEquipPanel()
		updateTemplateOutlines()
		isRequesting = false
	end)
end

if unequipBtn then
	unequipBtn.MouseButton1Click:Connect(function()
		if isRequesting or not selectedAnimal then return end
		if selectedAnimal ~= equippedAnimal   then return end
		if selectedAnimal == "Snail"          then return end
		isRequesting = true
		local ok, result = pcall(function() return UnequipAnimal:InvokeServer() end)
		if ok and result then equippedAnimal = "Snail"; selectedAnimal = "Snail" end
		if not ok then warn("[INV] Unequip error:", result) end
		refreshEquipPanel()
		updateTemplateOutlines()
		isRequesting = false
	end)
end

-- Remote updates

InventoryUpdate.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	ownedAnimals   = data.owned   or ownedAnimals
	equippedAnimal = data.equipped
	local hasSnail = false
	for _, name in ipairs(ownedAnimals) do if name == "Snail" then hasSnail = true; break end end
	if not hasSnail then table.insert(ownedAnimals, "Snail") end
	if inventoryFrame.Visible then
		local stillOwned = false
		for _, name in ipairs(ownedAnimals) do
			if name == selectedAnimal then stillOwned = true; break end
		end
		if not stillOwned then selectedAnimal = equippedAnimal end
		populateTemplates()
		refreshEquipPanel()
	end
end)

-- Frame open/close

inventoryFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if inventoryFrame.Visible then
		refreshInventory()
	else
		for _, conn in ipairs(renderConns) do conn:Disconnect() end
		table.clear(renderConns)
		if equipPanelConn  then equipPanelConn:Disconnect();  equipPanelConn  = nil end
		if equipEffectConn then equipEffectConn:Disconnect(); equipEffectConn = nil end
		if gridLayoutConn  then gridLayoutConn:Disconnect();  gridLayoutConn  = nil end
		if cellSizeConn    then cellSizeConn:Disconnect();    cellSizeConn    = nil end
		clearDisplay(equipDisplay)
	end
end)
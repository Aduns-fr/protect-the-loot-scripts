local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local openFrameRequest = gui:WaitForChild("OpenFrameRequest")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local unitPurchaseRemote = remotes:WaitForChild("UnitPurchase")
local inventoryRemote = remotes:WaitForChild("UnitInventoryUpdate")
local baseUpgradeRemote = remotes:WaitForChild("BaseUpgrade")
local baseDataRemote = remotes:WaitForChild("BaseDataUpdate")
local stockRemote = remotes:WaitForChild("UnitStockUpdate")
local buildRemote = remotes:WaitForChild("BuildAction")
local crateStockRemote = remotes:WaitForChild("CrateStockUpdate")
local cratePurchaseRemote = remotes:WaitForChild("CratePurchase")
local crateOpenedRemote = remotes:WaitForChild("CrateOpened")

local UnitsConfig = require(ReplicatedStorage.Configs.UnitsConfig)
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
local CratesConfig = require(ReplicatedStorage.Configs.CratesConfig)
local BaseUpgradesConfig = require(ReplicatedStorage.Configs.BaseUpgradesConfig)
local MAX_BASE_LEVEL = 7
local FALLBACK_BASE_LEVELS = {
    [1] = { Health = 500, UpgradeCost = 350 }, [2] = { Health = 800, UpgradeCost = 900 }, [3] = { Health = 1250, UpgradeCost = 1800 },
    [4] = { Health = 1850, UpgradeCost = 3600 }, [5] = { Health = 2700, UpgradeCost = 7000 }, [6] = { Health = 3800, UpgradeCost = 12500 }, [7] = { Health = 5200 },
}

local unitsFrame = frames:WaitForChild("Units")
local unitsScroll = unitsFrame:WaitForChild("ScrollingFrame")
local unitsTemplate = unitsScroll:WaitForChild("Template")
local unitsTimer = unitsFrame:WaitForChild("Timer")
local cratesFrame = frames:WaitForChild("Crates")
local cratesScroll = cratesFrame:WaitForChild("ScrollingFrame")
local cratesTemplate = cratesScroll:WaitForChild("Template")
local cratesTimer = cratesFrame:FindFirstChild("Timer")
if not cratesTimer then
    cratesTimer = unitsTimer:Clone()
    cratesTimer.Name = "Timer"
    cratesTimer.Parent = cratesFrame
end
local buildFrame = frames:WaitForChild("Build")
local buildScroll = buildFrame:WaitForChild("ScrollingFrame")
local buildTemplate = buildScroll:WaitForChild("Template")
local baseFrame = frames:WaitForChild("Base")
local currentPanel = baseFrame:WaitForChild("Current")
local nextPanel = baseFrame:WaitForChild("Next")
local upgradeButton = baseFrame:WaitForChild("Upgrade")
local unitModels = ReplicatedStorage:WaitForChild("UnitModels")

local stock, crateStock = {}, {}
local unitCardsById, crateCardsById = {}, {}
local nextReset, crateNextReset = 0, 0
local inventory = {}
local baseLevel = tonumber(player:GetAttribute("BaseLevel")) or 1
local placingUnit, rotation, ghost, lastSnapPosition = nil, 0, nil, nil
gui:SetAttribute("PlacementActive", false)
local placementBoxPart, placementSelection, deleteBoxPart, deleteSelection = nil, nil, nil, nil
local selectedBuildButton, hoveredDeleteModel = nil, nil
local lastHitPart, lastHitNormal = nil, nil
local canPlaceHere = false
local makeGhost
local setSelectedBuildButton
local CLICK_IN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLICK_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DEBUG_PLACEMENT = false
local lastPlacementDebug = 0
local lastPlacementCheck, cachedPlacementClear = 0, false

local function formatCash(value)
    value = math.floor(tonumber(value) or 0)
    local text = tostring(value)
    while true do local nextText, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2"); text = nextText; if count == 0 then break end end
    return "$" .. text
end

local function scaleButton(button)
    if not button or not button:IsA("GuiButton") or button:GetAttribute("ClickAnimBound") then return end
    button:SetAttribute("ClickAnimBound", true)
    local scale = button:FindFirstChild("ClickScale") or Instance.new("UIScale")
    scale.Name = "ClickScale"; scale.Parent = button
    button.MouseButton1Down:Connect(function() TweenService:Create(scale, CLICK_IN, { Scale = 0.92 }):Play() end)
    local function release() TweenService:Create(scale, CLICK_OUT, { Scale = 1 }):Play() end
    button.MouseButton1Up:Connect(release); button.MouseLeave:Connect(release)
end

local function normalizeShopScroll(scroll)
    local layout = scroll:FindFirstChildOfClass("UIListLayout")
    if layout then layout.Padding = UDim.new(0, 8) end
    local padding = scroll:FindFirstChildOfClass("UIPadding")
    if padding then
        padding.PaddingTop = UDim.new(0, 8)
        padding.PaddingBottom = UDim.new(0, 8)
        padding.PaddingLeft = UDim.new(0, 0)
        padding.PaddingRight = UDim.new(0, 0)
    end
end

local function canvasList(scroll)
    normalizeShopScroll(scroll)
    local layout = scroll:FindFirstChildOfClass("UIListLayout")
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.fromScale(0, 0)
    if layout then task.defer(function() scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 24) end) end
end

local function canvasGrid(scroll)
    local grid = scroll:FindFirstChildOfClass("UIGridLayout")
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.fromScale(0, 0)
    if grid then task.defer(function() scroll.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 24) end) end
end

local function updateUnitCards()
    local keepCanvasPosition = unitsScroll.CanvasPosition
    local hasCards = next(unitCardsById) ~= nil
    if not hasCards then
        for _, child in ipairs(unitsScroll:GetChildren()) do if child:IsA("Frame") and child ~= unitsTemplate then child:Destroy() end end
        unitsTemplate.Visible = false
        unitCardsById = {}
        for index, unitId in ipairs(UnitsConfig.Order) do
            local cfg = UnitsConfig.Units[unitId]
            if cfg then
                local card = unitsTemplate:Clone()
                card.Name = unitId
                card.LayoutOrder = index
                card.Visible = true
                card.Parent = unitsScroll
                unitCardsById[unitId] = card
                card:FindFirstChild("Name").Text = cfg.DisplayName or unitId
                card:FindFirstChild("Price").Text = formatCash(cfg.CashPrice or 0)
                scaleButton(card.Cash); scaleButton(card.Robux)
                card.Cash.Activated:Connect(function()
                    local ok, success, msg = pcall(function() return unitPurchaseRemote:InvokeServer(unitId, "Cash") end)
                    if ok and not success then
                        if _G.PlaySound then _G.PlaySound("Error") end
                        if _G.ShowNotif then
                            local reason = tostring(msg or "")
                            local text = (reason == "Not enough cash" or reason:lower():find("cash")) and "Not enough money!" or "Can't purchase right now"
                            _G.ShowNotif(text, Color3.fromRGB(255, 35, 35))
                        end
                    end
                end)
                card.Robux.Activated:Connect(function() local id = tonumber(cfg.RobuxProductId) or 0; if id > 0 then MarketplaceService:PromptProductPurchase(player, id) end end)
            end
        end
    end
    for unitId, card in pairs(unitCardsById) do
        if card and card.Parent then
            local stockLabel = card:FindFirstChild("Stock")
            if stockLabel then stockLabel.Text = "Stock: " .. tostring(stock[unitId] or 0) end
        end
    end
    canvasList(unitsScroll)
    task.defer(function()
        unitsScroll.CanvasPosition = keepCanvasPosition
        task.wait()
        unitsScroll.CanvasPosition = keepCanvasPosition
        task.wait()
        unitsScroll.CanvasPosition = keepCanvasPosition
    end)
end

local function startRewardMarquee(strip)
    local layout = strip:FindFirstChildOfClass("UIListLayout")
    if not layout then return end
    task.spawn(function()
        task.wait(0.2)
        while strip.Parent do
            local width = math.max(0, layout.AbsoluteContentSize.X - strip.AbsoluteWindowSize.X)
            if width > 0 then
                strip.CanvasPosition = Vector2.new(0, 0)
                local tween = TweenService:Create(strip, TweenInfo.new(math.clamp(width / 45, 2.2, 5.5), Enum.EasingStyle.Linear), { CanvasPosition = Vector2.new(width, 0) })
                tween:Play()
                tween.Completed:Wait()
                task.wait(0.25)
            else
                task.wait(0.5)
            end
        end
    end)
end


local function populateRewardStrip(card, cfg)
    local strip = card:FindFirstChild("ScrollingFrame"); if not strip then return end
    local template = strip:FindFirstChild("Template"); if not template then return end
    for _, child in ipairs(strip:GetChildren()) do if child:IsA("GuiObject") and child ~= template then child:Destroy() end end
    template.Visible = false
    local layout = strip:FindFirstChildOfClass("UIListLayout")
    if layout then layout.FillDirection = Enum.FillDirection.Horizontal end
    for _, reward in ipairs(cfg.Rewards or {}) do
        local item = template:Clone(); item.Visible = true; item.Parent = strip
        local label = item:FindFirstChild("TextLabel"); if label then label.Text = tostring(reward.Chance) .. "%" end
    end
    strip.AutomaticCanvasSize = Enum.AutomaticSize.X
    startRewardMarquee(strip)
end

local function populateChestViewport(card, crateId)
    local image = card:FindFirstChild("ImageLabel")
    local cfg = CratesConfig.Crates[crateId]
    local template = cfg and ReplicatedStorage:WaitForChild("Crates"):FindFirstChild(cfg.ModelName or crateId)
    if not image or not image:IsA("ImageLabel") or not template or not template:IsA("Model") then return end
    image.ImageTransparency = 1
    local viewport = image:FindFirstChild("ChestViewport") or Instance.new("ViewportFrame")
    viewport.Name = "ChestViewport"
    viewport.BackgroundTransparency = 1
    viewport.BorderSizePixel = 0
    viewport.Size = UDim2.fromScale(1, 1)
    viewport.Position = UDim2.fromScale(0, 0)
    viewport.Ambient = Color3.fromRGB(190, 190, 190)
    viewport.LightColor = Color3.fromRGB(255, 245, 225)
    viewport.LightDirection = Vector3.new(-1, -1, -1)
    viewport.Parent = image
    viewport:ClearAllChildren()
    local world = Instance.new("WorldModel")
    world.Parent = viewport
    local model = template:Clone()
    model.Parent = world
    local boxCf, boxSize = model:GetBoundingBox()
    local pivotToBox = model:GetPivot():ToObjectSpace(boxCf)
    model:PivotTo(CFrame.Angles(0, math.rad(-25), 0) * pivotToBox:Inverse())
    local camera = Instance.new("Camera")
    camera.FieldOfView = 34
    local distance = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 2.15
    camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.72, distance * 0.42, distance), Vector3.new(0, 0, 0))
    camera.Parent = viewport
    viewport.CurrentCamera = camera
end

local function updateCrateCards()
    local keepCanvasPosition = cratesScroll.CanvasPosition
    local hasCards = next(crateCardsById) ~= nil
    if not hasCards then
        for _, child in ipairs(cratesScroll:GetChildren()) do if child:IsA("Frame") and child ~= cratesTemplate then child:Destroy() end end
        cratesTemplate.Visible = false
        crateCardsById = {}
        for index, crateId in ipairs(CratesConfig.Order) do
            local cfg = CratesConfig.Crates[crateId]
            if cfg then
                local card = cratesTemplate:Clone()
                card.Name = crateId
                card.LayoutOrder = index
                card.Visible = true
                card.Parent = cratesScroll
                crateCardsById[crateId] = card
                populateChestViewport(card, crateId)
                card:FindFirstChild("Name").Text = cfg.DisplayName or crateId
                card:FindFirstChild("Price").Text = formatCash(cfg.CashPrice or 0)
                populateRewardStrip(card, cfg)
                scaleButton(card.Cash); scaleButton(card.Robux)
                card.Cash.Activated:Connect(function()
                    local ok, success, msg = pcall(function() return cratePurchaseRemote:InvokeServer(crateId, "Cash") end)
                    if ok and not success then
                        if _G.PlaySound then _G.PlaySound("Error") end
                        if _G.ShowNotif then
                            local reason = tostring(msg or "")
                            local text = (reason:lower():find("cash") or reason:lower():find("money")) and "Not enough money!" or "Can't purchase right now"
                            _G.ShowNotif(text, Color3.fromRGB(255, 35, 35))
                        end
                    end
                end)
                card.Robux.Activated:Connect(function() local id = tonumber(cfg.RobuxProductId) or 0; if id > 0 then MarketplaceService:PromptProductPurchase(player, id) end end)
            end
        end
    end
    for crateId, card in pairs(crateCardsById) do
        if card and card.Parent then
            local stockLabel = card:FindFirstChild("Stock")
            if stockLabel then stockLabel.Text = "Stock: " .. tostring(crateStock[crateId] or 0) end
        end
    end
    canvasList(cratesScroll)
    task.defer(function()
        cratesScroll.CanvasPosition = keepCanvasPosition
        task.wait()
        cratesScroll.CanvasPosition = keepCanvasPosition
        task.wait()
        cratesScroll.CanvasPosition = keepCanvasPosition
    end)
end

local function updateBuildInventory()
    for _, child in ipairs(buildScroll:GetChildren()) do if child:IsA("ImageButton") and child ~= buildTemplate then child:Destroy() end end
    buildTemplate.Visible = false
    local ids = {}
    for unitId, amount in pairs(inventory) do if (tonumber(amount) or 0) > 0 and resolveUnitId(unitId) then table.insert(ids, unitId) end end
    table.sort(ids)
    for _, unitId in ipairs(ids) do
        local item = buildTemplate:Clone(); item.Name = unitId; item.Visible = true; item.Parent = buildScroll
        item.Amt.Text = "x" .. tostring(inventory[unitId]); scaleButton(item)
        if placingUnit == unitId then setSelectedBuildButton(item) end
        item.Activated:Connect(function()
            rotation = 0
            gui:SetAttribute("DeleteMode", false)
            makeGhost(unitId)
            setSelectedBuildButton(item)
        end)
    end
    canvasGrid(buildScroll)
end

local function levelData(level)
    return (BaseUpgradesConfig.Levels and BaseUpgradesConfig.Levels[level]) or FALLBACK_BASE_LEVELS[level] or FALLBACK_BASE_LEVELS[1]
end

local function updateBaseFrame()
    baseLevel = math.clamp(tonumber(baseLevel) or 1, 1, MAX_BASE_LEVEL)
    local cur = levelData(baseLevel); local nextLevel = math.min(baseLevel + 1, MAX_BASE_LEVEL); local nxt = levelData(nextLevel)
    currentPanel.Level.Text = "Level " .. baseLevel; currentPanel.Health.Text = tostring(cur.Health) .. " HP"
    nextPanel.Level.Text = baseLevel >= MAX_BASE_LEVEL and "MAX" or ("Level " .. nextLevel); nextPanel.Health.Text = tostring(nxt.Health) .. " HP"
    if baseLevel >= MAX_BASE_LEVEL then upgradeButton.Text = "MAX LEVEL"; upgradeButton.Active = false else upgradeButton.Text = "Upgrade " .. formatCash(cur.UpgradeCost or 0); upgradeButton.Active = gui:GetAttribute("RaidActive") ~= true end
end

local function setBuildButtonSelected(button, selected)
    if not button then return end
    for _, stroke in ipairs(button:GetDescendants()) do
        if stroke:IsA("UIStroke") then
            if stroke:GetAttribute("OriginalColor") == nil then
                stroke:SetAttribute("OriginalColor", stroke.Color)
            end
            stroke.Color = selected and Color3.fromRGB(79, 171, 8) or stroke:GetAttribute("OriginalColor")
        end
    end
end

function setSelectedBuildButton(button)
    if selectedBuildButton and selectedBuildButton ~= button then
        setBuildButtonSelected(selectedBuildButton, false)
    end
    selectedBuildButton = button
    if selectedBuildButton then setBuildButtonSelected(selectedBuildButton, true) end
end

local function destroyPlacementVisuals()
    if placementBoxPart then placementBoxPart:Destroy(); placementBoxPart = nil end
    placementSelection = nil
    if deleteBoxPart then deleteBoxPart:Destroy(); deleteBoxPart = nil end
    deleteSelection = nil
end

local function clearGhost(keepSelection)
    if ghost then ghost:Destroy(); ghost = nil end
    placingUnit = nil; lastSnapPosition = nil; canPlaceHere = false
    gui:SetAttribute("PlacementActive", false)
    destroyPlacementVisuals()
    if not keepSelection then setSelectedBuildButton(nil) end
end

local function ensureBoxVisual(kind)
    local isDelete = kind == "Delete"
    local part = isDelete and deleteBoxPart or placementBoxPart
    local selection = isDelete and deleteSelection or placementSelection
    if not part then
        part = Instance.new("Part")
        part.Name = isDelete and "DeleteHitboxPreview" or "PlacementHitboxPreview"
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Transparency = 1
        part.Parent = Workspace
        selection = Instance.new("SelectionBox")
        selection.Name = "BoxOutline"
        selection.LineThickness = isDelete and 0.08 or 0.06
        selection.SurfaceTransparency = 0.92
        selection.Adornee = part
        selection.Parent = part
        if isDelete then deleteBoxPart, deleteSelection = part, selection else placementBoxPart, placementSelection = part, selection end
    end
    return part, selection
end

local function showBox(kind, boxCf, boxSize, color)
    local part, selection = ensureBoxVisual(kind)
    part.Size = boxSize
    part.CFrame = boxCf
    selection.Color3 = color
    selection.SurfaceColor3 = color
    selection.Visible = true
end

local function hideBox(kind)
    local selection = kind == "Delete" and deleteSelection or placementSelection
    if selection then selection.Visible = false end
end

local function currentPlot()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil, nil end
    local assignedName = player:GetAttribute("PlotName")
    local assignedPlot = assignedName and plots:FindFirstChild(assignedName)
    local assignedPart = assignedPlot and assignedPlot:FindFirstChild("Part")
    if assignedPart and assignedPart:IsA("BasePart") then return assignedPlot, assignedPart end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == player.UserId then
            local part = plot:FindFirstChild("Part")
            if part and part:IsA("BasePart") then return plot, part end
        end
    end
    return nil, nil
end

local function currentPlotPart()
    local _, part = currentPlot()
    return part
end

local function islandSurfaceParts(plot)
    local island = plot and plot:FindFirstChild("Island")
    if not island then return {} end
    local parts = {}
    for _, descendant in ipairs(island:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end
    return parts
end

local function plotHitPosition()
    lastHitPart = nil
    lastHitNormal = nil
    local plot, part = currentPlot()
    if not plot or not part then return nil end
    local surfaceParts = islandSurfaceParts(plot)
    if #surfaceParts == 0 then return nil end
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = surfaceParts
    local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
    if DEBUG_PLACEMENT and os.clock() - lastPlacementDebug > 0.5 then
        lastPlacementDebug = os.clock()
        if result then
            print(string.format("[PlacementDebug][ClientRay] hit=%s target=%s normal=(%.2f, %.2f, %.2f) topDot=%.3f pos=(%.1f, %.1f, %.1f)", result.Instance:GetFullName(), plot:GetFullName() .. ".Island", result.Normal.X, result.Normal.Y, result.Normal.Z, result.Normal:Dot(part.CFrame.UpVector), result.Position.X, result.Position.Y, result.Position.Z))
        else
            print(string.format("[PlacementDebug][ClientRay] no hit target=%s mouse=(%d,%d)", plot:GetFullName() .. ".Island", mouse.X, mouse.Y))
        end
    end
    if result and result.Instance and result.Instance:IsDescendantOf(plot:FindFirstChild("Island")) and result.Normal:Dot(part.CFrame.UpVector) > 0.75 then
        lastHitPart = result.Instance
        lastHitNormal = result.Normal
        return result.Position
    end
    return nil
end

local function placementCFrame(world)
    local part = currentPlotPart()
    if not part or not world or not ghost then return nil end
    local lp = part.CFrame:PointToObjectSpace(world)
    local half = part.Size * 0.5
    local boxCf, boxSize = ghost:GetBoundingBox()
    local radius = math.max(2, math.min(boxSize.X, boxSize.Z) * 0.5)
    local x = math.clamp(lp.X, -half.X + radius, half.X - radius)
    local z = math.clamp(lp.Z, -half.Z + radius, half.Z - radius)
    local normal = (lastHitNormal and lastHitNormal.Magnitude > 0.1) and lastHitNormal.Unit or part.CFrame.UpVector
    local surfaceWorld = part.CFrame:PointToWorldSpace(Vector3.new(x, lp.Y, z))
    local plotRotation = part.CFrame - part.CFrame.Position
    local targetBoxCf = CFrame.new(surfaceWorld + normal * (boxSize.Y * 0.5)) * plotRotation * CFrame.Angles(0, math.rad(rotation), 0)
    local pivotToBox = ghost:GetPivot():ToObjectSpace(boxCf)
    local cf = targetBoxCf * pivotToBox:Inverse()
    return cf, targetBoxCf, boxSize
end

local function localPlacementClear(boxCf, boxSize)
    local plot, plotPart = currentPlot()
    if not plotPart then return false end
    local island = plot and plot:FindFirstChild("Island")
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local excluded = {}
    if player.Character then table.insert(excluded, player.Character) end
    if ghost then table.insert(excluded, ghost) end
    if placementBoxPart then table.insert(excluded, placementBoxPart) end
    if deleteBoxPart then table.insert(excluded, deleteBoxPart) end
    params.FilterDescendantsInstances = excluded
    local extents = boxSize - Vector3.new(0.2, 0.2, 0.2)
    for _, part in ipairs(Workspace:GetPartBoundsInBox(boxCf, extents, params)) do
        if part ~= plotPart and not (island and part:IsDescendantOf(island)) then
            return false, part:GetFullName()
        end
    end
    return true
end

local function findPlacedUnitUnderMouse()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local excluded = {}
    if player.Character then table.insert(excluded, player.Character) end
    if placementBoxPart then table.insert(excluded, placementBoxPart) end
    if deleteBoxPart then table.insert(excluded, deleteBoxPart) end
    params.FilterDescendantsInstances = excluded
    local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
    local model = result and result.Instance and result.Instance:FindFirstAncestorOfClass("Model")
    if model and model:GetAttribute("OwnerUserId") == player.UserId and model:IsDescendantOf(Workspace:FindFirstChild("PlacedUnits") or Workspace) then
        return model
    end
    return nil
end

function makeGhost(unitId)
    clearGhost()
    lastPlacementCheck = 0
    cachedPlacementClear = false
    local templateId = resolveUnitId(unitId)
    if not templateId then return end
    local template = unitModels:FindFirstChild(templateId)
    if not template then return end
    placingUnit = unitId
    ghost = template:Clone()
    ghost.Name = "PlacementGhost"
    for _, part in ipairs(ghost:GetDescendants()) do if part:IsA("BasePart") then part.Transparency = 0.45; part.CanCollide = false; part.Anchored = true end end
    ghost.Parent = Workspace
    gui:SetAttribute("PlacementActive", true)
end

upgradeButton.Activated:Connect(function()
    if gui:GetAttribute("RaidActive") == true then return end
    local ok, success, _, newLevel = pcall(function() return baseUpgradeRemote:InvokeServer() end)
    if ok and success then
        baseLevel = tonumber(newLevel) or baseLevel + 1
        updateBaseFrame()
    elseif ok and not success then
        if _G.PlaySound then _G.PlaySound("Error") end
        if _G.ShowNotif then _G.ShowNotif("Not enough money!", Color3.fromRGB(255, 35, 35)) end
    end
end)
scaleButton(upgradeButton)

baseDataRemote.OnClientEvent:Connect(function(data) if type(data) == "table" and data.level then baseLevel = data.level; updateBaseFrame() end end)
inventoryRemote.OnClientEvent:Connect(function(data)
    inventory = type(data) == "table" and data or {}
    local activeUnit = placingUnit
    updateBuildInventory()
    if activeUnit then
        if (tonumber(inventory[activeUnit]) or 0) > 0 then
            if not ghost then makeGhost(activeUnit) end
        else
            clearGhost()
        end
    end
end)
stockRemote.OnClientEvent:Connect(function(data) if type(data) == "table" then stock = data.stock or {}; nextReset = data.nextReset or 0; updateUnitCards() end end)
crateStockRemote.OnClientEvent:Connect(function(data) if type(data) == "table" then crateStock = data.stock or {}; crateNextReset = data.nextReset or 0; updateCrateCards() end end)
crateOpenedRemote.OnClientEvent:Connect(function(data) if type(data) == "table" and data.config then print("Opened crate:", data.config.DisplayName or data.sword) end end)
gui:GetAttributeChangedSignal("RaidActive"):Connect(function()
    updateBaseFrame()
    if gui:GetAttribute("RaidActive") == true then
        clearGhost()
        gui:SetAttribute("DeleteMode", false)
    end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    local attachment = prompt.Parent; local basePart = attachment and attachment.Parent; local plot = basePart and basePart.Parent
    if attachment and attachment:IsA("Attachment") and basePart and basePart.Name == "Base" and plot and plot.Parent and plot.Parent.Name == "Plots" and gui:GetAttribute("RaidActive") ~= true then openFrameRequest:Fire("Base") end
end)

RunService.RenderStepped:Connect(function()
    if placingUnit and not ghost then makeGhost(placingUnit) end
    if ghost then
        hideBox("Delete")
        local hit = plotHitPosition()
        if hit then
            local cf, boxCf, boxSize = placementCFrame(hit)
            if cf then
                local now = os.clock()
                if now - lastPlacementCheck >= 0.05 then
                    lastPlacementCheck = now
                    local wasOk = cachedPlacementClear
                    cachedPlacementClear = localPlacementClear(boxCf, boxSize) == true
                    -- only touch transparency when the state actually changed, not every frame
                    if cachedPlacementClear ~= wasOk then
                        local alpha = cachedPlacementClear and 0.45 or 0.7
                        for _, p in ipairs(ghost:GetDescendants()) do
                            if p:IsA("BasePart") then p.Transparency = alpha end
                        end
                    end
                end
                canPlaceHere = cachedPlacementClear
                lastSnapPosition = canPlaceHere and hit or nil
                local current = ghost:GetPivot()
                ghost:PivotTo(current:Lerp(cf, 0.35))
                showBox("Place", boxCf, boxSize, canPlaceHere and Color3.fromRGB(80, 255, 90) or Color3.fromRGB(255, 60, 60))
            end
        else
            canPlaceHere = false
            hideBox("Place")
            if cachedPlacementClear ~= false then
                cachedPlacementClear = false
                for _, p in ipairs(ghost:GetDescendants()) do
                    if p:IsA("BasePart") then p.Transparency = 1 end
                end
            end
            lastSnapPosition = nil
        end
    elseif gui:GetAttribute("DeleteMode") == true then
        hideBox("Place")
        hoveredDeleteModel = findPlacedUnitUnderMouse()
        if hoveredDeleteModel then
            local boxCf, boxSize = hoveredDeleteModel:GetBoundingBox()
            showBox("Delete", boxCf, boxSize, Color3.fromRGB(255, 55, 55))
        else
            hideBox("Delete")
        end
    else
        hoveredDeleteModel = nil
        hideBox("Place")
        hideBox("Delete")
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- when actively placing a unit or in delete mode, don't let a held tool's
    -- gameProcessed flag block the click — the tool eats the click but we still want it
    local isPlacementInput = input.UserInputType == Enum.UserInputType.MouseButton1
        or input.KeyCode == Enum.KeyCode.R
    local inActiveMode = placingUnit ~= nil or gui:GetAttribute("DeleteMode") == true
    if gameProcessed and not (isPlacementInput and inActiveMode) then return end
    if input.KeyCode == Enum.KeyCode.R and placingUnit then
        rotation = (rotation + 90) % 360
        if _G.PlaySound then _G.PlaySound("Swoosh") end
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        if placingUnit then
            local unitId = placingUnit
            local hit = plotHitPosition()
            -- only place if the cursor is actually over the island surface right now.
            -- lastSnapPosition is cleared when cursor leaves the island, so this
            -- prevents placing on stale/invisible ghost positions
            local pos = hit or lastSnapPosition
            if not pos or not canPlaceHere then return end
            local ok, success, message = pcall(function() return buildRemote:InvokeServer("Place", unitId, pos, rotation, lastHitPart, lastHitNormal) end)
            if DEBUG_PLACEMENT then
                print(string.format("[PlacementDebug][ClientResult] ok=%s success=%s message=%s", tostring(ok), tostring(success), tostring(message)))
            end
            if ok and success then
                if _G.PlaySound then _G.PlaySound("Place") end
                -- inventory is server-authoritative; UnitInventoryUpdate decides whether chaining continues
                lastSnapPosition = nil
                canPlaceHere = false
            end
        elseif gui:GetAttribute("DeleteMode") == true then
            local model = hoveredDeleteModel or findPlacedUnitUnderMouse()
            if model then
                local ok, success = pcall(function() return buildRemote:InvokeServer("Delete", model) end)
                if ok and success then
                    if _G.PlaySound then _G.PlaySound("Remove") end
                    hoveredDeleteModel = nil; hideBox("Delete")
                end
            end
        end
    end
end)

buildFrame:GetPropertyChangedSignal("Visible"):Connect(function()
    if not buildFrame.Visible then clearGhost() end
end)
task.spawn(function() while true do local remaining = math.max(0, nextReset - os.time()); unitsTimer.Text = string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60); local crateRemaining = math.max(0, crateNextReset - os.time()); if cratesTimer then cratesTimer.Text = string.format("%02d:%02d", math.floor(crateRemaining / 60), crateRemaining % 60) end; task.wait(1) end end)

unitsTemplate.Visible = false; cratesTemplate.Visible = false; buildTemplate.Visible = false
updateBuildInventory(); updateBaseFrame()

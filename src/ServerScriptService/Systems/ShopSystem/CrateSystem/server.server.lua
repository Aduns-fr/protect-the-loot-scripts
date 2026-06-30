local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local CratesConfig = require(ReplicatedStorage.Configs.CratesConfig)
local WeaponsConfig = require(ReplicatedStorage.Configs.WeaponsConfig)
local PlotService = require(ServerScriptService.Systems.PlotSystem.Modules.PlotService)
local PlayerDataService = require(ServerScriptService.Systems.DataSystem.Modules.PlayerDataService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stockRemote = remotes:WaitForChild("CrateStockUpdate")
local purchaseRemote = remotes:WaitForChild("CratePurchase")
local openedRemote = remotes:WaitForChild("CrateOpened")
local crateTemplates = ReplicatedStorage:WaitForChild("Crates")
local timerTemplate = ReplicatedStorage:WaitForChild("Timer")
local attachmentTemplate = ReplicatedStorage:WaitForChild("ChestAttachment")

local stock = {}
local nextReset = 0
local placed = {}
local openingPlayers = {}

local function appears(cfg, rng)
    return rng:NextNumber(0, 100) <= (CratesConfig.RarityWeights[cfg.Rarity or "Common"] or 50)
end

local function refreshStock()
    local bucket = math.floor(os.time() / CratesConfig.StockResetSeconds)
    local rng = Random.new(bucket + 555)
    nextReset = (bucket + 1) * CratesConfig.StockResetSeconds
    table.clear(stock)
    for _, crateId in ipairs(CratesConfig.Order) do
        local cfg = CratesConfig.Crates[crateId]
        stock[crateId] = cfg and appears(cfg, rng) and rng:NextInteger(cfg.StockMin or 1, cfg.StockMax or 1) or 0
    end
end

local function stockPayload()
    return { stock = table.clone(stock), nextReset = nextReset, resetSeconds = CratesConfig.StockResetSeconds }
end

local function broadcastStock()
    stockRemote:FireAllClients(stockPayload())
end

local function takeStock(crateId)
    if (stock[crateId] or 0) <= 0 then return false end
    stock[crateId] -= 1
    broadcastStock()
    return true
end

local function getSlots(plot)
    return plot and plot:FindFirstChild("CrateSlots")
end

local function getFreeSlot(plot, preferredName)
    local slots = getSlots(plot)
    if not slots then return nil end
    if preferredName then
        local preferred = slots:FindFirstChild(preferredName)
        if preferred and not preferred:GetAttribute("Occupied") then return preferred end
    end
    for i = 1, 3 do
        local slot = slots:FindFirstChild("Slot" .. i)
        if slot and not slot:GetAttribute("Occupied") then return slot end
    end
    return nil
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function getPrompt(model)
    return model and model:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function updateChestStatus(model)
    if not model or not model.Parent then return end
    local remaining = math.max(0, (tonumber(model:GetAttribute("ReadyAt")) or 0) - os.time())
    local ready = remaining <= 0
    local prompt = getPrompt(model)
    if prompt then
        prompt.Enabled = ready
        prompt.ActionText = ready and "Open" or "Unlocking"
        prompt.ObjectText = CratesConfig.Crates[model:GetAttribute("CrateId")] and CratesConfig.Crates[model:GetAttribute("CrateId")].DisplayName or "Chest"
    end
    local timer = model:FindFirstChild("Timer", true)
    local label = timer and timer:FindFirstChildWhichIsA("TextLabel", true)
    if label then label.Text = ready and "Ready!" or formatTime(remaining) end
end

local function configureVisuals(model, root, boxSize)
    local oldTimer = model:FindFirstChild("Timer", true)
    if oldTimer then oldTimer:Destroy() end
    local oldAttachment = model:FindFirstChild("ChestAttachment", true)
    if oldAttachment then oldAttachment:Destroy() end

    local timer = timerTemplate:Clone()
    timer.Name = "Timer"
    timer.Adornee = root
    timer.StudsOffsetWorldSpace = Vector3.new(0, boxSize.Y * 0.5 + 1.1, 0)
    timer.AlwaysOnTop = true
    timer.MaxDistance = 80
    timer.Parent = root

    local attachment = attachmentTemplate:Clone()
    attachment.Name = "ChestAttachment"
    attachment.CFrame = CFrame.new(0, math.min(boxSize.Y * 0.15, 0.75), 0)
    attachment.Parent = root
    local prompt = attachment:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        prompt.HoldDuration = 0.35
        prompt.MaxActivationDistance = 10
        prompt.RequiresLineOfSight = false
        prompt.KeyboardKeyCode = Enum.KeyCode.F
    end
end

local function recordFor(crateId, slotName, readyAt)
    return { CrateId = crateId, SlotName = slotName, ReadyAt = readyAt }
end

local function saveRecords(player)
    local records = {}
    local plot = PlotService.GetPlayerPlot(player)
    if plot then
        for _, child in ipairs(plot:GetChildren()) do
            if child:IsA("Model") and child:GetAttribute("PlacedChest") and child:GetAttribute("OwnerUserId") == player.UserId then
                table.insert(records, recordFor(child:GetAttribute("CrateId"), child:GetAttribute("SlotName"), child:GetAttribute("ReadyAt")))
            end
        end
    end
    table.sort(records, function(a, b) return tostring(a.SlotName) < tostring(b.SlotName) end)
    PlayerDataService.SetCrates(player, records, true)
end

local function placeChest(player, crateId, readyAt, preferredSlot, restoring)
    local cfg = CratesConfig.Crates[crateId]
    local plot = PlotService.GetPlayerPlot(player)
    local slot = getFreeSlot(plot, preferredSlot)
    local template = cfg and crateTemplates:FindFirstChild(cfg.ModelName or crateId)
    if not cfg or not plot or not slot or not template or not template:IsA("Model") then
        return false, not slot and "Max 3 chests" or "Chest unavailable"
    end

    local model = template:Clone()
    model.Name = "Chest_" .. slot.Name
    local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not root then model:Destroy(); return false, "Chest model is invalid" end
    model.PrimaryPart = root
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = true
            part.Massless = true
        end
    end

    model.Parent = plot
    local boxCf, boxSize = model:GetBoundingBox()
    local pivotToBox = model:GetPivot():ToObjectSpace(boxCf)
    local targetBox = slot.CFrame * CFrame.new(0, slot.Size.Y * 0.5 + boxSize.Y * 0.5 + 0.55, 0)
    local basePivot = targetBox * pivotToBox:Inverse()
    model:PivotTo(basePivot)
    model:SetAttribute("PlacedChest", true)
    model:SetAttribute("OwnerUserId", player.UserId)
    model:SetAttribute("CrateId", crateId)
    model:SetAttribute("SlotName", slot.Name)
    model:SetAttribute("ReadyAt", math.floor(tonumber(readyAt) or (os.time() + (cfg.OpenSeconds or 60))))
    model:SetAttribute("IdleBasePivot", basePivot)
    configureVisuals(model, root, boxSize)
    slot:SetAttribute("Occupied", true)
    placed[model] = slot
    updateChestStatus(model)
    if not restoring then saveRecords(player) end
    return true, model
end

local function waitForPlayerReady(player)
    local deadline = os.clock() + 15
    while player.Parent and os.clock() < deadline do
        if PlayerDataService.GetData(player) and PlotService.GetPlayerPlot(player) then return true end
        task.wait(0.2)
    end
    return false
end

local function restorePlayerChests(player)
    if not waitForPlayerReady(player) then return end
    local plot = PlotService.GetPlayerPlot(player)
    local slots = getSlots(plot)
    if not slots then return end
    for i = 1, 3 do
        local slot = slots:FindFirstChild("Slot" .. i)
        if slot then slot:SetAttribute("Occupied", false) end
    end
    for _, child in ipairs(plot:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("PlacedChest") then child:Destroy() end
    end
    local records = PlayerDataService.GetCrates(player)
    local valid = {}
    for _, record in ipairs(records) do
        if type(record) == "table" and CratesConfig.Crates[record.CrateId] then
            local ok = placeChest(player, record.CrateId, record.ReadyAt, record.SlotName, true)
            if ok then table.insert(valid, recordFor(record.CrateId, record.SlotName, record.ReadyAt)) end
        end
    end
    PlayerDataService.SetCrates(player, valid, false)
end

local function pickWeapon(crateId)
    local cfg = CratesConfig.Crates[crateId]
    if not cfg then return nil end
    local rng = Random.new()
    local roll = rng:NextNumber(0, 100)
    local sum = 0
    local rarity = "Common"
    for _, reward in ipairs(cfg.Rewards or {}) do
        sum += tonumber(reward.Chance) or 0
        if roll <= sum then rarity = reward.Rarity or rarity; break end
    end
    local pool = {}
    for weaponId, weapon in pairs(WeaponsConfig.Swords or {}) do
        if weapon.Rarity == rarity then table.insert(pool, weaponId) end
    end
    if #pool == 0 then for weaponId in pairs(WeaponsConfig.Swords or {}) do table.insert(pool, weaponId) end end
    table.sort(pool)
    return #pool > 0 and pool[rng:NextInteger(1, #pool)] or nil
end

local function buildRollPool(crateId)
    local cfg = CratesConfig.Crates[crateId]
    local pool = {}
    for weaponId, weapon in pairs(WeaponsConfig.Swords or {}) do
        local chance = 0
        for _, reward in ipairs(cfg.Rewards or {}) do if reward.Rarity == weapon.Rarity then chance = reward.Chance end end
        table.insert(pool, { id = weaponId, name = weapon.DisplayName or weaponId, rarity = weapon.Rarity or "Common", damage = weapon.Damage or 0, chance = chance, imageId = weapon.ImageId or "" })
    end
    table.sort(pool, function(a, b) return a.name < b.name end)
    return pool
end

purchaseRemote.OnServerInvoke = function(player, crateId, purchaseType)
    crateId = tostring(crateId or "")
    local cfg = CratesConfig.Crates[crateId]
    if not cfg then return false, "Bad chest" end
    if purchaseType == "Robux" then return false, "Use Robux prompt" end
    local plot = PlotService.GetPlayerPlot(player)
    if not getFreeSlot(plot) then return false, "Max 3 chests" end
    local leaderstats = player:FindFirstChild("leaderstats")
    local cash = leaderstats and leaderstats:FindFirstChild("Cash")
    local price = math.max(0, math.floor(tonumber(cfg.CashPrice) or 0))
    if not cash or cash.Value < price then return false, "Not enough cash" end
    if not takeStock(crateId) then return false, "Out of stock" end

    cash.Value -= price
    local data = PlayerDataService.GetData(player)
    if data then data.Cash = cash.Value end
    local ok, result = placeChest(player, crateId, os.time() + (cfg.OpenSeconds or 60), nil, false)
    if not ok then
        cash.Value += price
        if data then data.Cash = cash.Value end
        stock[crateId] = (stock[crateId] or 0) + 1
        broadcastStock()
        return false, result
    end
    return true, "Chest purchased"
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    local model = prompt:FindFirstAncestorOfClass("Model")
    if not model or not model:GetAttribute("PlacedChest") or model:GetAttribute("OwnerUserId") ~= player.UserId then return end
    if openingPlayers[player] or model:GetAttribute("Opening") then return end
    if os.time() < (tonumber(model:GetAttribute("ReadyAt")) or math.huge) then
        updateChestStatus(model)
        return
    end

    openingPlayers[player] = true
    model:SetAttribute("Opening", true)
    local crateId = model:GetAttribute("CrateId")
    local weaponId = pickWeapon(crateId)
    local weapon = weaponId and WeaponsConfig.Swords[weaponId]
    if not weapon then
        model:SetAttribute("Opening", false)
        openingPlayers[player] = nil
        return
    end

    local _, isNew = PlayerDataService.AddWeapon(player, weaponId)
    local slot = placed[model]
    if not slot then
        local plot = PlotService.GetPlayerPlot(player)
        local slots = getSlots(plot)
        slot = slots and slots:FindFirstChild(model:GetAttribute("SlotName") or "")
    end
    if slot then slot:SetAttribute("Occupied", false) end
    placed[model] = nil
    model:Destroy()
    saveRecords(player)

    openedRemote:FireClient(player, {
        crateId = crateId,
        weapon = weaponId,
        sword = weaponId,
        isNew = isNew,
        config = { DisplayName = weapon.DisplayName or weaponId, Damage = weapon.Damage or 0, Rarity = weapon.Rarity or "Common", ImageId = weapon.ImageId or "" },
        pool = buildRollPool(crateId),
    })
    task.delay(0.5, function() openingPlayers[player] = nil end)
end)

refreshStock()
task.spawn(function()
    while true do
        if os.time() >= nextReset then refreshStock(); broadcastStock() end
        for model in pairs(placed) do
            if model.Parent then updateChestStatus(model) else placed[model] = nil end
        end
        task.wait(1)
    end
end)

local function onPlayerAdded(player)
    task.spawn(restorePlayerChests, player)
    task.defer(function() stockRemote:FireClient(player, stockPayload()) end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player) openingPlayers[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
broadcastStock()

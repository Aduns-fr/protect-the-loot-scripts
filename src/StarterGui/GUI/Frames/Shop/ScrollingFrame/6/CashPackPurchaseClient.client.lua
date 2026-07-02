local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local container = script.Parent
local CashProductsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CashProductsConfig"))
local analyticsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MonetizationAnalytics")

local function fireAnalytics(action, payload)
	analyticsRemote:FireServer(action, payload)
end

local function maxDescendantZIndex(root)
	local zIndex = root:IsA("GuiObject") and root.ZIndex or 1
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			zIndex = math.max(zIndex, descendant.ZIndex)
		end
	end
	return zIndex
end

local function getPressTarget(slotFrame)
	if slotFrame:IsA("GuiButton") then
		return slotFrame
	end

	local existing = slotFrame:FindFirstChild("Click")
	if existing and existing:IsA("GuiButton") then
		return existing
	end

	local click = Instance.new("TextButton")
	click.Name = "Click"
	click.BackgroundTransparency = 1
	click.BorderSizePixel = 0
	click.Text = ""
	click.AutoButtonColor = false
	click.Active = true
	click.Selectable = true
	click.Size = UDim2.fromScale(1, 1)
	click.Position = UDim2.fromScale(0, 0)
	click.ZIndex = maxDescendantZIndex(slotFrame) + 20
	click.Parent = slotFrame
	return click
end

local function bindSlot(slot)
	local pack = CashProductsConfig.Packs[slot]
	if not pack or not pack.ProductId or pack.ProductId <= 0 then return end

	local slotFrame = container:FindFirstChild(slot)
	if not slotFrame or not slotFrame:IsA("GuiObject") then
		return
	end

	local target = getPressTarget(slotFrame)
	if target:GetAttribute("CashPackBound") then return end
	target:SetAttribute("CashPackBound", true)
	target.Activated:Connect(function()
		fireAnalytics("CashPackClicked", { sku = pack.Sku })
		MarketplaceService:PromptProductPurchase(player, pack.ProductId)
	end)
end

local function bindAll()
	for slot in pairs(CashProductsConfig.Packs) do
		bindSlot(slot)
	end
end

bindAll()
container.ChildAdded:Connect(function(child)
	if CashProductsConfig.Packs[child.Name] then
		task.defer(bindSlot, child.Name)
	end
end)

local shopFrame = container:FindFirstAncestor("Shop")
if shopFrame and shopFrame:IsA("GuiObject") then
	local wasVisible = shopFrame.Visible
	if wasVisible then
		task.defer(function()
			fireAnalytics("ShopOpened")
		end)
	end
	shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if shopFrame.Visible and not wasVisible then
			fireAnalytics("ShopOpened")
		end
		wasVisible = shopFrame.Visible
	end)
end

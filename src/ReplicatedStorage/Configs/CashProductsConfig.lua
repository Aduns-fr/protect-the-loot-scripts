local CashProductsConfig = {}

CashProductsConfig.CurrencyName = "Cash"

CashProductsConfig.Packs = {
	["1"] = {
		Sku = "Cash250K",
		DisplayName = "$250k Cash Pack",
		Amount = 250000,
		RobuxPrice = 99,
		ProductId = 3607612378,
	},
	["2"] = {
		Sku = "Cash500K",
		DisplayName = "$500k Cash Pack",
		Amount = 500000,
		RobuxPrice = 299,
		ProductId = 3607612815,
	},
	["3"] = {
		Sku = "Cash1M",
		DisplayName = "$1m Cash Pack",
		Amount = 1000000,
		RobuxPrice = 499,
		ProductId = 3607613035,
	},
	["4"] = {
		Sku = "Cash10M",
		DisplayName = "$10m Cash Pack",
		Amount = 10000000,
		RobuxPrice = 1999,
		ProductId = 3607613050,
	},
}

local byProductId = {}
local bySku = {}
for slot, pack in pairs(CashProductsConfig.Packs) do
	pack.Slot = slot
	byProductId[pack.ProductId] = pack
	bySku[pack.Sku] = pack
end

function CashProductsConfig.GetByProductId(productId)
	return byProductId[tonumber(productId)]
end

function CashProductsConfig.GetBySku(sku)
	return bySku[tostring(sku or "")]
end

return CashProductsConfig

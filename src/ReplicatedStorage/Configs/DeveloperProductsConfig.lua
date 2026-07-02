local DeveloperProductsConfig = {}

DeveloperProductsConfig.StockRefresh = {
	ProductId = 3607645876,
	DisplayName = "Refresh Shop Stock",
	RobuxPrice = 49,
}

DeveloperProductsConfig.ChestSkip = {
	ProductId = 3607680179,
	DisplayName = "Skip Chest Wait",
	RobuxPrice = 49,
}

DeveloperProductsConfig.DailyRewardSkip = {
	ProductId = 3607689823,
	DisplayName = "Claim Next Daily Reward",
	RobuxPrice = 49,
}

DeveloperProductsConfig.Bundles = {
	StarterPack = {
		ProductId = 3607645963,
		DisplayName = "Starter Pack",
		RobuxPrice = 99,
		Cash = 100000,
		UnitId = "RapidBlock",
		WeaponId = "CrookedCutlass",
	},
	StarterPack2 = {
		ProductId = 3607645980,
		DisplayName = "Starter Pack 2",
		RobuxPrice = 199,
		Cash = 250000,
		UnitId = "HeavyBlock",
		WeaponId = "LaserRapier",
	},
	Bundle1 = {
		ProductId = 3607645998,
		DisplayName = "Bundle 1",
		RobuxPrice = 499,
		Cash = 750000,
		UnitId = "FrostBlock",
		WeaponId = "Frostbrand",
	},
	Bundle2 = {
		ProductId = 3607646109,
		DisplayName = "Bundle 2",
		RobuxPrice = 999,
		Cash = 1500000,
		UnitId = "VoidBlock",
		WeaponId = "DoomKatana",
	},
}

DeveloperProductsConfig.BundleOrder = {
	"StarterPack",
	"StarterPack2",
	"Bundle1",
	"Bundle2",
}

DeveloperProductsConfig.ReviveTiers = {
	{ ProductId = 3607646198, RobuxPrice = 29 },
	{ ProductId = 3607646265, RobuxPrice = 49 },
	{ ProductId = 3607646278, RobuxPrice = 79 },
	{ ProductId = 3607646299, RobuxPrice = 129 },
	{ ProductId = 3607646314, RobuxPrice = 199 },
}

DeveloperProductsConfig.Gifts = {
	GiftVIP = {
		ProductId = 3607680188,
		DisplayName = "V.I.P Member",
		RobuxPrice = 399,
		RewardType = "GamePass",
		RewardKey = "VIP",
	},
	GiftDoubleCash = {
		ProductId = 3607680199,
		DisplayName = "x2 Cash",
		RobuxPrice = 399,
		RewardType = "GamePass",
		RewardKey = "DoubleCash",
	},
	GiftTripleSpeed = {
		ProductId = 3607680214,
		DisplayName = "x3 Raid Speed",
		RobuxPrice = 149,
		RewardType = "GamePass",
		RewardKey = "TripleSpeed",
	},
	GiftCash250K = {
		ProductId = 3607680229,
		DisplayName = "$250k Cash Pack",
		RobuxPrice = 99,
		RewardType = "CashPack",
		RewardKey = "Cash250K",
	},
	GiftCash500K = {
		ProductId = 3607680240,
		DisplayName = "$500k Cash Pack",
		RobuxPrice = 299,
		RewardType = "CashPack",
		RewardKey = "Cash500K",
	},
	GiftCash1M = {
		ProductId = 3607680251,
		DisplayName = "$1m Cash Pack",
		RobuxPrice = 499,
		RewardType = "CashPack",
		RewardKey = "Cash1M",
	},
	GiftCash10M = {
		ProductId = 3607680260,
		DisplayName = "$10m Cash Pack",
		RobuxPrice = 1999,
		RewardType = "CashPack",
		RewardKey = "Cash10M",
	},
	GiftStarterPack = {
		ProductId = 3607680272,
		DisplayName = "Starter Pack",
		RobuxPrice = 99,
		RewardType = "Bundle",
		RewardKey = "StarterPack",
	},
	GiftStarterPack2 = {
		ProductId = 3607680281,
		DisplayName = "Starter Pack 2",
		RobuxPrice = 199,
		RewardType = "Bundle",
		RewardKey = "StarterPack2",
	},
	GiftBundle1 = {
		ProductId = 3607680299,
		DisplayName = "Bundle 1",
		RobuxPrice = 499,
		RewardType = "Bundle",
		RewardKey = "Bundle1",
	},
	GiftBundle2 = {
		ProductId = 3607680307,
		DisplayName = "Bundle 2",
		RobuxPrice = 999,
		RewardType = "Bundle",
		RewardKey = "Bundle2",
	},
}

DeveloperProductsConfig.GiftOrder = {
	"GiftVIP",
	"GiftDoubleCash",
	"GiftTripleSpeed",
	"GiftCash250K",
	"GiftCash500K",
	"GiftCash1M",
	"GiftCash10M",
	"GiftStarterPack",
	"GiftStarterPack2",
	"GiftBundle1",
	"GiftBundle2",
}

local byProductId = {}

local function register(productType, key, config)
	local productId = tonumber(config.ProductId) or 0
	if productId > 0 then
		byProductId[productId] = {
			Type = productType,
			Key = key,
			Config = config,
		}
	end
end

function DeveloperProductsConfig.RebuildIndex()
	table.clear(byProductId)
	register("StockRefresh", "StockRefresh", DeveloperProductsConfig.StockRefresh)
	register("ChestSkip", "ChestSkip", DeveloperProductsConfig.ChestSkip)
	register("DailyRewardSkip", "DailyRewardSkip", DeveloperProductsConfig.DailyRewardSkip)
	for key, config in pairs(DeveloperProductsConfig.Bundles) do
		register("Bundle", key, config)
	end
	for index, config in ipairs(DeveloperProductsConfig.ReviveTiers) do
		register("Revive", index, config)
	end
	for key, config in pairs(DeveloperProductsConfig.Gifts) do
		register("Gift", key, config)
	end
end

function DeveloperProductsConfig.GetByProductId(productId)
	if next(byProductId) == nil then
		DeveloperProductsConfig.RebuildIndex()
	end
	return byProductId[tonumber(productId) or 0]
end

DeveloperProductsConfig.RebuildIndex()

return DeveloperProductsConfig

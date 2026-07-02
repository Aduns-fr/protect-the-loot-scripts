-- 33 swords total, all from the finished sword pack (tools in ReplicatedStorage.Swords).
-- 1 starter + 20 crate swords (4 per crate, per-crate odds) + 9 special (server-verified
-- sources) + 3 daily-chest exclusives. Wooden Sword is outside every roll pool.
local SwordsConfig = {}

SwordsConfig.DefaultSword = "WoodenSword"
SwordsConfig.SlashAnimationId = "rbxassetid://139916702931926"

-- Source: Starter | Crate | VIP | Pack | Group | Invite | Playtime | Premium | DailyChest
local function S(name, damage, rarity, source, sourceLabel)
	return { DisplayName = name, Damage = damage, Rarity = rarity, Source = source, SourceLabel = sourceLabel }
end

SwordsConfig.Swords = {
	-- starter
	WoodenSword = S("Wooden Sword", 35, "Common", "Starter", "Starter sword"),

	-- Junk Crate
	IronSword = S("Iron Sword", 45, "Common", "Crate", "Junk Crate"),
	ThickBlade = S("Thick Blade", 60, "Common", "Crate", "Junk Crate"),
	GladiusSword = S("Gladius Sword", 80, "Uncommon", "Crate", "Junk Crate"),
	BoneBreaker = S("Bone Breaker", 110, "Rare", "Crate", "Junk Crate"),

	-- Slime Crate
	TheDevineBlade = S("The De-vine Blade", 95, "Common", "Crate", "Slime Crate"),
	PoisonTouch = S("Poison Touch", 125, "Uncommon", "Crate", "Slime Crate"),
	DuneBlade = S("Dune Blade", 155, "Uncommon", "Crate", "Slime Crate"),
	ToxicAbyss = S("Toxic Abyss", 200, "Rare", "Crate", "Slime Crate"),

	-- Laser Crate
	ModernCombatBlade = S("Modern Combat Blade", 180, "Uncommon", "Crate", "Laser Crate"),
	SwordoftheFuture = S("Sword of the Future", 235, "Uncommon", "Crate", "Laser Crate"),
	UraniumFusionBlade = S("Uranium Fusion Blade", 300, "Rare", "Crate", "Laser Crate"),
	BladeofFire = S("Blade of Fire", 380, "Epic", "Crate", "Laser Crate"),

	-- Doom Crate
	ButchersFury = S("Butcher's Fury", 350, "Rare", "Crate", "Doom Crate"),
	SwordoftheCursed = S("Sword of the Cursed", 460, "Rare", "Crate", "Doom Crate"),
	DemonSlayer = S("Demon Slayer", 600, "Epic", "Crate", "Doom Crate"),
	DevilsWrath = S("Devils Wrath", 780, "Legendary", "Crate", "Doom Crate"),

	-- Void Crate
	MidnightBlade = S("Midnight Blade", 700, "Rare", "Crate", "Void Crate"),
	MoonBlade = S("Moon Blade", 900, "Epic", "Crate", "Void Crate"),
	ShatteredRealmSword = S("Shattered Realm Sword", 1150, "Epic", "Crate", "Void Crate"),
	InfinityBlade = S("Infinity Blade", 1500, "Legendary", "Crate", "Void Crate"),

	-- special (strong sidegrades, never in crates)
	TheGoldenTouch = S("The Golden Touch", 1050, "Legendary", "VIP", "VIP gamepass"),
	HarpeBlade = S("Harpe Blade", 140, "Uncommon", "Pack", "Starter Pack"),
	OceansBlessing = S("Ocean's Blessing", 260, "Rare", "Pack", "Starter Pack 2"),
	BlizzardIce = S("Blizzard Ice", 650, "Epic", "Pack", "Bundle 1"),
	ChaosBlade = S("Chaos Blade", 1150, "Legendary", "Pack", "Bundle 2"),
	TheEmeraldOrder = S("The Emerald Order", 180, "Rare", "Group", "Join the group"),
	BladeofSpirits = S("Blade of Spirits", 260, "Rare", "Invite", "Play with a friend"),
	TheTitan = S("The Titan", 1050, "Epic", "Playtime", "Play for 4 hours"),
	SkywardSword = S("Skyward Sword", 720, "Epic", "Premium", "Roblox Premium"),

	-- daily chest exclusives (rare roulette outcomes only)
	AquaStoneSword = S("Aqua Stone Sword", 900, "Epic", "DailyChest", "Daily Chest (5%)"),
	TheExcorcist = S("The Excorcist", 1350, "Legendary", "DailyChest", "Daily Chest (1.5%)"),
	BladeofLight = S("Blade of Light", 1800, "Legendary", "DailyChest", "Daily Chest (0.35%)"),
}

-- fixed per-crate pools; odds get more generous toward top swords in higher crates
SwordsConfig.CratePools = {
	JunkCrate = {
		{ Id = "IronSword", Chance = 55 },
		{ Id = "ThickBlade", Chance = 28 },
		{ Id = "GladiusSword", Chance = 13 },
		{ Id = "BoneBreaker", Chance = 4 },
	},
	SlimeCrate = {
		{ Id = "TheDevineBlade", Chance = 52 },
		{ Id = "PoisonTouch", Chance = 28 },
		{ Id = "DuneBlade", Chance = 14 },
		{ Id = "ToxicAbyss", Chance = 6 },
	},
	LaserCrate = {
		{ Id = "ModernCombatBlade", Chance = 50 },
		{ Id = "SwordoftheFuture", Chance = 28 },
		{ Id = "UraniumFusionBlade", Chance = 15 },
		{ Id = "BladeofFire", Chance = 7 },
	},
	DoomCrate = {
		{ Id = "ButchersFury", Chance = 48 },
		{ Id = "SwordoftheCursed", Chance = 28 },
		{ Id = "DemonSlayer", Chance = 16 },
		{ Id = "DevilsWrath", Chance = 8 },
	},
	VoidCrate = {
		{ Id = "MidnightBlade", Chance = 45 },
		{ Id = "MoonBlade", Chance = 28 },
		{ Id = "ShatteredRealmSword", Chance = 17 },
		{ Id = "InfinityBlade", Chance = 10 },
	},
}

-- daily chest roulette: chance is % of the ENTIRE daily roll
SwordsConfig.DailyChestSwords = {
	{ Id = "AquaStoneSword", Chance = 5 },
	{ Id = "TheExcorcist", Chance = 1.5 },
	{ Id = "BladeofLight", Chance = 0.35 },
}

-- duplicate crate/daily sword -> cash compensation by rarity
SwordsConfig.DuplicateCash = {
	Common = 12000, Uncommon = 28000, Rare = 70000, Epic = 180000, Legendary = 450000,
}

SwordsConfig.RarityWeights = { Common = 70, Uncommon = 25, Rare = 4, Legendary = 1 } -- legacy, unused by new rolls

SwordsConfig.Order = {}
for id in pairs(SwordsConfig.Swords) do
	table.insert(SwordsConfig.Order, id)
end
table.sort(SwordsConfig.Order)

return SwordsConfig

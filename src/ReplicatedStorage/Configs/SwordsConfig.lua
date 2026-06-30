local SwordsConfig = {}

SwordsConfig.DefaultSword = "WoodenSword"
SwordsConfig.SlashAnimationId = "rbxassetid://121547878286765"
SwordsConfig.RarityWeights = { Common = 70, Uncommon = 25, Rare = 4, Legendary = 1 }

SwordsConfig.Swords = {}

-- wooden sword is the starter, everyone gets this by default
SwordsConfig.Swords["WoodenSword"] = {
	DisplayName = "Wooden Sword",
	Rarity = "Common",
	Damage = 10,
}

-- all the rollable swords from crates
local names = {
	"Rusty Fang","Slime Sabre","Bone Cutter","Scrap Katana","Crooked Cutlass","Villain Poker","Spiked Ruler","Tin Longsword","Toxic Shiv","Junkyard Blade",
	"Laser Rapier","Goo Greatsword","Bat Bite","Electric Edge","Shadow Sticker","Buzzsaw Sword","Acid Saber","Moonlit Machete","Gold Scimitar","Rocket Claymore",
	"Frostbrand","Meteor Edge","Venom Viper","Void Carver","Royal Doomblade","Plasma Cleaver","Nightmare Needle","Dragon Debt","Thunder Chopper","Hero Bonker",
	"Volcano Splitter","Galaxy Gouger","Sunset Slayer","Phantom Falchion","Crystal Crime","Doom Katana","Reality Razor","Moonbase Monarch","Black Hole Blade","Evilest Excalibur"
}
local rarities = {
	"Common","Common","Common","Common","Common","Common","Common","Common","Common","Common",
	"Uncommon","Uncommon","Uncommon","Uncommon","Uncommon","Uncommon","Uncommon","Uncommon","Uncommon","Uncommon",
	"Rare","Rare","Rare","Rare","Rare","Rare","Rare","Rare","Rare","Rare",
	"Legendary","Legendary","Legendary","Legendary","Legendary","Legendary","Legendary","Legendary","Legendary","Legendary"
}

for i, name in ipairs(names) do
	local id = name:gsub("%W", "")
	local rarity = rarities[i]
	local dmgMult = rarity == "Legendary" and 5 or rarity == "Rare" and 3 or rarity == "Uncommon" and 2 or 1
	SwordsConfig.Swords[id] = {
		DisplayName = name,
		Rarity = rarity,
		Damage = 10 + i * dmgMult,
	}
end

SwordsConfig.Order = {}
for id in pairs(SwordsConfig.Swords) do
	table.insert(SwordsConfig.Order, id)
end
table.sort(SwordsConfig.Order)

return SwordsConfig

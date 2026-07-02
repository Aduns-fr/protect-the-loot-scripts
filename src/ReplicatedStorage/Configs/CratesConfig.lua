local CratesConfig = {}

CratesConfig.StockResetSeconds = 300
CratesConfig.RarityWeights = { Common = 100, Uncommon = 60, Rare = 25, Epic = 10, Legendary = 4 }
CratesConfig.Crates = {
    JunkCrate = { DisplayName = "Junk Crate", ModelName = "JunkCrate", Rarity = "Common", CashPrice = 450, RobuxProductId = 3607619274, RobuxPrice = 19, StockMin = 3, StockMax = 7, OpenSeconds = 60, Color = Color3.fromRGB(120, 95, 70), Rewards = { {Rarity="Common",Chance=70}, {Rarity="Uncommon",Chance=25}, {Rarity="Rare",Chance=4}, {Rarity="Legendary",Chance=1} } },
    SlimeCrate = { DisplayName = "Slime Crate", ModelName = "SlimeCrate", Rarity = "Uncommon", CashPrice = 1100, RobuxProductId = 3607619607, RobuxPrice = 39, StockMin = 2, StockMax = 5, OpenSeconds = 180, Color = Color3.fromRGB(80, 220, 100), Rewards = { {Rarity="Common",Chance=55}, {Rarity="Uncommon",Chance=32}, {Rarity="Rare",Chance=10}, {Rarity="Legendary",Chance=3} } },
    LaserCrate = { DisplayName = "Laser Crate", ModelName = "LaserCrate", Rarity = "Rare", CashPrice = 2600, RobuxProductId = 3607619866, RobuxPrice = 69, StockMin = 1, StockMax = 3, OpenSeconds = 600, Color = Color3.fromRGB(255, 75, 75), Rewards = { {Rarity="Common",Chance=35}, {Rarity="Uncommon",Chance=40}, {Rarity="Rare",Chance=20}, {Rarity="Legendary",Chance=5} } },
    DoomCrate = { DisplayName = "Doom Crate", ModelName = "DoomCrate", Rarity = "Epic", CashPrice = 6200, RobuxProductId = 3607620107, RobuxPrice = 119, StockMin = 1, StockMax = 2, OpenSeconds = 1800, Color = Color3.fromRGB(105, 65, 180), Rewards = { {Rarity="Common",Chance=20}, {Rarity="Uncommon",Chance=35}, {Rarity="Rare",Chance=35}, {Rarity="Legendary",Chance=10} } },
    VoidCrate = { DisplayName = "Void Crate", ModelName = "VoidCrate", Rarity = "Legendary", CashPrice = 15000, RobuxProductId = 3607620351, RobuxPrice = 199, StockMin = 1, StockMax = 1, OpenSeconds = 3600, Color = Color3.fromRGB(25, 25, 35), Rewards = { {Rarity="Common",Chance=10}, {Rarity="Uncommon",Chance=25}, {Rarity="Rare",Chance=45}, {Rarity="Legendary",Chance=20} } },
}
CratesConfig.Order = {"JunkCrate","SlimeCrate","LaserCrate","DoomCrate","VoidCrate"}
return CratesConfig

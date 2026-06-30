local HeroesConfig = {}

HeroesConfig.Default = {
    MaxHealth = 100,
    WalkSpeed = 12,
    CoreDamage = 10,
    CashReward = 8,
}

HeroesConfig.Boss = {
    MaxHealth = 10000,
    WalkSpeed = 9,
    CoreDamage = 120,
    CashReward = 500,
}

HeroesConfig.Waves = {
    MaxWave = 100,
    BaseHeroCount = 5,
    SpawnInterval = 0.45,
    BetweenWaves = 1.5,
}

return HeroesConfig

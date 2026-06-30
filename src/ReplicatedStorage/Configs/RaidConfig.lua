local RaidConfig = {}

RaidConfig.MaxWave = math.huge

-- global walk speed — individual mobs can override with their Speed field
RaidConfig.MobWalkSpeed = 11

RaidConfig.Performance = {
    MaxActiveMobsPerPlayer = 18,
    HpUpdateInterval = 0.15,
    UseWalkAnimations = false,
}

-- Wave scaling knobs:
-- HealthExpo only (no linear term) keeps scaling smooth and predictable.
-- 1.048 per wave: wave 10 = 1.58x, wave 25 = 3.2x, wave 50 = 10.4x, wave 100 = 107x
-- That means a wave-100 Chicken Egg has ~5,900 HP — hard but killable with late units.
-- CashWaveBonus scales rewards up so late-game waves are worth grinding.
RaidConfig.Waves = {
    BossEvery        = 10,
    BaseCount        = 5,    -- wave 1 starts small so new players aren't overwhelmed
    AddEvery         = 3,    -- adds mobs more frequently for a smoother ramp
    AddAmount        = 2,
    MaxRegularCount  = 30,   -- cap so late waves don't take forever
    HealthLinear     = 0,    -- dropped: expo alone is smoother
    HealthExpo       = 1.048,
    CashWaveBonus    = 0.055, -- rewards scale faster than health so players can keep up
}

-- all 50 eggs ordered by unlock wave
RaidConfig.MobOrder = {
    "Egg_Chicken", "Egg_Rabbit", "Egg_Pig", "Egg_Sheep", "Egg_Duck",
    "Egg_Frog", "Egg_Cow", "Egg_Goat", "Egg_Cat", "Egg_Worm",
    "Egg_Bee", "Egg_Ant", "Egg_Ladybug", "Egg_Butterfly", "Egg_Crab",
    "Egg_Fish", "Egg_Turtle", "Egg_Penguin", "Egg_Panda", "Egg_Fox",
    "Egg_Wolf", "Egg_Horse", "Egg_Lion", "Egg_Shark", "Egg_Capybara",
    "Egg_Axolotl", "Egg_Beetle", "Egg_Scorpion", "Egg_Slime", "Egg_Rock",
    "Egg_Sand", "Egg_Cactus", "Egg_Ice", "Egg_Snow", "Egg_Yeti",
    "Egg_Ash", "Egg_Lava", "Egg_Oasis", "Egg_Crystal", "Egg_Mummy",
    "Egg_Knight", "Egg_Royal", "Egg_Treasure", "Egg_Wizard", "Egg_Dragon",
    "Egg_Phoenix", "Egg_Unicorn", "Egg_Meteor", "Egg_Void", "Egg_Obsidian",
}

RaidConfig.BossOrder = {
    "Boss1", "Boss2", "Boss3", "Boss4", "Boss5",
    "Boss6", "Boss7", "Boss8", "Boss9", "Boss10",
}

-- Mob base stats (before wave multiplier is applied).
-- Philosophy:
--   Waves 1-10  : tutorial zone — eggs die fast, cash is generous, player learns placement
--   Waves 11-30 : early game — new egg types appear every few waves, moderate pressure
--   Waves 31-55 : mid game — noticeable HP and damage jump, need diverse towers
--   Waves 56-80 : late game — survivability becomes a real concern, rewards ramp hard
--   Waves 81-100: endgame — only strong builds survive, cash rewards are massive
--
-- CashReward is per-egg BEFORE the CashWaveBonus multiplier.
-- CoreDamage is how much base HP the egg deals to your base if it reaches the end.
-- Weight controls spawn frequency (higher = appears more often in the pool).
RaidConfig.MobStats = {

    -- Waves 1-2: baby animals, basically punching bags — cash bumped so player can
    -- afford their first unit after wave 1
    Egg_Chicken   = { Template = "Chicken Egg",   MaxHealth = 55,    CoreDamage = 3,    CashReward = 14,   Weight = 130, UnlockWave = 1  },
    Egg_Rabbit    = { Template = "Rabbit Egg",    MaxHealth = 45,    CoreDamage = 3,    CashReward = 12,   Weight = 120, UnlockWave = 1,  Speed = 12 },
    Egg_Pig       = { Template = "Pig Egg",       MaxHealth = 90,    CoreDamage = 5,    CashReward = 18,   Weight = 100, UnlockWave = 2  },
    Egg_Sheep     = { Template = "Sheep Egg",     MaxHealth = 80,    CoreDamage = 4,    CashReward = 16,   Weight = 100, UnlockWave = 2  },
    Egg_Duck      = { Template = "Duck Egg",      MaxHealth = 60,    CoreDamage = 4,    CashReward = 15,   Weight = 110, UnlockWave = 2,  Speed = 12 },

    -- Waves 3-8: slightly tankier, still comfortable
    Egg_Frog      = { Template = "Frog Egg",      MaxHealth = 120,   CoreDamage = 6,    CashReward = 22,   Weight = 90,  UnlockWave = 3  },
    Egg_Cow       = { Template = "Cow Egg",       MaxHealth = 160,   CoreDamage = 8,    CashReward = 26,   Weight = 85,  UnlockWave = 4  },
    Egg_Goat      = { Template = "Goat Egg",      MaxHealth = 140,   CoreDamage = 7,    CashReward = 24,   Weight = 85,  UnlockWave = 5  },
    Egg_Cat       = { Template = "Cat Egg",       MaxHealth = 115,   CoreDamage = 6,    CashReward = 22,   Weight = 88,  UnlockWave = 5,  Speed = 13 },
    Egg_Worm      = { Template = "Worm Egg",      MaxHealth = 90,    CoreDamage = 5,    CashReward = 16,   Weight = 95,  UnlockWave = 3,  Speed = 13.5 },

    -- Waves 9-15: first real pressure — health and damage step up noticeably
    Egg_Bee       = { Template = "Bee Egg",       MaxHealth = 160,   CoreDamage = 8,    CashReward = 28,   Weight = 78,  UnlockWave = 9,  Speed = 14 },
    Egg_Ant       = { Template = "Ant Egg",       MaxHealth = 140,   CoreDamage = 7,    CashReward = 24,   Weight = 80,  UnlockWave = 9  },
    Egg_Ladybug   = { Template = "Ladybug Egg",   MaxHealth = 120,   CoreDamage = 6,    CashReward = 22,   Weight = 82,  UnlockWave = 11 },
    Egg_Butterfly = { Template = "Butterfly Egg", MaxHealth = 110,   CoreDamage = 6,    CashReward = 20,   Weight = 80,  UnlockWave = 11, Speed = 14.5 },
    Egg_Crab      = { Template = "Crab Egg",      MaxHealth = 210,   CoreDamage = 10,   CashReward = 32,   Weight = 68,  UnlockWave = 13 },

    -- Waves 16-24: mid-early, player should have 2-3 unit types by now
    Egg_Fish      = { Template = "Fish Egg",      MaxHealth = 190,   CoreDamage = 9,    CashReward = 30,   Weight = 70,  UnlockWave = 16, Speed = 13.5 },
    Egg_Turtle    = { Template = "Turtle Egg",    MaxHealth = 310,   CoreDamage = 13,   CashReward = 40,   Weight = 58,  UnlockWave = 17 },
    Egg_Penguin   = { Template = "Penguin Egg",   MaxHealth = 240,   CoreDamage = 11,   CashReward = 36,   Weight = 65,  UnlockWave = 18 },
    Egg_Panda     = { Template = "Panda Egg",     MaxHealth = 270,   CoreDamage = 12,   CashReward = 38,   Weight = 60,  UnlockWave = 19 },
    Egg_Fox       = { Template = "Fox Egg",       MaxHealth = 220,   CoreDamage = 10,   CashReward = 34,   Weight = 66,  UnlockWave = 20, Speed = 14 },

    -- Waves 25-35: things start requiring actual strategy
    Egg_Wolf      = { Template = "Wolf Egg",      MaxHealth = 360,   CoreDamage = 16,   CashReward = 50,   Weight = 52,  UnlockWave = 25 },
    Egg_Horse     = { Template = "Horse Egg",     MaxHealth = 400,   CoreDamage = 17,   CashReward = 55,   Weight = 50,  UnlockWave = 27, Speed = 14 },
    Egg_Lion      = { Template = "Lion Egg",      MaxHealth = 450,   CoreDamage = 19,   CashReward = 62,   Weight = 46,  UnlockWave = 29 },
    Egg_Shark     = { Template = "Shark Egg",     MaxHealth = 500,   CoreDamage = 21,   CashReward = 68,   Weight = 44,  UnlockWave = 31 },
    Egg_Capybara  = { Template = "Capybara Egg",  MaxHealth = 330,   CoreDamage = 14,   CashReward = 46,   Weight = 54,  UnlockWave = 26 },

    -- Waves 36-47: mid game proper — noticeably chunky, fast variants are dangerous
    Egg_Axolotl   = { Template = "Axolotl Egg",   MaxHealth = 550,   CoreDamage = 22,   CashReward = 76,   Weight = 40,  UnlockWave = 36 },
    Egg_Beetle    = { Template = "Beetle Egg",    MaxHealth = 600,   CoreDamage = 24,   CashReward = 84,   Weight = 38,  UnlockWave = 38 },
    Egg_Scorpion  = { Template = "Scorpion Egg",  MaxHealth = 660,   CoreDamage = 26,   CashReward = 92,   Weight = 35,  UnlockWave = 40 },
    Egg_Slime     = { Template = "Slime Egg",     MaxHealth = 580,   CoreDamage = 23,   CashReward = 80,   Weight = 37,  UnlockWave = 37 },
    Egg_Rock      = { Template = "Rock Egg",      MaxHealth = 820,   CoreDamage = 30,   CashReward = 108,  Weight = 30,  UnlockWave = 43 },

    -- Waves 48-60: late-mid, base damage getting meaningful, need HP upgrades
    Egg_Sand      = { Template = "Sand Egg",      MaxHealth = 740,   CoreDamage = 28,   CashReward = 100,  Weight = 32,  UnlockWave = 48 },
    Egg_Cactus    = { Template = "Cactus Egg",    MaxHealth = 800,   CoreDamage = 29,   CashReward = 108,  Weight = 30,  UnlockWave = 50 },
    Egg_Ice       = { Template = "Ice Egg",       MaxHealth = 880,   CoreDamage = 31,   CashReward = 118,  Weight = 27,  UnlockWave = 52 },
    Egg_Snow      = { Template = "Snow Egg",      MaxHealth = 950,   CoreDamage = 33,   CashReward = 128,  Weight = 26,  UnlockWave = 54 },
    Egg_Yeti      = { Template = "Yeti Egg",      MaxHealth = 1100,  CoreDamage = 37,   CashReward = 145,  Weight = 24,  UnlockWave = 57, Speed = 10 },

    -- Waves 61-74: late game, only well-placed diverse builds survive
    Egg_Ash       = { Template = "Ash Egg",       MaxHealth = 1250,  CoreDamage = 41,   CashReward = 165,  Weight = 22,  UnlockWave = 61 },
    Egg_Lava      = { Template = "Lava Egg",      MaxHealth = 1400,  CoreDamage = 45,   CashReward = 185,  Weight = 20,  UnlockWave = 64 },
    Egg_Oasis     = { Template = "Oasis Egg",     MaxHealth = 1180,  CoreDamage = 39,   CashReward = 158,  Weight = 21,  UnlockWave = 62 },
    Egg_Crystal   = { Template = "Crystal Egg",   MaxHealth = 1550,  CoreDamage = 50,   CashReward = 210,  Weight = 18,  UnlockWave = 67 },
    Egg_Mummy     = { Template = "Mummy Egg",     MaxHealth = 1750,  CoreDamage = 56,   CashReward = 235,  Weight = 16,  UnlockWave = 70 },

    -- Waves 75-88: endgame approach — rewards get juicy to keep players engaged
    Egg_Knight    = { Template = "Knight Egg",    MaxHealth = 2000,  CoreDamage = 62,   CashReward = 270,  Weight = 14,  UnlockWave = 75 },
    Egg_Royal     = { Template = "Royal Egg",     MaxHealth = 2300,  CoreDamage = 70,   CashReward = 310,  Weight = 12,  UnlockWave = 78 },
    Egg_Treasure  = { Template = "Treasure Egg",  MaxHealth = 2150,  CoreDamage = 66,   CashReward = 290,  Weight = 13,  UnlockWave = 76 },
    Egg_Wizard    = { Template = "Wizard Egg",    MaxHealth = 2550,  CoreDamage = 76,   CashReward = 340,  Weight = 11,  UnlockWave = 81, Speed = 12.5 },
    Egg_Dragon    = { Template = "Dragon Egg",    MaxHealth = 2900,  CoreDamage = 84,   CashReward = 390,  Weight = 9,   UnlockWave = 84 },

    -- Waves 89-100: endgame — you need everything maxed to survive this
    Egg_Phoenix   = { Template = "Phoenix Egg",   MaxHealth = 3400,  CoreDamage = 95,   CashReward = 460,  Weight = 8,   UnlockWave = 89, Speed = 13.5 },
    Egg_Unicorn   = { Template = "Unicorn Egg",   MaxHealth = 3200,  CoreDamage = 90,   CashReward = 440,  Weight = 8,   UnlockWave = 89 },
    Egg_Meteor    = { Template = "Meteor Egg",    MaxHealth = 4000,  CoreDamage = 108,  CashReward = 540,  Weight = 7,   UnlockWave = 93 },
    Egg_Void      = { Template = "Void Egg",      MaxHealth = 5000,  CoreDamage = 130,  CashReward = 640,  Weight = 6,   UnlockWave = 96, Speed = 10 },
    Egg_Obsidian  = { Template = "Obsidian Egg",  MaxHealth = 6500,  CoreDamage = 158,  CashReward = 780,  Weight = 5,   UnlockWave = 99 },

    -- Bosses: each one is a single-HP tank that needs your whole build to burst down.
    -- HP scales ~2.3x per boss tier. Cash reward is worth about 3-4 waves of grinding.
    -- CoreDamage is high because a boss reaching your base is basically game over.
    Boss1  = { Template = "Part", MaxHealth = 3500,    CoreDamage = 80,    CashReward = 320,   Scale = 1.45, BossWave = 10  },
    Boss2  = { Template = "Part", MaxHealth = 8500,    CoreDamage = 130,   CashReward = 650,   Scale = 1.6,  BossWave = 20  },
    Boss3  = { Template = "Part", MaxHealth = 18000,   CoreDamage = 200,   CashReward = 1100,  Scale = 1.75, BossWave = 30  },
    Boss4  = { Template = "Part", MaxHealth = 36000,   CoreDamage = 300,   CashReward = 1900,  Scale = 1.9,  BossWave = 40  },
    Boss5  = { Template = "Part", MaxHealth = 70000,   CoreDamage = 440,   CashReward = 3200,  Scale = 2.05, BossWave = 50  },
    Boss6  = { Template = "Part", MaxHealth = 125000,  CoreDamage = 640,   CashReward = 5200,  Scale = 2.2,  BossWave = 60  },
    Boss7  = { Template = "Part", MaxHealth = 210000,  CoreDamage = 880,   CashReward = 8000,  Scale = 2.35, BossWave = 70  },
    Boss8  = { Template = "Part", MaxHealth = 340000,  CoreDamage = 1200,  CashReward = 12000, Scale = 2.5,  BossWave = 80  },
    Boss9  = { Template = "Part", MaxHealth = 540000,  CoreDamage = 1650,  CashReward = 19000, Scale = 2.75, BossWave = 90  },
    Boss10 = { Template = "Part", MaxHealth = 860000,  CoreDamage = 2300,  CashReward = 32000, Scale = 3.0,  BossWave = 100 },
}

-- SpawnInterval is wave-dependent — calculated in RaidService.
-- These are the bounds: starts slow (new players need to react), compresses to fast.
-- BetweenWaves also scales down from 8s early to 2s at wave 50+.
-- RaidService reads SpawnInterval from here as the minimum (late game floor).
RaidConfig.Timing = {
    SpawnInterval      = 0.5,   -- base floor for spawn spacing (late game)
    SpawnIntervalEarly = 1.2,   -- wave 1 spacing — gives new players time to react
    SpawnIntervalRampWaves = 40, -- by wave 40 spacing is at the floor
    BetweenWaves       = 2.5,   -- late game inter-wave break (seconds)
    BetweenWavesEarly  = 9.0,   -- wave 1 break — time to buy and place units
    BetweenWavesRampWaves = 50, -- by wave 50 break is at the floor
    MoveTimeout        = 7,
}

return RaidConfig

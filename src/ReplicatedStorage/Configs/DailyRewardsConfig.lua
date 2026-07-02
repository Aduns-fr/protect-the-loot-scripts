-- Daily Chests: one chest per day, contents rolled at claim time from everything
-- obtainable in the game (cash, trap units, swords) and granted INSTANTLY — no
-- placed crates, no open timers. Rewards scale infinitely with the day streak.
-- BuildRollPool feeds the crate-style roulette (RollScreen) shown on claim.
local DailyRewardsConfig = {}

DailyRewardsConfig.CooldownSeconds = 24 * 60 * 60

-- category weights; Unit/Sword shares grow as days go on
local CATEGORY_WEIGHTS = {
	{ Type = "Cash", Base = 55, PerDay = 0 },
	{ Type = "Unit", Base = 30, PerDay = 0.7 },
	{ Type = "Sword", Base = 15, PerDay = 0.5 },
}

-- day a rarity tier starts appearing in chests, and how fast its weight ramps
local RARITY_GATES = {
	{ Rarity = "Common", Day = 1, Base = 100, PerDay = 0 },
	{ Rarity = "Uncommon", Day = 2, Base = 30, PerDay = 1 },
	{ Rarity = "Rare", Day = 4, Base = 12, PerDay = 1.5 },
	{ Rarity = "Epic", Day = 7, Base = 6, PerDay = 2 },
	{ Rarity = "Legendary", Day = 12, Base = 3, PerDay = 2.5 },
	{ Rarity = "Mythic", Day = 20, Base = 1, PerDay = 3 },
}

local CASH_BASE = 2500 -- day 1 average; grows ~day^1.25 forever

local function comma(value)
	value = math.floor(tonumber(value) or 0)
	local text = tostring(value)
	while true do
		local nextText, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = nextText
		if count == 0 then break end
	end
	return text
end

local function pickWeighted(rng, entries, weightOf)
	local total = 0
	for _, entry in ipairs(entries) do total += math.max(0, weightOf(entry)) end
	if total <= 0 then return entries[1] end
	local r = rng:NextNumber(0, total)
	local acc = 0
	for _, entry in ipairs(entries) do
		acc += math.max(0, weightOf(entry))
		if r <= acc then return entry end
	end
	return entries[#entries]
end

local function unlockedRarities(day)
	local unlocked = {}
	for _, gate in ipairs(RARITY_GATES) do
		if day >= gate.Day then table.insert(unlocked, gate) end
	end
	return unlocked
end

local function rollRarity(rng, day)
	local gate = pickWeighted(rng, unlockedRarities(day), function(g)
		return g.Base + (day - g.Day) * g.PerDay
	end)
	return gate.Rarity
end

local function rollCash(rng, day)
	local amount = CASH_BASE * (day ^ 1.25) * rng:NextNumber(0.85, 1.2)
	return math.max(500, math.floor(amount / 50) * 50)
end

local function cashRarity(amount)
	if amount < 10000 then return "Common"
	elseif amount < 50000 then return "Uncommon"
	elseif amount < 250000 then return "Rare"
	elseif amount < 1000000 then return "Epic"
	else return "Legendary" end
end

-- sword rarity ladder has no Epic/Mythic; remap chest rolls onto it
local function swordRarity(rarity)
	if rarity == "Epic" then return "Rare" end
	if rarity == "Mythic" then return "Legendary" end
	return rarity
end

-- picks a random id from a config table ({id = {Rarity=...}}) matching rarity; nil if none
local function pickByRarity(rng, items, rarity, excludeId)
	local pool = {}
	for id, cfg in pairs(items) do
		if cfg.Rarity == rarity and id ~= excludeId then table.insert(pool, id) end
	end
	table.sort(pool) -- deterministic order before random pick
	if #pool == 0 then return nil end
	return pool[rng:NextInteger(1, #pool)]
end

-- Rolls the contents of the day-N chest. Everything is instantly grantable.
-- Returns { Type, Cash?, UnitId?, SwordId?, Rarity, Label }
function DailyRewardsConfig.RollChest(day, seed)
	local UnitsConfig = require(script.Parent.UnitsConfig)
	local SwordsConfig = require(script.Parent.SwordsConfig)
	day = math.max(1, math.floor(tonumber(day) or 1))
	local rng = seed and Random.new(seed) or Random.new()

	local category = pickWeighted(rng, CATEGORY_WEIGHTS, function(c)
		return c.Base + (day - 1) * c.PerDay
	end).Type

	if category == "Unit" then
		local rarity = rollRarity(rng, day)
		local unitId = pickByRarity(rng, UnitsConfig.Units, rarity)
		if unitId then
			local cfg = UnitsConfig.Units[unitId]
			return { Type = "Unit", UnitId = unitId, UnitAmount = 1, Rarity = rarity,
				Label = (cfg.DisplayName or unitId) .. " (" .. rarity .. ")" }
		end
	elseif category == "Sword" then
		local rarity = swordRarity(rollRarity(rng, day))
		local swordId = pickByRarity(rng, SwordsConfig.Swords, rarity, SwordsConfig.DefaultSword)
		if swordId then
			local cfg = SwordsConfig.Swords[swordId]
			return { Type = "Sword", SwordId = swordId, Rarity = cfg.Rarity or rarity,
				Label = (cfg.DisplayName or swordId) .. " (" .. (cfg.Rarity or rarity) .. ")" }
		end
	end

	-- Cash category, or fallback when a pool came up empty
	local amount = rollCash(rng, day)
	return { Type = "Cash", Cash = amount, Rarity = cashRarity(amount), Label = "$" .. comma(amount) }
end

-- normalized share (0-1) of each category / unlocked rarity at a given day
local function categoryShares(day)
	local total, shares = 0, {}
	for _, c in ipairs(CATEGORY_WEIGHTS) do total += c.Base + (day - 1) * c.PerDay end
	for _, c in ipairs(CATEGORY_WEIGHTS) do shares[c.Type] = (c.Base + (day - 1) * c.PerDay) / total end
	return shares
end
local function rarityShares(day)
	local unlocked = unlockedRarities(day)
	local total, shares = 0, {}
	for _, g in ipairs(unlocked) do total += g.Base + (day - g.Day) * g.PerDay end
	for _, g in ipairs(unlocked) do shares[g.Rarity] = (g.Base + (day - g.Day) * g.PerDay) / total end
	return shares
end

-- Builds the roulette display pool for the RollScreen: every unit, every sword,
-- and representative cash cards, each with its real drop chance for that day.
function DailyRewardsConfig.BuildRollPool(day)
	local UnitsConfig = require(script.Parent.UnitsConfig)
	local SwordsConfig = require(script.Parent.SwordsConfig)
	day = math.max(1, math.floor(tonumber(day) or 1))
	local cat = categoryShares(day)
	local rar = rarityShares(day)
	local pool = {}
	local function round1(x) return math.floor(x * 10 + 0.5) / 10 end

	-- units: chance = unit share * rarity share / items in that rarity
	local unitCountByRarity = {}
	for _, cfg in pairs(UnitsConfig.Units) do
		unitCountByRarity[cfg.Rarity] = (unitCountByRarity[cfg.Rarity] or 0) + 1
	end
	for id, cfg in pairs(UnitsConfig.Units) do
		local share = rar[cfg.Rarity]
		if share then
			table.insert(pool, { id = id, name = cfg.DisplayName or id, rarity = cfg.Rarity,
				damage = cfg.Damage or 0, chance = round1(cat.Unit * share / unitCountByRarity[cfg.Rarity] * 100), imageId = "" })
		end
	end

	-- swords: Epic/Mythic shares fold into Rare/Legendary
	local swordShare = {
		Common = rar.Common, Uncommon = rar.Uncommon,
		Rare = (rar.Rare or 0) + (rar.Epic or 0),
		Legendary = (rar.Legendary or 0) + (rar.Mythic or 0),
	}
	local swordCountByRarity = {}
	for id, cfg in pairs(SwordsConfig.Swords) do
		if id ~= SwordsConfig.DefaultSword then
			swordCountByRarity[cfg.Rarity] = (swordCountByRarity[cfg.Rarity] or 0) + 1
		end
	end
	for id, cfg in pairs(SwordsConfig.Swords) do
		local share = swordShare[cfg.Rarity]
		if id ~= SwordsConfig.DefaultSword and share and share > 0 then
			table.insert(pool, { id = id, name = cfg.DisplayName or id, rarity = cfg.Rarity,
				damage = cfg.Damage or 0, chance = round1(cat.Sword * share / swordCountByRarity[cfg.Rarity] * 100), imageId = cfg.ImageId or "" })
		end
	end

	-- cash cards: low / typical / lucky roll for this day
	for _, mult in ipairs({ 0.85, 1.0, 1.2 }) do
		local amount = math.max(500, math.floor(CASH_BASE * (day ^ 1.25) * mult / 50) * 50)
		table.insert(pool, { id = "Cash" .. tostring(mult), name = "$" .. comma(amount),
			rarity = cashRarity(amount), damage = 0, chance = round1(cat.Cash / 3 * 100), imageId = "" })
	end

	table.sort(pool, function(a, b) return a.name < b.name end)
	return pool
end

function DailyRewardsConfig.Describe(reward)
	if type(reward) == "table" and reward.Label then return reward.Label end
	return "Daily Chest"
end

-- kept for anything still calling the old API: the "reward" for day N is a chest
function DailyRewardsConfig.GetDayIndex(streak)
	return math.max(1, math.floor(tonumber(streak) or 1))
end
function DailyRewardsConfig.GetReward(streak)
	return { Type = "Chest", Label = "Day " .. tostring(DailyRewardsConfig.GetDayIndex(streak)) .. " Chest" }
end

return DailyRewardsConfig
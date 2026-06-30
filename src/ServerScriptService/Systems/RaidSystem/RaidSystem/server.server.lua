-- CUTOVER: data-driven enemy system (R6 rigs) replaces the egg-model RaidService.
-- The old RaidService module is left in place (unused) for easy rollback.
local EnemyCore = require(script.Parent.Modules.EnemyCore)
EnemyCore.Start()

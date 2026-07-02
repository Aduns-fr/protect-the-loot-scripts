--!strict
-- Single source of truth for the infinite-water system.
-- The WaterTile part sits centered at TileCenterY with a thickness of TileHeight,
-- so the visible water surface is the top face of the tile.

local TILE_CENTER_Y = -4.05
local TILE_HEIGHT = 10.25

local WaterConfig = {}

-- Where the InfiniteWater renderer parks each tile (tile center).
WaterConfig.TileCenterY = TILE_CENTER_Y
WaterConfig.TileHeight = TILE_HEIGHT
WaterConfig.TileSize = 512

-- The actual water surface height everything should align to.
WaterConfig.SurfaceY = TILE_CENTER_Y + TILE_HEIGHT / 2 -- ~1.755

-- Texture scroll speed for the animated surface.
WaterConfig.ScrollU = 0.5
WaterConfig.ScrollV = 0.2

return WaterConfig

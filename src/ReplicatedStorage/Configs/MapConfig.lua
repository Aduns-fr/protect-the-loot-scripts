local MapConfig = {}

MapConfig.Maps = {
    [1] = {
        Name = "Classic",
        PartColor = Color3.fromRGB(99, 95, 98),
        -- map 1 uses the default Points/Path already in each plot
        -- no asset swap needed
        AssetFolder = nil,
    },
    [2] = {
        Name = "Map 2",
        PartColor = Color3.fromRGB(218, 134, 122),
        -- folder name in ReplicatedStorage that holds Path and Points2
        AssetFolder = "Map2",
    },
}

MapConfig.DefaultMap = 1
MapConfig.PointsFolderName = "Points" -- what the folder is named in-plot
MapConfig.PathName = "Path"           -- what the path union/part is named in-plot

return MapConfig

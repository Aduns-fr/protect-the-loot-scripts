# Protect the Loot Scripts

Scripts-only export from the Roblox Studio place currently open as `protect the treasure`.

## Layout

- `src/` contains exported `Script`, `LocalScript`, and `ModuleScript` source files.
- `assets/` contains exported Roblox model assets that script source alone cannot represent.
- `scripts-manifest.json` maps each Roblox instance path to its exported file.
- `export-meta.json` contains basic export metadata from Studio.

File extensions:

- `.server.lua` = `Script`
- `.client.lua` = `LocalScript`
- `.lua` = `ModuleScript`

Current asset exports:

- `assets/ReplicatedStorage_Swords_Final_NoVFX_Buffed.rbxm` is the final `ReplicatedStorage.Swords` folder after the sword grip, VFX removal, beam-plane rotation, and balance pass.

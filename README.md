# Protect the Loot Scripts

Scripts-only export from the Roblox Studio place currently open as `protect the treasure`.

## Layout

- `src/` contains exported `Script`, `LocalScript`, and `ModuleScript` source files.
- `scripts-manifest.json` maps each Roblox instance path to its exported file.
- `export-meta.json` contains basic export metadata from Studio.

File extensions:

- `.server.lua` = `Script`
- `.client.lua` = `LocalScript`
- `.lua` = `ModuleScript`


# FNVVR Epic Helper

[![Release](https://img.shields.io/github/v/release/Blowntobytes/fnvvr-epic-helper)](https://github.com/Blowntobytes/fnvvr-epic-helper/releases/latest)

Installs [FNVVR Reborn](https://github.com/df4l/FNVVR) on the **Epic Games Store** version of Fallout: New Vegas.

## Why this exists

FNVVR Reborn only understands the **Steam/GOG 1.4.0.525** executable. The Epic version is **1.4.0.1338**, a different 2023 recompile, so FNVVR fails with:

```
VR: The game's frame code was not found, stereo rendering is disabled
```

The community solution is to convert the user's own Epic executable to the 1.4.0.525 code with the **Epic Games Patcher**, then provide the 32-bit `d3dx9_38.dll` that the Steam code expects. This helper automates that process, installs FNVVR, and verifies the result.

## Download

Get the latest release:

**https://github.com/Blowntobytes/fnvvr-epic-helper/releases/latest**

The release zip contains:

- `Install-FNVVR-Epic.ps1`
- `Run-Installer.bat`
- `README.md`
- `DOWNLOAD-LINKS.txt`
- `FNVVR-Reborn.zip` - FNVVR Reborn binaries and data files (zlib/libpng, see `THIRD_PARTY_NOTICES.md`)

It does **not** contain:

- the Epic Games Patcher
- any Fallout executable or game asset
- Microsoft DirectX files

## Requirements

1. Fallout: New Vegas installed from Epic. The usual English folder is:
   `...\FalloutNewVegas\Fallout New Vegas English`
2. SteamVR installed, with the headset connected.
3. The **Epic Games Patcher** downloaded from its official Nexus Mods page:
   https://www.nexusmods.com/newvegas/mods/81281

## Installation

1. Download and extract the latest **FNVVR Epic Helper** release zip.
2. Download the Epic Games Patcher and extract `Patcher.exe`, `patch.xdelta`, and `xdelta3.exe` into the `Fallout New Vegas English` folder.
3. Double-click **`Run-Installer.bat`**.
4. If the helper cannot find the game, select the `Fallout New Vegas English` folder when asked.
5. If the helper asks for the FNVVR zip, select `FNVVR-Reborn.zip` from the extracted release folder.
6. Start **SteamVR** first.
7. Launch Fallout: New Vegas from Epic.

You do not need to rename files or use command-line options.

## What the helper does

- Finds the Epic game folder, including Epic manifests and common library layouts.
- Detects `1.4.0.1338` vs `1.4.0.525`.
- Runs the Epic Games Patcher if its files are present.
- Downloads Microsoft's official DirectX June 2010 redistributable and installs the 32-bit `d3dx9_38.dll` into the game folder.
- Installs FNVVR (`d3d9.dll`, `openvr_api.dll`, `dxvk.conf`, `fnvvr\*.json`, texts).
- Sets `d3d9.vrBackend = openvr` in `dxvk.conf`.
- Verifies the FNVVR hook at `0x0086EDE8 -> 0x0086FF70`.
- Backs up files it replaces and supports restoring the original Epic executable.

## If something goes wrong

### `The game's frame code was not found`

The executable is not the 1.4.0.525 code. Run the Epic Games Patcher, then run the helper again.

### Windows "System Error" when launching

The patched executable needs **32-bit `d3dx9_38.dll`**. The helper normally installs it. If it could not, install the Microsoft DirectX End-User Runtime (June 2010):

https://www.microsoft.com/download/details.aspx?id=35

### OpenVR / SteamVR errors

- Start SteamVR before the game.
- Check that `openvr_api.dll` is in the game folder.
- Read `FalloutNV_d3d9.log` in the game folder.

### Epic verified or updated the game

Epic restores the 1.4.0.1338 executable. Run the helper again (and the patcher).

### Controller bindings

FNVVR action/binding files are copied into `fnvvr\`. If your controllers are not mapped, set the bindings in SteamVR.

## Advanced options

Normal users can ignore these.

```powershell
# Only check what is installed / missing
powershell -ExecutionPolicy Bypass -File .\Install-FNVVR-Epic.ps1 -CheckOnly

# Point at a specific game folder and FNVVR zip
powershell -ExecutionPolicy Bypass -File .\Install-FNVVR-Epic.ps1 `
  -GamePath "F:\Epic Library\FalloutNewVegas\Fallout New Vegas English" `
  -FnvVrZip ".\FNVVR-Reborn.zip"

# Restore the original Epic executable
powershell -ExecutionPolicy Bypass -File .\Install-FNVVR-Epic.ps1 -Restore

# No dialog boxes (for automated use)
powershell -ExecutionPolicy Bypass -File .\Install-FNVVR-Epic.ps1 -CheckOnly -NoGui
```

Run PowerShell as Administrator if the game is installed under `Program Files`.

## Caveats

- The Epic Games Patcher partially removes Epic integration; playtime tracking and achievements may stop working.
- The patcher is a third-party community tool. This project does not include or redistribute it.
- This helper is unofficial and is not affiliated with FNVVR, Epic Games, Bethesda, Nexus Mods, or the Epic Games Patcher authors.

## Credits

- [FNVVR Reborn](https://github.com/df4l/FNVVR) by df4l and contributors.
- Epic Games Patcher by lStewieAl / C6.
- OpenVR by Valve Corporation.
- DXVK by Philip Rebohle and contributors.

See `THIRD_PARTY_NOTICES.md` for license details.

## License

The helper scripts and documentation are released under the MIT License. See `LICENSE`.

The bundled FNVVR Reborn package is distributed under its original zlib/libpng license; see `THIRD_PARTY_NOTICES.md` and the `LICENSE` file inside `FNVVR-Reborn.zip`.

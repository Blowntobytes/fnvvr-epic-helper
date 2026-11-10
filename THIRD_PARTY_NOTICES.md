# Third-party notices

This project includes or distributes the following third-party components.

## FNVVR Reborn

- Project: https://github.com/df4l/FNVVR
- Included in: `FNVVR-Reborn.zip` release asset
- Contents: `d3d9.dll`, `dxvk.conf`, `openvr_api.dll`, `fnvvr` action/binding files and texts
- License: zlib/libpng (DXVK-derived), see `licenses/FNVVR-DXVK-LICENSE.txt`

Copyright notices from the FNVVR/DXVK license:

```
Copyright (c) 2017 Philip Rebohle
Copyright (c) 2019 Joshua Ashton
Copyright (c) 2019 Robin Kertels
Copyright (c) 2023 Jeffrey Ellison
```

## OpenVR

- Project: https://github.com/ValveSoftware/openvr
- Included in: `openvr_api.dll` inside `FNVVR-Reborn.zip`
- License: BSD-3-Clause, see `licenses/OPENVR-LICENSE.txt`

Copyright (c) 2015, Valve Corporation.

## Epic Games Patcher

- Project: https://www.nexusmods.com/newvegas/mods/81281
- Authors: lStewieAl, C6
- Included: **No.** Users download it themselves from the official Nexus Mods page.
- The helper only runs `Patcher.exe` if the user placed it in the game folder.

The Epic Games Patcher's Nexus Mods permissions do not allow uploading the file to other sites. Do not bundle or redistribute it.

## Microsoft DirectX

- The helper downloads Microsoft's official DirectX June 2010 redistributable at runtime to provide the 32-bit `d3dx9_38.dll`.
- Microsoft DirectX files are **not** included in this repository or release assets.

## Fallout: New Vegas

- Game files, executables, and assets are **not** included.
- A legitimate copy of the game is required.

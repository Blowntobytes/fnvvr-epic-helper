# Changelog

## v1.0.0 - 2026-11-10

- Initial release.
- Detects Epic `1.4.0.1338` and verifies the FNVVR-compatible `1.4.0.525` code.
- Runs the user-supplied Epic Games Patcher when needed.
- Installs the 32-bit `d3dx9_38.dll` from Microsoft's official DirectX redistributable.
- Installs FNVVR Reborn files, action bindings, and texts.
- Sets `d3d9.vrBackend = openvr` in `dxvk.conf`.
- Verifies the FNVVR hook at `0x0086EDE8 -> 0x0086FF70`.
- Adds a GUI file/folder picker for non-technical users.
- Adds `-CheckOnly`, `-Restore`, `-GamePath`, `-FnvVrZip`, and `-NoGui` options.

# Building Mugen Deej

## Application script

The main application is `MugenDeej.ps1` and targets Windows PowerShell 5.1 with WinForms.

For a source-level test on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\MugenDeej.ps1
```

## Launcher

The launcher source is in `src/launcher`. It starts the PowerShell application without leaving a console window open and writes startup failures to `logs/launcher.log`.

The release launcher is built for Windows with the Mugen Deej multi-size icon embedded in the executable. A reproducible packaging script should be added before enabling automated public releases; until then, keep release building a maintainer-only process and verify the resulting archive manually.

## Release package contents

A portable release archive should contain:

- `MugenDeej.exe`
- `MugenDeej.ps1`
- `MugenDeej.ico`
- `MugenDeej-Debug.cmd`
- `README.txt`
- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- `SHA256SUMS.txt`

The GitHub release should also include a matching `Mugen-Deej-<version>-Portable.zip.sha256` checksum file.

`config.json`, backup configuration files, and the `logs/` and `drivers/` directories are created automatically at runtime when needed.

Do not bundle third-party driver installers unless their redistribution terms are confirmed. Mugen Deej downloads the official WCH driver only after the user requests it and verifies the publisher's digital signature before launch.

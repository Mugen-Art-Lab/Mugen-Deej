# Building Mugen Deej

## Application script

The main application is `MugenDeej.ps1` and targets Windows PowerShell 5.1 with WinForms.

For a source-level test on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\MugenDeej.ps1
```

## Launcher

The launcher source is in `src/launcher`. It starts the PowerShell application without leaving a console window open and writes startup failures to `logs/launcher.log`.

The official 0.8.4 release launcher was built for Windows with the Mugen Deej multi-size icon embedded in the executable. A reproducible packaging script should be added before enabling automated public releases; until then, keep release building a maintainer-only process and verify the resulting archive manually.

## Release package contents

A portable release should contain:

- `MugenDeej.exe`
- `MugenDeej.ps1`
- `MugenDeej.ico`
- `MugenDeej-Debug.cmd`
- `Start Mugen Deej.cmd`
- `config.json`
- documentation and license files
- `firmware/`
- `drivers/README.txt`
- `SHA256SUMS.txt`

Do not bundle third-party driver installers unless their redistribution terms are confirmed. Mugen Deej can direct the user to the official WCH download instead.

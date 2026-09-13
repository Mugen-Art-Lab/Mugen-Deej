# Building Mugen Deej

## Application script

The main application is `MugenDeej.ps1` and targets Windows PowerShell 5.1 with WinForms.

For a source-level test on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\MugenDeej.ps1
```

## Portable release builder

The repository contains one packaging path used both locally and by GitHub Actions:

```text
tools/Build-PortableRelease.ps1
```

The builder intentionally does **not** publish a GitHub Release. It only creates the portable package and checksums so the result can be inspected and smoke-tested first.

Before packaging it:

- reads the package version from `VERSION.txt` unless `-Version` is supplied;
- requires that version to match the first-line version in `MugenDeej.ps1`;
- parses the complete PowerShell application before packaging;
- builds the small Go launcher as a Windows GUI executable;
- embeds `MugenDeej.ico` into the launcher with pinned `github.com/akavel/rsrc@v0.10.2`;
- stages only the explicit portable-release files, never runtime configs or logs;
- writes an internal `SHA256SUMS.txt`;
- creates `Mugen-Deej-<version>-Portable.zip`;
- creates the matching `Mugen-Deej-<version>-Portable.zip.sha256` file.

### Local Windows build

Requirements:

- Windows PowerShell 5.1;
- Go 1.20 or newer in `PATH`;
- internet access on the first build so Go can obtain the pinned `rsrc` tool.

From the repository root, either double-click:

```text
BUILD_PORTABLE.cmd
```

or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-PortableRelease.ps1
```

Artifacts are written to `artifacts\` and are ignored by Git.

For a controlled build using an already trusted launcher binary, the script also accepts:

```powershell
.\tools\Build-PortableRelease.ps1 -LauncherPath C:\Path\To\MugenDeej.exe
```

### Manual GitHub Actions build

Open **Actions -> Build portable package -> Run workflow** on the branch you want to package.

The version input is optional. Leave it empty to use `VERSION.txt`. If a version is entered, the builder still requires it to match the version declared by `MugenDeej.ps1`; this prevents accidentally naming one build as another version.

The workflow uploads a temporary Actions artifact containing:

- `Mugen-Deej-<version>-Portable.zip`
- `Mugen-Deej-<version>-Portable.zip.sha256`

The workflow does not tag, merge, or publish anything.

## Launcher

The launcher source is in `src/launcher`. It starts the PowerShell application without leaving a console window open and writes startup failures to `logs/launcher.log`.

The release launcher is built for Windows x64 with the Mugen Deej multi-size icon embedded in the executable.

## Release package contents

A portable release archive contains:

- `MugenDeej.exe`
- `MugenDeej.ps1`
- `MugenDeej.ico`
- `MugenDeej-Debug.cmd`
- `README.txt`
- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- `SHA256SUMS.txt`

The GitHub release should also include the matching `Mugen-Deej-<version>-Portable.zip.sha256` checksum file.

`config.json`, recovery copies, button mappings, `.backup` files, and the `logs/` and `drivers/` directories are runtime data and are never bundled by the builder.

Do not bundle third-party driver installers unless their redistribution terms are confirmed. Mugen Deej downloads the official WCH driver only after the user requests it and verifies the publisher's digital signature before launch.

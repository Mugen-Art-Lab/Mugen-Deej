# Building Mugen Deej

## Application source

The main application is `MugenDeej.ps1` and targets Windows PowerShell 5.1 with WinForms. The release source is kept directly in the repository; packaging does not apply release-time source patches.

For a source-level test on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\MugenDeej.ps1
```

The Setup UI source is `src/setup/setup.ps1`. `src/setup/main.go` embeds that script together with the exact portable ZIP produced by the release builder.

## Release builder

The repository contains one packaging path used both locally and by GitHub Actions:

```text
tools/Build-Release.ps1
```

The builder intentionally does **not** merge branches, create tags, or publish a GitHub Release. It only creates release packages and checksum files so they can be inspected and smoke-tested first.

Before packaging, the builder:

- reads the requested version from `VERSION.txt` unless `-Version` is supplied;
- requires that version to match the version declared on the first line of `MugenDeej.ps1`;
- validates both `MugenDeej.ps1` and `src/setup/setup.ps1` with the Windows PowerShell 5.1 parser;
- builds the small Go launcher as a Windows GUI executable;
- embeds `MugenDeej.ico` into the launcher with pinned `github.com/akavel/rsrc@v0.10.2`;
- stages only the explicit portable-release files, never runtime configs, logs, backups, or downloaded drivers;
- writes an internal `SHA256SUMS.txt` for the portable package contents;
- creates `Mugen-Deej-<version>-Portable.zip` and its `.sha256` sidecar;
- builds a self-contained `Mugen-Deej-<version>-Setup.exe` around that exact portable ZIP and creates its `.sha256` sidecar.

### Local Windows build

Requirements:

- Windows PowerShell 5.1;
- Go 1.20 or newer in `PATH`;
- .NET SDK 10 in `PATH` for the self-contained virtual-gamepad helper;
- internet access so the first build can obtain the pinned `rsrc` tool and
  the pinned HIDMaestro backend archive used by `Prepare-HIDMaestro.ps1`.

From the repository root, either double-click:

```text
BUILD_RELEASE.cmd
```

or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
```

Artifacts are written to `artifacts\` and are ignored by Git.

For a controlled build using an already trusted launcher binary, the script also accepts:

```powershell
.\tools\Build-Release.ps1 -LauncherPath C:\Path\To\MugenDeej.exe
```

`-LauncherPath` replaces only the portable application's small launcher. Building the Setup EXE still requires Go because the Setup wrapper must embed the newly produced portable payload.

### Manual GitHub Actions build

Open **Actions -> Build release packages -> Run workflow** on the branch you want to package.

The version input is optional. Leave it empty to use `VERSION.txt`. If a version is entered, it must still match the version declared by `MugenDeej.ps1`; this prevents accidentally naming one source state as another version.

The workflow uploads one temporary Actions artifact containing:

- `Mugen-Deej-<version>-Portable.zip`
- `Mugen-Deej-<version>-Portable.zip.sha256`
- `Mugen-Deej-<version>-Setup.exe`
- `Mugen-Deej-<version>-Setup.exe.sha256`

The workflow does not tag, merge, or publish anything.

## Launcher

The launcher source is in `src/launcher`. It starts the PowerShell application without leaving a console window open and writes startup failures to `logs/launcher.log`.

The release launcher is built for Windows x64 with the Mugen Deej multi-size icon embedded in the executable.

## Setup wrapper

The Setup wrapper source is in `src/setup`. It embeds:

- the bilingual PowerShell/WinForms installer UI from `src/setup/setup.ps1`;
- the exact portable ZIP generated earlier in the same build.

The Setup EXE performs a portable-style installation/update. It intentionally does not register an uninstall entry in Windows Installed Apps. Its version is injected into the Go wrapper at build time from the same release version used for the portable package.

## Portable package contents

A portable release archive contains the desktop runtime plus the optional
virtual-controller backend and the tested Adaptive reference firmware:

- `MugenDeej.exe`
- `MugenDeej.ps1`
- `MugenDeej.ico`
- `MugenDeej-Debug.cmd`
- `README.txt`
- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- `SHA256SUMS.txt`
- `firmware/MugenDeejCardboardNanoPrototype/MugenDeejCardboardNanoPrototype.ino`
- `virtual-gamepad/MugenDeej.VirtualGamepad.ps1`
- `virtual-gamepad/HIDMaestro-LICENSE.txt`
- `virtual-gamepad/host/` — self-contained win-x64
  `MugenDeej.VirtualGamepadHost` output and its required managed/runtime files.

The release builder downloads the pinned HIDMaestro dependency, verifies it,
builds the helper with .NET 10, and smoke-runs the published helper before
packaging.

`config.json`, recovery copies, button mappings, Adaptive mapping/profile/layer
files, `.backup` files, and the `logs/` and `drivers/` directories are
runtime/user data and are never bundled by the builder.

Do not bundle third-party driver installers unless their redistribution terms are confirmed. Mugen Deej downloads the official WCH driver only after the user requests it and verifies the publisher's digital signature before launch.


## GitHub-hosted Windows runner

As of 2026-10-10, the public `feature/virtual-gamepad-ui` build uses
`runs-on: windows-latest` (GitHub-hosted Windows), **not** the private
self-hosted Mugen-Builder. The job still uses Windows PowerShell 5.1,
`actions/setup-dotnet` for .NET 10 and `actions/setup-go` for the
launcher/installer. No self-hosted hardware or custom runner setup is required
to produce the packages.

The first migrated run, [CI #39](https://github.com/Mugen-Art-Lab/Mugen-Deej/actions/runs/38036314621),
**succeeded**: Portable ZIP, Setup EXE and SHA-256 sidecars were uploaded as
`Mugen-Deej-packages-39` (artifact ID `11663877928`). This verifies the
build and packaging pipeline on a fresh GitHub-hosted machine; it does not
replace real hardware testing of the UI changes from CI #38. The personal
self-hosted runner is left untouched for separate private repositories.

## Code signing

The build pipeline does not currently Authenticode-sign the launcher or Setup
EXE. A locally or CI-built 2.0 package may therefore trigger Windows Unknown
publisher / SmartScreen UI.

For published releases, distribute the generated SHA-256 sidecars and keep the
release files on the official GitHub Release so users can verify provenance.
If code signing is added later, signing must happen in a reproducible release
step and any signed/repacked binary must receive a fresh hardware/package smoke
test before publication.

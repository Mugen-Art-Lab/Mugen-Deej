<p align="center">
  <img src="assets/mugen-deej-icon-64.png" width="64" height="64" alt="Mugen Deej icon">
</p>

<h1 align="center">Mugen Deej</h1>

<p align="center">
  A portable bilingual Windows client for deej-compatible USB audio controllers.
</p>

<p align="center">
  <a href="README_RU.md">Русский</a> · <strong>English</strong>
</p>

<p align="center">
  <a href="assets/screenshots/en/main-window.webp">
    <img src="assets/screenshots/en/main-window.webp" width="330" alt="Mugen Deej main window in Light theme">
  </a>
  <a href="assets/screenshots/en/main-window-dark.webp">
    <img src="assets/screenshots/en/main-window-dark.webp" width="330" alt="Mugen Deej main window in Dark theme">
  </a>
</p>

## Relationship to the original deej project

Mugen Deej is an independently developed Windows client inspired by and compatible with the original [deej](https://github.com/omriharel/deej) project created by Omri Harel.

It follows the same general idea of a physical volume mixer and accepts a compatible newline-delimited serial format. The Mugen Deej desktop client, interface, diagnostics, and connection logic were developed separately for this project.
Mugen Deej is **not a fork of the original desktop client**, does not bundle the original `deej.exe`, and is not an official continuation of or affiliated with the original deej project. Full acknowledgement is available in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## What it does

Mugen Deej turns a deej-compatible USB serial controller with physical controls into a friendly Windows volume mixer.

- Automatically discovers compatible controllers across COM ports.
- Reconnects after USB disconnects, resets, and COM-port changes.
- Supports automatic discovery and manual port selection.
- Shows live positions for five physical controls by default.
- Controls Windows master volume, one or more applications, the default microphone, or a selected input device.
- Lets silent applications be assigned before they create an audio session.
- Can start with Windows and optionally launch directly to the notification area.
- Includes **Auto, Light, and Dark** themes; Auto follows Windows theme changes while the app is running.
- Includes Russian and English interfaces and a first-run guide.
- Provides clearer diagnostics for busy ports, driver problems, and rare COM-number conflicts.
- Runs portably without an installer.

## Interface tour

The compact main window and configuration dialogs use the refreshed Friendly UI introduced in 0.8.7. Click any screenshot to view it at full size.

### First-run guide

Connect the controller, move a physical control, and immediately see which input is being detected.

<p align="center">
  <a href="assets/screenshots/en/first-run.webp">
    <img src="assets/screenshots/en/first-run.webp" width="662" alt="Mugen Deej first-run guide in English">
  </a>
</p>

### Configure physical controls

Rename each control and assign Windows master volume, applications, a microphone, or disable it entirely.

<p align="center">
  <a href="assets/screenshots/en/control-settings.webp">
    <img src="assets/screenshots/en/control-settings.webp" width="1000" alt="Mugen Deej control settings in English">
  </a>
</p>

### Select active or currently silent applications

Choose applications that already have an audio session or preselect running applications before they play any sound.

<p align="center">
  <a href="assets/screenshots/en/application-selection.webp">
    <img src="assets/screenshots/en/application-selection.webp" width="862" alt="Mugen Deej application selection in English">
  </a>
</p>

<details>
<summary><strong>Choose the interface language on first launch</strong></summary>
<br>
<p align="center">
  <a href="assets/screenshots/language-selection.png">
    <img src="assets/screenshots/language-selection.png" width="562" alt="Mugen Deej bilingual language selection">
  </a>
</p>
</details>

## Download

[Download the latest portable release](https://github.com/Mugen-Art-Lab/Mugen-Deej/releases/latest), extract the complete archive, and run `MugenDeej.exe`.

Current tested build: **0.8.7**.

## Controller protocol

The controller sends newline-terminated values such as:

```text
107|246|536|665|1020
```

The default configuration expects five values in the `0–1023` range at `9600` baud.

## Quick start

1. Connect a deej-compatible controller by USB.
2. Run `MugenDeej.exe` from the release archive.
3. Choose the interface language.
4. Open **Configure controls** and assign each physical control.

## Source layout

- `MugenDeej.ps1` — application UI, serial discovery, Core Audio control, diagnostics.
- `src/launcher/` — small Go launcher used for the Windows executable.
- `config.example.json` — clean default configuration example.
- `docs/` — building, troubleshooting, and release notes.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 or newer.
- A deej-compatible USB serial controller.
- A suitable USB-serial driver for the controller, such as CH340/CH341 or FTDI.

## Building

See [docs/BUILDING.md](docs/BUILDING.md). The current portable release contains a launcher with the Mugen Deej icon embedded in the executable.

## Contributing

Bug reports and focused pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## License

MIT © 2026 MrSoichi / Mugen Art Lab. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

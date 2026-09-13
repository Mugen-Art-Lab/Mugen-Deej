# Mugen Deej 0.9.0 internal development history

Branch lineage: `feature/controller-autodetect-buttons` -> `release/1.0.0`

Public base: `0.8.7`

Status: **internal development line, never published as a stable release**

The 0.9.0 series was the engineering line that introduced automatic legacy/extended controller detection and physical-button support while preserving the proven 0.8.7 slider/audio/USB behavior. It ultimately reached the soak-tested `0.9.0-dev25-soak-fixed` baseline. Before a public 0.9.0 release was cut, portable settings backup/restore and forward migration were added to the release plan; that work became the reason to promote the next public release to **1.0.0** instead of rewriting or erasing the 0.9.0 history.

This document preserves the development sequence. The detailed feature/test snapshot from the end of the line is kept separately in `docs/history/Mugen_Deej_0.9.0_RELEASE_CANDIDATE_NOTES.md`.

## Core compatibility rule

The 0.9.0 work intentionally treated the existing Windows audio, USB/serial reconnect, startup, suspend/resume and slider mapping paths as a known-good core. Extended-controller support was layered in front of that core rather than replacing it.

Two packet families are supported by one client:

### Legacy / classic deej

```text
512|123|900|42|777
```

Every field is an analog control in the range 0..1023. Existing classic controllers require no firmware change.

### Extended slider/button protocol

```text
s512|s123|s900|s42|s777|b1|b1|b0|b1|b1|b1
```

- `sN` = analog control value, 0..1023.
- `b1` = button released.
- `b0` = button pressed.
- Slider and button counts are learned from valid packets rather than hard-coded.

The application exposes generic legacy/extended capabilities rather than a separate product edition for one particular controller design.

## Development sequence

The local development archive contains installers and hotfixes for every dev number from dev1 through dev25. The points below describe the meaningful milestones; intermediate `fixed`, `fixed-v2`, `fixed-v3` and patch installers are retained as development artifacts outside the public runtime.

### 0.9.0-dev1 — protocol/capability foundation

- Added parsing for both classic numeric packets and the extended `s`/`b` packet family.
- Added automatic protocol, slider-count and button-count discovery.
- Kept slider values flowing through the established audio path.
- Added button-state diagnostics without assigning Windows actions yet.
- Added protection so experimental builds could not overwrite the stable installation's Windows startup registration while the new branch was still unsafe.

### 0.9.0-dev2 — button UI foundation

- Added button-aware UI that appears only for controllers reporting buttons.
- Began live button-state visualization and dynamic layouts based on detected capabilities.
- Follow-up point/layout fixes hardened initialization order.

### 0.9.0-dev3 — button configuration and UI stabilization

- Added the first configurable physical-button action layer.
- Added live button tiles/cards and themed button UI.
- Fixed layout timing, card backgrounds and theme inheritance issues discovered in the custom WinForms controls.

### 0.9.0-dev4 to dev8 — interaction/UI refinement

- Iterated on button settings, focus behavior and layout polish.
- Kept the existing Friendly UI style and brought the new button surfaces into the same rounded bilingual theme system.
- By dev8 the extended-controller UI was visually integrated with the rest of the application.

### 0.9.0-dev9 to dev10 — media transport

- Initial media actions used synthetic keyboard media keys.
- Browser/player compatibility was inconsistent.
- Media transport was moved to Windows `WM_APPCOMMAND` for Play/Pause, Previous and Next.

### 0.9.0-dev11 to dev13 — tray regression fixes

- An experimental tray/minimize path exposed recursive window-state handling and a StackOverflow.
- Guarding was added to stop recursion.
- The hide sequence was changed to `Hide()` -> normalize WindowState -> `ShowInTaskbar = false` (`order=hide-first`) to remove the brief empty-window flash.

### 0.9.0-dev14 — additional system actions

- Added media Stop.
- Added Windows Volume Up, Volume Down and Mute/Unmute using `WM_APPCOMMAND`.

### 0.9.0-dev15 to dev17 — configurable hotkeys

- Added custom keyboard shortcuts with Ctrl/Shift/Alt/Win modifiers.
- Added A-Z, 0-9, common keys, numpad and F1-F24, including F13-F24.
- Added physical hotkey capture and capture UI polish.
- Hotkeys use Windows `SendInput`.

### 0.9.0-dev18 — launch/file and URL actions

- Added launch program/file.
- Added URL opening with encoded payload storage.

### 0.9.0-dev19 — folder action and native interop fixes

- Added folder actions and the related warning/validation UI.
- Fixed x64 `SendInput` structure sizing by using the complete native `INPUT` union (`MOUSEINPUT`, `KEYBDINPUT`, `HARDWAREINPUT`). This fixed F13/F14 failures seen with the earlier hand-written layout.
- Fixed a PowerShell variable collision where URL logging used `$Host`/`$host`, which is case-insensitively reserved/read-only.

### 0.9.0-dev20 — modern folder picker

- Replaced the old `FolderBrowserDialog` with the native Windows `IFileDialog` folder picker.
- Custom title/OK wording is localized by Mugen Deej; Windows Shell navigation labels can still follow the Shell's own language resources.

### 0.9.0-dev21 — freeze/startup restoration

- Restored the proven 0.8.7 startup-registration behavior after the experimental startup guard was no longer needed.
- `Sync-StartupRegistrationPath` keeps the per-user Run entry pointed at the current portable folder.
- The installer itself does not directly modify the Run entry; the running application owns synchronization.

### 0.9.0-dev22 — final feature freeze

- Added `Run command / Выполнить команду` with Win+R-style command strings and arguments.
- Stored command payloads as `command64:<UTF-8 Base64>`.
- Froze the feature set after validating six different command mappings on the six-button controller.
- A real legacy COM5 suspend/resume cycle recovered the existing SerialPort without Close/Open.

### 0.9.0-dev23 — button-settings transaction clarity

- Added the amber notice explaining that selected button actions become live only after the final **Save / Сохранить** action.

### 0.9.0-dev24 — localization repaint fix

- Fixed owner-drawn `MugenButton` and `MugenGroupBox` retaining the previous RU/EN text until mouse hover.
- The custom controls now invalidate themselves from `OnTextChanged` rather than relying on a broad form refresh.

### 0.9.0-dev25 — soak candidate / slider-settings clarity

- Added the matching amber notice to physical-control settings:
  - names, modes and application assignments are pending until **Save**;
  - physical control positions continue updating live.
- The first dev25 installer used a brittle exact insertion marker and safely aborted before modifying the runtime when the marker did not match.
- `Install-MugenDeej-0.9.0-dev25-soak-fixed-v2.ps1` replaced that matcher with a robust anchor and produced the final soak folder:

```text
Mugen-Deej-0.9.0-dev25-soak-fixed
```

This folder is the **golden pre-1.0 runtime baseline**.

## Button action set at the end of 0.9.0

The golden dev25 baseline supports:

- per-control soft mute/unmute;
- Play/Pause, Previous, Next, Stop;
- Windows Volume Up, Volume Down, Mute/Unmute;
- configurable hotkeys including F13-F24;
- physical hotkey capture;
- launch program/file;
- open folder;
- open URL;
- run command.

Dynamic action payloads used by the internal line:

```text
hotkey:<vk>:<modifier-mask>
launch64:<UTF-8 Base64>
folder64:<UTF-8 Base64>
url64:<UTF-8 Base64>
command64:<UTF-8 Base64>
```

The development filename remained `button-actions.dev.json`. The 1.0.0 branch is responsible for a safe one-time migration to the public name `button-actions.json`.

## Final tested reference firmware

The final reference firmware for the tested extended controller is `arduino/MugenDeejController/MugenDeejController.ino`.

Hardware profile:

```text
Analog controls: A0, A1, A2, A3, A4
Buttons:         9, 8, 7, 6, 5, 4
Serial:          9600 baud
Buttons:          INPUT_PULLUP (0 pressed, 1 released)
```

The final firmware deliberately stays simple and state-oriented:

- direct `Serial.print()` output instead of Arduino `String` packet construction;
- non-blocking `millis()` scheduling;
- `PACKET_INTERVAL_MS = 60`;
- per-button `BUTTON_DEBOUNCE_MS = 25`;
- immediate full-state packet after a debounced button transition;
- raw analog values without aggressive firmware smoothing.

The full-state packet model helps capability detection, reconnect, suspend/resume recovery, hot-swap and button-state initialization.

## Soak result

The dev25 baseline was used on two real Windows systems for roughly two weeks before the 1.0.0 branch was started:

- one system exercised both legacy and extended controllers, hot-swap and repeated suspend/resume/hibernate scenarios;
- another system exercised the completed extended 5-control/6-button controller in normal daily use.

No release-blocking crash, StackOverflow, unhandled exception, configuration loss or stuck-action failure was established during that soak. Warnings observed in logs were dominated by unrelated/busy COM ports, deliberately rejected malformed/shape-changing packets, or expected reconnect situations.

This soak is why the `0.9.0-dev25-soak-fixed` runtime is preserved as the known-good baseline rather than rebuilt from the intermediate installers.

## Why 0.9.0 was not published

The internal 0.9.0 line had become feature-complete and soak-tested, but before a clean public release was cut a remaining release-engineering gap was identified: settings needed a user-facing portable backup/restore mechanism and an explicit forward migration story.

Rather than publish 0.9.0 and immediately change the settings contract again, development continued on `release/1.0.0` with a deliberately narrow scope:

1. preserve this tested dev25 baseline;
2. migrate `button-actions.dev.json` to `button-actions.json` safely;
3. add versioned portable `.backup` export/restore;
4. retain the existing `config.previous.json` / `config.last-good.json` safety model;
5. produce and smoke-test a clean 1.0.0 release package.

Thus 0.9.0 remains an **engineering milestone**, while 1.0.0 is the planned **product milestone**.

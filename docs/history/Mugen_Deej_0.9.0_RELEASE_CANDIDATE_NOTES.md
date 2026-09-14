# Mugen Deej 0.9.0 — Release Candidate Notes

Status: **feature frozen / soak testing**

Current candidate:
`0.9.0-dev25-soak-fixed`

Base stable release:
`0.8.7`

This file summarizes the development work that should become the public
Mugen Deej 0.9.0 update after soak testing completes successfully.

---

## 1. Main release goal

Mugen Deej 0.9.0 expands the project from a classic deej-compatible
slider controller into a controller that can also use physical buttons,
without breaking existing slider-only hardware.

The core design rule of 0.9.0 is:

- classic deej controllers continue to work unchanged
- extended controllers can expose sliders and buttons
- Mugen Deej discovers controller capabilities automatically
- button actions are configured in Windows, not hard-coded into Arduino
  firmware

---

# 2. Controller protocol and compatibility

## Legacy controllers

Classic slider-only deej serial packets remain supported.

Example:

```text
512|123|900|456|777
```

Mugen Deej detects this as a legacy controller and shows only controls that
are relevant to sliders.

No firmware update is required for existing legacy deej controllers.

## Extended controllers

Mugen Deej 0.9.0 supports an extended `s` / `b` packet format.

Example:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

Where:

- `sN` = analog slider/potentiometer value
- `b1` = button released
- `b0` = button pressed

The application derives slider and button counts from the packet itself.

This allows different controller layouts instead of hard-coding one exact
`5 sliders + 6 buttons` device.

## Automatic capability detection

The application distinguishes between:

- legacy slider-only controller
- extended slider + button controller

The main window changes accordingly.

When an extended controller is connected, the button-status area and
button-settings button appear.

When a legacy controller is connected, button-only UI is hidden.

## Controller hot-swap

The application has been tested switching between legacy and extended
controllers without restarting Mugen Deej.

The detected protocol, slider count, button count and visible UI update when
the active controller changes.

---

# 3. Physical button support

Mugen Deej 0.9.0 adds complete physical-button support.

The current tested controller has:

- 5 analog controls
- 6 buttons
- CH340 USB serial adapter
- extended protocol

The application displays live button state on the main window.

Pressed buttons visibly highlight their corresponding button tile.

Button configuration is separate from slider configuration.

---

# 4. Button actions

Each physical button can be assigned independently.

## Per-control soft mute

A button can mute/unmute one configured Mugen Deej control.

When a control is muted:

- its state is retained by Mugen Deej
- the main UI displays a visible `MUTED / БЕЗ ЗВУКА` state

Soft mute is automatically cleared when a button-capable controller
disconnects so a mute cannot remain unintentionally stuck after hardware
removal.

## Media controls

Media actions use Windows `WM_APPCOMMAND`, improving compatibility compared
with synthetic keyboard media keys.

Supported actions:

- Play / Pause
- Previous track
- Next track
- Stop

This transport has been tested with multiple kinds of Windows applications,
including browser/media-player scenarios.

## Windows volume controls

Supported Windows-level actions:

- Volume Up
- Volume Down
- Mute / Unmute system audio

These also use `WM_APPCOMMAND`.

## Configurable hotkeys

A button can send a configurable keyboard shortcut.

Supported modifier keys:

- Ctrl
- Shift
- Alt
- Win

Supported keys include:

- A-Z
- 0-9
- common navigation/edit keys
- numpad keys
- F1-F24

F13-F24 support is useful for software that benefits from rarely-used
dedicated shortcut keys.

Hotkeys are sent through Windows `SendInput`.

A bug in the original experimental `INPUT` interop structure was fixed by
using the complete native INPUT union layout. F13/F14 were subsequently
tested successfully.

### Hotkey capture

The hotkey editor can:

- configure a key combination manually
- capture the combination physically from the keyboard

The capture UI immediately shows the recorded combination.

A visible warning explains that some Win/Alt shortcuts may be reserved by
Windows or intercepted by the active application.

## Launch program / file

A button can launch a selected executable or open a selected file through its
registered Windows application.

The stored action uses a UTF-8 Base64 payload.

## Open folder

A button can open a configured folder.

The initial legacy `FolderBrowserDialog` experiment was replaced with a modern
Windows Common File Dialog / IFileDialog folder picker.

The selected folder is stored as a UTF-8 Base64 payload.

## Open URL

A button can open a configured `http` or `https` URL in the user's default
browser.

The URL editor validates supported schemes.

The selected URL is stored as a UTF-8 Base64 payload.

## Run command

The final action added before feature freeze is:

**Run command / Выполнить команду**

It accepts Win+R-style commands, for example:

```text
cmd
powershell
calc
control
regedit
shell:startup
%appdata%
ms-settings:display
cmd /k ipconfig
```

Commands can include arguments.

The command is executed through a hidden Windows command-processor bridge,
using the same privilege level as Mugen Deej.

This action was tested with all six physical buttons using different commands.

---

# 5. Button settings UX

Dynamic actions are configured immediately when selected:

- hotkey
- program/file
- folder
- URL
- command

However, the live button mapping is intentionally transactional.

Changes become active only after the final **Save / Сохранить** button is
pressed.

To make this behavior explicit, the button-settings dialog now contains an
amber notice:

> Important: selected actions take effect only after you click Save.

Russian:

> Важно: выбранные действия начнут работать только после нажатия «Сохранить».

---

# 6. Slider settings UX

The physical-control settings dialog now explicitly distinguishes:

1. **live hardware telemetry**
2. **pending configuration**

The physical knob/fader position continues to update immediately.

Changes to:

- control names
- modes
- application assignments

become active only after **Save / Сохранить**.

The dialog now contains an amber notice explaining this behavior.

Russian:

> Важно: названия, режимы и назначенные приложения применяются только после
> нажатия «Сохранить». Положение физических регуляторов отображается сразу.

English:

> Important: names, modes, and assigned applications are applied only after you
> click Save. Physical control positions are shown immediately.

The dialog layout was enlarged rather than squeezing the note into existing
content.

---

# 7. UI and theme work

The Friendly UI introduced before 0.9.0 remains the base visual style.

0.9.0 keeps:

- Auto / Light / Dark theme selection
- Windows theme tracking
- Russian / English UI
- rounded cards
- custom rounded buttons
- custom progress bars
- tray integration

## Owner-drawn localization repaint fix

A visual bug was fixed where owner-drawn Mugen controls could display text in
the previous language after switching RU <-> EN until the mouse hovered over
them.

Root cause:

- `MugenButton`
- `MugenGroupBox`

draw their own `Text`, but did not invalidate themselves when the `Text`
property changed.

Both controls now invalidate on `OnTextChanged`.

This fixes localization repainting at the custom-control level rather than
forcing a full-form refresh.

---

# 8. Tray behavior fixes

During 0.9.0 development, tray behavior received several stability fixes.

## Recursion / StackOverflow fix

An experimental minimize-to-tray path caused recursive state handling and a
StackOverflow.

A guard was added to prevent that recursion.

## Empty-window flash fix

The hide sequence was changed to:

1. `Hide()`
2. normalize window state
3. set `ShowInTaskbar = false`

The log identifies this path as:

```text
order=hide-first
```

This removes the brief empty-window flash that previously appeared when hiding
to the tray.

---

# 9. Startup behavior

Experimental builds originally disabled startup-registry changes so laboratory
copies could not overwrite the stable installation's Windows startup entry.

For the freeze/soak candidate, the proven startup behavior from 0.8.7 was
restored.

The application can:

- start with Windows
- start minimized to the notification area
- synchronize the startup path to the current portable folder

The installer itself does not directly modify the Windows Run entry.

The running application performs startup-path synchronization.

---

# 10. Suspend / resume / hibernation

The application preserves its existing SerialPort through system suspend when
possible.

On resume it waits for the existing serial connection to begin producing valid
packets again before falling back to reconnect logic.

A tested legacy-controller cycle successfully resumed the existing COM5
SerialPort without Close/Open.

Long-term suspend / hibernate testing remains part of the soak phase.

---

# 11. Arduino reference firmware

A Mugen Deej extended reference sketch was prepared for the tested 5-slider /
6-button controller.

Tested hardware pin profile:

```cpp
SLIDER_PINS:
A0, A1, A2, A3, A4

BUTTON_PINS:
9, 8, 7, 6, 5, 4
```

Serial:

```text
9600 baud
```

Button wiring uses `INPUT_PULLUP`:

```text
0 = pressed
1 = released
```

## Differences from the older Miodec-style sketch

The wire protocol intentionally remains compatible.

Implementation improvements:

| Area | Older sketch | Mugen reference |
|---|---|---|
| Packet construction | Arduino `String` | direct `Serial.print()` |
| Loop pacing | `delay(10)` | non-blocking `millis()` |
| Buttons | raw digital state | 25 ms debounce |
| State model | full packet | full packet |
| Baud | 9600 | 9600 |
| Analog filtering | raw ADC | raw ADC |
| Pin count | manually paired constants | derived from pin arrays |

### Why full packets remain

Every packet contains the full current controller state.

This helps:

- initial capability detection
- reconnect
- suspend/resume recovery
- controller hot-swap
- button-state initialization

### Why no aggressive slider filtering was added

The Arduino sends raw ADC values intentionally.

Mugen Deej already handles presentation-side visual stability.

Keeping the controller firmware simple avoids adding physical-control latency.

### Why button debounce is in firmware

Mechanical buttons can bounce.

A single physical press may now:

- launch a program
- send a hotkey
- open a URL
- run a command
- toggle mute

The reference firmware therefore guarantees a stable physical button state
before transmitting the transition.

---

# 12. Configuration

Button actions are persisted separately from the existing slider configuration.

Current development filename:

```text
button-actions.dev.json
```

Dynamic payload types include:

```text
hotkey:<vk>:<modifier-mask>
launch64:<UTF-8 Base64>
folder64:<UTF-8 Base64>
url64:<UTF-8 Base64>
command64:<UTF-8 Base64>
```

Before final 0.9.0 packaging, review whether the `.dev` suffix should remain in
the public release or be migrated to a final filename.

Any migration must preserve existing dev25 test configuration during release
validation.

---

# 13. Compatibility principles

0.9.0 should preserve these rules:

- do not break classic slider-only deej hardware
- do not require button firmware for slider-only users
- do not encode Windows actions into Arduino firmware
- do not hard-code one exact controller layout
- do not change stable slider/audio behavior unnecessarily
- capability detection belongs to the serial packet
- action meaning belongs to the Windows application

---

# 14. Known non-blocking cosmetic behavior

## Windows file/folder dialogs may contain English Shell labels

On some systems the native Windows file/folder dialogs may display a mixture
such as:

- Russian Mugen title
- English Shell navigation labels (`Home`, `This PC`, `Open`, `Cancel`, etc.)

This is produced by Windows Shell resources rather than Mugen's own translated
controls.

The dialogs function correctly.

Unless a safe Windows-localization fix is found, this should be documented as
a cosmetic system behavior rather than delaying 0.9.0.

---

# 15. Tests already performed during development

The following scenarios have been exercised successfully during development:

- legacy 5-slider controller detection
- extended 5-slider / 6-button controller detection
- legacy <-> extended controller hot-swap
- repeated USB disconnect/reconnect
- live physical-button status
- simultaneous physical-button states
- per-control soft mute
- media Previous / Play-Pause / Next / Stop
- Windows Volume Up / Down / Mute
- hotkeys including F13 and F14
- hotkey capture
- program/file launch
- folder open
- URL open
- command execution
- six different command actions mapped to six buttons
- tray hide/restore
- startup path synchronization
- start minimized
- RU <-> EN switching
- owner-drawn localization repaint fix
- legacy controller suspend/resume with existing SerialPort recovery
- extended controller operation with the Mugen reference Arduino firmware

---

# 16. Soak-test checklist before release

Do not add new features while this checklist is active.

## Daily use

- [ ] Run dev25 for several normal-use days
- [ ] Keep it resident in the notification area
- [ ] Confirm no unexplained crashes or UI freezes
- [ ] Review logs periodically

## Windows lifecycle

- [ ] Normal Windows restart
- [ ] Cold boot
- [ ] Start with Windows
- [ ] Start minimized to tray
- [ ] Repeated sleep
- [ ] Repeated hibernation
- [ ] Resume after short suspend
- [ ] Resume after long suspend/hibernate

## Legacy controller

- [ ] Detect automatically
- [ ] All configured sliders work
- [ ] Disconnect/reconnect
- [ ] Resume from sleep/hibernate
- [ ] Long-running daily use

## Extended controller

- [ ] Detect automatically
- [ ] Correct slider count
- [ ] Correct button count
- [ ] All sliders work
- [ ] All buttons work
- [ ] Rapid presses
- [ ] Simultaneous presses
- [ ] Disconnect/reconnect
- [ ] Resume from sleep/hibernate
- [ ] Long-running daily use

## Hot-swap

- [ ] legacy -> extended
- [ ] extended -> legacy
- [ ] repeat several times
- [ ] verify button UI appears/disappears correctly
- [ ] verify soft mute cannot remain stuck

## Actions

- [ ] per-control mute
- [ ] Play/Pause
- [ ] Previous
- [ ] Next
- [ ] Stop
- [ ] Windows Volume Up
- [ ] Windows Volume Down
- [ ] Windows Mute
- [ ] ordinary hotkey
- [ ] F13-F24 hotkey
- [ ] launch program
- [ ] open file
- [ ] open folder
- [ ] open URL
- [ ] run command

## Config persistence

- [ ] slider config survives restart
- [ ] button actions survive restart
- [ ] language survives restart
- [ ] theme survives restart
- [ ] startup options survive restart
- [ ] canceling settings does not apply pending changes
- [ ] Save applies pending changes

## UI

- [ ] Russian
- [ ] English
- [ ] Light
- [ ] Dark
- [ ] Auto
- [ ] switch RU <-> EN repeatedly without mouse-hover repaint artifacts
- [ ] button Save notice is visible/readable
- [ ] slider Save/live-position notice is visible/readable
- [ ] diagnostics expand/collapse
- [ ] tray hide/restore

---

# 17. Final cleanup before GitHub release

After soak testing passes, create a clean release build instead of publishing
the development folder directly.

Recommended release cleanup:

- [ ] copy dev25 runtime changes into a clean release branch
- [ ] remove devXX installer files
- [ ] remove devXX backup files
- [ ] remove experimental build notes from the portable runtime
- [ ] change displayed version to `0.9.0`
- [ ] review `button-actions.dev.json` final naming
- [ ] update README
- [ ] add extended-controller documentation
- [ ] add Arduino reference sketch
- [ ] add Arduino wiring/pin notes
- [ ] add button-action documentation
- [ ] add command/hotkey caveats
- [ ] add known cosmetic Windows Shell localization note if still relevant
- [ ] update SHA256 checksums for release files
- [ ] verify LICENSE / third-party notices
- [ ] test the clean release build on both controller types
- [ ] create final Git commit/tag
- [ ] publish GitHub release notes
- [ ] attach the final portable release package through the normal release flow

---

# 18. Suggested public changelog

## Mugen Deej 0.9.0

### Added

- Physical-button support for extended deej controllers
- Automatic legacy/extended controller capability detection
- Live button-state display
- Per-control soft mute actions
- Media Play/Pause, Previous, Next and Stop actions
- Windows Volume Up, Volume Down and Mute actions
- Configurable keyboard hotkeys, including F13-F24
- Keyboard shortcut capture
- Launch program/file action
- Open folder action
- Open URL action
- Run Windows command action
- Modern folder picker
- Mugen Deej extended Arduino reference firmware

### Improved

- Controller hot-swap behavior
- Controller disconnect handling
- Button state initialization
- Tray hide/restore behavior
- Windows startup handling in portable builds
- Suspend/resume serial recovery
- Physical-button configuration UX
- Physical-control configuration UX
- Localization repaint behavior for owner-drawn controls
- Bilingual action descriptions and warnings

### Fixed

- Tray recursion / StackOverflow in an experimental minimize path
- Brief empty-window flash when hiding to tray
- SendInput x64 INPUT-structure sizing issue
- URL action logging variable collision with PowerShell `$Host`
- Old FolderBrowserDialog-based folder selection
- Owner-drawn controls retaining old-language text until hover
- Ambiguous settings UX where pending choices looked immediately active

### Compatibility

Classic slider-only deej controllers remain supported without firmware changes.

---

# 19. Release gate

**0.9.0 is ready to publish when:**

1. dev25 survives the soak checklist without release-blocking failures
2. both legacy and extended controllers are stable in real daily use
3. suspend/hibernate/resume is stable over repeated cycles
4. no config-loss or stuck-action issues appear
5. a clean non-development 0.9.0 portable build is produced and retested

Until then:

**feature freeze stays locked — bug fixes and compatibility fixes only.**

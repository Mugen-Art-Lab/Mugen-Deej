# Mugen Deej — living project state

Last updated: 2026-09-16

This file is the authoritative handoff/state note for active development. Update it whenever a meaningful implementation or hardware-test milestone changes. If an older design note conflicts with this file, this file wins until the older note is revised.

## Stable baseline

- Public release: `v1.0.0`
- Stable branch: `main`
- Stable squash commit: `214273e0c845ba9932544521da856af4a7a4fe24`
- Release page: `https://github.com/Mugen-Art-Lab/Mugen-Deej/releases/tag/v1.0.0`
- Stable runtime: Windows PowerShell 5.1 + small Go launcher.
- Stable 1.0.0 must not be modified while experimental virtual-controller work is being developed.

### 1.0.0 hardware status

PASS — Legacy controller:

- 5 sliders / 0 buttons
- COM detection and reconnect
- real Windows/application volume control
- Setup install
- backup/restore and emergency pre-restore backup
- post-restore visible one-shot launch

PASS — Extended controller:

- 5 sliders / 6 buttons
- real slider/audio control
- physical button actions including mute, play/pause and script launch
- setup/backup/restore paths tested

## Active development branch

- Branch: `feature/virtual-gamepad-ui`
- Base: stable `main` 1.0.0
- Goal: add optional virtual game-controller output while preserving Mugen Deej as a generic, low-cost DIY controller router rather than a game-specific application.

Core model:

```text
physical DIY hardware
        |
        v
Mugen serial protocol
        |
        v
Mugen Deej routing / profiles
   |          |           |
   v          v           v
audio      actions     virtual controller
```

The physical microcontroller should stay simple. Game-specific meaning belongs on the PC side so the same hardware can be reused without reflashing.

## Current protocol / hardware facts

Stable Extended packets are dynamic and currently use fields such as:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

Current parser accepts at most 64 total fields.

Planned experimental hardware:

- 5 analog controls
- 5 x 6 button matrix = 30 buttons
- total Extended packet fields = 35, so this fits the existing parser limit
- Arduino Nano prototype hardware has been ordered
- 30 switches and 1N4148 matrix diodes are planned

NOT TESTED — 5 controls + 30 buttons on real hardware.

Serial bandwidth note: a full 35-field packet is much larger than the current 5+6 packet. At 9600 baud, a roughly 115–120-byte packet takes about 120 ms on the wire with 8N1 framing. The current 60 ms reference-firmware cadence therefore cannot remain unchanged for a 5+30 controller. Before the XL/matrix firmware is finalized, either add a higher configurable baud rate to Mugen Deej or deliberately reduce the full-state packet cadence.

## Virtual controller direction

### Product behavior

Virtual output is optional. Existing audio-only users should not get a surprise game controller.

A physical element can eventually route to one of several destinations. The important distinction is semantic:

- normal button actions are edge-triggered on physical press;
- virtual buttons are stateful and must receive both press and release;
- virtual axes are continuous values.

On disconnect, suspend, backend failure, profile change, app exit, or bridge failure, all virtual buttons must be released and the virtual device must be torn down so a game never sees stuck or orphaned input.

**A reboot requirement for normal creation/removal/recovery is not acceptable product behavior.** Mugen is expected to coexist with long-running PCs, sleep/hibernate cycles, and unrelated uptime tests. Any backend or integration path that routinely needs Windows restart for virtual-controller teardown is a blocker, not an acceptable cleanup instruction.

### Compatibility modes

Planned user-facing virtual-controller types:

- `Xbox 360 / XInput` — compatibility-first profile for modern games; fixed Xbox-style control set.
- `Generic / DirectInput` — arbitrary DIY controller shape for simulator panels, many buttons and custom axes.

Possible later presets can sit on top of those controller types, for example Arcade/Fight Pad. A preset is not necessarily a different backend.

### Backend research / prototype decision

Current prototype backend: HIDMaestro 1.8.0.

Why it is being tested:

- active project;
- MIT license;
- user-mode UMDF2 implementation;
- built-in Xbox 360 profile;
- supports DirectInput/XInput/GameInput/WGI/SDL-visible virtual devices;
- SDK can also build arbitrary custom HID controllers with chosen button/axis counts.

Pinned release archive SHA-256:

`1e5f5019c20e4be8f922c7aa5a86ee87eb01f7aa851fe38daea14d0ce4fd8240`

Important constraint verified from HIDMaestro source: Windows requires elevation both to install its driver and to create virtual controllers. Therefore the prototype uses an elevated helper process and a named-pipe bridge instead of elevating the whole Mugen Deej UI.

HIDMaestro also supports overriding the joy.cpl / DirectInput display label through `HMOemNameOverride.Set(...)`, and custom profiles can define their own `Name` / `ProductString`. For Xbox/XInput mode, a custom joy.cpl label does not change the fact that games see an Xbox-compatible XInput device. The override is per VID:PID, so it is not a unique per-instance identity and can affect another device with the same VID:PID while active.

## Current implementation milestone: prototype 0

The first build intentionally does NOT modify stable `MugenDeej.ps1`. It is a separate development harness in the feature branch so the backend can be proven before invasive UI/runtime integration.

Files:

- `src/virtual-gamepad-helper/` — .NET 10 x64 elevated helper using HIDMaestro.
- `tools/Prepare-HIDMaestro.ps1` — downloads HIDMaestro 1.8.0, verifies the pinned archive hash, extracts the SDK DLL/license for the build.
- `dev/virtual-gamepad/Mugen-VirtualGamepad-Prototype.ps1` — serial bridge test harness.
- `dev/virtual-gamepad/RUN-VIRTUAL-GAMEPAD-PROTOTYPE.cmd` — test launcher.
- `dev/virtual-gamepad/RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd` — explicit live cleanup launcher.
- `.github/workflows/build-virtual-gamepad-prototype.yml` — isolated prototype artifact build.

Prototype behavior:

```text
Extended controller over COM @ 9600
        |
        v
prototype PowerShell bridge
        |
        v named pipe
Elevated MugenDeej.VirtualGamepadHost
        |
        v HIDMaestro 1.8.0
Virtual Xbox 360 controller
        |
        v
joy.cpl / game
```

First six physical buttons are temporarily mapped as:

1. A
2. B
3. X
4. Y
5. Left Bumper
6. Right Bumper

### Prototype 0 build status

PASS — CI build/package smoke test.

Latest cleanup-hardened package:

- workflow run: `35110165971` / run number `8`
- head: `98902bebf7b7eaaf84e52b904348836cff295da6`
- artifact: `Mugen-Deej-VirtualGamepad-Prototype-8`
- artifact ID: `10452027277`
- inner ZIP SHA-256: `37bebc2cc315f2cb54dc0a87b359cd1f4a6866f66f249d4b40e3cb9738173cfa`

Changes in this build:

- helper command `cleanup` calls `HMContext.RemoveAllVirtualControllers(preserveInstall: true)`;
- normal helper exit now runs the same preserve-install sweep as a teardown backstop after controller/context disposal;
- bridge disconnect is logged explicitly;
- packaged `RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd` elevates and runs the cleanup command without uninstalling the backend.

### Prototype 0 real-hardware status

CORE INPUT PATH PASS / TEARDOWN BEHAVIOR NOT YET ACCEPTABLE.

Confirmed with the existing 5-control / 6-button Extended controller on COM10:

- Extended controller detection: PASS
- elevated helper startup: PASS
- HIDMaestro virtual Xbox 360 creation: PASS
- `joy.cpl` sees `Controller (XBOX 360 For Windows)` with OK status: PASS
- physical buttons 1–6 all drive virtual button activity: PASS
- hold state over several seconds: PASS
- immediate release: PASS
- multiple simultaneous button holds and independent releases: PASS

Observed bridge masks included `0x01`, `0x02`, `0x04`, `0x08`, `0x10`, and `0x20`.

Known teardown findings:

- hard-closing the terminal can leave the virtual controller enumerated after the bridge/helper process disappears;
- exiting with `Q` released input state, but Windows later reported restart-required for the virtual Xbox device;
- repeated full close/reopen of `joy.cpl` did not remove the entry, so this was not a stale applet cache;
- the user is deliberately maintaining a multi-day hibernation/uptime test and rebooting just to clean a virtual controller is explicitly unacceptable;
- current recovery target is therefore live cleanup on the running Windows session, not reboot-based recovery.

Next test: use prototype build 8's `RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd` against the currently orphaned controller. If it removes the controller immediately, mark the emergency cleanup path PASS and then retest normal exit/hard-close behavior with the new exit sweep. If it still leaves Windows pending reboot, HIDMaestro's Xbox teardown path is not suitable as-is and needs deeper investigation or a backend change before product integration.

Remaining before Prototype 0 is fully PASS:

- explicit cleanup removes current orphan without reboot;
- normal Q/Esc teardown removes the virtual controller immediately;
- hard-close/bridge-loss recovery removes the virtual controller without reboot;
- at least one successful button bind in a real game.

Full attempt-by-attempt history is in `docs/VIRTUAL_CONTROLLER_TEST_LOG.md`.

## Profiles: planned architecture

Terminology:

- **Profile** = a complete user configuration for the connected control surface.
- **Preset** = an optional built-in template used to create a profile, such as Xbox Gamepad, Arcade Pad, 30-button DirectInput, Streaming.

For Extended controllers, the main UI may eventually show:

```text
Profile: [ Desktop v ]  [ Manage... ]
```

Profile management should support:

- New
- Duplicate
- Rename
- Delete
- Select from drop-down

A permanent `Default` profile must preserve current Mugen Deej behavior and provide migration from 1.0.0 without breaking existing users.

A profile should eventually own the full logical routing of the device, including:

- button actions;
- analog-control destinations;
- virtual-controller enabled state;
- virtual-controller type (`Xbox 360 / XInput`, `Generic / DirectInput`);
- virtual button/axis mappings;
- controller shape metadata such as detected control/button counts;
- virtual-controller display name where the selected backend/profile supports it safely.

If a profile was created for 5+30 hardware and a 5+6 controller is connected, Mugen should warn that unavailable mappings will be skipped rather than fail. Extra physical controls not present in the profile should default to unassigned.

Manual profile switching comes first. Automatic switching by foreground game/process is deferred until manual profiles are reliable.

## Planned integration after prototype 0

1. Resolve no-reboot teardown behavior, add explicit cleanup, and verify hard-close recovery.
2. Prove a real game accepts the virtual Xbox controller input.
3. Add a minimal virtual-controller service abstraction to Mugen Deej.
4. Integrate `virtual:button:N` mappings into Extended button settings.
5. Route virtual button state from `Update-ButtonStates`, not the press-only action dispatcher.
6. Add safe release on disconnect/suspend/app exit/backend failure.
7. Add `Virtual axis` mode for analog controls.
8. Build a custom Generic/DirectInput profile for many-button hardware and test 30 buttons.
9. Add user profiles and profile management.
10. Rework the 30-button UI into a matrix/grid only after real 5x6 hardware proves useful.

## Deferred / explicitly not first-pass work

- game telemetry back to LEDs/displays;
- bidirectional simulator panels;
- force feedback;
- custom Mugen kernel/UMDF driver;
- automatic game/profile switching;
- layers/pages for static-keycap hardware;
- OLED/LCD per-key displays;
- plugin marketplace/ecosystem;
- matrix-layout designer.

## Design principles to preserve

- Stable Legacy behavior must remain intact.
- Extended remains auto-detected; do not make users manually toggle a protocol mode.
- Hardware should remain cheap and simple; intelligence lives in Mugen Deej.
- Static/custom keycaps or printed labels are preferred over expensive per-key displays for the low-cost deck concept.
- Do not call theoretical support a PASS. Code inspection and calculated limits are not hardware validation.
- Keep experimental work off `main` until it has passed real hardware smoke tests.
- Update this file after each major implementation/test result so a new chat can resume from the repository without reconstructing context.

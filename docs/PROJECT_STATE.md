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

HIDMaestro supports overriding the joy.cpl / DirectInput display label through `HMOemNameOverride.Set(...)`. Current Xbox/XInput label:

`Mugen Deej Virtual Gamepad`

This is presentation only; it does not change Xbox/XInput compatibility. The override is scoped by VID:PID, so another real Xbox 360-compatible device with the same VID/PID can temporarily share the label while the Mugen virtual is active. Mugen must not use the display string as its internal device identity.

## Current implementation milestone: prototype 0

The prototype intentionally does NOT modify stable `MugenDeej.ps1`. It is a separate development harness used to prove the backend before invasive runtime/UI integration.

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
joy.cpl / XInput-aware game
```

First six physical buttons are temporarily mapped as:

1. A
2. B
3. X
4. Y
5. Left Bumper
6. Right Bumper

### Current build status

- neutral-axis implementation commit: `487592fe3a23986bfb3a9be63754a92a651e5ef2`
- naming lifecycle implementation commit: `540648f6680cc2b37667cb7fe95b83ea71112ad7`
- naming workflow run: `35114290248` / run number `10`
- CI result: PASS

The naming helper lifecycle:

- startup calls `HMOemNameOverride.RecoverOrphans()` before claiming a new label;
- live virtual is labelled `Mugen Deej Virtual Gamepad` in joy.cpl / DirectInput;
- clean teardown calls `HMOemNameOverride.Clear(...)`;
- explicit cleanup also recovers orphaned OEM-name overrides.

### Prototype 0 real-hardware status

PASS so far on the existing 5-control / 6-button Extended controller on COM10:

- Extended controller detection
- elevated helper startup
- virtual Xbox 360 creation
- `joy.cpl` enumeration/status OK
- display label `Mugen Deej Virtual Gamepad`
- physical buttons 1–6 drive virtual button activity
- hold state over several seconds
- immediate release
- simultaneous button holds and independent releases
- explicit no-reboot orphan cleanup
- hard-close / bridge-loss device cleanup without reboot
- explicit neutral startup axes / triggers / POV
- first real packet reports `Buttons mask: 0x00`
- HardwareTester GamepadTester detects the virtual as `xinput`, connected, standard mapping
- right-side face buttons and both bumper mappings respond in the XInput tester
- `Cult of the Lamb` reacts to the virtual gamepad in a real game session

The last point is a **REAL-GAME INPUT PASS**. It proves an XInput-aware game accepts physical Mugen input routed through the virtual backend. It is not yet a claim that an in-game remapping screen successfully stored a custom bind.

Observed bridge masks include `0x00`, `0x01`, `0x02`, `0x04`, `0x08`, `0x10`, `0x20`, and multi-button combinations such as `0x21` / `0x31`.

### Remaining before Prototype 0 is fully PASS

- normal Q/Esc teardown on the latest naming build removes the device immediately and restores the prior OEM label;
- one fresh hard-close on the naming build confirms both device teardown and OEM-name recovery behave without reboot.

If both pass, the standalone backend proof is complete enough to move into the real Mugen Deej runtime/UI.

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

1. Finish latest naming-build teardown/name-recovery validation.
2. Add a minimal virtual-controller service abstraction to Mugen Deej.
3. Integrate `virtual:button:N` mappings into Extended button settings.
4. Route virtual button state from `Update-ButtonStates`, not the press-only action dispatcher.
5. Add safe release on disconnect/suspend/app exit/backend failure.
6. Add `Virtual axis` mode for analog controls.
7. Add user profiles and profile management: New / Duplicate / Rename / Delete / select from dropdown.
8. Store virtual-controller enabled state/type and virtual mappings per profile.
9. Build a custom Generic/DirectInput profile for many-button hardware and test 30 buttons.
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

# Mugen Deej — living project state

Last updated: 2026-09-16

This file is the authoritative handoff/state note for active development. Update it whenever a meaningful implementation or hardware-test milestone changes. If an older design note conflicts with this file, this file wins until the older note is revised.

## Stable baseline

- Public release: `v1.0.0`
- Stable branch: `main`
- Stable squash commit: `214273e0c845ba9932544521da856af4a7a4fe24`
- Release page: `https://github.com/Mugen-Art-Lab/Mugen-Deej/releases/tag/v1.0.0`
- Stable runtime: Windows PowerShell 5.1 + small Go launcher.
- Stable 1.0.0 must not be modified while experimental virtual-controller work is developed.

### Stable hardware status

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
- Goal: add optional virtual game-controller output while preserving Mugen Deej as a generic low-cost DIY controller router.

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

The microcontroller should stay simple. Game-specific meaning belongs on the PC side so the same hardware can be reused without reflashing.

## Current protocol / hardware facts

Stable Extended packets are dynamic, for example:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

Current parser accepts at most 64 total fields.

Planned experimental hardware:

- 5 analog controls
- 5 x 6 switch matrix = 30 buttons
- total Extended packet fields = 35, which fits the parser limit
- Arduino Nano prototype hardware has been ordered
- 1N4148 matrix diodes are planned

NOT TESTED — 5 controls + 30 buttons on real hardware.

Serial bandwidth note: a full 35-field packet is much larger than the current 5+6 packet. At 9600 baud a roughly 115–120-byte packet takes about 120 ms on the wire with 8N1 framing, so the current 60 ms full-state cadence cannot remain unchanged for 5+30 hardware. Before the matrix firmware is finalized, either add a higher configurable baud rate or deliberately reduce the full-state cadence.

## Virtual controller direction

### Product behavior

Virtual output is optional. Existing audio-only users must not get a surprise game controller.

Element semantics:

- normal button actions are edge-triggered on press;
- virtual buttons are stateful and require press + release;
- virtual axes are continuous values.

On disconnect, suspend, backend failure, profile change, app exit or bridge failure, all virtual input must be released and the virtual device must be torn down.

**Reboot requirement for normal creation/removal/recovery is not acceptable product behavior.** Live cleanup without reboot is a hard requirement.

### Planned compatibility modes

- `Xbox 360 / XInput` — compatibility-first mode for modern games; fixed Xbox-style control set.
- `Generic / DirectInput` — arbitrary DIY controller shape for simulator panels, many buttons and custom axes.

Possible later presets can sit on top of those controller types, e.g. Arcade/Fight Pad. A preset is not necessarily a different backend.

## Backend choice under test

Current backend: HIDMaestro 1.8.0.

Why it is being used:

- active project;
- MIT license;
- user-mode UMDF2 implementation;
- built-in Xbox 360 profile;
- supports XInput/DirectInput/GameInput/WGI/SDL-visible devices;
- SDK can also build arbitrary custom HID controllers with chosen button/axis counts.

Pinned release archive SHA-256:

`1e5f5019c20e4be8f922c7aa5a86ee87eb01f7aa851fe38daea14d0ce4fd8240`

Important verified constraint: Windows requires elevation to install the HIDMaestro driver and to create virtual controllers. Therefore Mugen uses an elevated helper process with a named-pipe bridge instead of elevating the whole UI.

Current Xbox/XInput display label:

`Mugen Deej Virtual Gamepad`

This is presentation only; it does not change XInput compatibility. The OEM-name override is VID:PID scoped, so another real device with the same Xbox VID/PID can temporarily share the label. Mugen must never use the display name as its internal identity.

## Prototype 0 — completed backend proof

The standalone prototype intentionally does not modify stable `MugenDeej.ps1`. It exists to prove the backend/cleanup architecture before real UI integration.

Important files:

- `src/virtual-gamepad-helper/` — .NET 10 x64 elevated helper using HIDMaestro
- `tools/Prepare-HIDMaestro.ps1` — pinned SDK preparation
- `dev/virtual-gamepad/Mugen-VirtualGamepad-Prototype.ps1` — serial bridge harness
- `dev/virtual-gamepad/RUN-VIRTUAL-GAMEPAD-PROTOTYPE.cmd`
- `dev/virtual-gamepad/RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd`
- `.github/workflows/build-virtual-gamepad-prototype.yml`

Temporary 5+6 button mapping:

1. A
2. B
3. X
4. Y
5. Left Bumper
6. Right Bumper

### Prototype 0 final result

**PASS — backend proof complete enough to move into the real Mugen runtime/UI.**

Hardware-tested with the existing Extended 5-control / 6-button controller on COM10:

- Extended detection: PASS
- elevated helper startup: PASS
- virtual Xbox 360 creation: PASS
- `joy.cpl` enumeration/status: PASS
- display name `Mugen Deej Virtual Gamepad`: PASS
- neutral startup axes/triggers/POV: PASS
- first real state packet `Buttons mask: 0x00`: PASS
- physical buttons 1–6: PASS
- hold/release state: PASS
- simultaneous button combinations: PASS
- emergency live orphan cleanup without reboot: PASS
- hard-close / bridge-loss cleanup without reboot: PASS
- normal Q/Esc cleanup without reboot: PASS after teardown fix
- HardwareTester detection as XInput, connected, standard mapping: PASS
- real-game recognition/input in `Cult of the Lamb`: PASS

Observed button masks include `0x00`, `0x01`, `0x02`, `0x04`, `0x08`, `0x10`, `0x20`, and combinations such as `0x21` / `0x31`.

Important implementation commits:

- `487592fe3a23986bfb3a9be63754a92a651e5ef2` — explicit neutral axis initialization
- `540648f6680cc2b37667cb7fe95b83ea71112ad7` — crash-safe display-name override lifecycle
- `e887e4ac857c40f53566dd82e3ed0ad7c1b4a09e` — normal teardown uses bridge-disconnect cleanup path and waits for helper completion

Latest validated prototype build:

- workflow run `35118021710`
- run number `11`
- artifact `Mugen-Deej-VirtualGamepad-Prototype-11`
- artifact ID `10456900609`
- CI: PASS
- real normal-Q teardown retest: PASS; controller disappeared and did not reappear

Detailed attempt-by-attempt history: `docs/VIRTUAL_CONTROLLER_TEST_LOG.md`.

The standalone harness should now be treated as a proven development fixture, not as the product UI.

## Profiles: planned architecture

Terminology:

- **Profile** = complete user configuration for a connected control surface.
- **Preset** = optional built-in template used to create a profile, e.g. Xbox Gamepad, Arcade Pad, 30-button DirectInput, Streaming.

Planned Extended-controller UI concept:

```text
Profile: [ Desktop v ]  [ Manage... ]
```

Profile management should support:

- New
- Duplicate
- Rename
- Delete
- Select from dropdown

A permanent `Default` profile must preserve current Mugen Deej behavior and provide safe migration from 1.0.0.

A profile should eventually own:

- button actions;
- analog-control destinations;
- virtual-controller enabled state;
- virtual-controller type (`Xbox 360 / XInput`, `Generic / DirectInput`);
- virtual button/axis mappings;
- controller-shape metadata such as detected control/button counts;
- virtual-controller display name where safe/supported.

If a profile was created for 5+30 hardware and a 5+6 controller is connected, Mugen should warn that unavailable mappings will be skipped rather than fail. Extra physical controls not present in the profile default to unassigned.

Manual profile switching comes first. Automatic game/process switching is deferred.

## Next implementation phase

1. Add a minimal virtual-controller service abstraction to real Mugen Deej.
2. Keep virtual output disabled by default so 1.0.0 behavior remains unchanged.
3. Add `Xbox 360 / XInput` controller mode using the proven elevated helper architecture.
4. Integrate virtual-button mappings into Extended button settings.
5. Route virtual button state from the state-update path, not the press-only action dispatcher.
6. Preserve safe release on disconnect/suspend/app exit/backend failure/profile change.
7. Add virtual-axis routing for analog controls.
8. Add user profiles and management: New / Duplicate / Rename / Delete / select.
9. Store virtual-controller enabled/type/mappings per profile.
10. Build a custom Generic/DirectInput virtual profile for many-button hardware.
11. Test future 5+30 matrix hardware physically.
12. Rework 30-button UI into a matrix/grid only after real matrix hardware proves useful.

## Deferred / not first pass

- automatic game/profile switching;
- telemetry back to LEDs/displays;
- bidirectional simulator panels;
- force feedback;
- custom Mugen kernel/UMDF driver;
- layers/pages for static-keycap hardware;
- OLED/LCD per-key displays;
- plugin marketplace/ecosystem;
- matrix-layout designer.

## Design principles

- Stable Legacy behavior must remain intact.
- Extended remains auto-detected; do not make users manually toggle a protocol mode.
- Hardware should remain cheap/simple; intelligence lives in Mugen Deej.
- Static/custom keycaps or printed labels are preferred over expensive per-key displays for the low-cost deck concept.
- Do not call theoretical support a PASS. Code inspection and calculated limits are not hardware validation.
- Keep experimental work off `main` until real-hardware smoke tests pass.
- Update this file after each major implementation/test milestone so a new chat can resume from the repository without reconstructing context.

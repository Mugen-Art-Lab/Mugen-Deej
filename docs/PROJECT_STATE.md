# Mugen Deej — living project state

Last updated: 2026-09-17

This is the authoritative short handoff for active development. Detailed prototype history is in `docs/VIRTUAL_CONTROLLER_TEST_LOG.md`; current product-integration work is in `docs/VIRTUAL_GAMEPAD_INTEGRATION.md`.

## Stable baseline

- Public release: `v1.0.0`
- Stable branch: `main`
- Stable squash commit: `214273e0c845ba9932544521da856af4a7a4fe24`
- Release page: `https://github.com/Mugen-Art-Lab/Mugen-Deej/releases/tag/v1.0.0`
- Runtime: Windows PowerShell 5.1 + small Go launcher.
- Stable v1.0.0 stays frozen while virtual-controller work is developed in a feature branch.

Hardware-tested stable behavior:

- Legacy: 5 sliders / 0 buttons — PASS.
- Extended: 5 sliders / 6 buttons — PASS.
- Real audio control, Extended button actions, Setup, backup/restore and release packaging — PASS.

## Active branch

`feature/virtual-gamepad-ui`

Goal: keep Mugen Deej a generic low-cost DIY controller router while adding optional game-controller output on the PC side.

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

The microcontroller should remain simple. The same physical hardware should be reusable without reflashing when the user changes what controls mean.

## Protocol / future hardware facts

Extended packets are dynamic, e.g.:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

The current parser accepts at most 64 total fields.

Planned matrix prototype:

- 5 analog controls;
- 5×6 switch matrix = 30 buttons;
- 35 total packet fields, within the parser limit;
- Arduino Nano-class hardware;
- 1N4148 diodes for the switch matrix.

5+30 is **NOT hardware-tested yet**.

Bandwidth warning: a roughly 115–120 byte full-state packet needs about 120 ms at 9600 baud with 8N1, so the current 60 ms cadence cannot be reused unchanged. Before final matrix firmware, add configurable/higher baud or deliberately lower the full-state cadence.

## Virtual controller architecture

Virtual output is optional and must be OFF by default for existing users.

Semantics:

- ordinary Mugen button actions are press-edge-triggered;
- virtual buttons are stateful (press + hold + release);
- virtual axes are continuous.

Cleanup requirement: disconnect, app exit, bridge failure, backend failure, profile switch and hard-close must never leave stuck input or an orphaned gamepad. Reboot as a normal recovery path is unacceptable.

Planned user-facing modes:

- `Xbox 360 / XInput` — compatibility-first, fixed Xbox control set;
- `Generic / DirectInput` — arbitrary DIY shapes, many buttons and custom axes.

Current backend: HIDMaestro 1.8.0.

Why it is currently accepted for development:

- active project;
- MIT license;
- user-mode UMDF2;
- built-in Xbox 360 profile;
- supports XInput/DirectInput/GameInput/WGI/SDL visibility;
- SDK can create custom HID layouts.

Pinned HIDMaestro release archive SHA-256:

`1e5f5019c20e4be8f922c7aa5a86ee87eb01f7aa851fe38daea14d0ce4fd8240`

Windows elevation is required for the virtual HID operations, so Mugen keeps its UI unelevated and uses an elevated helper connected by a named pipe.

Current Xbox display label:

`Mugen Deej Virtual Gamepad`

The label is presentation only and must not be used as internal identity; HIDMaestro's OEM-name override is VID:PID-scoped.

## Prototype 0 — backend proof

**PASS / COMPLETE ENOUGH FOR PRODUCT INTEGRATION.**

Real hardware: existing Extended 5-control / 6-button controller on COM10.

Hardware-proven:

- Extended detection;
- elevated helper startup;
- Xbox/XInput virtual device creation;
- `joy.cpl` enumeration;
- display name `Mugen Deej Virtual Gamepad`;
- neutral axes/triggers/POV;
- stateful press/hold/release;
- simultaneous button combinations;
- emergency live orphan cleanup without reboot;
- hard-close / bridge-loss cleanup without reboot;
- normal Q/Esc teardown without reboot;
- HardwareTester recognition as XInput / standard mapping;
- real-game recognition/input in `Cult of the Lamb`.

Important commits:

- `487592fe3a23986bfb3a9be63754a92a651e5ef2` — explicit neutral axes.
- `540648f6680cc2b37667cb7fe95b83ea71112ad7` — crash-safe display-name lifecycle.
- `e887e4ac857c40f53566dd82e3ed0ad7c1b4a09e` — safe normal teardown using proven bridge-disconnect cleanup.

Latest validated standalone prototype:

- workflow run `35118021710`, run #11;
- artifact ID `10456900609`;
- CI PASS;
- normal Q teardown hardware PASS.

The standalone harness is now a development fixture, not the intended product UI.

## Integrated product milestone 1 — current work

Status: **PARTIAL REAL-HARDWARE PASS / NONBLOCKING STARTUP HARDWARE RE-TEST PENDING.**

The integrated development build routes the proven Xbox backend through the actual Mugen Deej Button Settings/runtime while leaving the stable source/release untouched.

Current integrated behavior:

- virtual output defaults to `Off`;
- Button Settings gains `Virtual controller: Off / Xbox 360 / XInput`;
- physical gamepad mappings use a dedicated Xbox-button picker instead of a long flat action list;
- virtual actions are stateful and are fed from `Update-ButtonStates` before press-edge detection;
- virtual mappings do not fall through to the old press-only action executor;
- controller disconnect tears down the virtual gamepad;
- normal helper teardown uses the proven no-force-kill cleanup lifecycle;
- setting is temporarily stored in `virtual-controller.json` next to the app;
- dev builds suppress Windows startup registration so they cannot steal the stable app's HKCU Run path;
- analog virtual axes, D-pad, triggers, DirectInput and Profiles are not in this milestone yet.

First integrated real-hardware attempt exposed two bugs:

1. Helper startup was reentrant because `Start-MugenVirtualGamepad` used `Application.DoEvents()` while waiting for UAC/helper connection. Full-state serial packets could re-enter startup before the first helper became active, spawning dozens of helpers and starving COM processing until the controller timed out/reconnected.
2. The stable v1.0.0 `Normalize-ButtonActions` function did not know `virtual:xbox:*`, so capability re-detection rewrote valid virtual mappings to `none`.

Fixes:

- `aafb1c85784568228023e659bbeae4c0543e5fe1` — single-start guard for the virtual helper;
- `d255724b6e75e980289ad03cab38591b0690ff6a` — preserve virtual mappings through normalization using literal source patching;
- `5bc2fee8db9a98c130b288a4142a4c88c9d0921a` — CI reports PowerShell parser errors correctly instead of using the read-only `$Error` variable.

Run #10 real-hardware re-test proved the catastrophic integration bugs fixed:

- only one elevated helper startup;
- COM10 remained connected;
- `Mugen Deej Virtual Gamepad` enumerated in `joy.cpl` with neutral axes;
- A/B mappings worked and remained present when Button Settings was reopened;
- adding another mapping after the virtual gamepad was already active was responsive.

Remaining UX issue from run #10: the first virtual-controller creation blocked the Mugen UI for about 16.8 seconds while HIDMaestro/Windows completed HID/PnP setup. The user observed the device notification before Mugen became responsive again.

Nonblocking startup fix:

- `7308b73f2507d795cb1a0fd4c43dce11bb8ea5cc` — replace the synchronous `DoEvents()` / sleep wait loop with `BeginWaitForConnection` plus a WinForms timer, so startup is pending in the background while the UI and serial processing remain responsive.

Latest integration CI:

- run #11 `35133757062`: **PASS**;
- head: `7308b73f2507d795cb1a0fd4c43dce11bb8ea5cc`;
- Windows PowerShell 5.1 parse check: PASS;
- helper publish/smoke test: PASS;
- launcher build/package: PASS;
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-11`;
- artifact ID: `10462991104`;
- inner dev ZIP SHA-256: `d7e082d69f87bf0e73393760a7dfcf466c64ad7ddf88db00578988dfb761258e`.

Do not call the startup-lag issue hardware PASS until run #11 is exercised on the physical Extended controller.

Implementation files:

- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.ps1`
- `tools/Build-VirtualGamepad-Integration.ps1`
- `tools/Harden-VirtualGamepad-DevRuntime.ps1`
- `.github/workflows/build-virtual-gamepad-integration.yml`

The build-time patcher is temporary. Once the integrated path is hardware-proven, consolidate it into normal source before any release/merge, then remove the experimental patch chain.

Detailed current test plan: `docs/VIRTUAL_GAMEPAD_INTEGRATION.md`.

## Profiles — planned architecture

Terminology:

- **Profile** = complete user configuration for a connected control surface.
- **Preset** = optional template used to create a profile, e.g. Xbox Gamepad, Arcade Pad, 30-button DirectInput, Streaming.

Planned UI concept:

```text
Profile: [ Desktop v ]  [ Manage... ]
```

Profile management:

- New;
- Duplicate;
- Rename;
- Delete;
- select from dropdown.

A permanent `Default` profile must preserve migrated 1.0.0 behavior.

Eventually a profile owns:

- ordinary button actions;
- analog destinations;
- virtual controller enabled/type;
- virtual button/axis mappings;
- controller-shape metadata;
- optional safe display-name settings.

Hardware mismatch must degrade gracefully: a 5+30 profile used with 5+6 hardware skips unavailable mappings; extra physical controls default unassigned.

Manual profile switching comes first. Automatic switching by game/process is deferred.

## Next steps

1. Hardware-test run #11 and verify the Mugen UI stays responsive throughout first XInput creation.
2. Confirm COM10 remains stable while virtual startup is pending and exactly one helper is launched.
3. Reopen/reconnect and confirm saved virtual mappings remain intact.
4. Verify normal close and one hard-close cleanup from the integrated runtime.
5. Re-check a real XInput game from the integrated runtime.
6. After PASS, consolidate integration into normal source and remove the temporary runtime patcher.
7. Add analog control → virtual axis routing.
8. Introduce Profiles and move virtual config/mappings into them.
9. Add Generic / DirectInput.
10. Build/test the future 5+30 matrix controller.

## Deferred

- automatic game/profile switching;
- telemetry back to LEDs/displays;
- bidirectional simulator panels;
- force feedback;
- custom Mugen driver;
- layers/pages;
- OLED/LCD per-key displays;
- plugin marketplace;
- matrix-layout designer.

## Design principles

- Do not break stable Legacy behavior.
- Extended stays auto-detected.
- Hardware stays cheap/simple; intelligence lives in Mugen Deej.
- Static/custom keycaps or printed labels remain preferred for the low-cost deck idea.
- Do not call theoretical/code-inspection support a PASS.
- Experimental work stays off `main` until real-hardware smoke tests pass.
- Keep this file and the integration/test notes current so a new chat can resume from the repository.

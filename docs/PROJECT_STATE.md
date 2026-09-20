# Mugen Deej — living project state

Last updated: 2026-09-19

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

### Current active milestone

Integrated **#101** is the current hardware-review build. Foreground application profiles cover ordinary momentary buttons plus Adaptive toggles/encoders, and physical buttons can now act as stateful digital Xbox stick directions (left/right stick, four cardinal directions each). Release returns the virtual axis to center; opposite directions cancel to center; Xbox buttons and stick directions are submitted as one coherent state.

Profile switching is based on the **effective profile**. A dedicated game profile -> unprofiled window transition becomes Game -> Global and neutralizes state. Moving between two unprofiled applications remains Global -> Global and does not reset merely because the foreground process changed. Any physical input held across a real profile boundary is suppressed until release so it cannot become a synthetic action in the new profile. This explicitly covers multi-monitor borderless-fullscreen workflows where focus changes by mouse click as well as Alt+Tab/Win+Tab.

Backward compatibility remains deliberate: Legacy has no buttons and is unchanged; Extended and Adaptive can use the same PC-side button/profile layer without firmware changes; `button-actions.json` remains Global; old #89/#90 profiles without `buttons` inherit Global; backup v1 and older v2 shapes remain accepted. Digital stick mappings are stored as ordinary button-action strings, so #101 does not require a backup schema bump.

See `docs/CURRENT_HANDOFF.md` for #101 run/artifact hashes and the exact real-machine test sequence.

The first large physical cardboard panel is now wired for Uno bring-up as a 4x8 matrix: 28 momentary buttons, 2 matrix toggles, and a separate S1/S2/KEY encoder module. A dedicated Adaptive v3 sketch exposes 5 temporary software sliders + 28 buttons + 2 toggles + 1 encoder/push at 115200. Hardware validation is pending before the same wiring is migrated to Nano and real potentiometers.

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

Windows elevation is required for the virtual HID operations, so Mugen keeps its UI unelevated and uses an elevated helper connected by a named pipe. A UAC prompt may or may not be visible depending on the Windows/UAC configuration.

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

Status: **PARTIAL REAL-HARDWARE PASS / NONBLOCKING TEARDOWN HARDWARE RE-TEST PENDING.**

The integrated development build routes the proven Xbox backend through the actual Mugen Deej Button Settings/runtime while leaving the stable source/release untouched.

Hardware/UI proven so far:

- virtual output defaults to `Off`;
- Button Settings exposes `Virtual controller: Off / Xbox 360 / XInput`;
- Xbox buttons are assigned through a dedicated visual picker;
- virtual mappings survive reopening Button Settings and controller capability re-detection;
- stateful virtual button output works through the real integrated runtime;
- one helper is launched instead of the original reentrant helper storm;
- COM10 stays connected while virtual output starts;
- first virtual-controller creation is nonblocking: the UI remains responsive during the roughly 16.6-second HID/PnP creation window;
- main-window virtual status row is bilingual and only appears while virtual output is enabled;
- status transitions `connecting -> connected` were visually verified in RU and EN;
- dev builds suppress Windows startup registration so they cannot steal the stable app's HKCU Run path.

The first integrated attempt exposed and fixed two major bugs:

1. helper startup reentrancy spawned many elevated helpers and starved COM processing;
2. the stable action normalizer rejected `virtual:xbox:*` and rewrote mappings to `none`.

Important integration fixes:

- `aafb1c85784568228023e659bbeae4c0543e5fe1` — single-start guard;
- `d255724b6e75e980289ad03cab38591b0690ff6a` — preserve virtual mappings through normalization;
- `7308b73f2507d795cb1a0fd4c43dce11bb8ea5cc` — nonblocking virtual-controller startup;
- `049e5d1a88ee4437897e5356a64fc5bf5dbe7117` — conditional main-window virtual-controller status;
- `e3eadbfa70db0c078f6149e7f07ddc19014629dd` / `c39f4fb31a259905d99a63fb1e7c3d29d2ef497f` — dev-stage nonblocking teardown overlay and packaging.

### Current teardown finding

Disabling virtual output and exiting Mugen still froze the UI for about 10.3 seconds in run 12. Logs proved the delay is real HIDMaestro/controller disposal, not the final orphan sweep:

- disable at `00:54:58.362`;
- helper `STOP` at `00:54:58.368`;
- `OEM_NAME_CLEARED` at `00:55:08.630`;
- `EXIT_SWEEP_DONE` at `00:55:08.645`;
- Mugen returned from stop at `00:55:08.678`.

Normal app exit showed the same ~10.3-second wait.

The visible freeze was caused by Mugen synchronously calling `WaitForExit(30000)` while the helper performed cleanup. Run 14 replaces that UI-thread wait with background helper reaping. It also prevents a new virtual controller from starting until the previous helper finishes cleanup, avoiding a create/remove race if the user toggles the feature quickly.

A secondary helper-log issue remains: after successful cleanup, disposing an already-broken pipe writer can log `System.IO.IOException: Pipe is broken` as `FATAL`. Cleanup has already completed, so this is log noise rather than evidence of an orphan, but it should be cleaned up before release.

Latest integration CI:

- run #14 `35138005925`: **PASS**;
- head: `c39f4fb31a259905d99a63fb1e7c3d29d2ef497f`;
- Windows PowerShell 5.1 parse check: PASS;
- nonblocking startup/teardown static checks: PASS;
- helper publish/smoke: PASS;
- launcher build/package: PASS;
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-14`;
- artifact ID: `10463797250`;
- inner dev ZIP SHA-256: `4581329c6065f14f7de08704ef9006650d9c413527d25549f290692e9b267ddb`.

Do not call nonblocking teardown a hardware PASS until run #14 is exercised on the physical Extended controller.

Implementation files:

- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.ps1`
- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.AsyncStop.ps1` — temporary dev-stage teardown override;
- `tools/Build-VirtualGamepad-Integration.ps1`
- `tools/Harden-VirtualGamepad-DevRuntime.ps1`
- `.github/workflows/build-virtual-gamepad-integration.yml`

The build-time patcher/overlay is temporary. Once the integrated path is hardware-proven, consolidate it into normal source before any release/merge, then remove the experimental patch chain.

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

1. Hardware-test run #14: disable virtual output and confirm Save returns immediately while the gamepad disappears in the background.
2. Exit Mugen with the virtual gamepad active and confirm the Mugen window/process closes promptly while helper cleanup continues independently.
3. Re-enable immediately after disabling once and verify the new controller waits for old HID cleanup rather than racing it.
4. Confirm no orphaned gamepad remains after the background cleanup and no reboot is required.
5. Clean up the helper's expected broken-pipe disposal being logged as `FATAL`.
6. Reopen/reconnect and confirm saved virtual mappings remain intact.
7. Re-check a real XInput game from the integrated runtime.
8. After milestone 1 PASS, consolidate integration into normal source and remove temporary runtime patchers/overlays.
9. Add analog control → virtual axis routing.
10. Introduce Profiles and move virtual config/mappings into them.
11. Add Generic / DirectInput.
12. Build/test the future 5+30 matrix controller.

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
- Cardboard Uno prototype matrix hardware PASS: after correcting the row wiring to parallel shared buses (one diode per switch, no series-chained row diodes), all 28 momentary buttons register correctly in Mugen. The prior C5..C8 failure was physical matrix wiring, not Uno pins or desktop parsing.

- Full digital cardboard-panel smoke test PASS: 28 buttons, 2 toggles, and encoder/push work on real Uno hardware; a >20-button simultaneous hold also registered cleanly. Five slider channels remain software placeholders pending real potentiometers.


## Current hardware-review build — Integrated #124

#122 real-machine review confirmed backup restore/restart remains healthy and the localized Russian overwrite dialog works. D-pad assignments were created and persisted as ordinary virtual action strings; explicit joy.cpl D-pad output evidence is still pending.

#124 adds digital full-press Xbox triggers: a physical button mapped to LT or RT drives that analog trigger to 100% while held and back to 0% on release. This deliberately matches the current digital stick-direction model. Analog potentiometer -> trigger routing remains future work.

The virtual helper state frame now carries buttons, four stick directions, D-pad X/Y, LT and RT. The picker top row is `LT | LB | RB | RT`. No backup schema bump is required because LT/RT remain ordinary `virtual:xbox:*` action strings in the existing button mapping containers.

#124 also refines the main status card: physical and virtual rows share an aligned text column and tighter row geometry, the XInput toggle is centered over the full two-row card, and virtual status uses the same middle-dot separator style as the physical summary.

The product subtitle is broadened from the audio-only wording to `Настольный центр управления` / `Desktop control hub`.

Run #124 (ID `35504754125`) succeeded at code head `f8bc133d8e41678ad9dcb3906038386e8b867f5a`; artifact ID `10603432810`; outer digest `sha256:d3d286c7d8aacf8e2a6e5c1408f5d4ef3a5e6e08e35b5392ee7bec276fc1a315`; inner ZIP SHA-256 `51adb7e3f7fa51a6191de06fc4bddb4a704074b61ecb3444224223f1e9693bf7`.

#124 is CI PASS for the new trigger/status/subtitle slice. LT/RT real-machine output, revised status composition, and subtitle acceptance are pending.

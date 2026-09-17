# Mugen Deej — current development handoff

Last updated: 2026-09-18

This is the short resume point for the active `feature/virtual-gamepad-ui` branch. Keep it current after meaningful implementation, CI, UI, or hardware-test changes.

For deeper history see `docs/PROJECT_STATE.md`, `docs/VIRTUAL_GAMEPAD_INTEGRATION.md`, `docs/VIRTUAL_CONTROLLER_TEST_LOG.md`, and `docs/PROTOCOL.md`.

## Stable baseline

- Public/stable release: `v1.0.0`
- Stable branch: `main`
- Stable behavior must remain untouched while feature work is validated.
- Legacy hardware: 5 analog controls, no buttons — hardware PASS.
- Extended hardware: 5 analog controls + 6 buttons — hardware PASS.

## Active direction

1. Preserve Legacy and Extended compatibility.
2. Keep optional PC-side virtual Xbox/XInput output.
3. Add Adaptive v3 as a self-describing typed-input protocol for larger DIY control surfaces.
4. Keep mapping intelligence in Mugen Deej so hardware does not need reflashing when assignments change.
5. Keep the main window compact even for larger Adaptive controllers.

## Protocol generations

- `Legacy` — old numeric-only full-state packets.
- `Extended` — typed slider/button packets such as `s512|...|b1|b0`.
- `Adaptive v3` — packets begin with `v3` and expose first-class control types:
  - `sN` analog control;
  - `bN` momentary button;
  - `tN` latching toggle;
  - `ePOSITION[:PUSH]` rotary encoder with cumulative signed position and optional push switch.

Encoder position is cumulative so a missed serial packet does not permanently lose a detent.

## Current Adaptive Uno test fixture

Firmware: `arduino/MugenDeejUnoAdaptiveTest/MugenDeejUnoAdaptiveTest.ino`

Synthetic shape:

- 5 analog controls;
- 29 momentary buttons;
- 2 toggles;
- 1 rotary encoder with push;
- 115200 baud;
- full-state packet every 25 ms.

Temporary Uno bench pins:

- D2 — momentary button;
- D3 / D4 — toggles;
- D5 — encoder push;
- D6 / D7 — synthetic encoder direction steps.

## Adaptive transport status

Real Uno on COM14: **PASS for detection/transport**.

Observed repeatedly on the real machine:

`protocol=adaptive; sliders=5; buttons=29; toggles=2; encoders=1`

The five analog values display correctly as 0%, 25%, 50%, 75%, 100%.

Do not call live D3–D7 interaction a complete hardware PASS until those physical pin tests are performed.

## Adaptive UI history

### #25

First functional typed-control UI worked after fixing a PowerShell `$Host` variable collision, but it looked blocky: toggle states resembled ordinary buttons and encoder push was a detached `Кнопка` tile.

### #28

Presentation was redesigned into small switch metaphors plus a drawn rotary knob with cumulative numeric position. Real screenshot feedback was positive, but the owner-drawn controls visibly flickered; one screenshot caught the encoder during a missing repaint frame.

### #29

Flicker/push revision:

- owner-drawn toggle/encoder indicators are double-buffered;
- repaint happens only when state, position, push, surface, or theme actually changes, not on every 25 ms packet;
- detached `Кнопка / Push` chip removed;
- pressing an encoder now highlights the encoder knob itself.

CI #29: SUCCESS.

### #30 — compact main UI revision

Physical buttons, toggles, and encoders now share one main status card.

For the current 29-button / 2-toggle / 1-encoder fixture:

- two wrapped rows of button tiles;
- one compact row beneath them containing both toggles and the encoder;
- RU title: `Состояние кнопок и переключателей`;
- EN title: `Buttons and controls`.

The old separate `Тумблеры и энкодеры` card is hidden and consumes no layout height.

`Подключение и диагностика / Connection and diagnostics` now opens a separate dialog instead of expanding the main window vertically. The dialog reparents the existing connection/driver/log controls so their existing state and handlers are reused.

Relevant patchers:

- `tools/Polish-AdaptiveInputStatusUi.ps1`
- `tools/Revise-AdaptiveMainUi.ps1`
- staging hook: `tools/Run-OptimizedLargeButtonSettings.ps1`

## Integrated #30 real-machine observation

Integrated #30 was run on the real machine and the compact revision is visually successful:

- main window is substantially shorter;
- 29 buttons, 2 toggles and 1 encoder fit in one combined card;
- separate diagnostics dialog opens correctly;
- main-window height no longer grows when diagnostics are opened;
- previous switch/encoder flicker is no longer visible during idle observation;
- encoder is represented by the knob itself, with no detached push button.

Log from the same run is clean with respect to Adaptive detection and the UI revision:

- fresh dev config was created normally;
- COM1 opened but did not speak Mugen protocol at 9600/115200;
- COM3, COM4 and COM13 were busy/access-denied and put on the normal 60-second retry path;
- COM14 appeared later as a newly detected port;
- Mugen probed COM14 at 9600, then 115200;
- Adaptive capabilities were detected as 5/29/2/1;
- controller connected successfully on COM14 at 115200;
- no exception or UI error was logged after detection.

The launcher log for this run contains only the normal launcher-start marker; no launcher-side failure was recorded.

## Current successful build

Workflow: `Build virtual gamepad integration`

Current test build:

- run number: **#30**
- run ID: `35262142312`
- head: `ebd4a051e0aacadfb619ede863f888f1e246ef69`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-30`
- artifact ID: `10515023574`
- outer Actions digest: `sha256:eac9414389e61176ef74d79d2ce30bcf0e015b0e162c9ba8371f932c4a10b8ee`
- inner program ZIP SHA-256: `6b1751030e84cb49726987f2e3680f5b8651f36358f68dd86deab13b373fb12a`
- PowerShell 5.1 parse check: PASS
- launcher/package: PASS

## Immediate next hardware/UI test

The structural/UI #30 test is now substantially proven. Remaining physical-input checks:

1. Ground D3 / D4 and verify each toggle switch changes independently.
2. Pulse D6 / D7 and verify encoder cumulative position moves in opposite directions and the marker rotates.
3. Ground D5 and verify the encoder knob itself highlights only while held.
4. Ground D2 and verify ordinary button state still updates independently.
5. Close/reopen the diagnostics dialog and exercise reconnect/refresh/manual-port controls once.
6. Switch RU/EN while connected and verify compact card/dialog labels relocalize correctly.
7. Disconnect/reconnect the Uno and verify no stale or duplicate typed controls appear.

Do not convert live toggle/encoder interaction into full hardware PASS until D3–D7 are exercised.

## Virtual Xbox integration status

The optional HIDMaestro-backed Xbox/XInput integration remains staged in this branch.

Already hardware-proven before Adaptive work:

- one-helper startup guard;
- real XInput device creation;
- joy.cpl visibility;
- neutral axes;
- press/hold/release and simultaneous button combinations;
- mapping persistence;
- nonblocking first-time startup;
- bilingual main-window virtual-controller status;
- real-game recognition in `Cult of the Lamb`.

Nonblocking teardown code exists and has CI coverage, but its final real-hardware re-test remains pending in the older integration notes.

## Known history / notes

- Run #24 failed after Adaptive detection because encoder UI used local `$host`, colliding case-insensitively with PowerShell's read-only `$Host`. Fixed in `6dd026e5668eb4f7c9a79f0316a546588cb8c69d`.
- The old setup-go cache warning was cleaned up by pointing cache dependency handling at `src/launcher/go.mod`.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- Do not call code inspection or CI alone a hardware PASS.
- Keep Legacy and Extended behavior intact while adding Adaptive.
- Adaptive controls remain first-class types; do not flatten toggles/encoders into fake momentary buttons.
- Encoder transport uses cumulative signed position.
- For changes that trigger GitHub Actions: wait for the final result, fix/rebuild if needed, then provide the successful artifact directly instead of making the tester hunt through Actions.
- After meaningful code changes, CI findings, UI observations, or hardware observations, update this handoff before moving on.

# Mugen Deej — current development handoff

Last updated: 2026-09-18

This file is the short resume point for the active `feature/virtual-gamepad-ui` branch. Keep it current after meaningful implementation or hardware-test changes so a new chat/session can continue without reconstructing the project from conversation history.

For older background and detailed history, see:

- `docs/PROJECT_STATE.md`
- `docs/VIRTUAL_GAMEPAD_INTEGRATION.md`
- `docs/VIRTUAL_CONTROLLER_TEST_LOG.md`
- `docs/PROTOCOL.md`

## Stable baseline

- Public/stable release: `v1.0.0`
- Stable branch: `main`
- Stable behavior must remain untouched while feature work is validated.
- Legacy hardware: 5 analog controls, no buttons — hardware PASS.
- Extended hardware: 5 analog controls + 6 buttons — hardware PASS.

## Active branch

`feature/virtual-gamepad-ui`

Current direction:

1. Keep Legacy and Extended compatibility.
2. Add optional PC-side virtual controller output.
3. Add Adaptive v3 as a self-describing typed-input protocol for larger DIY control surfaces.
4. Keep intelligence in Mugen Deej so hardware does not need reflashing when mappings change.

## Protocol generations

### Legacy

Old numeric-only full-state packets.

### Extended

Typed slider/button packets such as `s512|...|b1|b0`.

### Adaptive v3

Packets begin with `v3` and report controls as first-class types:

- `sN` — analog control;
- `bN` — momentary button;
- `tN` — latching toggle;
- `ePOSITION[:PUSH]` — rotary encoder with cumulative signed position and optional push switch.

Encoder position is cumulative rather than a one-packet CW/CCW pulse so a missed serial packet does not permanently lose a detent.

## Current Adaptive Uno test fixture

Firmware:

`arduino/MugenDeejUnoAdaptiveTest/MugenDeejUnoAdaptiveTest.ino`

Current synthetic shape:

- 5 analog controls;
- 29 momentary buttons;
- 2 toggles;
- 1 rotary encoder with push;
- 115200 baud;
- full-state packet every 25 ms.

Useful temporary Uno pins for bench testing:

- D2 — momentary button;
- D3 / D4 — toggles;
- D5 — encoder push;
- D6 / D7 — synthetic encoder direction steps.

Grounding those pins is enough for transport/UI testing before the real encoder and final panel arrive.

## Adaptive transport hardware status

Real Uno test on COM14: **PASS for detection/transport**.

Observed in the real Mugen runtime:

`protocol=adaptive; sliders=5; buttons=29; toggles=2; encoders=1`

The five analog values also appeared correctly in the main UI (0%, 25%, 50%, 75%, 100%).

This proves the current 115200 autodetection and Adaptive capability parser on real hardware.

## Adaptive high-button-count UI

Large controllers no longer use one endlessly wide/scrolling button strip or one heavy editor row per button.

Current staged behavior:

- main window uses a wrapped grid for many physical buttons;
- large Button Settings uses lightweight numbered selector tiles plus one shared action editor;
- pressing a physical button can auto-select its numbered tile;
- an assignment overview remains fixed-height rather than creating 30+ full editor rows.

## Toggle / encoder live status UI

### First functional version — hardware/UI observation

Integrated #25 successfully launched on the real Adaptive Uno after the `$Host` fix. The main window showed:

- the 29-button wrapped grid;
- a `Тумблеры и энкодеры` block;
- two toggle states;
- one encoder cumulative position;
- a separate encoder push tile.

So typed-control UI construction is now real-hardware/UI proven enough to proceed. However, the first presentation was intentionally functional and the tester judged it visually too blocky/top-heavy: toggle states looked like ordinary buttons and the encoder line (`1 ↺ 0 ↻` plus another rectangular `Кнопка`) did not visually read as a physical rotary control.

### Polished presentation now staged

New patcher:

`tools/Polish-AdaptiveInputStatusUi.ps1`

It runs after `Apply-AdaptiveInputStatusUi.ps1` and changes presentation only; Adaptive transport semantics stay unchanged.

New design:

- each toggle is shown as a real switch metaphor rather than a button tile;
- toggle number is a plain label;
- switch track moves left/right and uses the normal Mugen accent when ON;
- adjacent state text is `Вкл / Выкл` (`On / Off`), not shouty all-caps button text;
- each encoder is shown with a small drawn rotary knob;
- the knob marker rotates one 15-degree step per cumulative detent so direction/movement is visible;
- the cumulative signed position is still shown numerically and remains the source of truth;
- encoder push remains a separate `Кнопка / Push` state chip and lights only while physically held;
- layout remains dynamic for multiple toggles/encoders;
- the typed-control block remains hidden for hardware without those capabilities.

Important implementation note: endless encoders have no absolute min/max. The visual knob therefore wraps its marker every 24 detents; it is only a movement cue. The numeric cumulative position is authoritative.

## `$Host` collision history

Run #24 produced a WinForms/.NET unhandled exception after Adaptive detection because the first encoder UI used local variable `$host`. PowerShell variable names are case-insensitive, so that collided with the built-in read-only `$Host` automatic variable.

The transport had already been correctly detected as Adaptive 5/29/2/1; the failure was UI construction only.

Fix commit:

`6dd026e5668eb4f7c9a79f0316a546588cb8c69d`

Run #25 then succeeded and launched correctly on the real Uno.

The old compatibility repair in `Run-OptimizedLargeButtonSettings.ps1` expected exactly eight `$host` references in the staged encoder block. Once the polished UI already used `$encoderItemHost`, run #26 correctly exposed that stale assumption and failed staging with `expected 8 $host references, found 0`. The compatibility guard is now tolerant of either old unsafe staged code (repair it) or already-safe newer code (skip the repair).

## Current successful build

Workflow: `Build virtual gamepad integration`

Latest polished build:

- run number: **#28**
- run ID: `35259422264`
- head: `c3cbf3fb7cc612c9dab7f352541964d01634f708`
- result: **SUCCESS**
- staged Adaptive protocol: PASS
- polished toggle/encoder UI staging: PASS
- Windows PowerShell 5.1 parse check: PASS
- launcher/package: PASS

The setup-go cache warning seen in earlier runs is also cleaned up by explicitly using `src/launcher/go.mod` as the cache dependency path.

Run #28 supersedes #25 for the next UI test.

## Immediate next hardware test

With the Uno Adaptive test firmware still loaded:

1. Launch Integrated #28 and confirm the polished typed-control block appears after COM14 detection.
2. Confirm the two toggles now look like switches rather than ordinary buttons.
3. Ground D3 / D4 and verify each switch moves and changes `Вкл / Выкл` independently.
4. Pulse D6 / D7 and verify the numeric encoder position moves in opposite directions and the small knob marker rotates.
5. Ground D5 and verify only the `Кнопка` chip lights while held, then returns to idle on release.
6. Ground D2 and verify ordinary button state still updates independently.
7. Switch RU/EN while connected and verify typed-control labels relocalize correctly.
8. Disconnect/reconnect the Uno and verify the typed-control block is rebuilt correctly without stale values or duplicate controls.
9. Judge the visual proportions/spacing on the real main window; further polish is allowed before mapping UI work.

Do not call live toggle/encoder interaction a complete hardware PASS until D3–D7 behavior is physically exercised.

## Virtual Xbox integration status

The existing optional HIDMaestro-backed Xbox/XInput integration remains staged in this same branch.

Already hardware-proven before Adaptive work:

- one-helper startup guard;
- real XInput device creation;
- joy.cpl visibility;
- neutral axes;
- press/hold/release and simultaneous button combinations;
- mapping persistence;
- nonblocking first-time startup;
- main-window bilingual virtual-controller status;
- real-game recognition in `Cult of the Lamb`.

Nonblocking teardown code exists and has CI coverage, but its final real-hardware re-test is still pending in the older integration milestone notes. Do not silently convert that pending item into PASS.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- Do not call code inspection or CI alone a hardware PASS.
- Keep Legacy and Extended behavior intact while adding Adaptive.
- Adaptive controls are first-class types; do not flatten toggles/encoders back into fake momentary buttons.
- Encoder transport uses cumulative signed position.
- For changes that trigger GitHub Actions: wait for the final workflow result, fix/rebuild if needed, then provide the successful artifact directly rather than making the tester hunt through Actions manually.
- After meaningful code changes, CI findings, or hardware observations, update this handoff (and the deeper integration/protocol docs when appropriate) before moving on.

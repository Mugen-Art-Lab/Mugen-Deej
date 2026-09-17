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

This proves the current 115200 autodetection and Adaptive capability parser on real hardware. It does **not** yet prove live toggle/encoder UI interaction; that is the immediate next hardware test.

## Adaptive high-button-count UI

Large controllers no longer use one endlessly wide/scrolling button strip or one heavy editor row per button.

Current staged behavior:

- main window uses a wrapped grid for many physical buttons;
- large Button Settings uses lightweight numbered selector tiles plus one shared action editor;
- pressing a physical button can auto-select its numbered tile;
- an assignment overview remains fixed-height rather than creating 30+ full editor rows.

## Toggle / encoder live status UI

A new main-window block is staged for Adaptive typed controls.

Design:

- group title RU: `Тумблеры и энкодеры`;
- group title EN: `Toggles and encoders`;
- toggle tiles show `1 · ВКЛ` / `1 · ВЫКЛ` (`ON` / `OFF` in English);
- active toggle uses the normal Mugen accent color;
- encoder position is shown as a cumulative value, e.g. `1   ↺ 0 ↻`;
- encoder push is a separate `Кнопка` / `Push` tile;
- the push tile lights only while physically held;
- no awkward `нажатие отпущено` wording is used;
- layout is dynamic for multiple toggles/encoders and wraps to more rows when needed;
- the whole block is hidden when the connected controller reports no toggles/encoders.

Implementation patcher:

`tools/Apply-AdaptiveInputStatusUi.ps1`

## Run #24 hardware finding

CI run #24 succeeded, but real launch after Adaptive detection produced a WinForms/.NET unhandled exception.

Root cause:

The new encoder UI used local variable `$host` for a panel. PowerShell variable names are case-insensitive, so this collided with the built-in read-only `$Host` variable and threw:

`SessionStateUnauthorizedAccessException: Cannot overwrite variable Host because it is read-only or constant.`

Important point: the exception happened **after** the controller had already been correctly identified as Adaptive 5/29/2/1, so this was UI construction only, not a serial/protocol failure.

## Current fix / build

Fix commit:

`6dd026e5668eb4f7c9a79f0316a546588cb8c69d`

Change:

- rename the encoder panel variable from `$host` to `$encoderHost` in the staged runtime patcher.

Integrated build:

- workflow: `Build virtual gamepad integration`
- run number: **#25**
- run ID: `35258185903`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-25`
- artifact ID: `10513084569`
- outer Actions digest: `sha256:6d1c6a16e8887156fa464fed75509c258ad48841da4400905c0d550fbdf12579`

Run #25 is the build to use for the next Adaptive hardware/UI test. Run #24 should be considered superseded because of the `$Host` collision.

## Immediate next hardware test

With the Uno Adaptive test firmware still loaded:

1. Launch Integrated #25 and confirm no .NET exception after COM14 detection.
2. Confirm the normal button grid appears for all 29 buttons.
3. Confirm the new `Тумблеры и энкодеры` block appears.
4. Ground D3 and D4 one at a time and verify the two toggle tiles visibly change between ВКЛ/ВЫКЛ.
5. Ground D5 and verify only the encoder `Кнопка` tile lights while held, then returns to idle on release.
6. Pulse D6 / D7 and verify the encoder cumulative position moves in opposite directions without losing state.
7. Ground D2 and verify ordinary button state still updates independently.
8. Switch RU/EN while connected and verify the typed-control labels relocalize correctly.
9. Disconnect/reconnect the Uno and verify the typed-control block is rebuilt correctly without stale values or duplicate controls.

Do not call toggle/encoder UI hardware PASS until these checks are performed on the physical Uno.

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

## Known CI warning

`actions/setup-go` can show a yellow cache warning because it looks for `go.mod` at the repository root while the launcher module actually lives at:

`src/launcher/go.mod`

This warning does not fail the build. It can later be cleaned up by setting the setup-go cache dependency path explicitly. Avoid changing the workflow only for cosmetic reasons in the middle of a hardware test unless another build is already needed.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- Do not call code inspection or CI alone a hardware PASS.
- Keep Legacy and Extended behavior intact while adding Adaptive.
- Adaptive controls are first-class types; do not flatten toggles/encoders back into fake momentary buttons.
- Encoder transport uses cumulative signed position.
- For changes that trigger GitHub Actions: wait for the final workflow result, fix/rebuild if needed, then provide the successful artifact directly rather than making the tester hunt through Actions manually.
- After meaningful code changes, CI findings, or hardware observations, update this handoff (and the deeper integration/protocol docs when appropriate) before moving on.

# Mugen Deej — current development handoff

Last updated: 2026-09-18

This file is the short resume point for the active `feature/virtual-gamepad-ui` branch. Keep it current after meaningful implementation, CI, UI, or hardware-test changes so a new chat/session can continue without reconstructing the project from conversation history.

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
2. Keep optional PC-side virtual Xbox/XInput output.
3. Add Adaptive v3 as a self-describing typed-input protocol for larger DIY control surfaces.
4. Keep intelligence in Mugen Deej so mappings can change without reflashing hardware.
5. Keep the main UI compact enough that larger Adaptive controllers do not turn the app into a tall scrolling/expanding window.

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

The five analog values appeared correctly in the main UI (0%, 25%, 50%, 75%, 100%). The 29-button wrapped grid and typed toggle/encoder state UI also constructed successfully on the real machine after the earlier `$Host` fix.

Do not call live D3–D7 interaction a complete hardware PASS until the physical pin tests below are performed.

## Adaptive high-button-count UI

Large controllers no longer use one endlessly wide/scrolling button strip or one heavy editor row per button.

Current staged behavior:

- main window uses a wrapped grid for many physical buttons;
- large Button Settings uses lightweight numbered selector tiles plus one shared action editor;
- pressing a physical button can auto-select its numbered tile;
- assignment overview remains fixed-height instead of creating 30+ full editor rows.

## Typed toggle / encoder UI evolution

### Integrated #25

The first real-hardware functional UI showed the 29-button grid plus a separate `Тумблеры и энкодеры` card. It worked after the `$Host` collision was fixed, but looked too blocky: toggle states resembled ordinary buttons and the encoder was represented by a position tile plus a detached `Кнопка` tile.

### Integrated #28

Presentation was redesigned:

- toggles became small switch metaphors with `Вкл / Выкл` (`On / Off`);
- encoder became a small drawn rotary knob with a rotating marker;
- cumulative signed position remained visible numerically;
- the visual knob marker wraps every 24 detents because an endless encoder has no absolute min/max.

Real screenshot feedback: this presentation looked much better, but the owner-drawn switches/encoder visibly flickered. A screenshot even caught the rotary control during a frame where it had disappeared.

### Integrated #29

Flicker fix and encoder-push simplification:

- owner-drawn Adaptive indicators are double-buffered;
- switches/knob are invalidated only when state, position, push, surface, or theme actually changes instead of every 25 ms packet;
- the detached `Кнопка / Push` chip was removed;
- pressing an encoder now highlights the encoder knob itself, which better matches the physical control.

Run #29 CI: **SUCCESS**.

Relevant patcher:

`tools/Polish-AdaptiveInputStatusUi.ps1`

## Compact main-window UI revision

The next real screenshot showed another structural problem: with Adaptive controls present, expanding `Подключение и диагностика` made the main window taller than a normal Full HD working area.

Decision: do not solve this by adding a scrollbar to the entire main window. Reformat instead.

New staged layout in Integrated #30:

- physical buttons, toggles, and encoders now share one main status card;
- RU title when buttons + typed controls are present: `Состояние кнопок и переключателей`;
- EN title: `Buttons and controls`;
- for the current 29-button / 2-toggle / 1-encoder fixture, toggles and encoder share one compact row under the two-row button grid;
- larger typed-control counts automatically fall back to stacked rows;
- the old dedicated `Тумблеры и энкодеры` card stays hidden and consumes no layout height;
- the main window no longer expands vertically for diagnostics.

New patcher:

`tools/Revise-AdaptiveMainUi.ps1`

Staging hook:

`tools/Run-OptimizedLargeButtonSettings.ps1`

### Connection and diagnostics

`Подключение и диагностика / Connection and diagnostics` is now intended to open a separate fixed dialog instead of expanding an accordion inside the main window.

The dialog reuses the existing connection and driver/log controls rather than duplicating their state/event logic. Closing it reparents those controls back to the hidden compatibility panel.

This keeps the main window height stable while leaving room for future diagnostics additions such as raw protocol information, baud rate, packet timing, firmware information, etc.

## `$Host` collision history

Run #24 produced a WinForms/.NET unhandled exception after Adaptive detection because the first encoder UI used local variable `$host`. PowerShell variable names are case-insensitive, so that collided with the built-in read-only `$Host` automatic variable.

The transport had already been correctly detected as Adaptive 5/29/2/1; the failure was UI construction only.

Fix commit:

`6dd026e5668eb4f7c9a79f0316a546588cb8c69d`

Run #25 then succeeded and launched correctly on the real Uno.

The old compatibility repair later had to become tolerant of already-safe `$encoderItemHost` code; run #26 exposed that stale assumption and the guard was fixed before the polished builds continued.

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
- Adaptive protocol staging: PASS
- flicker/push-visual patch staging: PASS
- compact combined-input layout staging: PASS
- separate diagnostics-dialog staging: PASS
- Windows PowerShell 5.1 parse check: PASS
- launcher/package: PASS

Run #30 supersedes #28/#29 for the next hardware/UI test.

## Immediate next hardware/UI test

With the Uno Adaptive test firmware still loaded:

1. Launch Integrated #30 and confirm COM14 still detects as Adaptive 5/29/2/1.
2. Confirm buttons, toggles, and encoder are now inside one status card instead of two stacked cards.
3. Confirm the current 2 toggles + 1 encoder share one compact row below the button grid and the main window is visibly shorter.
4. Watch the two toggle switches and rotary knob while idle for several seconds; confirm the previous 25 ms flicker/disappearing-frame problem is gone.
5. Ground D3 / D4 and verify each switch moves and changes `Вкл / Выкл` independently.
6. Pulse D6 / D7 and verify encoder position changes in opposite directions and the knob marker rotates.
7. Ground D5 and verify the encoder knob itself highlights while held; there should be no separate `Кнопка` chip.
8. Ground D2 and verify ordinary button state still updates independently.
9. Click `Подключение и диагностика` and verify a separate dialog opens while the main window height remains unchanged.
10. Test reconnect/refresh/manual-port controls inside that dialog, then close and reopen it once to verify control reparenting remains healthy.
11. Switch RU/EN while connected and verify the compact status-card labels relocalize correctly.
12. Disconnect/reconnect the Uno and verify no stale/duplicate typed controls appear.

Do not convert these pending hardware/UI observations into PASS until they are actually exercised on the real machine.

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

## CI note

The old setup-go cache warning was cleaned up by explicitly using `src/launcher/go.mod` as the cache dependency path.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- Do not call code inspection or CI alone a hardware PASS.
- Keep Legacy and Extended behavior intact while adding Adaptive.
- Adaptive controls are first-class types; do not flatten toggles/encoders back into fake momentary buttons.
- Encoder transport uses cumulative signed position.
- For changes that trigger GitHub Actions: wait for the final workflow result, fix/rebuild if needed, then provide the successful artifact directly rather than making the tester hunt through Actions manually.
- After meaningful code changes, CI findings, UI observations, or hardware observations, update this handoff (and deeper integration/protocol docs when appropriate) before moving on.

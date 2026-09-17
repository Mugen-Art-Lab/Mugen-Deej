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
6. Treat the current Uno fixture as one topology, not a hardcoded product shape: future DIY firmware may report different counts of analog controls, buttons, toggles and encoders.

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

## Adaptive transport + live-input hardware status

Real Uno on COM14: **PASS** for Adaptive detection, transport and live typed-control interaction.

Observed repeatedly on the real machine:

`protocol=adaptive; sliders=5; buttons=29; toggles=2; encoders=1`

The five analog values display correctly as 0%, 25%, 50%, 75%, 100%.

Physical bench exercise after Integrated #30:

- ordinary test button path reported working;
- toggle 1 and toggle 2 both changed state correctly;
- synthetic encoder steps moved cumulative position in both directions;
- encoder push highlighted the encoder itself and released correctly;
- the polished owner-drawn controls did not visibly flicker during the test.

The runtime log independently confirms repeated toggle state transitions, signed encoder movement in both directions, and encoder push press/release events. This closes the earlier D3–D7 hardware-validation gap for the current Uno test fixture.

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
- previous switch/encoder flicker is no longer visible;
- encoder is represented by the knob itself, with no detached push button;
- physical toggle, encoder movement and encoder-push interaction all work on the Uno fixture.

Log from the same session is clean with respect to Adaptive detection and the UI revision:

- COM14 is detected as Adaptive 5/29/2/1 at 115200;
- toggle state changes are logged correctly;
- encoder delta and cumulative position are logged correctly in both directions;
- encoder push press/release is logged correctly;
- no exception or UI error follows these events.

## Scalable UI rule for arbitrary Adaptive controllers

Do not assume the current 5/29/2/1 topology in future UI work. Adaptive v3 is intentionally self-describing, so the Windows UI must derive its layout from the capabilities actually reported by firmware.

Recommended policy for custom/community controllers:

- small and medium control counts: wrap dynamically in the combined main status card;
- keep per-control visuals lightweight (button tile, toggle switch, encoder knob + numeric position);
- never let arbitrary firmware make the main window grow without bound;
- give the combined status card a practical maximum height;
- if a topology exceeds that compact budget, show a concise overflow affordance such as `Ещё N… / N more…` and open a dedicated full controller-state view with its own scrolling/wrapping;
- settings/editors remain separate from the live main-window summary;
- diagnostics should report the detected topology explicitly so unusual DIY firmware is easy to understand.

This allows projects such as 0 sliders + many buttons, many toggles, several encoders, or mixed custom panels without changing the PC-side protocol parser or hardcoding new layouts per device.

## Diagnostics expansion direction

The new separate diagnostics dialog now has room to grow without affecting main-window height. Useful next read-only controller information:

- connected COM port;
- detected protocol generation;
- active baud rate;
- analog/button/toggle/encoder counts;
- connection mode (automatic/manual);
- latest packet age / connection freshness;
- optional packet/update rate if measured cheaply;
- virtual-controller state where relevant.

Do not display firmware version/identity unless a future protocol extension actually supplies those fields.

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

## Immediate next work

The current Uno Adaptive transport and live-input UI are hardware-proven enough to move on from basic state validation.

Next useful work:

1. Expand the separate diagnostics dialog with detected protocol/topology/baud/freshness information.
2. Make the main combined status card explicitly safe for arbitrary larger Adaptive topologies (bounded compact layout + overflow/full-state view).
3. Add first-class mapping/configuration behavior for toggles and encoders instead of only displaying their live state.
4. Re-test RU/EN switching and disconnect/reconnect after further UI changes.
5. Keep the current 5/29/2/1 Uno fixture as the regression test, not as a hardcoded UI assumption.

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
- Do not hardcode the current Uno control counts into generic Adaptive UI behavior.
- For changes that trigger GitHub Actions: wait for the final result, fix/rebuild if needed, then provide the successful artifact directly instead of making the tester hunt through Actions.
- After meaningful code changes, CI findings, UI observations, or hardware observations, update this handoff before moving on.

# Mugen Deej Uno Adaptive v3 topology test

This folder contains the bare-Arduino regression fixture for **Adaptive v3**. It can now boot into several controller shapes so the Windows client can be tested as a genuinely self-describing UI rather than only against the current 5/29/2/1 prototype.

Adaptive remains syntax-selected: packets begin with `v3`, followed by any supported combination of `s`, `b`, `t`, and `e` fields. The fixture sends only normal state packets; it does not print a banner that could confuse protocol probing.

## Topology selector

D8 and D9 use `INPUT_PULLUP` and are sampled once during `setup()`. Set them before reset/power-up:

| D8 | D9 | Adaptive shape | Purpose |
| --- | --- | --- | --- |
| open | open | 5 sliders / 29 buttons / 2 toggles / 1 encoder | Current full regression fixture |
| GND | open | 0 sliders / 8 buttons / 4 toggles / 2 encoders | Prove zero-slider Adaptive + mixed typed input |
| open | GND | 2 sliders / 0 buttons / 0 toggles / 0 encoders | Prove fewer sliders and no discrete-input card |
| GND | GND | 0 sliders / 0 buttons / 12 toggles / 6 encoders | Prove bounded main summary + overflow/full-state view |

The selected topology stays fixed until the Arduino is reset again. This deliberately makes reconnect tests deterministic.

## Live test pins

D2..D7 keep the original fixture behavior wherever the selected topology contains that family:

| Pin | Test input | Open | Short to GND |
| --- | --- | --- | --- |
| D2 | first momentary button | released | pressed |
| D3 | first toggle | OFF | ON |
| D4 | second toggle | OFF | ON |
| D5 | first encoder push | released | pressed |
| D6 | first encoder CW test | idle | one falling edge adds `+1` |
| D7 | first encoder CCW test | idle | one falling edge adds `-1` |

Additional buttons/toggles/encoders in the larger synthetic profiles remain deterministic and idle. They exist to test topology/layout capacity on a bare board, not to emulate a fully wired panel.

## Packet semantics

- `s0..1023` — analog control;
- `b0/b1` — momentary button (`0 = pressed`, `1 = released`);
- `t0/t1` — logical toggle (`0 = OFF`, `1 = ON`);
- `ePOSITION[:PUSH]` — signed cumulative encoder position; optional push reuses button semantics.

Encoder 1 carries the optional push field. Additional synthetic encoders in this fixture report position only.

The heartbeat remains **25 ms** at **115200 baud**, so a healthy diagnostics view should settle near roughly 40 packets/second while the controller is idle.

## Expected Windows-client behavior

### Profile 0 — 5 / 29 / 2 / 1

This is the existing hardware regression shape. The compact combined button/toggle/encoder card should look essentially like Integrated #30, with the normal five-regulator section above it.

### Profile 1 — 0 / 8 / 4 / 2

This is the important zero-slider case:

- Adaptive v3 must still auto-detect successfully;
- regulator status must disappear from the main window;
- `Configure controls` / regulator settings must disappear;
- buttons, toggles and encoders remain visible;
- diagnostics must report zero sliders rather than fabricating the old configured expectation.

### Profile 2 — 2 / 0 / 0 / 0

Only two regulator rows should appear. There should be no button/toggle/encoder status card and no button-settings control.

### Profile 3 — 0 / 0 / 12 / 6

The main window must remain bounded. It should show a compact typed-control summary plus `Show all… / Показать все…`; the full-state window should expose all 12 toggles and all 6 encoders.

## Why these profiles exist

The current Mugen prototype happens to be 5/29/2/1, but Adaptive is not a hardware SKU. Community firmware may legally report different counts, omit entire control families, or build a panel around mostly toggles/encoders.

These profiles are therefore regression cases for a capability-driven desktop UI. They should not change Legacy or Extended behavior.

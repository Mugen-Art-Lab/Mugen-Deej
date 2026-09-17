# Mugen Deej Uno Adaptive v3 test

This folder contains a bare-Arduino fixture for the third Mugen serial protocol generation: **Adaptive v3**.

It is intentionally separate from the proven Extended transport fixture and from the future full Nano panel firmware.

## Why Adaptive exists

Mugen currently understands two older protocol generations:

1. **Legacy** — raw numeric values such as `512|200|900`;
2. **Extended** — typed slider/button fields such as `s512|s200|b1|b0`.

Adaptive adds an explicit protocol marker and first-class typed controls so the desktop can discover a controller shape without pretending every non-analog input is an ordinary button.

Example:

```text
v3|s0|s256|s512|s768|s1023|b1|b1|...|t0|t1|e42:1
```

Field semantics:

- `v3` — Adaptive protocol marker;
- `s0..1023` — continuous analog control;
- `b0/b1` — momentary button, preserving Extended semantics (`0 = pressed`, `1 = released`);
- `t0/t1` — latching toggle logical state (`0 = OFF`, `1 = ON`);
- `ePOSITION:PUSH` — rotary encoder cumulative signed detent position plus optional push state; push uses button semantics (`0 = pressed`, `1 = released`).

Encoder position is cumulative rather than a short CW/CCW pulse. If one serial frame is skipped, the next position still lets Mugen recover the complete movement delta.

## Emulated controller shape

The Uno fixture reports:

- 5 analog controls;
- 29 momentary buttons;
- 2 latching toggles;
- 1 rotary encoder with push;
- 115200 baud;
- 25 ms heartbeat.

The five analog values are fixed at approximately 0 / 25 / 50 / 75 / 100 percent so a bare Uno does not show floating ADC noise.

## Jumper-wire test pins

All test pins use `INPUT_PULLUP`, so no resistor is required for this fixture.

| Pin | Adaptive input | Open | Short to GND |
| --- | --- | --- | --- |
| D2 | Button 1 | released | pressed |
| D3 | Toggle 1 | OFF | ON |
| D4 | Toggle 2 | OFF | ON |
| D5 | Encoder push | released | pressed |
| D6 | Encoder CW test | idle | one falling edge adds `+1` |
| D7 | Encoder CCW test | idle | one falling edge adds `-1` |

Buttons 2..29 remain released.

For D6/D7, briefly touch the pin to GND and release it. Each new falling edge is treated as one complete synthetic encoder detent.

## Expected Serial Monitor output

Open Serial Monitor at **115200 baud**. A normal idle line begins approximately like:

```text
v3|s0|s256|s512|s768|s1023|b1|b1|...|t0|t0|e0:1
```

Close Serial Monitor before starting Mugen Deej because the COM port cannot be shared.

## Expected Mugen result

The Adaptive-capable development build should detect the device as:

```text
protocol=adaptive
sliders=5
buttons=29
toggles=2
encoders=1
```

The main connection status should also show all four control families rather than flattening toggles/encoder into the button count.

Expected behavior during jumper tests:

- D2 still behaves as ordinary Button 1, including live identification in Button Settings;
- D3/D4 state changes are accepted as typed toggles and logged;
- D5 encoder push transitions are accepted and logged;
- D6/D7 change the cumulative encoder position and Mugen logs the resulting signed delta.

This stage validates **transport/discovery/state parsing only** for toggles and encoders. First-class toggle/encoder mapping UI and actions come afterward.

## Compatibility goal

Adaptive is additive. Existing Legacy and Extended devices must continue to auto-detect and work exactly as before. The protocol generation is determined from packet syntax, not from COM-port number or a manual device setting.

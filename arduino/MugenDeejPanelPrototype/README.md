# Mugen Deej Panel Prototype — wiring plan

This is the first large hardware prototype for the software-defined Mugen control-surface direction.

**Status: experimental / not hardware-tested.**

The tested 5-control / 6-button reference firmware remains in `arduino/MugenDeejController/`. This folder is intentionally separate so prototype work cannot silently replace the known-good reference controller.

## Target control set

- 5 analog controls;
- 29 standalone momentary buttons;
- 1 push switch built into the rotary encoder;
- 2 latching guarded toggle switches;
- 1 quadrature rotary encoder;
- classic ATmega328P Arduino Nano-class board;
- no I/O expander for the first build.

The 29 standalone buttons plus the encoder push occupy all 30 positions of a 5×6 switch matrix.

## Nano pin map

| Function | Pins |
| --- | --- |
| Analog controls | `A0 A1 A2 A3 A4` |
| Encoder A/B | `D2 D3` |
| Matrix columns | `D4 D5 D6 D7 D8 A5` |
| Matrix rows | `D9 D10 D11 D12 D13` |
| Toggle 1 / 2 | `A6 A7` |
| USB serial | `D0 D1` reserved |

This consumes essentially the whole classic Nano without adding an expander.

## 5×6 matrix

The firmware scans one LOW row at a time while all six columns use `INPUT_PULLUP`.

Recommended row-major numbering:

```text
          C1   C2   C3   C4   C5   C6
R1        b0   b1   b2   b3   b4   b5
R2        b6   b7   b8   b9   b10  b11
R3        b12  b13  b14  b15  b16  b17
R4        b18  b19  b20  b21  b22  b23
R5        b24  b25  b26  b27  b28  b29
```

Reserve `R5C6 / b29` for the encoder push switch. The other 29 positions are ordinary panel buttons.

### Matrix diodes

Use one 1N4148-class diode per matrix position if simultaneous presses are expected.

For the active-LOW scan used by the prototype firmware, current must be able to flow from the pulled-up **column toward the active LOW row**. Therefore the diode's **anode faces the column side and the striped cathode faces the row side**.

Do not permanently solder the entire 30-key matrix before checking one test key with the actual firmware. Verify one row/column/diode orientation first, then replicate it.

## Encoder

The ordered EC11-style encoder is expected to provide:

- channel A;
- common;
- channel B;
- two separate push-switch terminals.

Rotation wiring:

```text
encoder common -> GND
encoder A      -> D2
encoder B      -> D3
```

`D2/D3` use Arduino internal pull-ups. If clockwise/counter-clockwise are reversed, either swap A/B physically or change `ENCODER_DIRECTION` in the sketch.

The push switch is treated as a normal matrix key. Recommended slot:

```text
encoder push -> R5C6 / b29
```

The exact EC11 edge count is hardware-dependent. The sketch starts with `ENCODER_EDGES_PER_DETENT = 4`; change it only after checking the real part one detent at a time.

## Guarded latching toggles

The two ordered automotive-style 12 V illuminated toggles are used only as switch contacts in the first prototype. Their illumination is ignored.

**Do not assume the product's visible 12 V / lamp terminals are safe logic terminals.** Identify the actual switching contacts with a multimeter/continuity test after the parts arrive.

For each verified dry switching contact:

```text
+5 V --- 10 kOhm ---+--- A6 (toggle 1)
                    |
                 switch
                    |
                   GND
```

Repeat on `A7` for toggle 2.

Firmware interpretation:

- open / OFF -> ADC near 1023 -> `b1`;
- closed / ON -> ADC near 0 -> `b0`.

A6/A7 are analog-only on a classic Nano, so the external 10 kOhm pull-up is intentional.

## Temporary protocol mapping

Until Mugen Deej gains native toggle/encoder input semantics, the prototype deliberately stays within the existing Extended `s` / `b` field vocabulary:

```text
s0..s4   = five analog controls
b0..b29  = matrix positions
b30      = toggle 1
b31      = toggle 2
b32      = encoder clockwise pulse
b33      = encoder counter-clockwise pulse
```

This makes the prototype appear as **5 analog controls + 34 button-like fields** to the current Extended parser.

This is temporary. Long term:

- toggles should be first-class persistent controls with optional separate ON/OFF actions;
- the encoder should be a directional step source rather than two user-visible fake buttons.

## Serial speed

The prototype firmware uses **115200 baud**.

A 39-field full-state packet is too large for the current 9600-baud / 60-ms reference path. The desktop client currently needs a deliberate higher-baud discovery/configuration path before this panel can be tested end-to-end in Mugen.

Do not change the stable tested controller to 115200 merely to match this prototype.

## First bring-up order

1. Flash the prototype sketch and open Serial Monitor at 115200.
2. Test the five analog inputs.
3. Build **one** matrix key + diode and verify orientation.
4. Add the encoder rotation channels and inspect CW/CCW pulses.
5. Add the encoder push as the reserved matrix slot.
6. Identify the real toggle terminals with a multimeter, then test A6/A7 with the external pull-ups.
7. Expand the matrix gradually to all 30 positions.
8. Only after raw hardware is clean, add 115200 support to Mugen and start end-to-end routing tests.

This sequence keeps electrical mistakes separate from desktop-protocol bugs.

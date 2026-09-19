# Mugen Deej cardboard prototype — Uno wiring / bring-up

This sketch is the first firmware for the physically assembled cardboard prototype shown during development on 2026-09-20.

## Current hardware

- Arduino Uno for bring-up;
- 28 momentary switches;
- 2 latching toggles;
- 1 rotary encoder module labelled `5V / KEY / S2 / S1 / GND`;
- encoder push is read from the module's dedicated `KEY` output;
- potentiometers are not fitted yet;
- five software slider placeholders are transmitted as `0 / 256 / 512 / 768 / 1023`.

The desktop sees an Adaptive v3 topology of:

`5 sliders / 28 buttons / 2 toggles / 1 encoder with push`

## Uno pin map

### Encoder module

| Module | Uno |
| --- | --- |
| S1 | D2 |
| S2 | D3 |
| KEY | A2 |
| 5V | 5V |
| GND | GND |

If clockwise/counter-clockwise are reversed, swap S1/S2 or change `ENCODER_DIRECTION`.

The first firmware assumption is `ENCODER_EDGES_PER_STEP = 4`. If one physical click counts incorrectly, adjust that constant after observing the real module.

### 4x8 matrix

Columns:

- C1 = D4
- C2 = D5
- C3 = D6
- C4 = D7
- C5 = D8
- C6 = D9
- C7 = D10
- C8 = D11

Rows:

- R1 = D12
- R2 = D13
- R3 = A0
- R4 = A1

Layout:

```text
        C1  C2  C3  C4  C5  C6  C7  C8
R1      B1  B2  B3  B4  B5  B6  B7  T1
R2      B8  B9  B10 B11 B12 B13 B14 T2
R3      B15 B16 B17 B18 B19 B20 B21 spare
R4      B22 B23 B24 B25 B26 B27 B28 spare
```

The two unused C8 cells remain electrically available but are not transmitted.

## Matrix diode rule

Every matrix switch gets its own diode.

For the active-LOW scan used by this sketch:

```text
COLUMN -> switch -> diode anode -> diode cathode/stripe -> ROW
```

The striped end therefore faces the row bus.

Do not use one diode for an entire row.

## Serial

- Adaptive v3
- 115200 baud
- 25 ms heartbeat

D0/D1 are reserved for USB serial and are not used by the panel.

## First test sequence

1. Flash the sketch.
2. Run current Mugen Deej development build.
3. Confirm discovery reports `5 / 28 / 2 / 1`.
4. Press B1, then one key from each physical row.
5. Test several simultaneous key presses.
6. Toggle T1 and T2.
7. Rotate the encoder one physical click at a time and confirm direction/count.
8. Press the encoder and confirm its push state.
9. Only after the raw panel is clean, test virtual Xbox mappings and application profiles.

## Later Nano migration

This Uno layout was deliberately chosen so most wiring can be retained on a classic Nano. The future five real potentiometers can use the remaining analog inputs on the Nano; that firmware change should be made after the actual potentiometers are fitted and measured.

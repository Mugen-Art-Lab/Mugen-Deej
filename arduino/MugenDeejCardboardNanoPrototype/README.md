# Mugen Deej cardboard prototype — Nano full analog build

This is the first firmware variant for the cardboard prototype with all five real potentiometers fitted.

The existing Uno bring-up sketch is intentionally preserved as the digital-regression version. The Nano build keeps the proven matrix/encoder wiring and uses the classic Nano's extra analog-only A6/A7 inputs for potentiometers 4 and 5.

## Adaptive topology

`5 sliders / 28 buttons / 2 toggles / 1 encoder with push`

Serial:

- Adaptive v3;
- 115200 baud;
- 25 ms heartbeat.

## Nano pin map

### Encoder module

| Module | Nano |
| --- | --- |
| S1 | D2 |
| S2 | D3 |
| KEY | A2 |
| 5V | 5V |
| GND | GND |

### Matrix

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

### Five potentiometers

| Potentiometer | Wiper / middle pin |
| --- | --- |
| P1 | A3 |
| P2 | A4 |
| P3 | A5 |
| P4 | A6 |
| P5 | A7 |

For every potentiometer:

```text
outer pin -> 5V
middle/wiper -> Ax
outer pin -> GND
```

All grounds must be common with the Nano, encoder module and matrix controller wiring.

If a potentiometer moves backwards in Mugen, swapping that potentiometer's two outer 5V/GND wires reverses its physical direction. Do not move the middle/wiper wire.

## Why Nano instead of rewiring the Uno

The current proven panel layout consumes A0/A1 for matrix rows and A2 for encoder push. Uno then has only A3/A4/A5 available, so it can read only three real pots without rewiring the already working control matrix.

The classic ATmega328P Nano adds A6/A7 as analog-input-only pins. That gives exactly five free ADC inputs (A3..A7) while retaining every proven digital connection.

## Analog behavior in this first build

The firmware deliberately transmits raw 10-bit ADC readings (0..1023). It does not yet add smoothing, calibration, dead zones or endpoint remapping.

Each channel is sampled twice and the first conversion is discarded after ADC channel switching. This reduces multiplexer carry-over while keeping the signal otherwise raw enough to measure real potentiometer behavior.

That is intentional: first measure the actual pots in Mugen before deciding whether firmware-side filtering is needed.

## First hardware test

1. Flash this sketch to the Nano.
2. Confirm Mugen detects Adaptive `5 / 28 / 2 / 1` at 115200.
3. Turn P1 slowly from end to end and note the minimum/maximum displayed percentage.
4. Repeat P2..P5.
5. Leave all five untouched for 20-30 seconds and look for visible jitter.
6. Move two or more pots together.
7. While moving a pot, press several matrix buttons, flip both toggles, rotate the encoder and press its key.
8. Verify the previously hardware-proven 28-button matrix, toggles and encoder still behave normally after the Uno -> Nano migration.
9. Only after the raw analog path is understood, decide whether endpoint calibration, inversion or smoothing belongs in firmware or Mugen.

## Board selection

For a classic ATmega328P Nano in Arduino IDE use the matching Arduino Nano board definition. Many CH340 Nano clones use the classic/old bootloader option; if upload fails with the normal processor selection, try the old bootloader setting.


## Matrix hold / same-column ghosting note

The first full Nano hardware run exposed a timing-sensitive matrix artifact with the long cardboard wiring: holding a bottom-row key could briefly make the same column appear pressed in the other rows (for example B23/R4C2 also appearing as B2/B9/B16, and B22/R4C1 as B1/B8/B15).

The Nano firmware now leaves an explicit recovery interval after each row is released HIGH before the next row is sampled. This gives columns time to recharge through the ATmega internal pull-ups and prevents stale LOW state from carrying into the next row.

If same-column ghosting remains after flashing the updated sketch, inspect the affected row's diode orientation and soldering next; the expected per-key path remains:

```text
COLUMN -> switch -> diode anode -> diode cathode/stripe -> ROW
```

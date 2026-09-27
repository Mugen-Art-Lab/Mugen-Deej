# Mugen Deej Adaptive v3 reference — Nano 5/28/2/1 build

This is the hardware-proven Adaptive v3 reference firmware used by the Mugen Deej 2.0 release. The directory name is historical: this build originated on the cardboard prototype, but the firmware is now the accepted Nano reference for the tested 5/28/2/1 controller.

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
- C2 = D6
- C3 = D5
- C4 = D7
- C5 = D8
- C6 = D9
- C7 = D10
- C8 = D11

The C2/C3 D5/D6 swap is intentional and matches the hardware-proven build. During bring-up, keeping these two physical jumpers swapped eliminated same-column ghost presses while the firmware preserved the original logical C1..C8 / B1..B28 numbering.

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

## Analog behavior

The firmware deliberately transmits raw 10-bit ADC readings (0..1023). It does not yet add smoothing, calibration, dead zones or endpoint remapping.

Each channel is sampled twice and the first conversion is discarded after ADC channel switching. This reduces multiplexer carry-over while keeping the signal otherwise raw enough to measure real potentiometer behavior.

Mugen 2.0 handles the normal desktop-side response/noise behavior while the reference firmware keeps the ADC transport simple and predictable.

## Reference hardware smoke test

1. Flash this sketch to the Nano.
2. Confirm Mugen detects Adaptive `5 / 28 / 2 / 1` at 115200.
3. Turn P1 slowly from end to end and note the minimum/maximum displayed percentage.
4. Repeat P2..P5.
5. Leave all five untouched for 20-30 seconds and look for visible jitter.
6. Move two or more pots together.
7. While moving a pot, press several matrix buttons, flip both toggles, rotate the encoder and press its key.
8. Verify the 28-button matrix, both toggles, encoder rotation and encoder push behave normally.
9. If virtual Xbox output is enabled in Mugen, verify the configured Game-layer mappings in Windows `joy.cpl` or a game.

## Board selection

For a classic ATmega328P Nano in Arduino IDE use the matching Arduino Nano board definition. Many CH340 Nano clones use the classic/old bootloader option; if upload fails with the normal processor selection, try the old bootloader setting.


## Matrix hold / same-column ghosting note

The first full Nano hardware run exposed a timing-sensitive matrix artifact with the long cardboard wiring: holding a bottom-row key could briefly make the same column appear pressed in the other rows (for example B23/R4C2 also appearing as B2/B9/B16, and B22/R4C1 as B1/B8/B15).

The Nano firmware now leaves an explicit recovery interval after each row is released HIGH before the next row is sampled. This gives columns time to recharge through the ATmega internal pull-ups and prevents stale LOW state from carrying into the next row.

If same-column ghosting remains after flashing the updated sketch, inspect the affected row's diode orientation and soldering next; the expected per-key path remains:

```text
COLUMN -> switch -> diode anode -> diode cathode/stripe -> ROW
```


## Matrix logical layout

```text
        C1   C2   C3   C4   C5   C6   C7   C8
R1      B1   B2   B3   B4   B5   B6   B7   T1
R2      B8   B9   B10  B11  B12  B13  B14  T2
R3      B15  B16  B17  B18  B19  B20  B21  spare
R4      B22  B23  B24  B25  B26  B27  B28  spare
```

The 28 normal button fields use C1..C7 across the four rows. R1C8 and R2C8 are the two latching toggles. R3C8 and R4C8 are unused spare cells.

## Timing and diagnostics

The current accepted reference values are:

- matrix debounce: 6 ms;
- encoder-push debounce: 20 ms;
- active-row settle: 6 us;
- row-release / column-recharge settle: 60 us;
- Adaptive heartbeat: 25 ms at 115200 baud.

The firmware also appends the optional Adaptive diagnostic token:

```text
d<debounceMs>:<filteredCount>:<filteredMaskHex>:<rapidCount>:<rapidMaskHex>
```

Mugen Deej 2.0 reads this diagnostic information separately from the controller topology.

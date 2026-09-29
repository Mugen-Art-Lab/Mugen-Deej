# Adaptive v3 reference wiring — Nano 5/28/2/1

This document describes the **hardware-proven Mugen Deej 2.0 Adaptive
reference controller**. It is intentionally narrower than the Adaptive protocol
itself.

Reference topology:

```text
5 analog controls
28 momentary buttons
2 latching toggles
1 rotary encoder with push
```

Reference firmware:

`arduino/MugenDeejCardboardNanoPrototype/MugenDeejCardboardNanoPrototype.ino`

Reference transport: **115200 baud / 25 ms heartbeat**.

## Nano pin map

Classic ATmega328P Nano-class board:

| Function | Logical signal | Nano pin |
| --- | --- | --- |
| Encoder | S1 | D2 |
| Encoder | S2 | D3 |
| Encoder | KEY / push | A2 |
| Matrix | C1 | D4 |
| Matrix | C2 | **D6** |
| Matrix | C3 | **D5** |
| Matrix | C4 | D7 |
| Matrix | C5 | D8 |
| Matrix | C6 | D9 |
| Matrix | C7 | D10 |
| Matrix | C8 | D11 |
| Matrix | R1 | D12 |
| Matrix | R2 | D13 |
| Matrix | R3 | A0 |
| Matrix | R4 | A1 |
| Potentiometer | P1 wiper | A3 |
| Potentiometer | P2 wiper | A4 |
| Potentiometer | P3 wiper | A5 |
| Potentiometer | P4 wiper | A6 |
| Potentiometer | P5 wiper | A7 |
| USB serial | RX/TX | D0/D1 reserved |

**C2=D6 and C3=D5 are intentionally swapped.** This matches the
hardware-proven build and removed same-column ghost presses on the long
prototype wiring while preserving logical C1..C8 / B1..B28 numbering.

A6/A7 are analog-input-only on the classic Nano and are used exactly that way.

## Matrix logical layout

```text
        C1   C2   C3   C4   C5   C6   C7   C8
R1      B1   B2   B3   B4   B5   B6   B7   T1
R2      B8   B9   B10  B11  B12  B13  B14  T2
R3      B15  B16  B17  B18  B19  B20  B21  spare
R4      B22  B23  B24  B25  B26  B27  B28  spare
```

The 28 normal button fields occupy C1..C7. R1C8/R2C8 are the two latching
toggles. R3C8/R4C8 are unused in the public reference firmware.

Development firmware has used those two spare cells for a second encoder, but
that experiment is deliberately kept out of the public 2.0 reference wiring.

## Matrix electrical rule

Firmware configuration:

- columns: `INPUT_PULLUP`;
- rows: outputs, idle HIGH;
- one row at a time is driven LOW while scanning.

Every populated matrix contact is diode isolated. The proven orientation is:

```text
COLUMN -> switch/contact -> diode anode -> diode cathode/stripe -> ROW
```

Do not reverse only one diode in the matrix.

Reference scan timing:

- active-row settle: 6 microseconds;
- row-release / column-recharge settle: 60 microseconds;
- stable-state button/toggle debounce: 6 ms.

The 60 microsecond recharge interval is intentional for the proven long-wiring
build and prevents stale same-column LOW state from leaking into the next row.

## Potentiometers

Each potentiometer uses:

```text
5V ---- outer leg
        |
        +---- wiper / middle ---- A3..A7
        |
GND --- outer leg
```

Mapped wipers:

- P1 -> A3
- P2 -> A4
- P3 -> A5
- P4 -> A6
- P5 -> A7

The firmware reports raw 10-bit ADC values `0..1023`. It discards the first
conversion after switching ADC channels and sends the second reading.

If one physical potentiometer moves backwards, swap that potentiometer's two
outer 5V/GND wires. Keep the wiper on its ADC pin.

Mugen also has a whole-controller inversion option for builders whose entire
set of controls is wired in the opposite direction.

## Encoder module

The accepted reference uses a module exposing:

```text
S1  -> D2
S2  -> D3
KEY -> A2
5V  -> 5V
GND -> GND
```

D2/D3 are decoded through CHANGE interrupts and a Gray-code transition table.
The reference firmware currently assumes four quadrature edges per reported
detent/step. Encoder push is active LOW and has a 20 ms firmware debounce.

Different EC11 encoders/modules can have different phase ordering or
edges-per-detent behavior. Verify direction and one-detent counting on the real
part instead of copying assumptions from an unrelated module.

## Illuminated latching toggles

The proven prototype uses three-terminal illuminated switches where:

- two terminals are the switch contact;
- the third terminal is LED negative;
- internal LED positive is tied to one of the switch-contact terminals.

For that tested construction, orient the switch so the terminal internally tied
to **LED+** is on the ROW/diode side.

Conceptual wiring:

```text
+5V
 |
325 ohm
 |
C8 / D11
 |
+---- T1 switch ---- LED+ node ---- matrix diode ---- R1
|                         |
|                         +---- internal LED ---- GND
|
+---- T2 switch ---- LED+ node ---- matrix diode ---- R2
                          |
                          +---- internal LED ---- GND
```

The external matrix diode orientation remains:

```text
contact -> diode anode -> diode cathode/stripe -> ROW
```

The hardware-proven C8 pull-up is **325 ohm to +5 V**. With both tested
illuminated toggles ON, C8/D11 measured approximately **3.43-3.44 V** and the
full button matrix continued to operate without observed false activations.

This wiring is specific to the tested three-terminal internal construction.
Identify which contact terminal is internally tied to LED+ before soldering a
different illuminated switch. Do not infer terminal numbers from this document.

## Common ground

Nano, potentiometers, encoder module, illuminated-switch LED negatives and any
other powered module must share a common GND.

Keep D0/D1 free for USB serial.

## Reference smoke expectations

After flashing the reference firmware, Mugen should discover:

```text
Adaptive v3
5 sliders
28 buttons
2 toggles
1 encoder
115200 baud
```

For flashing and the complete test sequence, see
[ADAPTIVE_V3_BUILD.md](ADAPTIVE_V3_BUILD.md).

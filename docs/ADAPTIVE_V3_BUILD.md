# Build and test the Adaptive v3 Nano reference

This guide flashes and validates the Mugen Deej 2.0 hardware-proven Adaptive
reference controller.

It intentionally targets the accepted **5/28/2/1 / 115200-baud** reference,
not the experimental second-encoder / 500000-baud development firmware.

## 1. Firmware

Open:

`arduino/MugenDeejCardboardNanoPrototype/MugenDeejCardboardNanoPrototype.ino`

The directory name is historical; this sketch is the accepted Adaptive v3 Nano
reference shipped with Mugen Deej 2.0.

Expected topology:

```text
5 analog controls
28 momentary buttons
2 latching toggles
1 rotary encoder with push
```

See [ADAPTIVE_V3_WIRING.md](ADAPTIVE_V3_WIRING.md) before wiring or changing
pins.

## 2. Arduino IDE board selection

Use the board definition matching a classic ATmega328P Arduino Nano.

Many CH340-based Nano clones require the classic/old bootloader processor
option. If upload fails with the normal Nano processor selection, retry with
the old bootloader option appropriate to the board.

The reference sketch uses:

- D0/D1 for the board's normal USB serial path;
- A6/A7 only as analog inputs.

## 3. Flash the sketch

1. Disconnect anything that would interfere with board programming.
2. Select the Nano board and its COM port in Arduino IDE.
3. Compile and upload the reference sketch.
4. Reconnect the complete control panel if it was disconnected for flashing.

The reference firmware uses **115200 baud**.

If you inspect raw output with a serial terminal, close that terminal before
starting Mugen Deej; only one process can normally own the COM port.

## 4. Verify raw Adaptive output

A healthy line begins with `v3` and contains five `s` fields, twenty-eight
`b` fields, two `t` fields and one `ePOSITION:PUSH` field.

The firmware may append a diagnostic field beginning with `d`.

Conceptually:

```text
v3|s...|s...|...|b...|...|t...|t...|ePOSITION:PUSH|d...
```

You do not need to count or edit these fields manually during normal use; Mugen
discovers them automatically.

## 5. Connect with Mugen Deej

Start Mugen Deej and allow automatic COM detection.

Expected diagnostics:

- protocol: Adaptive v3;
- baud: 115200;
- sliders: 5;
- buttons: 28;
- toggles: 2;
- encoders: 1.

The exact COM number is assigned by Windows and is not part of controller
identity.

## 6. Hardware smoke test

Run this sequence on the real controller:

1. Move P1 slowly from end to end and check useful full-range movement.
2. Repeat P2..P5.
3. Leave all five potentiometers untouched for 20-30 seconds and look for
   visible jitter.
4. Move two or more potentiometers together.
5. Press buttons across all matrix rows, including simultaneous holds.
6. Flip T1 and T2 independently and together.
7. Rotate the encoder clockwise and counter-clockwise.
8. Press/release the encoder push switch.
9. Move an analog control while pressing buttons/toggles/encoder to exercise
   mixed traffic.
10. Open **Connection and diagnostics** and confirm the detected topology and
    firmware debounce values remain stable.

If virtual Xbox/XInput output is enabled, optionally verify mapped controls in
Windows `joy.cpl` or a game after the physical-input smoke test passes.

## 7. Direction and inversion

### One potentiometer backwards

Swap only that potentiometer's two outer 5V/GND wires. Keep its wiper on the
same ADC input.

### All potentiometers backwards

Mugen can remember whole-controller slider inversion by protocol/topology
signature. This is useful when the whole panel is wired consistently opposite
to the preferred direction.

### Encoder backwards

For a different encoder/module, verify phase wiring and firmware direction
assumptions. Do not change unrelated matrix wiring to compensate for an encoder
direction problem.

## 8. If the matrix shows ghost or same-column presses

Confirm first:

- every populated contact has its diode;
- diode stripe/cathode faces the ROW side;
- C2 is D6 and C3 is D5 on the proven Nano mapping;
- rows/columns match the table in
  [ADAPTIVE_V3_WIRING.md](ADAPTIVE_V3_WIRING.md).

The reference firmware already includes a 60 microsecond row-release/column
recharge interval that was required by the long prototype wiring.

## 9. Reference boundary

The following are development results, not requirements for this guide:

- a second encoder on the two spare C8 cells;
- `5/28/2/2` topology;
- 500000-baud transport;
- 10 ms / approximately 100 Hz heartbeat experiments;
- future CD74HC4067 four-encoder hardware.

They are intentionally separated so a builder can reproduce the accepted 2.0
reference without inheriting unfinished vNext experiments.

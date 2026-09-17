# Mugen Deej Uno transport test

This folder contains a deliberately small **transport-only** Arduino Uno sketch for validating Mugen Deej's experimental 115200-baud auto-detection before the large panel is physically assembled.

It is not the final panel firmware.

## What it emulates

The sketch sends the same packet shape planned for the first large prototype:

- 5 analog/control fields;
- 34 button-like fields;
- 39 fields total;
- Extended `s...|b...` protocol;
- 115200 baud;
- 25 ms heartbeat.

The five analog values are fixed at roughly 0 / 25 / 50 / 75 / 100 percent so a bare Uno does not show random floating ADC noise in the Mugen UI.

Button field 1 is connected to `D2` using `INPUT_PULLUP`:

- leave `D2` open -> released;
- short `D2` to `GND` -> pressed.

The remaining 33 button fields always report released.

No resistor or external button is required for the basic test; a jumper wire from `D2` to `GND` is enough to test one press/release path.

## Upload

In Arduino IDE select the matching Uno board and COM port, then upload:

`MugenDeejUnoTransportTest.ino`

For a quick sanity check, open Serial Monitor at **115200 baud**. You should see lines beginning roughly like:

```text
s0|s256|s512|s768|s1023|b1|b1|...
```

Close Serial Monitor before opening Mugen Deej because the COM port cannot be shared.

## Expected desktop auto-baud test

With the experimental Mugen build that probes `9600` and `115200`, the first connection should look conceptually like:

```text
Opening COMx for protocol probe; baud candidates=9600,115200
Probing COMx at 9600 baud
Probing COMx at 115200 baud
Controller detected on COMx at 115200 baud
```

Expected detected capabilities:

- protocol: Extended;
- controls/sliders: 5;
- buttons: 34.

After the first successful detection, Mugen should remember 115200 and prefer that baud rate on the next connection.

## Why this exists separately from the panel firmware

The real panel firmware uses Nano-only resources such as `A6/A7` for the two guarded toggles. A classic Uno does not expose those inputs, but that does not matter for testing serial transport.

Keeping this fixture separate means:

- the hardware-prototype sketch stays honest about its Nano pin map;
- the Uno test stays trivial to upload to spare boards;
- auto-baud can be proven independently of the switch matrix, encoder, toggles and analog hardware.

A Mega can also run this transport sketch with the normal Uno-compatible `D2`/Serial behavior, but it is intentionally not used as the pin-budget reference for the cheap Nano-class panel.

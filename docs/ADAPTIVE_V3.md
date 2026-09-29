# Mugen Deej Adaptive v3

Adaptive v3 is Mugen Deej's self-describing serial protocol for DIY controllers
that need more than analog sliders and momentary buttons.

A controller sends its complete typed state in ordinary serial lines beginning
with `v3`. Mugen derives the connected topology directly from those packets;
there is no separate hardware handshake and the desktop does not hardcode one
particular panel layout.

## Supported physical input families

Adaptive v3 currently models four first-class input families:

| Field | Physical control | Value |
| --- | --- | --- |
| `sVALUE` | analog control / potentiometer | `0..1023` |
| `bSTATE` | momentary button | `0` pressed, `1` released |
| `tSTATE` | latching toggle | `0` OFF, `1` ON |
| `ePOSITION[:PUSH]` | rotary encoder | signed cumulative position, optional push |

Example:

```text
v3|s512|s128|b1|b0|t1|e42:1
```

No physical family is mandatory. A valid controller can have zero sliders,
zero buttons, zero toggles, or zero encoders as long as at least one supported
physical input field follows `v3`.

The optional firmware diagnostics token is documented in
[PROTOCOL.md](PROTOCOL.md). It does not count as a physical control.

## Why encoder position is cumulative

Encoders transmit a signed cumulative position instead of a one-shot
"clockwise" / "counter-clockwise" event:

```text
e41
e42
e45
```

The desktop uses the difference between positions. If one serial frame is
skipped, the next cumulative position still carries the movement already
counted by firmware.

An encoder with a push switch adds button-style push state:

```text
e45:0   # position 45, push pressed
e45:1   # position 45, push released
```

## Tested public reference controller

Mugen Deej 2.0 ships a hardware-proven Nano reference firmware at:

`arduino/MugenDeejCardboardNanoPrototype/`

The directory name is historical. This is the accepted Adaptive v3 Nano
reference for the tested topology:

```text
5 analog controls
28 momentary buttons
2 latching toggles
1 rotary encoder with push
```

Reference transport:

- classic ATmega328P Nano-class board;
- 115200 baud;
- 25 ms periodic heartbeat;
- selected button/toggle/direct-encoder changes can request an update before the
  next heartbeat.

That **5/28/2/1** shape is a tested reference, not an Adaptive protocol limit.

## Dynamic topology

The desktop counts `s`, `b`, `t` and `e` fields in accepted packets and
builds the UI from the discovered capabilities. Developer fixtures intentionally
exercise very different shapes, including zero-slider and encoder-heavy
controllers.

While connected, Mugen guards the established topology. A malformed or partial
line that happens to remain syntactically parseable but suddenly describes a
different shape is ignored rather than silently redefining the controller.

## What Adaptive unlocks in Mugen

Depending on the detected hardware, Mugen can expose:

- physical audio/control mappings;
- momentary button actions;
- separate ON/OFF actions for latching toggles;
- encoder clockwise/counter-clockwise/push actions;
- Control layers driven by toggles;
- application-specific mapping profiles;
- optional virtual Xbox 360 / XInput output.

Missing control families are simply omitted from the relevant UI.

## Reference vs experimental hardware

The public 2.0 reference remains **5/28/2/1 at 115200 baud**.

Development has also demonstrated a second matrix-backed encoder and a
`5/28/2/2` topology, including high-rate 500000-baud / 10 ms experiments.
Those tests are useful for future two- and four-encoder hardware, but they are
not required to build or use the public Adaptive reference controller.

For the accepted reference build, use:

- [Adaptive v3 wiring](ADAPTIVE_V3_WIRING.md)
- [Adaptive v3 build and smoke test](ADAPTIVE_V3_BUILD.md)
- [Serial protocol details](PROTOCOL.md)

# Mugen Deej — serial protocol generations

Mugen Deej keeps older controller firmware compatible while newer DIY control
surfaces can describe richer physical inputs. Protocol selection is automatic
and syntax-based; the user does not choose a protocol manually.

## 1. Legacy

Original numeric-only deej-compatible packets:

```text
0|512|1023|300|700
```

Every field is an analog/control value in `0..1023`. There is no explicit
version marker and there are no first-class button, toggle, or encoder types.

## 2. Extended

Typed slider and momentary-button packets without a version marker:

```text
s0|s512|s1023|b1|b0|b1
```

- `s0..1023` — continuous analog/control value;
- `b0` — momentary button pressed;
- `b1` — momentary button released.

Extended remains supported for existing slider+button hardware.

## 3. Adaptive v3

Adaptive packets begin with the explicit marker:

```text
v3
```

The remaining fields describe the physical controller shape in encounter order.
**No particular control family is mandatory.** A valid Adaptive packet may
contain sliders, buttons, toggles, encoders, or any supported combination of
those families. In particular, a zero-slider Adaptive controller is valid.

Examples:

```text
v3|s0|s256|b1|t0|e42:1
v3|b1|b1|t0|t1|e-4
v3|s128|s900
v3|t0|t1|t0|e12|e-3:1
```

A packet containing only the marker (`v3`) is rejected; at least one typed
physical input field must follow it.

### Analog control

```text
sVALUE
```

`VALUE` is `0..1023`.

### Momentary button

```text
bSTATE
```

Extended semantics are preserved:

- `b0` = pressed;
- `b1` = released.

### Latching toggle

```text
tSTATE
```

- `t0` = OFF;
- `t1` = ON.

Firmware converts its electrical polarity into this logical state. An
`INPUT_PULLUP` switch may electrically read LOW while closed/ON but should
still transmit `t1`.

### Rotary encoder

```text
ePOSITION
```

or, with push:

```text
ePOSITION:PUSH
```

`POSITION` is a signed cumulative detent counter since firmware boot.
Optional `PUSH` reuses button semantics (`0 = pressed`, `1 = released`).

The desktop computes:

```text
delta = newPosition - previousPosition
```

Cumulative transport means a skipped serial frame does not permanently lose the
movement already accumulated by firmware. On a new connection, the first
received encoder position establishes the baseline and is not treated as user
movement.

### Optional firmware diagnostics token

The hardware-proven Adaptive Nano firmware may append one diagnostic field:

```text
d<debounceMs>:<filteredCount>:<filteredMaskHex>:<rapidCount>:<rapidMaskHex>
```

Example:

```text
d6:0:00000000:0:00000000
```

The desktop parses this separately from physical inputs. It is **not** counted
as a slider, button, toggle or encoder and therefore does not change the
controller topology/signature. Only one `d...` field is accepted per packet.

The current reference firmware uses this token to expose matrix-debounce
diagnostics: configured debounce time, filtered-transition count/mask, and
rapid-reversal count/mask.

## Shape discovery

Adaptive has no separate fixed hardware descriptor. The normal state packet
itself describes the topology:

```text
v3|s...|b...|t...|e...
```

Mugen counts each typed physical family. The hardware-proven public Nano
reference is `5 / 28 / 2 / 1`, but this is not a hardcoded product shape.
Developer fixtures also exercise shapes such as `5 / 29 / 2 / 1`,
`0 / 8 / 4 / 2`, `2 / 0 / 0 / 0`, and `0 / 0 / 12 / 6`.

Missing families are represented as zero controls of that type. Hardware
discovery is authoritative for what exists in the live UI.

## Automatic protocol and baud detection

- all-numeric packet -> `legacy`;
- `s` / `b` typed packet without a version marker -> `extended`;
- packet beginning with `v3` -> `adaptive`.

Serial baud probing is independent of protocol generation. Mugen remembers the
last successful rate and supports the normal 9600/115200 compatibility path.
The current desktop can also probe **500000 baud** for high-rate Adaptive
experiments. The public Adaptive reference firmware remains **115200 baud**;
500000 is not required for protocol compatibility.

## Compatibility guarantees

Adaptive is additive:

- Legacy parsing remains supported;
- Extended parsing remains supported;
- existing Extended button actions and virtual-XInput mappings remain usable
  for Adaptive `b` fields;
- old controllers never need to emit `t` or `e` fields;
- controller shape is derived from packet contents, never from remembered
  COM-port number;
- live UI sections are capability-driven and do not fabricate missing families;
- saved mappings for temporarily absent controls may remain dormant rather than
  being destroyed.

## Parser ceiling

The desktop accepts at most **64 pipe-separated fields per line**.

For Adaptive, the `v3` marker consumes one field. Without the optional
diagnostic token, up to 63 typed physical fields fit under the current parser
ceiling. With a `d...` token present, up to 62 typed physical fields fit.

## Reference firmware and regression fixtures

Public hardware-proven Adaptive reference:

- `arduino/MugenDeejCardboardNanoPrototype/`;
- classic ATmega328P Nano-class board;
- `5 sliders / 28 buttons / 2 toggles / 1 push encoder`;
- 115200 baud;
- 25 ms heartbeat plus event-driven updates for selected input changes.

The directory name is historical; the firmware is the accepted 2.0 Adaptive
Nano reference. See `ADAPTIVE_V3_WIRING.md` and `ADAPTIVE_V3_BUILD.md`.

Developer topology fixture:

`arduino/MugenDeejUnoAdaptiveTest/` can boot into synthetic shapes selected
by D8/D9 before reset:

- `5 / 29 / 2 / 1`;
- `0 / 8 / 4 / 2`;
- `2 / 0 / 0 / 0`;
- `0 / 0 / 12 / 6`.

These are parser/UI regression shapes, not the public reference panel.

## Current implementation status

Mugen Deej 2.0 currently has real-hardware coverage for:

- Legacy 9600-baud slider-only autodetection;
- Extended slider/button compatibility;
- Adaptive v3 topology discovery;
- the public Nano `5/28/2/1` reference;
- first-class toggles and signed cumulative encoders, including optional push;
- topology-driven UI;
- typed toggle/encoder actions, application profiles and Control layers;
- optional virtual Xbox/XInput output;
- topology-shape guarding against malformed/partial packets.

A separate experimental hardware path has also demonstrated
`5/28/2/2` at 500000 baud with a 10 ms heartbeat and a matrix-backed second
encoder. That result informs future hardware development, but it does not
replace the public 5/28/2/1 / 115200-baud reference firmware.

# Mugen Deej — serial protocol generations

Mugen Deej keeps older controller firmware compatible while newer DIY control surfaces can describe richer physical inputs. Protocol selection is automatic and syntax-based; the user does not choose a protocol manually.

## 1. Legacy

Original numeric-only deej-compatible packets:

```text
0|512|1023|300|700
```

Every field is an analog/control value in `0..1023`. There is no explicit version marker and there are no first-class button, toggle, or encoder types.

## 2. Extended

Typed slider and momentary-button packets without a version marker:

```text
s0|s512|s1023|b1|b0|b1
```

- `s0..1023` — continuous analog/control value;
- `b0` — momentary button pressed;
- `b1` — momentary button released.

Extended remains supported for the existing slider+button hardware generation.

## 3. Adaptive v3

Adaptive packets begin with the explicit marker:

```text
v3
```

The remaining fields describe the physical controller shape in encounter order. **No particular control family is mandatory.** A valid Adaptive packet may contain sliders, buttons, toggles, encoders, or any supported combination of those families. In particular, a zero-slider Adaptive controller is valid.

Examples:

```text
v3|s0|s256|b1|t0|e42:1
v3|b1|b1|t0|t1|e-4
v3|s128|s900
v3|t0|t1|t0|e12|e-3:1
```

A packet containing only the marker (`v3`) is not a useful controller state and is rejected; at least one typed input field must follow it.

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

Firmware converts its electrical polarity into this logical state. An `INPUT_PULLUP` switch may electrically read LOW while closed/ON but should still transmit `t1`.

### Rotary encoder

```text
ePOSITION
```

or, with push:

```text
ePOSITION:PUSH
```

`POSITION` is a signed cumulative detent counter since firmware boot. Optional `PUSH` reuses button semantics (`0 = pressed`, `1 = released`).

The desktop computes:

```text
delta = newPosition - previousPosition
```

Cumulative transport means a skipped serial frame does not permanently lose individual detents. On a new connection, the first received encoder position establishes the baseline and is not treated as user movement.

## Shape discovery

Adaptive has no separate fixed hardware descriptor. The normal state packet itself describes the topology:

```text
v3|s...|b...|t...|e...
```

Mugen counts each typed family. The current Uno regression fixture is `5 / 29 / 2 / 1`, but this is not a hardcoded product shape. Examples such as `0 / 8 / 4 / 2`, `2 / 0 / 0 / 0`, or `0 / 0 / 12 / 6` are legal Adaptive topologies.

Missing families are represented as zero controls of that type. Hardware discovery is authoritative for what exists in the live UI.

## Automatic protocol detection

- all-numeric packet -> `legacy`;
- `s` / `b` typed packet without a version marker -> `extended`;
- packet beginning with `v3` -> `adaptive`.

Serial baud probing is independent of protocol generation. The current staged desktop probes `9600` and `115200`, remembers the last successful rate, and parses whichever supported Mugen protocol is present at that rate.

## Compatibility guarantees

Adaptive is additive:

- Legacy parsing must remain unchanged;
- Extended parsing must remain unchanged;
- existing Extended button actions and virtual-XInput mappings remain usable for Adaptive `b` fields;
- old controllers never need to emit `t` or `e` fields;
- controller shape is derived from packet contents, never from remembered COM-port number;
- live UI sections are capability-driven and must not fabricate missing families;
- saved mappings for temporarily absent controls may remain dormant rather than being destroyed.

## Current parser ceiling

The desktop currently accepts at most **64 pipe-separated fields per line**. Adaptive consumes one field for `v3`, leaving at most 63 typed input fields before a future parser-limit change is needed.

## Adaptive regression fixture

`arduino/MugenDeejUnoAdaptiveTest/` can boot into four synthetic shapes selected by D8/D9 before reset:

- `5 / 29 / 2 / 1` — current full regression fixture;
- `0 / 8 / 4 / 2` — zero-slider mixed typed input;
- `2 / 0 / 0 / 0` — two sliders only;
- `0 / 0 / 12 / 6` — large toggle/encoder topology for bounded-summary/overflow testing.

D2..D7 keep the original live-input bench semantics wherever the selected profile contains that family.

## Implementation status

On the active feature branch:

- Legacy and Extended compatibility remain staged;
- Adaptive transport/discovery on the real Uno is hardware PASS for the 5/29/2/1 fixture;
- real toggle state, signed encoder movement, and encoder push are hardware PASS;
- zero-slider Adaptive parsing and capability-driven/bounded UI are staged in Integrated #31 and await alternate-topology hardware validation;
- first-class toggle/encoder mapping actions are the next larger feature after topology hardening.

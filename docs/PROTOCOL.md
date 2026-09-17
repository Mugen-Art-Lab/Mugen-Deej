# Mugen Deej — serial protocol generations

Mugen Deej intentionally keeps old controller firmware compatible while allowing newer DIY control surfaces to describe richer physical inputs.

The desktop therefore recognizes three protocol generations.

## 1. Legacy

Legacy is the original deej-compatible numeric protocol.

Example:

```text
0|512|1023|300|700
```

Semantics:

- every field is a continuous analog/control value;
- valid value range is `0..1023`;
- there is no explicit protocol marker;
- there are no first-class button, toggle or encoder types.

Legacy remains supported for existing simple controllers.

## 2. Extended

Extended adds typed slider and momentary-button fields while remaining compact.

Example:

```text
s0|s512|s1023|b1|b0|b1
```

Semantics:

- `s0..1023` — continuous analog/control value;
- `b0` — momentary button pressed;
- `b1` — momentary button released;
- packet shape is discovered by counting typed fields;
- there is no explicit version marker.

Extended is the currently hardware-proven button protocol and remains fully supported.

## 3. Adaptive v3

**Adaptive** is the third generation. The name reflects its purpose: the desktop should adapt its UI/routing model to the physical controls the firmware actually reports.

Adaptive is explicitly versioned and adds first-class typed controls instead of flattening toggles and encoders into fake buttons.

Example:

```text
v3|s0|s256|s512|s768|s1023|b1|b0|t0|t1|e42:1
```

The first token must be exactly:

```text
v3
```

Remaining fields describe the physical input shape in encounter order.

### Analog control

```text
sVALUE
```

`VALUE` is an integer from `0` through `1023`.

Example:

```text
s512
```

### Momentary button

```text
bSTATE
```

Extended semantics are preserved:

- `b0` = pressed;
- `b1` = released.

Keeping this convention means existing Mugen button-state/action logic can continue to work for Adaptive momentary buttons.

### Latching toggle

```text
tSTATE
```

Toggle state is logical rather than electrical:

- `t0` = OFF;
- `t1` = ON.

Firmware is responsible for converting its wiring polarity into this logical state. For example, an `INPUT_PULLUP` toggle may electrically read LOW while closed/ON, but it should still transmit `t1`.

### Rotary encoder

```text
ePOSITION
```

or, for an encoder with a push switch:

```text
ePOSITION:PUSH
```

`POSITION` is a signed cumulative detent counter since firmware boot.

Examples:

```text
e0
e17
e-4
e42:1
```

For the optional `PUSH` part, button semantics are reused:

- `0` = pressed;
- `1` = released.

#### Why cumulative position instead of CW/CCW pulses

A rotary encoder is a relative step source, but transporting each detent as a short synthetic button pulse is fragile. If a desktop frame is skipped while the user turns the knob quickly, an individual pulse can disappear.

Adaptive therefore transports a cumulative position counter. The desktop remembers the previous position and computes:

```text
delta = newPosition - previousPosition
```

If one or several serial packets are skipped, the next received position still represents the complete movement since the last accepted packet.

On a new connection Mugen establishes the first received encoder position as the baseline and must not interpret that initial value as user movement.

## Shape discovery

Adaptive has no separate fixed hardware descriptor. The normal state packet itself is the descriptor:

```text
v3|s...|s...|b...|t...|e...
```

Mugen counts each typed field family and can therefore discover, for example:

```text
protocol = adaptive
analog controls = 5
momentary buttons = 29
toggles = 2
encoders = 1
```

This keeps cheap firmware simple and avoids coupling a controller to a Windows COM-port number, game, profile, HID layout or hard-coded desktop configuration.

## Automatic protocol detection

Protocol selection is syntax-based:

- all-numeric packet -> `legacy`;
- `s` / `b` typed packet without a version marker -> `extended`;
- packet beginning with `v3` -> `adaptive`.

No manual protocol setting should be required for normal use.

Serial baud probing is independent of protocol generation. The current staged desktop build can probe `9600` and `115200`, remember the last successful rate, and then parse whichever Mugen protocol is present at that rate.

## Compatibility guarantees

Adaptive is additive.

- Legacy parsing must remain unchanged.
- Extended parsing must remain unchanged.
- Existing Extended button actions and virtual-XInput mappings must continue to operate for Adaptive `b` fields.
- Toggle/encoder support must not require old controllers to emit new fields.
- Missing optional typed families are represented as zero controls of that type.
- A controller shape must be derived from packet contents, never from a remembered COM-port number.

## Current parser ceiling

The current desktop parser accepts at most **64 pipe-separated fields per line**.

For Adaptive, the leading `v3` marker is one field, so a packet can currently contain at most 63 typed input fields before a future parser-limit change is needed.

The planned first large Nano prototype fits comfortably within this limit.

## First Adaptive test fixture

`arduino/MugenDeejUnoAdaptiveTest/` is a transport fixture that can run on a bare Uno/Mega-class Arduino at 115200 baud.

It reports:

- 5 analog controls;
- 29 momentary buttons;
- 2 toggles;
- 1 encoder with push.

Jumper wires can exercise one real button, both toggle states, encoder push, and synthetic CW/CCW encoder detents before the final panel hardware is assembled.

## Implementation status

At the time Adaptive v3 was introduced on the feature branch:

- protocol specification: implemented;
- staged Windows parser/state bookkeeping: implemented, CI validation required;
- bare-Uno Adaptive fixture: implemented;
- Legacy/Extended compatibility regression: requires real-hardware re-test after the parser change;
- Adaptive transport/discovery: requires real-hardware test on the Uno fixture;
- first-class toggle/encoder UI and mappings: not implemented yet;
- full Nano panel firmware migration from its temporary Extended compatibility shim: deferred until Adaptive transport is hardware-proven.

Do not mark Adaptive hardware PASS until the real serial fixture has been exercised against the staged desktop build.

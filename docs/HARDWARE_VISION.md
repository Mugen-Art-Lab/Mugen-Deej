# Mugen Deej — hardware vision

This note captures the broader hardware direction behind Mugen Deej beyond the original deej-style volume mixer.

## Product idea

Mugen Deej should evolve into a **software-defined DIY control-surface platform**: inexpensive, simple physical hardware whose meaning is assigned on the PC side instead of being hard-coded into each microcontroller build.

The same physical panel should be reusable through Mugen profiles without reflashing the controller. A user should be able to build a cheap custom control surface from common parts and repurpose it for very different jobs:

- sim racing;
- flight simulation;
- space simulation;
- streaming;
- desktop/application control;
- game-specific or hobby-specific custom panels.

The goal is not to clone expensive commercial panels one-for-one. The goal is to expose reusable physical control primitives and let Mugen map them to audio, actions, virtual game-controller outputs and future profile-specific behaviors.

## Design principle

Keep the hardware cheap and deliberately simple. Put the intelligence in Mugen Deej.

```text
buttons / toggles / encoders / analog controls
                  |
                  v
          simple MCU firmware
                  |
                  v
          Mugen serial protocol
                  |
                  v
        Mugen routing + profiles
          |        |        |
          v        v        v
        audio    actions   virtual HID
```

Changing what a control does should normally be a profile/configuration change, not a firmware change.

## Candidate first large prototype

A practical first prototype target is:

- Arduino Nano-class controller;
- 5 analog controls;
- 30 momentary buttons in a 5×6 switch matrix;
- one diode per matrix key (1N4148-class part);
- 2 latching guarded toggle switches;
- 1 quadrature rotary encoder;
- USB serial connection to Mugen Deej.

This configuration is **not hardware-tested yet**.

### ATmega328P / classic Nano pin-budget sketch

With `D0/D1` reserved for serial, a classic Nano exposes enough usable pins for this target if the two guarded toggles are read through the analog-only `A6/A7` inputs:

- `A0–A4` — five analog controls;
- `D2–D13` + `A5` — 13 digital-capable lines total;
- 11 of those digital lines — 5×6 button matrix;
- remaining 2 digital lines — quadrature encoder A/B;
- `A6/A7` — two latching toggles read with `analogRead()` and suitable external pull-up/pull-down wiring.

That uses the classic Nano almost completely without an I/O expander.

If the encoder also has a push switch, that push input needs an additional strategy: use one matrix position, reduce the ordinary button count by one, or add an I/O expander/shift-register solution.

## Control semantics Mugen should eventually understand

The physical controls are not all the same kind of input, even if early firmware temporarily transports some of them using existing button fields.

- **Momentary button** — press/release state.
- **Latching toggle** — persistent OFF/ON state; future mappings may support separate ON and OFF actions.
- **Rotary encoder** — directional step input (clockwise/counter-clockwise), not merely two user-visible buttons.
- **Analog control** — continuous value suitable for audio or virtual axes.

Dedicated toggle/encoder protocol semantics are **not implemented yet**. The existing Extended parser currently knows the released/pressed button model and analog controls; any protocol extension for encoder steps or typed switches must remain backward-compatible.

## Output direction

A future profile should be able to route those physical primitives to different output families, for example:

- Windows audio targets;
- existing Mugen actions/hotkeys/media/launch actions;
- Xbox/XInput virtual controller buttons and axes;
- future Generic/DirectInput buttons, hats and axes;
- future simulator-specific integrations if they are added without making the microcontroller application-specific.

This is why Profiles are a core part of the long-term architecture: one inexpensive physical panel can become a different device by changing its Mugen profile.

## Protocol / bandwidth note

The current parser ceiling of 64 packet fields is sufficient for the rough control count of this prototype, but the existing 9600-baud reference cadence is not a good target for a much larger full-state packet.

Before building the large prototype firmware, Mugen should gain a deliberate higher/configurable serial-rate path. `115200` baud is a candidate for prototype work, but it is **not hardware-validated yet** and should not be treated as a final requirement until tested.

## Longer-term hardware options

If a later prototype needs more controls than fit directly on a Nano, prefer cheap commodity expansion rather than a more expensive MCU solely for pin count. Candidate approaches include:

- 74HC165-style parallel-in shift registers for large button banks;
- MCP23017-class I/O expanders;
- larger matrix arrangements where electrically appropriate.

The exact expansion method is secondary to the main rule: keep the physical device inexpensive and generic, and keep user-facing behavior in Mugen Deej.

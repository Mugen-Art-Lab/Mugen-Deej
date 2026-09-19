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

## Arbitrary DIY controllers instead of firmware-defined HID devices

A major long-term goal is that a DIY device does **not** need to implement its own USB HID game-controller personality at all.

For the Windows implementation, the microcontroller's job should normally stop at reporting physical inputs over the Mugen serial protocol. Mugen Deej then owns the difficult PC-side responsibilities:

- physical-input discovery;
- mapping and profiles;
- XInput / virtual gamepad output;
- future Generic / DirectInput-style virtual devices;
- axis/button/hat semantics;
- virtual-device lifecycle and cleanup.

That should make very different low-cost devices possible without writing a different HID firmware for every project. Examples include:

- DDR / metal dance pads;
- arcade panels and fight controls;
- sim-racing button boxes;
- flight-sim switch and encoder panels;
- space-sim cockpit panels;
- large macro/button decks;
- unusual one-off game controllers built around whatever physical controls are useful.

The intended mental model is:

```text
custom physical controller
        |
        | simple serial input description/state
        v
     Mugen Deej
        |
        | profile-defined routing
        v
Windows audio / actions / virtual game controller
```

The firmware should know **what physical inputs exist and what state they are in**, but normally should not need to know what game they belong to or what Windows control they eventually become.

This concept is currently proven only in part: the existing Nano/Extended controller can already travel through Mugen serial input into a real Xbox/XInput virtual controller recognized by Windows and a real game. Arbitrary Generic/DirectInput layouts and portable profile exchange are still planned work, not completed features.

## Portable profiles and sharing

Profiles should eventually be portable enough that a user can configure a physical controller once, export the profile, and import it on another Windows system running Mugen Deej.

A profile must therefore describe **logical hardware capabilities and mappings**, not transient machine details such as `COM10`.

The export/import design should aim to carry at least:

- profile name and schema version;
- expected physical-control shape/capabilities;
- button actions;
- analog destinations and calibration/inversion data where appropriate;
- encoder and toggle mappings once those become first-class inputs;
- virtual-controller enabled/type;
- virtual button/axis/hat mappings;
- optional presentation metadata such as control labels.

Machine-specific resources need careful handling. A profile may refer to an application, executable, file, folder, URL, audio device or another local resource that does not exist on a second PC. Import should preserve what can be preserved, clearly mark unresolved machine-specific targets, and let the user repair them without losing the rest of the profile.

Hardware compatibility should be capability-based and degrade gracefully:

- the COM-port number is never the controller identity;
- a compatible controller with the same logical shape should be able to use the imported profile even if Windows assigns another COM port;
- missing physical controls should leave the corresponding mappings unavailable instead of breaking the profile;
- extra physical controls should appear unassigned until the user maps them;
- future typed inputs such as encoders and toggles should be matched by type and logical position/identity rather than being flattened permanently into ordinary buttons.

A practical end-state example is a DIY metal dance pad: wire the switches to a cheap MCU, let the firmware report them to Mugen, map the directions and service buttons once, save/export a `DDR Pad` profile, and reuse that profile on another Windows installation without teaching the microcontroller anything about HID descriptors or game APIs.

Profile export/import is therefore a core architectural capability, not merely a backup convenience.

## Candidate first large prototype

The first large prototype has moved from paper planning into a real cardboard bring-up build.

Actual first physical control set:

- Arduino Uno for initial testing, with Nano migration planned after validation;
- five analog channels represented temporarily by software placeholders until potentiometers are fitted;
- 4×8 switch matrix;
- 28 standalone momentary buttons in C1..C7 across four rows;
- 2 latching toggles in R1C8 / R2C8;
- one diode per populated matrix position (1N4148-class part);
- one ready-made quadrature encoder module with separate S1/S2/KEY/5V/GND;
- encoder push uses the module's dedicated KEY line rather than a matrix position;
- USB serial connection to Mugen Deej.

Current Uno pin budget:

- D2/D3 — encoder S1/S2;
- A2 — encoder KEY;
- D4..D11 — matrix columns C1..C8;
- D12/D13/A0/A1 — matrix rows R1..R4;
- D0/D1 — USB serial, reserved;
- A3..A5 remain free on Uno while software slider placeholders are used.

Dedicated firmware/wiring notes for the actual build live in:

- `arduino/MugenDeejCardboardUnoPrototype/MugenDeejCardboardUnoPrototype.ino`
- `arduino/MugenDeejCardboardUnoPrototype/README.md`

The earlier `MugenDeejPanelPrototype` 5×6 sketch remains useful as design history, but it no longer describes the exact first physical panel.

The current physical build is **not hardware-tested yet**. Its intended Adaptive topology is 5 / 28 / 2 / 1 at 115200 baud.

## Control semantics Mugen should eventually understand

The physical controls are not all the same kind of input, even if early firmware temporarily transports some of them using existing button fields.

- **Momentary button** — press/release state.
- **Latching toggle** — persistent OFF/ON state; future mappings may support separate ON and OFF actions.
- **Rotary encoder** — directional step input (clockwise/counter-clockwise), not merely two user-visible buttons.
- **Analog control** — continuous value suitable for audio or virtual axes.

Dedicated toggle/encoder protocol semantics are **not implemented yet**. The first panel firmware deliberately uses a compatibility shim so the existing Extended parser can still understand the control count:

- matrix positions are `b` fields;
- the two toggles are temporarily stateful `b` fields;
- encoder CW/CCW detents are temporarily short synthetic `b` pulses;
- the five analog controls remain normal `s` fields.

That temporary mapping appears as **5 analog controls + 34 button-like fields = 39 total fields**, still below the current parser ceiling of 64.

Long term, encoder and toggle types should become first-class Mugen inputs without breaking older Extended controllers.

## Output direction

A future profile should be able to route those physical primitives to different output families, for example:

- Windows audio targets;
- existing Mugen actions/hotkeys/media/launch actions;
- Xbox/XInput virtual controller buttons and axes;
- future Generic/DirectInput buttons, hats and axes;
- future simulator-specific integrations if they are added without making the microcontroller application-specific.

This is why Profiles are a core part of the long-term architecture: one inexpensive physical panel can become a different device by changing its Mugen profile.

## Protocol / bandwidth note

The current parser ceiling of 64 packet fields is sufficient for this prototype, but the existing 9600-baud reference cadence is not suitable for a roughly 39-field full-state packet.

The experimental panel firmware therefore starts at **115200 baud** with a 25 ms heartbeat. This is a prototype choice, not yet a hardware-validated product requirement.

### Staged desktop auto-baud path

The experimental development runtime now has a staged automatic serial-rate probe while stable `main` remains untouched.

Behavior:

- existing controllers still prefer `9600` first on a clean or migrated configuration;
- the same COM port is opened only once, so trying a second rate does not deliberately reset the Nano a second time;
- after the normal MCU startup wait, the open `SerialPort` is tested at candidate baud rates by changing `BaudRate` in place;
- automatic mode currently considers the remembered successful rate, the configured rate, `9600`, and `115200`, with duplicates removed;
- protocol acceptance still requires multiple valid Mugen packets with the same protocol/slider/button signature, reducing the chance that wrong-baud garbage is mistaken for a controller;
- after a successful probe, `lastWorkingBaudRate` is saved and tried first on the next connection;
- a `fixed` config mode remains available for diagnostics or unusual custom hardware.

The staged implementation passed Windows PowerShell 5.1 parsing and the normal integration CI in workflow run #16 (`35172137771`). It is **CI PASS / hardware regression test pending**. The next real-hardware check is to confirm that the existing 9600-baud Extended 5+6 controller still connects normally before testing a 115200-baud device.

## Longer-term hardware options

If a later prototype needs more controls than fit directly on a Nano, prefer cheap commodity expansion rather than a more expensive MCU solely for pin count. Candidate approaches include:

- 74HC165-style parallel-in shift registers for large button banks;
- MCP23017-class I/O expanders;
- larger matrix arrangements where electrically appropriate.

The exact expansion method is secondary to the main rule: keep the physical device inexpensive and generic, and keep user-facing behavior in Mugen Deej.

# Mugen Deej — control model

This document defines the intended user-facing control model for Mugen Deej as it grows from a deej-style audio controller into a software-defined DIY control-surface platform.

## Core terms

### Profile

A **Profile** is the complete configuration for one use case or device role, for example:

- `Desktop`;
- `Elite Dangerous`;
- `MSFS`;
- `DDR Pad`;
- `Streaming`.

A profile may eventually own:

- ordinary button actions;
- analog/audio destinations;
- virtual-controller enabled/type;
- virtual button/axis/hat mappings;
- labels and presentation metadata;
- calibration/inversion settings;
- typed input mappings for encoders and toggles;
- one or more layers.

Profiles are intended to be exportable/importable. They must not depend on transient details such as a Windows COM-port number.

### Layer

A **Layer** is an alternate mapping set inside one profile.

Layers are deliberately lighter than profiles. Switching a layer should normally change how existing physical inputs are interpreted without recreating the serial connection or virtual HID device.

Example:

```text
Profile: Elite Dangerous

Layer 0: Default flight
Layer 1: Navigation
Layer 2: Combat
Layer 3: Engineering
```

A simple controller can ignore layers completely and behave exactly like current Mugen Deej. Layers are an optional advanced feature.

### Momentary button

A **Button** has press/release state. Its assigned action may depend on the current profile and layer.

For large button panels, Mugen must keep live physical identification visible: pressing a real button should visibly highlight/select the matching numbered input in the UI.

### Latching toggle

A **Toggle** has persistent `OFF` / `ON` state.

A toggle should eventually be configurable as one of several roles rather than being hard-coded to one behavior:

- normal stateful virtual input;
- separate `ON` and `OFF` actions;
- layer selector/modifier;
- profile selector where explicitly requested;
- no action / diagnostics only.

Layer selection is preferred over full profile switching for fast in-profile modifiers because it does not require recreating the controller or changing the whole configuration context.

With two binary toggles a profile may optionally expose four layer states:

```text
T1 OFF, T2 OFF -> Layer 0
T1 ON,  T2 OFF -> Layer 1
T1 OFF, T2 ON  -> Layer 2
T1 ON,  T2 ON  -> Layer 3
```

This is optional power-user behavior, not a requirement for ordinary users.

### Rotary encoder

An **Encoder** is a directional step source, not conceptually two ordinary buttons.

Its first-class model should expose:

- clockwise step;
- counter-clockwise step;
- optional push switch as a separate button input.

The current large-panel firmware temporarily transports encoder rotation as two synthetic button pulses only as a compatibility shim. That transport detail should not become the permanent user-facing model.

### Analog control

An **Analog control** is a continuous value. It may route to audio, a virtual axis, simulator-specific output, or other future destinations.

## Profile vs layer

The practical distinction is:

- **Profile** answers: “what is this panel being used for?”
- **Layer** answers: “which mapping page is active inside that use case?”

Example:

```text
Profile: MSFS
  Layer: Normal flight
  Layer: Radio
  Layer: Autopilot

Profile: Desktop
  Layer: Default
```

Switching from `MSFS` to `Desktop` is a profile change. Holding or toggling a modifier that changes the meaning of the same physical buttons inside `MSFS` is a layer change.

## UI principles for large controllers

The UI must adapt to control count without losing live diagnostics.

### Main window

Small controllers can keep the current large numbered button tiles.

Large controllers should use smaller wrapped tiles so all physical buttons remain visible without a horizontal scrollbar. A pressed input must still light its exact tile.

The current staged prototype uses this rule:

- up to 11 buttons: existing large one-row tiles;
- above 11: compact wrapped live grid.

### Button Settings

A one-row-per-button editor does not scale to 30+ controls.

For large controllers the intended interaction is:

- numbered live selector grid;
- one editor for the currently selected physical button;
- pressing a real physical button automatically selects its matching tile;
- the selected tile remains visually distinct;
- small controllers retain the simpler existing row-based editor.

The current staged implementation switches to the compact selector/editor above 12 buttons.

### Future typed controls

When toggles and encoders become first-class inputs, the main diagnostics surface should show them separately instead of flattening them permanently into the button grid.

Possible presentation:

```text
Buttons:  [1] [2] [3] ...
Toggles:  T1 OFF   T2 ON
Encoder:  E1  <  push  >
Profile:  Elite Dangerous
Layer:    Combat
```

The exact visual design is not final, but the UI must make it obvious which physical control Mugen is receiving while wiring and testing custom hardware.

## Compatibility rules

- Existing Legacy and Extended devices must keep working without profiles/layers being mandatory.
- A permanent default profile should preserve migrated current behavior.
- Typed controls must be introduced without breaking old `s` / `b` packets.
- Missing controls in an imported profile should become unavailable, not corrupt the profile.
- Extra controls should appear unassigned.
- Controller identity must not be tied to a COM-port number.
- Firmware should report physical inputs; the PC-side profile/layer model determines meaning.

## Current implementation status

Implemented/proven today:

- dynamic Extended slider/button counts;
- real 5-control / 6-button hardware;
- real 115200 test transport recognized as 5 controls / 34 buttons;
- PC-side Xbox/XInput virtual output;
- staged adaptive high-button-count UI in the development build.

Planned/not yet first-class:

- Profiles UI and storage schema;
- profile export/import;
- Layers;
- typed toggles;
- typed encoders;
- analog-to-virtual-axis routing;
- Generic / DirectInput virtual layouts.

Do not treat planned semantics as hardware PASS until they are implemented and exercised on physical hardware.

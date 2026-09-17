# Mugen Deej — profiles, layers and typed control architecture

This note captures the intended configuration model for arbitrary DIY Mugen control surfaces. It is design guidance, not a claim that every item below is implemented already.

## Core model

Mugen should distinguish four different concepts instead of flattening every physical input into an ordinary button.

### Profile

A **Profile** is the complete configuration for one use case.

Examples:

- `Desktop`;
- `Elite Dangerous`;
- `MSFS`;
- `DDR Pad`;
- `Streaming`.

A profile eventually owns the virtual-controller type, analog routing, button mappings, labels, typed-control mappings, layers and other behavior needed for that use case.

Changing profile means changing what the whole physical surface is being used for.

### Layer

A **Layer** is an alternate control layout inside the same profile.

Examples inside an `Elite Dangerous` profile:

- `Default` / flight;
- `Navigation`;
- `Combat`;
- `Engineering`.

Changing layer should be lightweight. It must not require reflashing the MCU or recreating the physical controller. Ideally it also does not recreate the virtual HID device; Mugen simply routes the same physical inputs through another mapping table.

Layers are optional. A simple profile can have only one default layer and never expose this concept to the user.

### Toggle

A **Toggle** is a persistent OFF/ON physical input.

Possible mappings should eventually include:

- ordinary ON/OFF actions;
- a held virtual-controller button while ON;
- separate action-on-ON and action-on-OFF behavior;
- optional layer selection/modification;
- no action.

A toggle is therefore not automatically a layer switch. Layer behavior is an opt-in mapping.

With two independent toggles, a user could optionally map the four physical states `00`, `01`, `10`, and `11` to four layers. This is powerful for cockpit-style panels, but it should remain an advanced capability rather than a required workflow.

### Encoder

A **Rotary Encoder** is a directional step source, not two permanent user-visible buttons.

The logical input should expose:

- clockwise step(s);
- counter-clockwise step(s);
- optional push switch as a separate momentary input.

Early firmware may temporarily transport CW/CCW as synthetic button pulses for compatibility, but the long-term Mugen model should preserve encoder semantics explicitly.

## Layer behavior and state safety

Layer changes must not leave stateful outputs stuck.

When changing layer, Mugen should eventually follow rules such as:

1. release stateful virtual outputs owned by the old layer before activating the new mapping;
2. do not fire ordinary press-edge actions merely because a layer changed while a physical button was already held;
3. reconcile persistent inputs such as toggles with the new layer deliberately;
4. keep the virtual controller itself alive when the output shape did not change;
5. log the layer change and the physical source that requested it.

This matters for XInput/DirectInput-style mappings where a held physical button can otherwise become a stuck virtual button after the mapping table changes underneath it.

## Main-window live diagnostics are required

Large controllers must still show which physical input Mugen is receiving.

A count-only summary such as `34 buttons` is not enough for DIY assembly and troubleshooting. A user wiring a panel needs to press a real switch and immediately see that Mugen received, for example, **Button 17**.

Therefore the main window should always preserve live physical button indicators:

- small controllers keep the existing roomy tiles;
- larger controllers use smaller wrapped tiles;
- pressed tiles remain visibly highlighted;
- the layout grows by rows instead of forcing a long horizontal scrollbar.

This is diagnostics first, decoration second.

## Large-controller Button Settings UI

The old one-row-per-button editor works well for six buttons but scales poorly to 30–60 inputs.

For larger controllers, the intended editor is:

```text
Physical buttons                 Selected button 17

[ 1 ][ 2 ][ 3 ][ 4 ][ 5 ]       Action:
[ 6 ][ 7 ][ 8 ][ 9 ][10 ]       [ Gamepad — X              v ]
[11 ][12 ][13 ][14 ][15 ]
[16 ][17 ][18 ][19 ][20 ]       ● live state
...
```

Important behavior:

- every numbered tile is a live physical-state indicator;
- clicking a tile selects that physical button for editing;
- pressing a real physical button automatically selects its numbered tile;
- only the selected button's action editor is shown in large-controller mode;
- small controllers keep the simpler existing row editor;
- virtual-gamepad mappings, hotkeys, launch actions and other existing actions continue to use the same underlying action model.

The first staged implementation uses a threshold of more than 12 buttons for the compact editor. This threshold is an implementation detail and may be tuned after real use.

## Future typed-control diagnostics

Once toggles and encoders become first-class protocol inputs, the main UI should not pretend that they are ordinary buttons.

A future diagnostic presentation can expose, for example:

```text
Buttons:  [1][2][3] ...
Toggle 1: OFF
Toggle 2: ON
Encoder 1:  ↶   ●   ↷
Layer: Combat
```

The encoder directions can flash briefly when steps are received; the center can represent the encoder push switch when present.

## Automatic hardware understanding

The current desktop client can already discover Legacy/Extended packet shape dynamically and the staged development build can probe `9600` and `115200` baud automatically.

That is not yet enough to distinguish future semantic input types. A packet containing 34 `b` fields tells Mugen that 34 button-like states exist, but not which two are toggles or which two synthetic pulses came from an encoder.

The long-term protocol therefore needs a backward-compatible way to expose typed capabilities without breaking existing Legacy and Extended controllers.

Possible requirements for that future capability description:

- input type: button / toggle / encoder / analog;
- stable logical index within the device shape;
- optional encoder push relationship;
- optional matrix/layout metadata for presentation only;
- protocol/schema version;
- no dependency on transient COM-port numbers.

Until that exists, the large-panel prototype deliberately uses the existing `s`/`b` compatibility transport.

## Relationship to portable profiles

Profiles and layers should be exportable together.

A portable profile should eventually contain:

- profile identity/name and schema version;
- expected logical hardware capabilities;
- layer definitions;
- mappings per layer;
- toggle-to-layer modifier rules where configured;
- typed encoder/toggle mappings;
- virtual-controller output configuration;
- presentation labels.

Machine-specific resources still require rebinding on another PC where necessary, but layer structure and logical control mappings should survive profile export/import.

## Current implementation boundary

Implemented or hardware-proven today:

- Legacy and Extended serial discovery;
- dynamic slider/button counts;
- staged automatic `9600` / `115200` probing;
- ordinary button actions;
- integrated Xbox/XInput virtual button routing;
- live button-state visualization;
- real virtual game-controller input in Windows and a game.

Planned / experimental:

- adaptive high-button-count UI is currently staged for hardware/UI testing;
- Profiles are designed but not implemented;
- Layers are designed but not implemented;
- typed Toggle and Encoder protocol fields are designed conceptually but not implemented;
- Generic/DirectInput output is planned;
- profile export/import is planned.

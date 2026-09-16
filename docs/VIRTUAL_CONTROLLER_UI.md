# Virtual controller UI and routing design

Branch: `feature/virtual-gamepad-ui`

Living project/test state is tracked in `docs/PROJECT_STATE.md`. That file is authoritative when this design note and current implementation temporarily differ.

## Goal

Add virtual game-controller output without turning Mugen Deej into a game-specific application.

The hardware remains generic:

```text
hardware -> serial protocol -> Mugen Deej -> audio / actions / virtual controller
```

Legacy controllers remain unchanged. Extended controllers can optionally route buttons and analog controls to virtual-controller outputs.

## Product principles

- Keep the normal audio-only experience uncluttered.
- Extended protocol remains auto-detected; do not add a manual "Extended mode" switch.
- Do not expose implementation/backend names as the primary UX.
- Normal actions are edge-triggered; virtual buttons are stateful; virtual axes are continuous.
- Existing audio and macro behavior stays unchanged when virtual output is unused.
- Backend failure must not prevent Mugen Deej from starting or using normal audio/actions.
- On disconnect, suspend, helper/backend failure, profile change, or app exit, release every virtual button.
- Keep game-specific meaning on the PC side so the same cheap DIY hardware can be reused without reflashing.

## User-facing virtual-controller types

Do not present `DInput`, `XInput`, and `X360` as three equivalent peer modes. Xbox 360 is a concrete XInput/XUSB-style device profile.

Initial user-facing types:

### Xbox 360 / XInput

Compatibility-first mode for games expecting a conventional Xbox-style pad.

The logical control set is fixed by the Xbox controller shape, for example:

- A / B / X / Y
- LB / RB
- Back / Start
- stick clicks
- D-pad
- left/right sticks
- triggers

This mode is useful for ordinary games and an eventual Arcade/Fight Pad preset.

### Generic / DirectInput

Flexible mode for DIY panels, simulators, many buttons, and arbitrary axes.

This is the natural target for the planned 5 controls + 30 buttons hardware.

The backend may expose the same virtual device to several Windows APIs, but the UI should describe the controller shape/compatibility goal rather than make the user understand implementation details.

## Button settings

Add a virtual-controller mapping alongside the existing physical-button actions.

Possible UI entry:

- RU: `Виртуальный контроллер…`
- EN: `Virtual controller…`

For Generic/DirectInput mapping, selecting it can open a small editor:

- physical source: read-only `Кнопка N` / `Button N`
- output: `Button 1 ... Button N`
- convenience: `Использовать тот же номер` / `Use physical button number`
- Save / Cancel

Example persisted action:

```text
virtual:button:17
```

This can remain compatible with the existing `button-actions.json` idea for an early implementation, although the final profile system may move complete mappings into profile-owned data.

### Stateful runtime semantics

The current normal button-action path calls an action only when a physical button becomes pressed.

Virtual mappings must receive both transitions:

```text
physical b0 -> virtual button DOWN
physical b1 -> virtual button UP
```

Therefore virtual button routing must happen in physical-state transition processing, not only through the existing press-only `Invoke-ButtonAction` dispatcher.

## Xbox mapping UI

For `Xbox 360 / XInput`, output choices should use controller names rather than numbered generic buttons:

```text
A
B
X
Y
Left Bumper
Right Bumper
Back
Start
Left Stick Click
Right Stick Click
D-pad Up
D-pad Down
D-pad Left
D-pad Right
```

Triggers and stick axes belong in analog-control mapping rather than the normal physical-button action list unless a future preset deliberately supports digital-to-analog behavior.

## Analog-control settings

Add a mode:

- RU: `Виртуальная ось`
- EN: `Virtual axis`

When selected, the current target area becomes an axis selector.

For Generic/DirectInput an initial set can include:

- X
- Y
- Z
- Rx
- Ry
- Rz
- Slider 1
- Slider 2

For Xbox mode, user-facing names should be semantic:

- Left Stick X
- Left Stick Y
- Right Stick X
- Right Stick Y
- Left Trigger
- Right Trigger

Proposed early slider property:

```json
"virtualAxis": "x"
```

For the first implementation, virtual-axis mode can be exclusive with normal audio targets to keep behavior obvious. Mixed routing can be reconsidered later if there is a real use case.

## Virtual-controller status / global settings

Do not add a permanent large card for users who never enable virtual output.

A settings/diagnostics entry can open a dialog with:

- enable virtual-controller output;
- controller type;
- status: Disabled / Ready / Backend unavailable / Error;
- mapped buttons/axes summary;
- backend/version as diagnostic text only.

Default is OFF.

Mappings may be edited while output is disabled. Missing backend support should produce a clear warning, not delete mappings.

## Profiles

Profiles are now part of the intended architecture, but backend proof comes first.

Terminology:

- **Profile** = complete user configuration for the control surface.
- **Preset** = optional built-in template from which a profile can be created.

For Extended hardware, a compact main-window control may eventually look like:

```text
Profile: [ Desktop                 v ] [ Manage... ]
```

Profile management:

- New
- Duplicate
- Rename
- Delete
- Select

A permanent `Default` profile preserves current 1.0.0 behavior and migration safety.

A profile should eventually own:

- physical-button actions;
- analog-control destinations;
- virtual-controller enable state;
- virtual-controller type (`Xbox 360 / XInput`, `Generic / DirectInput`);
- virtual button/axis mappings;
- source hardware shape metadata (detected control/button count).

If a profile was built for a larger controller than the one currently connected, unavailable mappings are skipped with a warning. If the connected controller has extra controls, they remain unassigned until configured.

Manual profile switching comes first. Foreground-game automatic switching is deferred.

## Presets

Possible later presets:

- Desktop / Audio
- Streaming
- Xbox Gamepad
- Arcade / Fight Pad
- Generic 30-button panel
- Elite Dangerous
- MSFS / simulator base

A preset is only a starting template. It must not hard-wire the physical Arduino firmware to a particular game.

## Backend architecture

Current prototype candidate: HIDMaestro 1.8.0 (MIT).

HIDMaestro supports built-in controller profiles plus custom HID descriptors. It can therefore cover both the Xbox compatibility case and later arbitrary multi-button Generic/DirectInput devices.

Important Windows constraint: creating the HID device requires elevation. Do not elevate the entire Mugen Deej UI just for this feature.

Prototype architecture:

```text
Mugen / prototype bridge (normal user)
        |
        v named pipe
MugenDeej.VirtualGamepadHost (elevated)
        |
        v
HIDMaestro
        |
        v
virtual HID / Xbox controller
```

The final broker lifecycle and installation UX remain open until this path has passed real hardware tests.

## Main-window behavior

The existing physical-button indicators represent physical input, not virtual output.

For the first backend proof they remain unchanged.

For 30-button hardware, the current one-line scrolling strip is functionally valid but poor UX. A grid/matrix view should be designed after real 5x6 hardware is available and useful, rather than guessed in advance.

## Runtime routing model

```text
serial packet
    |
    +-- analog controls ----+--> audio targets
    |                       \--> virtual axes
    |
    +-- buttons ------------+--> press-triggered actions
                            \--> stateful virtual buttons
```

This is routing, not a single exclusive "game mode". One physical panel may eventually mix audio, macros and game-controller outputs.

## Current first milestone

Before integrating full profiles or axes, prove the backend end-to-end using the already-tested 5+6 Extended hardware.

The branch contains a standalone prototype harness that temporarily maps:

```text
button 1 -> Xbox A
button 2 -> Xbox B
button 3 -> Xbox X
button 4 -> Xbox Y
button 5 -> Xbox LB
button 6 -> Xbox RB
```

Acceptance:

1. physical Extended controller is recognized;
2. virtual Xbox controller appears in `joy.cpl`;
3. physical press produces virtual DOWN;
4. holding remains held;
5. release produces virtual UP;
6. teardown releases everything;
7. a real game accepts at least one binding.

Only after that path is physically PASS should it be integrated into normal Mugen Deej button settings.

## Next implementation order

1. Backend/joy.cpl physical proof.
2. Real-game bind proof.
3. Normal Mugen Deej backend abstraction and lifecycle.
4. Virtual button mappings in UI.
5. Safe release paths.
6. Virtual axes.
7. Custom Generic/DirectInput many-button device.
8. 5x6 hardware test.
9. User profiles and profile manager.
10. Better matrix UI if real usage justifies it.

## Deferred

- automatic foreground-game/profile switching;
- layers/pages;
- game telemetry back to hardware;
- LEDs/displays driven from games;
- force feedback;
- custom Mugen virtual-device driver;
- per-key LCD/OLED UI;
- plugin marketplace;
- matrix-layout editor.

# Virtual controller UI design

Branch: `feature/virtual-gamepad-ui`

## Goal

Add a virtual game-controller output path without turning Mugen Deej into a game-specific application.

The physical controller should remain generic:

`hardware -> serial protocol -> Mugen Deej -> audio/actions/virtual controller`

Legacy controllers remain unchanged. Extended controllers can optionally route buttons and analog controls to a virtual controller.

## Product principles

- Keep the main window uncluttered for existing audio-only users.
- Do not tie UI wording to a specific backend such as vJoy/ViGEm.
- Treat virtual buttons as stateful outputs: press must stay down until the physical button is released.
- Treat virtual axes as continuous outputs, not edge-triggered actions.
- Existing audio and macro actions continue to work exactly as before when virtual output is unused.
- If the virtual-controller backend is missing or unavailable, Mugen Deej should stay usable and report the problem clearly instead of failing startup.

## Button settings

Add one new configurable action to the existing physical-button action list:

- RU: `Виртуальный контроллер…`
- EN: `Virtual controller…`

Selecting it opens a small editor:

- title: `Виртуальная кнопка` / `Virtual button`
- physical source: read-only `Кнопка N` / `Button N`
- output: `Button 1 ... Button 64`
- convenience option: `Использовать тот же номер` / `Use physical button number`
- Save / Cancel

Saved display text in the normal button list:

- RU: `Виртуальная кнопка 17`
- EN: `Virtual button 17`

Proposed persisted action string:

`virtual:button:17`

This can remain in `button-actions.json`, so current backup/restore naturally carries the mapping.

### Important runtime semantic difference

Normal actions are edge-triggered on physical press.

A virtual-button mapping must instead receive both transitions:

- physical `b0` -> virtual button DOWN
- physical `b1` -> virtual button UP

Therefore the runtime path must handle `virtual:button:N` inside button-state transition processing, rather than calling it only through the existing press-only action dispatcher.

On disconnect, suspend, backend failure, or app exit, all virtual buttons must be released to prevent stuck inputs.

## Analog-control settings

Add one mode to the existing control-mode combo:

- RU: `Виртуальная ось`
- EN: `Virtual axis`

When selected, the current application/microphone chooser area becomes an axis selector.

Initial axis set:

- X
- Y
- Z
- Rx
- Ry
- Rz
- Slider 1
- Slider 2

No backend-specific names should appear here.

Proposed slider property:

`virtualAxis: "x"`

When `virtualAxis` is non-empty, the slider is routed to that virtual axis. For the first implementation this mode is exclusive with normal audio targets, which keeps the UI and runtime behavior unambiguous.

The current global invert-sliders option continues to affect the normalized value before virtual-axis output. Per-axis calibration/inversion is intentionally deferred.

On disconnect or backend shutdown, axes should be returned to a defined neutral policy chosen by the backend implementation.

## Virtual controller status / global settings

Do not add a permanent top-level card to the normal main window.

Place a `Virtual controller...` entry in the existing advanced/diagnostics area.

The dialog should contain:

- `Enable virtual controller output` checkbox
- status line:
  - Disabled
  - Ready
  - Backend not available
  - Error
- backend name/version shown as diagnostic text only
- a small summary derived from saved mappings, for example:
  - `18 mapped buttons`
  - `3 mapped axes`
- `Test` section in a later pass

Default is OFF so existing users never get a surprise virtual device.

Mappings may be configured while output is disabled. If mappings exist but the backend is unavailable, save them normally and show an amber warning/status instead of discarding them.

## Main-window behavior

Keep the existing physical-button indicator strip unchanged for the first pass. It represents physical input state, not virtual output state.

For 30-button hardware this strip already scrolls horizontally. A matrix-style visualization can be designed separately after the 5x6 prototype proves useful.

## Data model draft

`button-actions.json`:

```json
{
  "schemaVersion": 1,
  "actions": [
    "virtual:button:1",
    "virtual:button:2",
    "media:playpause"
  ]
}
```

`config.json` additions:

```json
{
  "virtualController": {
    "enabled": false,
    "backend": "auto"
  },
  "sliders": [
    {
      "name": "Control 1",
      "targets": [],
      "virtualAxis": "x"
    }
  ]
}
```

`backend` is deliberately abstract in the config/UI draft. Backend selection should be decided after checking the best maintained Windows virtual-controller option for generic multi-button joystick use.

## Runtime routing model

```text
serial packet
    |
    +-- sliders --------+--> audio targets
    |                   \--> virtual axes
    |
    +-- buttons --------+--> edge-triggered actions
                        \--> stateful virtual buttons
```

This is intentionally routing, not a separate "game mode". A future controller may mix audio controls, macros, and virtual-game-controller outputs at the same time.

## First implementation milestone

Before profiles, layers, game presets, or special simulator integrations:

1. Detect the existing Extended controller normally.
2. Save `virtual:button:N` mappings from the UI.
3. Enable the virtual-controller backend.
4. Press/release a physical button.
5. Verify the matching virtual button changes state in `joy.cpl`.
6. Map that button inside a real game.

Only after that path is reliable should virtual axes be enabled and tested.

## Explicitly deferred

- profiles per game
- layers/pages
- automatic foreground-game switching
- LEDs/displays/feedback from games
- force feedback
- custom kernel driver
- Xbox-specific controller emulation
- matrix layout editor

These are separate features, not requirements for the first virtual-controller implementation.

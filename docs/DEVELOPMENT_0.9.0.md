# Mugen Deej 0.9.0 development notes

Branch: `feature/controller-autodetect-buttons`

This branch is the laboratory for controller auto-detection and button support. The stable `main` branch remains the released 0.8.7 line until this work is proven safe.

## Core rule

Do not rewrite or casually modify the proven Windows audio, USB/serial reconnect, startup, suspend/resume, mapping, or Core Audio behavior. New controller support should be added as a protocol/capabilities layer in front of the existing slider path.

## Protocols to support

### Classic / legacy deej

Example frame:

```text
512|123|900|42|777
```

All fields are analog controls in the range 0..1023. The control count is detected from the valid frame instead of being assumed to be five.

### Extended s/b protocol

Example frame:

```text
s512|s123|s900|s42|s777|b1|b1|b0|b1|b1|b1
```

- `s` fields are analog controls, 0..1023.
- `b` fields are buttons.
- With `INPUT_PULLUP`, `b1` means released and `b0` means pressed.
- Slider and button counts are detected from a valid frame.
- This format is compatible with the button-prefixed protocol used by the Miodec/deej fork.

The application should not expose "Miodec mode" as a user-facing product mode. User-facing wording should stay generic: Standard/Classic or Extended controller, with detected control/button counts.

## Reference hardware currently available for testing

Current button-controller sketch/wiring supplied during development:

- 5 analog controls: `A0, A1, A2, A3, A4`
- 6 buttons: digital pins `9, 8, 7, 6, 5, 4`
- buttons use `INPUT_PULLUP`
- serial: 9600 baud
- frame interval: approximately 10 ms

This existing sketch is useful as the first compatibility target and should remain unchanged until the client can read it reliably.

## Mugen reference sketch

`arduino/MugenDeejController/MugenDeejController.ino` is the clean reference sketch for new Mugen builds.

Design goals:

- preserve the extended `s`/`b` wire format;
- no dynamic Arduino `String` construction in the hot loop;
- send fields directly with `Serial.print`;
- keep wiring/configuration obvious near the top of the file;
- keep raw button polarity compatible with `INPUT_PULLUP` (`0 = pressed`, `1 = released`);
- allow a controls-only build by setting `MUGEN_DEEJ_HAS_BUTTONS` to `0`;
- leave button debouncing primarily to the PC client so debounce behavior can be tuned without reflashing the Arduino.

## Planned implementation stages

### 0.9.0-dev1 — protocol and capabilities only

- Parse classic numeric frames.
- Parse extended `s`/`b` frames.
- Auto-detect protocol, control count, and button count from valid serial data.
- Re-detect capabilities after reconnect/device replacement.
- Feed detected slider values into the existing slider/audio path.
- Log button press/release events only; do not generate Windows input yet.
- Show detected capabilities in status/diagnostics.
- Invalid or changing/malformed frames must be ignored safely, never crash the app.

### 0.9.0-dev2 — button UI

- Button section appears only when buttons are detected.
- Number of button rows follows detected capabilities rather than static config.
- Show button identity/state for diagnostics.
- Preserve existing slider configuration and old configs.

### 0.9.0-dev3 — actions

Initial action ideas:

- Disabled / no action
- Mute/unmute the target assigned to a selected physical control
- Play/Pause
- Previous / Next media
- Microphone mute/unmute
- Keyboard key / shortcut
- Later: launch application or other explicit actions

Actions must be bounds-checked. Missing mappings, unexpected button IDs, malformed serial data, or a different controller layout must never crash Mugen Deej.

## Button debounce

The current hardware sends raw button state. Mechanical bounce may produce rapid transitions. Prefer a small client-side debounce/stability window (initial target roughly 20–30 ms) rather than baking policy into the reference firmware. Press/release state still needs to remain responsive and deterministic.

## Compatibility goals

One Mugen Deej client should support:

1. Existing classic deej controllers without requiring reflashing.
2. Existing `s`/`b` button-controller sketches such as the Miodec-style protocol.
3. New controllers built with the Mugen reference sketch.

There should be two wire-protocol families, not three separate application editions.

## Regression test matrix before merge to main

Test both a classic knobs-only controller and the 5-control + 6-button controller:

- initial detection
- correct control order and values
- correct button order and press/release polarity
- malformed serial lines
- stationary/noisy potentiometers
- repeated button presses and bounce behavior
- unplug/replug
- reconnect after COM changes
- replace one controller type with the other
- suspend / resume / hibernation
- Windows startup / startup minimized to tray
- RU and EN UI
- Light / Dark / Auto theme
- existing 0.8.7 configuration migration

Only after these tests are clean should the feature branch be considered for a PR into `main` and a public 0.9.0 release.

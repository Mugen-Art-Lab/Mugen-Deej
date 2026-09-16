# Virtual gamepad prototype

This is a development-only harness for the `feature/virtual-gamepad-ui` branch. It exists to prove the complete physical-button -> Mugen bridge -> virtual controller -> Windows/game path before the feature is merged into the main Mugen Deej UI.

## What it does

- scans COM ports at 9600 baud for an Extended Mugen Deej packet;
- requires at least one `s...` field and one `b...` field;
- launches an elevated helper process that creates a virtual Xbox 360 controller through HIDMaestro;
- maps the first six physical buttons to A, B, X, Y, LB, RB;
- keeps press and release state, so held physical buttons stay held virtually;
- opens `joy.cpl` automatically for the smoke test;
- releases all virtual buttons and removes the virtual controller when the prototype exits.

## Test steps

1. Close the normal Mugen Deej application so it does not own the controller COM port.
2. Connect the known-good Extended controller.
3. Run `RUN-VIRTUAL-GAMEPAD-PROTOTYPE.cmd`.
4. Accept the UAC prompt for the virtual-controller host.
5. In the automatically opened Game Controllers window, open Properties for the virtual Xbox controller.
6. Press and hold each physical button, then release it.
7. Confirm the matching virtual button changes state while held and clears on release.
8. Press `Q` or `Esc` in the prototype console to stop.

Optional explicit COM port:

```text
RUN-VIRTUAL-GAMEPAD-PROTOTYPE.cmd -Port COM5
```

## Expected first milestone

PASS only when a real Extended controller drives the matching virtual button in `joy.cpl` for both DOWN and UP transitions.

After that, test binding inside a real game. The prototype is not considered integrated into Mugen Deej until the same backend is routed through the normal UI and configuration model.

## Important prototype limitations

- Xbox 360 output only.
- First six physical buttons only.
- No axes yet.
- No profiles yet.
- The helper currently requires elevation for its lifetime because HIDMaestro/Windows requires admin rights to create the virtual HID device.
- The normal Mugen Deej application and this prototype cannot own the same serial port simultaneously.
- This harness is intentionally separate from the stable 1.0.0 runtime.

## Backend

Pinned for this prototype:

- HIDMaestro 1.8.0
- release archive SHA-256: `1e5f5019c20e4be8f922c7aa5a86ee87eb01f7aa851fe38daea14d0ce4fd8240`
- license: MIT

The GitHub Actions prototype build downloads that exact release, verifies the archive hash, builds a self-contained x64 helper, and includes the HIDMaestro license in the artifact.

## Logs

The elevated helper writes diagnostics to:

```text
%TEMP%\MugenDeej-VirtualGamepadHost.log
```

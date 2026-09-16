# Mugen Deej — virtual gamepad integration

Living implementation/test note for the product integration phase on `feature/virtual-gamepad-ui`.

## Status

Prototype 0 backend proof: **PASS**.

Integrated Mugen Deej milestone 1: **PARTIAL REAL-HARDWARE PASS / NONBLOCKING STARTUP HARDWARE RE-TEST PENDING**.

The stable `main` / v1.0.0 source and release are not modified by this experiment.

## Integrated milestone 1

Goal: move the proven Xbox/XInput path from the standalone prototype into the real Mugen Deej UI/runtime without changing normal 1.0.0 behavior for users who do not enable it.

Current scope:

- virtual controller is OFF by default;
- only Extended controllers with physical buttons can drive it;
- Button Settings gains a `Virtual controller` selector with:
  - `Off`
  - `Xbox 360 / XInput`
- physical button destinations gain Xbox button mappings through a dedicated visual picker;
- virtual button output is stateful and is updated from `Update-ButtonStates`, before the existing press-edge action dispatcher;
- virtual mappings are ignored by the old press-only `Invoke-ButtonAction` path;
- physical-controller disconnect tears down the virtual controller;
- the proven elevated helper / named-pipe / HIDMaestro lifecycle is reused;
- normal stop waits for helper cleanup and does not force-kill the helper during HID/PnP teardown;
- display label remains `Mugen Deej Virtual Gamepad`;
- virtual-controller setting is temporarily stored in `virtual-controller.json` next to the app.

Not in milestone 1:

- virtual analog axes;
- D-pad/hat mapping;
- triggers;
- Generic / DirectInput mode;
- user profiles/presets;
- backup/restore integration for `virtual-controller.json`;
- final source consolidation / release packaging.

## Files

- `src/virtual-gamepad-helper/` — proven elevated .NET/HIDMaestro helper.
- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.ps1` — Mugen-side virtual-controller service.
- `tools/Build-VirtualGamepad-Integration.ps1` — experimental patch/staging step that injects the integration hooks into a development copy of `MugenDeej.ps1`.
- `tools/Harden-VirtualGamepad-DevRuntime.ps1` — dev-only isolation plus staged compatibility fixes.
- `.github/workflows/build-virtual-gamepad-integration.yml` — isolated development package build.

The patch/staging approach is temporary. Before this work is release-ready, the validated changes should be consolidated into normal source and the experimental patcher removed, matching the source-cleanliness approach used for v1.0.0.

## CI history

### Run 1

- workflow: `Build virtual gamepad integration`
- run ID: `35120305651`
- result: FAIL during staging
- cause: one patcher regex used a double-quoted PowerShell string containing `$action`, so StrictMode could interpolate the token instead of treating it as literal source text.

Fix:

- commit `0f423de80bdeee2142cf3c5b971e7b4c4b3874b8` — make the pattern literal.

### Run 2

- workflow: `Build virtual gamepad integration`
- run ID: `35120553251`
- run number: `2`
- head: `0f423de80bdeee2142cf3c5b971e7b4c4b3874b8`
- result: **PASS**
- Windows PowerShell 5.1 parser check: PASS for both patched runtime and integration module
- helper publish/smoke test: PASS
- normal Mugen launcher build: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-2`
- artifact ID: `10457004970`
- outer Actions artifact digest: `sha256:64b4b32e4c3c94ef830ca138dd87892212dd1dccd80d1119d95a644be8ce46fa`
- inner development ZIP SHA-256: `2cc5b32ea56abbf5c82868fdcfe8ca9ed2fc2c65401313d87a3fb86ee43f327a`

### First real-hardware integration attempt

Real hardware: existing Extended 5-control / 6-button controller on COM10.

Observed after saving `Button 1 -> A`, `Button 2 -> B` and enabling Xbox/XInput:

- UI became severely laggy;
- virtual gamepad repeatedly appeared/disappeared;
- physical controller repeatedly disconnected/reconnected;
- saved virtual button mappings later appeared as `none`.

The log proved two independent integration bugs:

1. **Reentrant helper startup.** While `Start-MugenVirtualGamepad` waited for the elevated helper it called `Application.DoEvents()`. Incoming full-state serial packets re-entered `Update-MugenVirtualGamepadButtonStates`, which called `Start-MugenVirtualGamepad` again because the first startup had not yet marked the bridge active. Dozens of elevated helpers were started within seconds, starving normal serial processing until the 2500 ms controller timeout fired.
2. **Virtual mappings rejected by the stable action normalizer.** `Normalize-ButtonActions` from v1.0.0 did not recognize `virtual:xbox:*`, so capability re-detection rewrote valid saved virtual mappings to `none`.

Fixes:

- commit `aafb1c85784568228023e659bbeae4c0543e5fe1` — add a startup-in-progress guard so only one virtual-controller startup may exist at a time;
- commit `0e2ff9cc3086de1581d886410b9ad411c367bcb9` / follow-up `d255724b6e75e980289ad03cab38591b0690ff6a` — preserve validated virtual mappings through the existing action normalizer using literal source patching;
- commit `5bc2fee8db9a98c130b288a4142a4c88c9d0921a` — make Windows PowerShell 5.1 CI parser errors report correctly instead of colliding with the read-only `$Error` variable.

### Run 10

- workflow run ID: `35128191508`
- run number: `10`
- head: `d255724b6e75e980289ad03cab38591b0690ff6a`
- result: **PASS**
- staging: PASS
- Windows PowerShell 5.1 parser check: PASS
- reentrant-start guard static check: PASS
- helper publish/smoke test: PASS
- launcher build/package: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-10`
- artifact ID: `10459379492`
- inner development ZIP SHA-256: `95634c6036fccbfee44c012e171f1209c75c7b65401403d882afb21a7ffe73d6`

### Run 10 real-hardware re-test

Run 10 fixed the catastrophic integration failure:

- exactly one elevated helper startup was logged;
- COM10 stayed connected instead of entering the disconnect/reconnect loop;
- `Mugen Deej Virtual Gamepad` appeared in `joy.cpl` with neutral axes;
- physical button mappings A/B were routed successfully;
- reopening Button Settings preserved the saved mappings;
- adding another mapping after the gamepad was already active did not reproduce the startup lag.

One UX problem remained: first-time virtual-controller creation still blocked the Mugen UI while the helper performed HID/PnP setup. The log measured the blocking window from `00:07:15.908` (`Starting elevated virtual controller helper`) to `00:07:32.685` (`Virtual controller ready`), about **16.8 seconds** on the test PC. The controller itself could already trigger a Windows/Stream Deck device notification before Mugen's synchronous wait returned.

### Nonblocking startup fix

Commit `7308b73f2507d795cb1a0fd4c43dce11bb8ea5cc` changes the Mugen-side startup path from a synchronous `DoEvents()` / `Start-Sleep` wait loop to an asynchronous named-pipe wait polled by a WinForms timer.

Expected behavior:

- Save returns immediately after the UAC launch step;
- Mugen remains responsive while HIDMaestro creates/enumerates the Xbox device;
- serial processing continues normally during the 10–20 second Windows HID/PnP setup;
- while startup is pending, further full-state serial packets see the existing `starting` guard and do not launch another helper;
- once the helper connects, Mugen finalizes the pipe and immediately pushes the freshest full button state.

### Run 11

- workflow run ID: `35133757062`
- run number: `11`
- head: `7308b73f2507d795cb1a0fd4c43dce11bb8ea5cc`
- result: **PASS**
- staging: PASS
- Windows PowerShell 5.1 parser check: PASS
- helper publish/smoke test: PASS
- launcher build/package: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-11`
- artifact ID: `10462991104`
- inner development ZIP SHA-256: `d7e082d69f87bf0e73393760a7dfcf466c64ad7ddf88db00578988dfb761258e`

Run 11 is **CI PASS / nonblocking-start hardware re-test pending**. Do not call the startup-lag issue fixed on hardware until the user verifies that the actual Mugen UI stays interactive during first virtual-controller creation.

## First real-hardware test plan

Use the already-tested Extended 5-control / 6-button controller.

1. Close the stable Mugen Deej instance so the development build owns the COM port.
2. Run the integrated development `MugenDeej.exe` from a separate folder.
3. Confirm ordinary Mugen connection/audio behavior is still intact before enabling virtual output.
4. Open Button Settings.
5. Confirm the new `Virtual controller` row is present and defaults to `Off` on a clean folder.
6. Select `Xbox 360 / XInput`.
7. Map several physical buttons through `Choose gamepad button...`.
8. Save and accept UAC.
9. Confirm Mugen remains responsive while the virtual HID is being created and exactly one helper startup occurs.
10. Confirm the physical COM connection stays stable throughout startup.
11. Confirm `joy.cpl` shows `Mugen Deej Virtual Gamepad`.
12. Confirm press, hold, release and simultaneous button states work.
13. Reopen Button Settings and confirm virtual mappings are still present.
14. Force a physical-controller reconnect and confirm mappings survive capability re-detection.
15. Confirm ordinary non-gamepad button actions can coexist with virtual mappings on different physical buttons.
16. Close Mugen normally and verify the virtual controller disappears and does not return.
17. Start again with the saved configuration and verify persistence/reconnect behavior.
18. Hard-close once and verify bridge-loss cleanup still removes the virtual controller without reboot.
19. Re-check a real XInput game after integrated runtime validation.

Do not call integrated milestone 1 a complete hardware PASS until the above path has been tested on the real controller.

## Next after milestone 1 hardware PASS

1. Fold the proven integration into normal source instead of build-time patching.
2. Add a small user-facing status for the virtual controller if useful.
3. Add analog-control → virtual-axis routing.
4. Introduce the Profile model (Default + New/Duplicate/Rename/Delete/select).
5. Move virtual enabled/type/mappings into profiles.
6. Add Generic / DirectInput for arbitrary DIY shapes and many buttons.
7. Test the future 5-control + 30-button matrix hardware.

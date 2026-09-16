# Mugen Deej — virtual gamepad integration

Living implementation/test note for the product integration phase on `feature/virtual-gamepad-ui`.

## Status

Prototype 0 backend proof: **PASS**.

First integrated Mugen Deej development package: **CI PASS / REAL-HARDWARE TEST PENDING**.

The stable `main` / v1.0.0 source and release are not modified by this experiment.

## Integrated milestone 1

Goal: move the proven Xbox/XInput path from the standalone prototype into the real Mugen Deej UI/runtime without changing normal 1.0.0 behavior for users who do not enable it.

Current scope:

- virtual controller is OFF by default;
- only Extended controllers with physical buttons can drive it;
- Button Settings gains a `Virtual controller` selector with:
  - `Off`
  - `Xbox 360 / XInput`
- physical button destinations gain:
  - Gamepad — A
  - Gamepad — B
  - Gamepad — X
  - Gamepad — Y
  - Gamepad — LB
  - Gamepad — RB
  - Gamepad — Back / View
  - Gamepad — Start / Menu
  - Gamepad — L3
  - Gamepad — R3
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

CI proves that the development package stages, parses under Windows PowerShell 5.1, builds the launcher/helper and packages successfully. It does **not** prove the integrated UI/runtime on physical hardware yet.

## First real-hardware test plan

Use the already-tested Extended 5-control / 6-button controller.

1. Close the stable Mugen Deej instance so the development build owns the COM port.
2. Run the integrated development `MugenDeej.exe` from a separate folder.
3. Confirm ordinary Mugen connection/audio behavior is still intact before enabling virtual output.
4. Open Button Settings.
5. Confirm the new `Virtual controller` row is present and defaults to `Off` on a clean folder.
6. Select `Xbox 360 / XInput`.
7. Map several physical buttons to Gamepad A/B/X/Y/LB/RB.
8. Save and accept UAC.
9. Confirm `joy.cpl` shows `Mugen Deej Virtual Gamepad`.
10. Confirm press, hold, release and simultaneous button states work.
11. Confirm ordinary non-gamepad button actions can coexist with virtual mappings on different physical buttons.
12. Close Mugen normally and verify the virtual controller disappears and does not return.
13. Start again with the saved configuration and verify persistence/reconnect behavior.
14. Hard-close once and verify bridge-loss cleanup still removes the virtual controller without reboot.
15. Re-check a real XInput game after integrated runtime validation.

Do not call integrated milestone 1 a hardware PASS until the above path has been tested on the real controller.

## Next after milestone 1 hardware PASS

1. Fold the proven integration into normal source instead of build-time patching.
2. Add a small user-facing status for the virtual controller if useful.
3. Add analog-control → virtual-axis routing.
4. Introduce the Profile model (Default + New/Duplicate/Rename/Delete/select).
5. Move virtual enabled/type/mappings into profiles.
6. Add Generic / DirectInput for arbitrary DIY shapes and many buttons.
7. Test the future 5-control + 30-button matrix hardware.

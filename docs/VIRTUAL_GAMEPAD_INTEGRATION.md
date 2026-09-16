# Mugen Deej — virtual gamepad integration

Living implementation/test note for the product integration phase on `feature/virtual-gamepad-ui`.

## Status

Prototype 0 backend proof: **PASS**.

Integrated Mugen Deej milestone 1: **PARTIAL REAL-HARDWARE PASS / NONBLOCKING TEARDOWN HARDWARE RE-TEST PENDING**.

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
- virtual-controller creation is nonblocking on the Mugen UI thread;
- virtual-controller teardown is also staged as background cleanup in the current dev build;
- a second status row is shown in the main connection card only while virtual-controller output is enabled;
- the status row reports waiting / connecting / connected / startup error and is bilingual;
- the proven elevated helper / named-pipe / HIDMaestro lifecycle is reused;
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
- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.AsyncStop.ps1` — temporary dev-stage override that moves slow helper teardown off the WinForms UI thread and blocks restart until cleanup finishes.
- `tools/Build-VirtualGamepad-Integration.ps1` — experimental patch/staging step that injects the integration hooks into a development copy of `MugenDeej.ps1`.
- `tools/Harden-VirtualGamepad-DevRuntime.ps1` — dev-only isolation plus staged compatibility fixes.
- `.github/workflows/build-virtual-gamepad-integration.yml` — isolated development package build.

The patch/staging approach is temporary. Before this work is release-ready, the validated changes should be consolidated into normal source and the experimental patcher/overlay removed, matching the source-cleanliness approach used for v1.0.0.

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

- Save returns immediately after the elevation launch step;
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

### Run 11 real-hardware re-test

**NONBLOCKING STARTUP — HARDWARE PASS.**

On the same Extended 5+6 controller, enabling Xbox/XInput left the Button Settings window responsive while the helper continued HID/PnP creation in the background. The main log recorded asynchronous start at `00:53:11.821`, immediate return to background wait at `00:53:12.001`, and `Virtual controller ready` at `00:53:28.408` — roughly **16.6 seconds** of Windows/HID setup without freezing the Mugen UI. COM10 stayed connected.

### Main-window status UI

Run 12 added a second row to the main connection card only while virtual-controller output is enabled.

Real-hardware/UI observation:

- Russian `подключается…` shown during HID creation;
- Russian `Mugen Deej Virtual Gamepad: подключён` shown after READY;
- English `Mugen Deej Virtual Gamepad: connected` updates correctly after language change;
- when virtual-controller output is Off, the extra status row is removed and the physical-controller status returns to the single-row layout.

**MAIN STATUS UI — HARDWARE/UI PASS.**

### Teardown timing finding

Run 12 exposed the mirror-image startup problem on disable and application exit: Mugen still synchronously waited for the helper process to finish HIDMaestro teardown.

The user-visible freeze is directly visible in both logs:

- disable saved at `00:54:58.362`;
- helper saw `BRIDGE_DISCONNECTED` / `STOP` at `00:54:58.368`;
- HIDMaestro/controller disposal did not reach `OEM_NAME_CLEARED` until `00:55:08.630`;
- orphan sweep itself then finished almost immediately at `00:55:08.645`;
- Mugen logged `Virtual controller stopped` at `00:55:08.678`.

So roughly **10.3 seconds** are spent in the actual controller/HID disposal path before the OEM-name clear. The explicit `EXIT_SWEEP` is only a few milliseconds and is not the source of the delay.

Normal application exit showed the same pattern: request at `00:56:37.233`, helper `STOP` at `00:56:37.236`, cleanup reached OEM-name clear at `00:56:47.483`, and Mugen finally exited at `00:56:47.543`.

The Mugen-side cause of the visible freeze was the synchronous `WaitForExit(30000)` in `Stop-MugenVirtualGamepad`. The cleanup must still be allowed to finish, but the WinForms thread does not need to wait for it.

The helper log also records a secondary cleanup-noise issue: after successful `EXIT_SWEEP_DONE`, disposing the already-broken pipe writer can throw `System.IO.IOException: Pipe is broken`, which is currently logged as `FATAL`. Cleanup has already completed at that point; this false-fatal log entry should be cleaned up separately before release.

### Nonblocking teardown fix — Run 14

The dev-stage teardown override was added in `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.AsyncStop.ps1` and appended after the core module during experimental packaging.

Behavior:

- release buttons immediately;
- close the Mugen side of the pipe so the helper begins the already-proven cleanup path;
- return to the UI immediately instead of calling `WaitForExit`;
- poll the helper process with a WinForms timer only for bookkeeping;
- prevent a new virtual controller from starting while the previous helper is still removing HID/PnP state;
- if the user re-enables during cleanup, start the fresh controller only after the old helper exits;
- application exit no longer needs to keep the Mugen UI/process alive while the elevated helper finishes its own cleanup.

CI:

- workflow run ID: `35138005925`;
- run number: `14`;
- head: `c39f4fb31a259905d99a63fb1e7c3d29d2ef497f`;
- result: **PASS**;
- Windows PowerShell 5.1 parser: PASS;
- nonblocking-teardown static markers: PASS;
- helper publish/smoke: PASS;
- launcher/package: PASS;
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-14`;
- artifact ID: `10463797250`;
- inner development ZIP SHA-256: `4581329c6065f14f7de08704ef9006650d9c413527d25549f290692e9b267ddb`.

Run 14 is **CI PASS / nonblocking-teardown hardware re-test pending**.

## Remaining real-hardware test plan for milestone 1

Use the already-tested Extended 5-control / 6-button controller.

1. Confirm ordinary Mugen connection/audio behavior remains intact.
2. Enable Xbox/XInput and confirm startup remains nonblocking and exactly one helper is launched.
3. Confirm the main status row transitions from connecting to connected and language switching remains correct.
4. Confirm `joy.cpl` shows `Mugen Deej Virtual Gamepad` and mapped press/hold/release/combinations still work.
5. Reopen Button Settings and confirm virtual mappings remain present.
6. Set Virtual controller to Off, click Save, and confirm the settings/main UI remains responsive immediately while the device disappears after background cleanup.
7. Re-enable immediately after disabling once to verify restart waits safely for the previous cleanup instead of racing HIDMaestro.
8. Exit Mugen while the virtual controller is active and confirm the Mugen window/process closes promptly while the helper removes the gamepad shortly afterward.
9. Confirm no orphaned virtual controller remains after background cleanup; no reboot is acceptable.
10. Force a physical-controller reconnect and confirm mappings survive capability re-detection.
11. Confirm ordinary non-gamepad button actions can coexist with virtual mappings on different physical buttons.
12. Hard-close once and verify bridge-loss cleanup still removes the virtual controller without reboot.
13. Re-check a real XInput game after integrated runtime validation.

Do not call integrated milestone 1 a complete hardware PASS until the remaining teardown/reconnect path has been tested on real hardware.

## Next after milestone 1 hardware PASS

1. Fold the proven integration into normal source instead of build-time patching/overlays.
2. Fix the helper's expected broken-pipe disposal being logged as `FATAL` after successful cleanup.
3. Add analog-control → virtual-axis routing.
4. Introduce the Profile model (Default + New/Duplicate/Rename/Delete/select).
5. Move virtual enabled/type/mappings into profiles.
6. Add Generic / DirectInput for arbitrary DIY shapes and many buttons.
7. Test the future 5-control + 30-button matrix hardware.
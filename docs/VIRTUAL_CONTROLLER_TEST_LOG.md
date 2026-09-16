# Virtual controller hardware test log

Living test record for `feature/virtual-gamepad-ui`.

## 2026-09-16 — Prototype 0, attempt 1

Hardware:

- existing physically-tested Extended Mugen Deej controller
- detected as 5 controls / 6 buttons
- detected on COM10 at 9600 baud

Result: PARTIAL / FAIL at bridge connection.

What passed:

- prototype PowerShell harness launched;
- normal Mugen Deej was not holding the COM port;
- Extended packet detection succeeded;
- elevated helper launched after UAC;
- helper log reached `START` and then `WAITING_FOR_CLIENT`.

Diagnosis: the first prototype created the named-pipe server inside the elevated helper and connected to it from the unelevated PowerShell bridge. This crossed the UAC integrity boundary in the inconvenient direction.

Fix commits:

- `ae142e00bbb06c6fa0b35c0ce3a18690fd0edf7d` — reverse helper pipe direction
- `b36187250980726dd9c2e72596b8094adae03a5f` — let unelevated bridge own named pipe

## 2026-09-16 — Prototype 0, attempt 2

Result: FAIL before the bridge wait began.

Observed PowerShell error:

```text
Exception calling "BeginWaitForConnection" with "2" argument(s):
"The pipe has not been opened in asynchronous mode."
```

Diagnosis: the reversed pipe server used `PipeOptions.None`, but `BeginWaitForConnection(...)` requires an asynchronous `NamedPipeServerStream`.

Fix commit:

- `66928682b4409fd4c24d9a7a1b3b365585261fb2` — create async named pipe server for prototype wait

CI after this fix:

- workflow: `Build virtual gamepad prototype`
- run ID: `35104680482`
- run number: `4`
- head: `66928682b4409fd4c24d9a7a1b3b365585261fb2`
- result: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Prototype-4`
- artifact ID: `10449403249`
- inner prototype ZIP SHA-256: `cee785912cd67d78bc29dc069d3c7a3ab9569fb6e07e757d067f0788d7ada22c`

## 2026-09-16 — Prototype 0, attempt 3

Result: CORE INPUT PATH PASS / CLEANUP BUG FOUND.

Confirmed on the real Extended controller:

- controller detected on COM10 as 5 controls / 6 buttons;
- UAC helper startup completed;
- harness printed `Virtual Xbox 360 controller is ready.`;
- Windows `joy.cpl` listed `Controller (XBOX 360 For Windows)` with status OK;
- physical buttons 1 through 6 all produced corresponding virtual button activity;
- observed masks included `0x01`, `0x02`, `0x04`, `0x08`, `0x10`, and `0x20`;
- holding a physical button for several seconds kept the matching virtual button held continuously;
- releasing immediately cleared the virtual button;
- multiple buttons could be held together and released independently without incorrect state transitions.

This proved the stateful path on real hardware:

```text
Extended Mugen controller
    -> serial parser
    -> PowerShell bridge
    -> named pipe
    -> elevated helper
    -> HIDMaestro
    -> virtual Xbox 360 controller
    -> joy.cpl
```

### Cleanup bug discovered

The terminal window was closed directly instead of stopping with Q/Esc. The physical buttons stopped affecting the virtual device, but `joy.cpl` still showed the Xbox controller.

Interpretation: hard termination bypassed the PowerShell `finally` path and left the virtual device enumerated after the bridge/helper session ended. Final Mugen integration must not depend on graceful UI exit for controller teardown.

## 2026-09-16 — Prototype 0, attempt 4

Result: NORMAL Q SHUTDOWN RELEASED INPUT STATE, BUT DEVICE REMOVAL WENT PENDING-REBOOT.

Observed:

- prototype restarted successfully;
- virtual Xbox controller recreated and worked;
- exit with `Q` released input and stopped the bridge;
- `joy.cpl` continued to enumerate the controller after repeated close/reopen cycles;
- Windows displayed a restart-required notification.

This is not acceptable product behavior. Mugen must not require reboot to recover from virtual-controller teardown.

## 2026-09-16 — cleanup hardening build

A no-reboot recovery path was added.

Changes:

- helper command `cleanup` calls `HMContext.RemoveAllVirtualControllers(preserveInstall: true)`;
- normal helper exit runs the same preserve-install sweep after controller/context disposal as a backstop;
- bridge loss is logged explicitly;
- package includes `RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd`, which leaves the HIDMaestro backend installed.

Build:

- workflow: `Build virtual gamepad prototype`
- run ID: `35110165971`
- run number: `8`
- head: `98902bebf7b7eaaf84e52b904348836cff295da6`
- result: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Prototype-8`
- artifact ID: `10452027277`
- inner prototype ZIP SHA-256: `37bebc2cc315f2cb54dc0a87b359cd1f4a6866f66f249d4b40e3cb9738173cfa`

## 2026-09-16 — Prototype 0, attempt 5

Result: LIVE ORPHAN CLEANUP PASS.

Procedure/result:

- Windows was intentionally not rebooted;
- `RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd` was launched elevated;
- helper reported success;
- the persistent Xbox controller disappeared from `joy.cpl` immediately;
- HIDMaestro backend remained installed.

Conclusion: emergency live orphan recovery is hardware-tested PASS.

## 2026-09-16 — Prototype 0, attempt 6

Result: HARD-CLOSE / BRIDGE-LOSS CLEANUP PASS; NEUTRAL ANALOG STATE ISSUE FOUND.

Observed:

- virtual Xbox controller created normally;
- physical button routing remained functional;
- closing the terminal window directly made the virtual controller disappear from `joy.cpl` without cleanup command or reboot.

Conclusion: hard-close recovery is hardware-tested PASS.

A separate presentation/state issue was visible in `joy.cpl`: left/right stick axes were not centered before any physical analog mapping existed.

Fix commit:

- `487592fe3a23986bfb3a9be63754a92a651e5ef2` — initialize `HMGamepadStateHelpers.StandardAxes(profile)` and `HMHat.None` before the first submit.

## 2026-09-16 — Prototype 0, attempt 7

Result: EXPLICIT NEUTRAL ANALOG STATE PASS.

Observed:

- left-stick X/Y centered;
- right-stick rotation axes centered;
- combined trigger/Z presentation neutral;
- POV/hat centered;
- first real packet reports `Buttons mask: 0x00`.

Conclusion: neutral startup state is hardware-tested PASS.

## 2026-09-16 — Prototype 0, attempt 8

Result: DISPLAY NAME PASS / XINPUT DETECTION PASS / REAL-GAME INPUT PASS.

Implementation commit:

- `540648f6680cc2b37667cb7fe95b83ea71112ad7` — crash-safe HIDMaestro OEM-name override lifecycle.

Observed:

- `joy.cpl` shows `Mugen Deej Virtual Gamepad`;
- neutral axes remain centered;
- physical buttons work, including simultaneous combinations;
- HardwareTester GamepadTester detects the virtual as `xinput`, index 0, connected, standard mapping;
- expected face buttons and both bumper mappings respond;
- `Cult of the Lamb` reacts to the virtual gamepad in a real game session.

Conclusion: the Xbox/XInput path is proven outside `joy.cpl`. A real XInput-aware game accepts physical Mugen input routed through the prototype.

Note: this proves real-game recognition/input, not a user-configurable in-game rebinding screen.

## 2026-09-16 — Prototype 0, attempt 9

Result: NORMAL Q/ESC TEARDOWN BUG REPRODUCED, FIXED, THEN PASS.

Observed on naming build v0.5:

- hard-close with the window close button still removed the virtual controller correctly;
- normal `Q` exit made the controller disappear briefly and then reappear in `joy.cpl`.

Diagnosis:

- the PowerShell harness sent `quit` and accepted `BYE` before the elevated helper had necessarily completed the full HID/PnP teardown;
- the harness only waited 5 seconds before it was allowed to kill the helper;
- therefore the normal path could terminate the cleanup worker while teardown was still in progress, while the bridge-loss path was allowed to unwind naturally.

Fix commit:

- `e887e4ac857c40f53566dd82e3ed0ad7c1b4a09e` — `fix: let helper finish virtual controller teardown`

Fix behavior:

- Q/Esc releases all virtual buttons;
- the bridge closes instead of depending on a `BYE` response as proof of teardown completion;
- the elevated helper sees bridge disconnect and runs the same already-proven cleanup path as hard-close;
- the harness waits up to 30 seconds for helper completion and no longer force-kills it during normal teardown.

CI:

- workflow run: `35118021710`
- run number: `11`
- result: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Prototype-11`
- artifact ID: `10456900609`

Hardware retest with v0.6:

- virtual `Mugen Deej Virtual Gamepad` appeared normally;
- exit with `Q` removed it;
- it did not reappear.

Conclusion: **NORMAL Q/ESC TEARDOWN — HARDWARE PASS.**

## Prototype 0 final status

**PROTOTYPE 0 — PASS / backend proof complete enough for real Mugen integration.**

Hardware-proven items include:

- Extended serial detection on the existing 5-control / 6-button controller;
- elevated helper and HIDMaestro backend startup;
- Xbox 360 / XInput virtual controller creation;
- custom `Mugen Deej Virtual Gamepad` display label;
- neutral startup state;
- stateful press / hold / release;
- simultaneous button combinations;
- live orphan cleanup with no reboot;
- hard-close / bridge-loss cleanup with no reboot;
- normal Q/Esc cleanup with no reboot;
- XInput tester recognition;
- real-game recognition/input in `Cult of the Lamb`.

The standalone harness should now be treated as a proven development fixture rather than the product UI. Next work should move into the actual Mugen Deej runtime/UI while preserving the tested helper/cleanup architecture.

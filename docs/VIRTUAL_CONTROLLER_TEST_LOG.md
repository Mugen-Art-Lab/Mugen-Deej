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

This proves the stateful path on real hardware:

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

The user closed the console/terminal window directly instead of stopping with Q/Esc. The physical buttons then stopped affecting the virtual device, but `joy.cpl` still showed the Xbox controller.

Interpretation: hard termination bypassed the PowerShell `finally` path and left the virtual device enumerated after the bridge/helper session ended. This is a prototype robustness bug, not user error. Final Mugen integration must not depend on a graceful UI exit for controller teardown.

## 2026-09-16 — Prototype 0, attempt 4

Result: NORMAL Q SHUTDOWN RELEASED INPUT STATE, BUT DEVICE REMOVAL WENT PENDING-REBOOT.

Observed:

- prototype restarted successfully;
- virtual Xbox controller recreated and worked;
- user exited with `Q`;
- harness printed `Prototype stopped. Virtual buttons were released and the virtual controller host was closed.`;
- `joy.cpl` continued to enumerate `Controller (XBOX 360 For Windows)` even after repeated full close/reopen cycles;
- Windows displayed a Settings notification saying a restart was required to finish configuring/removing `Controller (XBOX 360 For Windows)`.

This is not acceptable product behavior. The user's machine is intentionally in a multi-day hibernation/uptime test, and Mugen must not require Windows reboot to recover from virtual-controller teardown.

## 2026-09-16 — cleanup hardening build

A no-reboot recovery path was added before asking for any restart.

Changes:

- helper command `cleanup` calls `HMContext.RemoveAllVirtualControllers(preserveInstall: true)`;
- normal helper exit runs the same preserve-install sweep after controller/context disposal as a backstop;
- bridge loss is logged explicitly;
- package includes `RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd`, which elevates only the helper and leaves the HIDMaestro backend installed.

Build:

- workflow: `Build virtual gamepad prototype`
- run ID: `35110165971`
- run number: `8`
- head: `98902bebf7b7eaaf84e52b904348836cff295da6`
- result: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Prototype-8`
- artifact ID: `10452027277`
- inner ZIP SHA-256: `37bebc2cc315f2cb54dc0a87b359cd1f4a6866f66f249d4b40e3cb9738173cfa`

## 2026-09-16 — Prototype 0, attempt 5

Result: LIVE ORPHAN CLEANUP PASS.

Procedure:

1. Windows was intentionally **not** rebooted, despite the earlier restart-required notification.
2. `RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd` from cleanup-hardened build 8 was launched.
3. UAC elevation was accepted.
4. The helper reported `Cleanup command finished successfully.`
5. `joy.cpl` was checked after cleanup.

Observed:

- the previously persistent `Controller (XBOX 360 For Windows)` entry disappeared from `joy.cpl` immediately;
- no Windows reboot was required;
- the HIDMaestro backend remained installed because cleanup used `preserveInstall: true`.

Conclusion:

**Emergency live orphan recovery is hardware-tested PASS.** The current backend is capable of removing a stuck/orphaned virtual Xbox controller on the live Windows session. The earlier restart-required state is therefore recoverable without reboot and is not, by itself, grounds to reject HIDMaestro.

## 2026-09-16 — Prototype 0, attempt 6

Result: HARD-CLOSE / BRIDGE-LOSS CLEANUP PASS; NEUTRAL ANALOG STATE ISSUE FOUND.

Observed with cleanup-hardened build 8:

- virtual Xbox controller created normally;
- physical button routing remained functional;
- the user closed the prototype terminal window directly with the window close button;
- the virtual Xbox controller disappeared from `joy.cpl` without running the emergency cleanup command and without rebooting Windows.

Conclusion:

**Hard-close recovery is hardware-tested PASS.** The helper now notices bridge loss, unwinds, and the preserve-install exit sweep removes the virtual device on the live Windows session.

A separate presentation/state issue was visible in `joy.cpl` before close:

- the left-stick X/Y cross was parked near the minimum/top-left instead of center;
- right-stick rotation axes also did not appear centered;
- the POV/hat indicator itself appears essentially centered in the screenshot, so the primary confirmed defect is neutral analog-axis initialization, not necessarily the D-pad;
- no physical analog controls are routed to the virtual pad in Prototype 0 yet, so every stick axis should be neutral.

The prototype host had initialized `HMGamepadState` with only `Buttons = None` and left `Axes` null. HIDMaestro's public API documents omitted axes as automatically neutral, but the observed Xbox 360 result on this machine is not neutral. Mugen will therefore initialize the standard axis set explicitly instead of relying on implicit defaults.

Fix commit:

- `487592fe3a23986bfb3a9be63754a92a651e5ef2` — initialize `HMGamepadStateHelpers.StandardAxes(profile)` and `HMHat.None` before the first submit.

## Next test

1. Build/run the explicit-neutral-axis prototype.
2. Open controller Properties in `joy.cpl` before pressing anything.
3. Verify left and right stick axes are centered and triggers are released/neutral.
4. Verify buttons 1–6 still work normally.
5. Exit normally with Q/Esc once and confirm immediate device removal.
6. Bind at least one physical Mugen button in a real game.

Do not call Prototype 0 fully PASS until the neutral state is correct, normal Q/Esc teardown has a fresh PASS on the hardened build, and a real-game bind is confirmed.

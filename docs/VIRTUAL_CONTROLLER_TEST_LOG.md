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

## Next test

1. Do **not** reboot Windows.
2. Run `RUN-VIRTUAL-GAMEPAD-CLEANUP.cmd` from build 8 and accept UAC.
3. Close/reopen `joy.cpl` and check whether the existing orphan disappears immediately.
4. If live cleanup succeeds, mark emergency orphan recovery PASS.
5. Then start build 8 normally, verify buttons, exit with Q, and confirm the controller disappears without reboot.
6. After that, deliberately hard-close the prototype once and run cleanup again to validate hard-close recovery.
7. Bind at least one physical Mugen button in a real game.

If explicit preserve-install cleanup still leaves the controller pending reboot, stop treating this as a harness issue and investigate HIDMaestro's Xbox teardown path or replace the backend before integrating it into Mugen Deej.

Do not call Prototype 0 fully PASS until no-reboot cleanup, normal teardown, hard-close recovery, and a real-game bind are confirmed.

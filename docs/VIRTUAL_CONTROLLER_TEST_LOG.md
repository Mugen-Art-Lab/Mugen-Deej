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

Interpretation: hard termination bypassed the PowerShell `finally` path and left the elevated virtual-controller helper / virtual device orphaned. This is a prototype robustness bug, not user error. The final Mugen integration must not depend on a graceful UI exit for controller teardown.

## 2026-09-16 — Prototype 0, attempt 4

Result: NORMAL Q SHUTDOWN RELEASED INPUT STATE, BUT DEVICE REMOVAL WENT PENDING-REBOOT.

Observed:

- prototype restarted successfully;
- virtual Xbox controller recreated and worked;
- user exited with `Q`;
- harness printed `Prototype stopped. Virtual buttons were released and the virtual controller host was closed.`;
- `joy.cpl` continued to enumerate `Controller (XBOX 360 For Windows)` even after repeated full close/reopen cycles;
- Windows then displayed a Settings notification: restart is required to complete configuration for `Controller (XBOX 360 For Windows)`.

Important detail: `joy.cpl` was open while the prototype was being torn down. HIDMaestro teardown uses PnP removal and its own source explicitly treats a `Removed on reboot` result as a possible removal outcome. The current evidence therefore indicates a real pending-removal device state, not a stale `joy.cpl` window cache.

Next cleanup test after reboot:

1. Confirm the pending Xbox controller is gone after Windows restarts.
2. Start the prototype again.
3. Open `joy.cpl`, confirm the controller exists and inputs work.
4. Close **all** `joy.cpl` / controller-properties windows before pressing Q.
5. Press Q, wait for clean shutdown, then reopen `joy.cpl`.
6. If the controller disappears immediately, an open consumer handle was provoking pending-reboot removal; if it still remains, treat this as a backend teardown defect/limitation that must be solved before integration.

Planned hardening regardless of result:

- add an explicit elevated `cleanup` command using `HMContext.RemoveAllVirtualControllers(preserveInstall: true)`;
- add helper-side bridge-loss detection so hard-closing Mugen cannot strand an active state publisher;
- keep virtual-button release best-effort on every teardown path;
- do not call Prototype 0 fully PASS until no-reboot teardown behavior is understood and a real-game bind is confirmed.

## Remaining Prototype 0 acceptance checks

1. Reboot once to clear the current Windows pending-removal state.
2. Run the clean-exit test with all consumers closed before Q.
3. Fix/verify hard-close/orphan cleanup.
4. Bind at least one physical Mugen button in a real game.

Do not call Prototype 0 fully PASS until cleanup and a real-game bind are confirmed.

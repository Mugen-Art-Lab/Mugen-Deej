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

The old helper only wrote `WAITING_FOR_CLIENT` after `HMContext.InstallDriver()`, profile lookup, `CreateController(...)`, and an initial neutral `SubmitState(...)` had returned. Therefore the failure occurred after the HIDMaestro setup/create path and before the Mugen-side process connected to the named pipe.

Observed host log:

```text
2026-09-16T19:42:58.6050747+06:00 START profile=xbox-360-wired; identity=mugen-deej-prototype; pipe=MugenDeejVirtualGamepad-239ebbc81f7b47efb4531391aafb6f41
2026-09-16T19:43:07.0116936+06:00 WAITING_FOR_CLIENT
```

The PowerShell bridge timed out connecting and then cleaned up the helper.

### Diagnosis / fix

The first prototype created the named-pipe server inside the elevated helper and connected to it from the unelevated PowerShell bridge. This crossed the UAC integrity boundary in the inconvenient direction.

The pipe architecture was reversed:

```text
unelevated Mugen bridge = NamedPipeServerStream
            ^
            | elevated helper connects as client
            |
elevated virtual-controller host
```

The unelevated side now creates the pipe before showing UAC. The elevated helper connects down to it after HIDMaestro initializes. The bridge also uses asynchronous wait + timeout/process-exit checks so a cancelled UAC prompt cannot hang the prototype forever.

Fix commits:

- `ae142e00bbb06c6fa0b35c0ce3a18690fd0edf7d` — reverse helper pipe direction
- `b36187250980726dd9c2e72596b8094adae03a5f` — let unelevated bridge own named pipe

CI after fix:

- workflow: `Build virtual gamepad prototype`
- run ID: `35104003784`
- run number: `3`
- head: `b36187250980726dd9c2e72596b8094adae03a5f`
- result: PASS
- artifact: `Mugen-Deej-VirtualGamepad-Prototype-3`
- artifact ID: `10449596226`
- inner prototype ZIP SHA-256: `b8a46e795d700055cd2e957a5b22f1714c23d94a833b79a10b9e0d5168b94d9f`

## 2026-09-16 — Prototype 0, attempt 2

Result: FAIL before the bridge wait began.

What passed again:

- Extended controller detection on COM10: 5 controls / 6 buttons;
- elevated helper launched after UAC;
- helper log reached `START` for the new pipe name.

Observed PowerShell error:

```text
Exception calling "BeginWaitForConnection" with "2" argument(s):
"The pipe has not been opened in asynchronous mode."
```

Observed helper log tail:

```text
2026-09-16T19:50:07.5920629+06:00 START profile=xbox-360-wired; identity=mugen-deej-prototype; pipe=MugenDeejVirtualGamepad-bc48044fc8434e7d9a6a70dbe1155b05
```

### Diagnosis / fix

This is a prototype-harness bug, not a HIDMaestro/backend failure. The reversed pipe server was created with `PipeOptions.None`, but the PowerShell harness uses `BeginWaitForConnection(...)`, which requires an asynchronous `NamedPipeServerStream`.

Fix:

- create the bridge-side server with `PipeOptions.Asynchronous`;
- keep the existing timeout/process-exit handling around `BeginWaitForConnection(...)`.

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

Result: PARTIAL PASS — end-to-end virtual Xbox button routing proven in `joy.cpl`.

Observed on the real Extended controller:

- controller detected on COM10 as 5 controls / 6 buttons;
- UAC helper startup completed;
- harness printed `Virtual Xbox 360 controller is ready.`;
- Windows `joy.cpl` listed `Controller (XBOX 360 For Windows)` with status OK;
- physical buttons 1 through 6 all produced corresponding virtual button activity in `joy.cpl`;
- console masks changed through `0x01`, `0x02`, `0x04`, `0x08`, `0x10`, and `0x20`, confirming all six mapped inputs reached the bridge/backend path.

This proves the current chain works on real hardware:

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

Still to verify before calling Prototype 0 fully PASS:

1. Hold behavior: virtual button remains down for the full duration of a physical hold.
2. Release behavior: virtual button clears immediately on physical release.
3. Clean shutdown: Q/Esc releases all buttons and removes the virtual controller without leaving an orphan device.
4. Real game binding: at least one physical Mugen button is accepted by a game as a gamepad input.

No additional log is required for the successful `joy.cpl` button-routing result unless one of the remaining checks behaves incorrectly.

## Next test

Status: JOY.CPL ROUTING PASS / FINAL ACCEPTANCE CHECKS PENDING.

Required observations:

1. Hold one physical button for several seconds and verify its virtual button stays held the entire time.
2. Release it and verify the virtual state clears immediately.
3. Press Q or Esc and verify the virtual Xbox controller disappears from `joy.cpl` or is otherwise cleanly removed.
4. Launch one real game, enter its control-binding screen, and bind any one of physical buttons 1–6.

Do not mark Prototype 0 fully hardware PASS until these remaining observations are confirmed.
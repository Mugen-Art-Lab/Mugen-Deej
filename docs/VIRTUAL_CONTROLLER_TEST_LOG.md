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

## Next test

Status: WAITING FOR RETEST.

Required observations:

1. Extended 5+6 controller is detected.
2. UAC accepted.
3. Host log reaches `CONNECTING_TO_BRIDGE` then `BRIDGE_CONNECTED`.
4. Harness prints `Virtual Xbox 360 controller is ready.`
5. `joy.cpl` shows the virtual Xbox controller.
6. Physical buttons 1–6 drive A/B/X/Y/LB/RB.
7. Holding a physical button keeps the matching virtual input held.
8. Releasing clears it.
9. Q/Esc cleanly removes the virtual controller.

Do not mark Prototype 0 hardware PASS until all relevant observations are confirmed on the real controller.

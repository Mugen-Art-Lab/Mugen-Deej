# Mugen Deej 2.0 pre-merge working checklist

> **TEMPORARY FEATURE-BRANCH HANDOFF FILE.**
>
> This file exists only to preserve release-preparation context while
> `feature/virtual-gamepad-ui` is being cleaned for 2.0.0.
> **Delete this file before merging the branch into `main`.**
>
> Runtime feature freeze is active. Do not introduce new product features here.
> Documentation/repository cleanup must not change the hardware-accepted 2.0.0
> runtime unless a concrete release blocker is found.

## Accepted release baseline

Final runtime/package state before repository cleanup:

- version: **2.0.0**;
- final normal release workflow validation: **Build release packages #4 — PASS**;
- final package head used for validation: `f289cc4e319f41aac974907c0f9560903cfdd544`;
- Portable ZIP SHA-256:
  `10a31a431317efc9beb79acbe9bbd4a18df86fc3183f399fabc9aa218151adc3`;
- Setup EXE SHA-256:
  `43cb6ac96b523a4297fc974a596cd11ac1e2352637b033cc84a9c4d2483916da`;
- recursive Portable `SHA256SUMS.txt`: 205 files checked, 0 mismatches;
- final 2.0.0 real-machine hardware smoke: **PASS**;
- RC1 -> final 2.0.0 in-place update: **PASS**;
- Adaptive 5/28/2/1 detection: **PASS**;
- Control-layer switching: **PASS**;
- virtual Xbox/XInput output verified in Windows `joy.cpl`: **PASS**;
- clean Setup, schema-v3 restore, reboot/autostart and multi-generation
  slider-inversion tests were already accepted in the RC1 line.

The isolated malformed/partial Adaptive startup packet
`adaptive:2:9:2:1` was rejected by the topology-shape guard while the real
controller remained `adaptive:5:28:2:1`; virtual-controller startup then
completed normally. This is not currently treated as a release blocker.

Post-baseline runtime follow-up is intentionally tracked separately from the
original #4 acceptance package. The newest CI-built runtime under hardware
validation is **Build release packages #16** from
`1d414f6d5a0f5eeccc3ec7e9519e1a4e04e02efd`
(`ui: add fast encoder indicator lane`). Documentation-only commits after
that source state must not be mistaken for a newer packaged runtime.

## Pre-merge rule

Work through this document in order. After each completed step:

1. commit the actual repository/documentation change;
2. update this checklist with the result and any relevant commit/hash;
3. update `docs/CURRENT_HANDOFF.md` if the result materially changes what the
   next session needs to know;
4. do not merge until the final cleanup section is complete.

## Step 1 — repository inventory and cleanup plan

Status: **PASS / classification captured**

Current release-facing root includes the expected project files such as
`README.md`, `README_RU.md`, `CHANGELOG.md`, `VERSION.txt`,
`MugenDeej.ps1`, release/build scripts, licensing and documentation.

Important cleanup observations:

- `tools/` contains the current release builder plus many historical RC
  transformation/patch scripts. These must be classified before merge instead
  of being blindly retained or deleted.
- `.github/workflows/build-virtual-gamepad-integration.yml` is the historical
  RC patch-chain builder. Automatic triggering has already been disabled; it is
  manual-only/forensic at present.
- `.github/workflows/build-virtual-gamepad-prototype.yml` must be reviewed to
  decide whether it is still useful developer tooling or obsolete prototype
  infrastructure.
- `arduino/` currently contains six controller/prototype directories:
  `MugenDeejController`, `MugenDeejCardboardNanoPrototype`,
  `MugenDeejCardboardUnoPrototype`, `MugenDeejPanelPrototype`,
  `MugenDeejUnoAdaptiveTest`, and `MugenDeejUnoTransportTest`.
  Their user-facing status is currently unclear and must be documented.
- `docs/CURRENT_HANDOFF.md` and `docs/PROJECT_STATE.md` are large internal
  development-history files. Their final disposition must be decided before
  merge; they must not accidentally become the primary public documentation.
- existing useful architecture/reference docs include `PROTOCOL.md`,
  `CONTROL_MODEL.md`, `PROFILE_LAYER_ARCHITECTURE.md`,
  `BACKUP_COMPATIBILITY.md`, `BUILDING.md` and virtual-controller docs.

### Step 1 tasks

- [x] Capture top-level repository inventory.
- [x] Capture `arduino/`, `tools/`, `.github/workflows/` and `dev/` inventory.
- [x] Classify files as **public/current**, **developer/current**,
  **historical/archive**, or **remove before main**.
- [x] Record the proposed final public repository structure before moving or
  deleting anything.

### Step 1 classification

#### Public / current

Keep visible and intentionally supported:

- root project/release files: `README.md`, `README_RU.md`, `CHANGELOG.md`,
  `LICENSE`, `ACKNOWLEDGEMENTS.md`, `SECURITY.md`, `CONTRIBUTING.md`,
  `THIRD_PARTY_NOTICES.md`, `VERSION.txt`, `MugenDeej.ps1`,
  `MugenDeej.ico`, `MugenDeej-Debug.cmd`, `BUILD_RELEASE.cmd`;
- `src/launcher/`, `src/setup/`, `src/virtual-gamepad-helper/`;
- canonical `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.ps1`;
- `tools/Build-Release.ps1` and `tools/Prepare-HIDMaestro.ps1`;
- `tools/Build-SetupFromPortable.ps1` is retained for now as a useful exact-
  payload Setup wrapper, especially while the code-signing workflow is still
  undecided;
- `.github/workflows/build-release.yml` is the canonical package workflow;
- current public docs: `PROTOCOL.md`, `CONTROL_MODEL.md`,
  `BACKUP_COMPATIBILITY.md`, `TROUBLESHOOTING.md`, plus the new Adaptive v3
  build/wiring docs to be written;
- `arduino/MugenDeejController/` remains the tested Extended reference
  firmware;
- `arduino/MugenDeejCardboardNanoPrototype/` is in fact the hardware-proven
  Adaptive 5/28/2/1 firmware and is shipped in the 2.0 package. Its
  `Prototype`/cardboard naming is now misleading and should be promoted to a
  clear Adaptive reference-firmware name before merge.

#### Developer / current

Keep, but clearly separate from normal user-facing material:

- `docs/BUILDING.md` — current in concept but needs its 2.0 package/dependency
  list updated;
- `docs/HARDWARE_VISION.md` — useful architecture direction, but its
  candidate-prototype section contains stale pre-final topology wording and must
  be updated;
- `docs/PROFILE_LAYER_ARCHITECTURE.md` — useful contributor architecture;
- `docs/VIRTUAL_CONTROLLER_UI.md` and
  `docs/VIRTUAL_GAMEPAD_INTEGRATION.md` — retain only after checking/removing
  old prototype/branch language;
- `arduino/MugenDeejUnoAdaptiveTest/` — useful Adaptive capability/topology
  regression fixture, but should live under an explicitly developer/test path;
- `arduino/MugenDeejUnoTransportTest/` — useful auto-baud/transport regression
  fixture if retained, but should also live under a developer/test path;
- `config.example.json` — intended public/developer example, but must be
  audited against the actual 2.0 schema before merge.

#### Historical / archive

Preserve only material that has ongoing explanatory value:

- existing `docs/history/`;
- old version-specific release/development notes can be grouped under history
  rather than left mixed with current 2.0 documentation;
- `arduino/MugenDeejCardboardUnoPrototype/` documents the physical bring-up
  that preceded the final Nano Adaptive build. It may be preserved as history
  if desired, but it must not be presented as current firmware.

#### Remove before main

These are construction artifacts whose useful history already exists in Git:

- `.github/workflows/build-virtual-gamepad-integration.yml` — obsolete RC
  patch-chain builder; automatic triggering is already disabled;
- `.github/workflows/build-virtual-gamepad-prototype.yml` and
  `dev/virtual-gamepad/` — proof-of-concept harness superseded by the
  integrated production virtual-controller path;
- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.AsyncStop.ps1` —
  development overlay already consolidated into the canonical module;
- obsolete source-rewrite/RC patchers:
  - `tools/Add-AdaptiveControlMappings.ps1`
  - `tools/Add-AdaptiveLayers.ps1`
  - `tools/Apply-AdaptiveButtonUi.ps1`
  - `tools/Apply-AdaptiveInputStatusUi.ps1`
  - `tools/Apply-AdaptiveProtocol.ps1`
  - `tools/Apply-PerControllerSliderInversion.ps1`
  - `tools/Build-VirtualGamepad-Integration.ps1`
  - `tools/Ensure-WindowsPowerShellUtf8Bom.ps1`
  - `tools/Harden-AdaptiveTopologyUi.ps1`
  - `tools/Harden-VirtualGamepad-DevRuntime.ps1`
  - `tools/Optimize-LargeButtonSettings.ps1`
  - `tools/Polish-AdaptiveInputStatusUi.ps1`
  - `tools/Polish-UiLanguage.ps1`
  - `tools/Revise-AdaptiveMainUi.ps1`
  - `tools/Run-OptimizedLargeButtonSettings.ps1`;
- `arduino/MugenDeejPanelPrototype/` — obsolete pre-Adaptive design that
  explicitly emulates toggles/encoders as fake Extended buttons;
- `docs/CURRENT_HANDOFF.md`, `docs/PROJECT_STATE.md`, and this
  `PRE_MERGE_2_0_CHECKLIST.md` are internal continuity scaffolding and should
  be deleted in final pre-merge cleanup after all durable information has been
  moved into proper documentation.

`docs/VIRTUAL_CONTROLLER_TEST_LOG.md` is tentatively classified as
**historical/remove**: its important acceptance result belongs in release notes
or contributor docs; the long chronological test log itself does not need to
become public 2.0 documentation.

### Proposed final repository shape

The exact directory names can be adjusted while moving files, but the intended
shape is:

```text
/
  README.md
  README_RU.md
  CHANGELOG.md
  VERSION.txt
  MugenDeej.ps1
  ...normal license/security/build entry files...

  .github/workflows/
    build-release.yml
    [future signing workflow/integration, if SignPath is approved]

  arduino/
    reference/
      Extended/          # current tested s/b reference firmware
      Adaptive/          # current tested Adaptive v3 5/28/2/1 firmware
    tests/
      AdaptiveTopology/  # bare-board dynamic-topology regression fixture
      Transport/         # optional 9600/115200 transport fixture

  docs/
    ADAPTIVE_V3.md
    ADAPTIVE_V3_WIRING.md
    ADAPTIVE_V3_BUILD.md
    PROTOCOL.md
    CONTROL_MODEL.md
    BACKUP_COMPATIBILITY.md
    TROUBLESHOOTING.md
    BUILDING.md
    PROFILE_LAYER_ARCHITECTURE.md
    VIRTUAL_CONTROLLER_UI.md
    VIRTUAL_GAMEPAD_INTEGRATION.md
    HARDWARE_VISION.md
    history/
      ...version/development history intentionally retained...

  src/
    launcher/
    setup/
    virtual-gamepad-helper/
    virtual-gamepad-integration/
      MugenDeej.VirtualGamepad.ps1

  tools/
    Build-Release.ps1
    Build-SetupFromPortable.ps1
    Prepare-HIDMaestro.ps1
```

### Experimental second matrix encoder (E2)

A second bare EC11 encoder has now been physically wired into the two previously
unused C8 matrix cells:

- EC11 COM -> C8 / D11;
- EC11 A -> diode -> R3 / A0 (R3C8);
- EC11 B -> diode -> R4 / A1 (R4C8);
- encoder push contacts intentionally unused;
- matrix diode stripe/cathode remains on the ROW side.

Experimental firmware is kept separate from the 2.0 reference firmware at:

`dev/firmware/MugenDeejCardboardNanoE2Test/MugenDeejCardboardNanoE2Test.ino`

The experimental firmware decodes R3C8/R4C8 from raw matrix scans, bypassing
the ordinary 6 ms button/toggle debounce for those two cells, and emits E2 as a
second Adaptive `e<position>` field without a push suffix.

Hardware/runtime result:

- Mugen Deej detected `adaptive:5:28:2:2`;
- the main status header displayed 5 sliders / 28 buttons / 2 toggles /
  2 encoders;
- runtime logging recorded repeated Encoder 2 movement in both directions;
- Adaptive action configuration saved with `encoders=2`;
- the initial E2 physical direction was reversed; the EC11 A/B connections
  were then swapped physically, after which clockwise/counter-clockwise
  direction matched the intended behavior without a firmware direction hack.

The test also exposed a dashboard layout bug: the shared toggle/encoder row
allowed two encoders logically but only reserved enough width for one visual
indicator. The final compact geometry rebalances the shared row so two toggles
and two encoder indicators fit on one line without clipping the Russian section
labels or encoder values.

Visual hardware acceptance now passes:

- both "Тумблеры" and "Энкодеры" labels remain on one line;
- both toggle indicators remain readable;
- E1 and E2 indicators and their numeric positions are visible simultaneously;
- the fixed-width main dashboard did not need to grow;
- additional horizontal breathing room remains to the right of E2.

The local acceptance install reached this final geometry through the v4 test
patch, while the feature branch already contains the same final layout.

Do not promote the E2 test firmware to the 2.0 reference firmware until the
hardware/UI test is explicitly accepted.

### Matrix encoder fast-rotation follow-up

The experimental matrix-backed E2 exposed a separate timing issue during fast
rotation. Direct E1 is counted from D2/D3 interrupts, while E2 is polled from
R3C8/R4C8 during the matrix scan. Under a fast spin, E1 continued to accumulate
multi-step deltas between desktop packets, while E2 was much easier to starve.

The key firmware-side cause was that every completed E2 detent immediately
requested a full Adaptive-v3 snapshot. At 115200 baud that full-state
`Serial.print()` path creates blind time for a polling-based encoder, which can
then miss later quadrature transitions.

Experimental mitigation committed in:

`1b38ae6e5cb3fdfa07ada636e45aa8ba2e25829f`
(`firmware: reduce matrix encoder edge loss during fast rotation`)

The E2 test firmware now:

- accumulates E2 position locally instead of forcing a complete v3 packet on
  every E2 step;
- publishes the cumulative E2 position on the normal 25 ms heartbeat;
- keeps direct interrupt-driven E1 on its existing immediate-notification path;
- briefly re-samples E2 A/B between chunks of the full serial snapshot so UART
  buffer waits do not create one long blind polling window;
- leaves the accepted 2.0 reference firmware unchanged.

**Acceptance status: PENDING HARDWARE TEST.** Compare direct E1 and matrix E2
with deliberately fast spins after flashing this exact experimental firmware.
The desired result is that E2 no longer visibly falls behind or drops a
meaningful fraction of physical detents. This result is also important input
for the future CD74HC4067 / multi-encoder design; do not call four
matrix/multiplexer encoders reference-ready until high-speed rotation is proven
on real hardware.

### 500000-baud Adaptive transport experiment

A follow-up test intentionally raises only the experimental E2 firmware
transport from 115200 to **500000 baud** while keeping the fast-scan/polling
mitigation otherwise unchanged. The accepted 2.0 reference firmware remains
untouched.

Pinned combined source state:

- desktop 500000-baud auto-probe support:
  `97e300027d619491a92a553cc68b7550ed4d80c8`;
- experimental E2 firmware switched to 500000:
  `fa421797a33163923faa46470a9f507a9387bac5`;
- combined test head:
  `852a8cd721f03533288bf84075b1915d74d22cbd`.

Desktop auto-probe keeps the last known working baud first, then includes
500000 before the remaining configured/legacy fallbacks. Existing 115200/9600
support is not removed.

CI provenance for the matching desktop test build:

- workflow: `Build release packages`;
- run: **#11**, run ID `36439846440`;
- result: **success**;
- artifact: `Mugen-Deej-packages-11`, artifact ID `10976813395`;
- artifact digest:
  `sha256:ac03b1aef47d6fa32aee3583912e9fb3f201023735441be223425a4f6e161c73`;
- Portable SHA-256:
  `6262caaf5f1e26c823ab0392e94021c5a9ddedd916288cb46f71f506a6e469da`;
- Setup SHA-256:
  `7aa659281dc2b26ae1d21e16b77e0006026a9bf36a9ab221a7bf3e281b1a3d4d`.

The exact experimental firmware blob is
`403a23f7388f75e688743b8b6b3621cb2768d289`.

**Acceptance status: PRELIMINARY HARDWARE PASS.** The #11 desktop build and
the exact 500000-baud E2 firmware were tested on the real controller.

Observed on hardware:

- diagnostics reported COM5 / Adaptive v3 / 500000 baud / 5 sliders /
  28 buttons / 2 toggles / 2 encoders;
- firmware debounce remained 6 ms with no immediate diagnostic regression at
  connection;
- deliberately fast E2 back-and-forth spins no longer felt like they were
  dropping chunks of movement;
- the desktop log showed cumulative E2 deltas such as +4, +5, -4 and -3,
  confirming that the polling encoder can now accumulate several physical
  detents between Adaptive snapshots instead of requiring one packet per step;
- the on-screen encoder animation still looked slightly delayed, while the
  actual back-and-forth action response felt substantially more exact.

This is strong evidence that the fast-scan plus 500000-baud transport removes
the obvious E2 starvation seen at 115200. It is not yet a mathematical proof
of zero missed detents: a controlled test with a known physical detent count
should be used before declaring the matrix/multiplexer encoder path fully
reference-ready.

Follow-up latency experiment:

- commit `5f0865abb01ce5101ec88649cf522ea3c8174b0b`
  (`firmware: test 100 Hz adaptive snapshots at 500k`);
- experimental E2 firmware remains at 500000 baud;
- `PACKET_INTERVAL_MS` is reduced from 25 ms to **10 ms**;
- target is up to 100 full Adaptive snapshots/s;
- desktop build does not change: CI #11 already supports the 500000-baud
  controller and should be reused for this firmware-only comparison.

**10 ms acceptance status: HARDWARE OBSERVED, DESKTOP HARDENING RETEST
PENDING.** The 500000-baud / 10 ms firmware connected successfully as Adaptive
`5/28/2/2`. Fast E2 back-and-forth movement continued to produce cumulative
multi-step deltas (commonly +/-2 and occasionally +/-3), so the matrix encoder
did not regress to the original one-step starvation behavior.

The diagnostics window reported roughly **17-18 ms packet age / ~55-60 Hz**
rather than 100 Hz. This is consistent with the current firmware scheduling:
`lastPacketAt` is assigned *after* `sendAdaptivePacket()`, so
`PACKET_INTERVAL_MS = 10` means approximately "finish a packet, then wait
10 ms" rather than a strict 10 ms start-to-start period. The full snapshot
itself therefore remains part of the observed frame time.

Two malformed capability-shaped packets were also rejected during this test
while opening/handling diagnostics (examples observed by the desktop were
`adaptive:5:45:4:3` and `adaptive:3:7:2:2` while the established topology
was `adaptive:5:28:2:2`). Mugen correctly discarded them, but this is not
acceptable as a reference transport result.

A correlated desktop issue was identified: `Show-ConnectionDiagnosticsWindow`
performed the synchronous CIM/WMI-backed `Update-DriverStatus` call *before*
showing the dialog. On the test machine this could take multiple seconds, making
the diagnostics button appear unresponsive. If the main form was hidden to the
tray during that delay, the modal dialog could then be created with an invisible
owner and only become visible after the main form was restored. The same UI
stall also pauses `Process-SerialData`, which is a plausible contributor to
receive-buffer pressure at the higher packet rate.

Desktop hardening commit:

`04bfd6088ac30a1c60eda83c84145b1d9b01a315`
(`fix: keep diagnostics responsive during high-rate serial input`)

Matching CI test build:

- workflow: `Build release packages`;
- run: **#12**, run ID `36443484827`;
- result: **success**;
- artifact: `Mugen-Deej-packages-12`, artifact ID `10978654829`;
- artifact digest:
  `sha256:18e0604ad0e68f55171a7f6d717d0cf1db90eeae2dcc5f0f5e908e1ab66b7543`;
- Portable SHA-256:
  `6befca51d35ca55f35d0b02f0a36281ac5bbdcc82e42b9e6ecbcb72eee0d2b50`;
- Setup SHA-256:
  `2e02beb5e7fc528640fe8b9740a147279175e0a1664c91f38d5db64fca61199b`.

It:

- removes the synchronous driver-status refresh from the diagnostics pre-show
  path and from the COM-list refresh button;
- uses the already event-refreshed/cached driver status instead;
- explicitly brings the shown diagnostics dialog into view/foreground;
- increases `SerialPort.ReadBufferSize` to 65536 bytes before opening the
  port, providing headroom for short UI stalls at high Adaptive rates.

**Desktop-hardening retest: SHORT HARDWARE PASS.** With CI #12 installed and
the same 500000-baud / old 10 ms-after-send firmware still flashed:

- the diagnostics window opened immediately;
- the controller was detected as Adaptive `5/28/2/2` at 500000 baud;
- debounce diagnostics remained `6 ms / filtered=0 / rapid=0`;
- encoder activity continued while the diagnostics modal was open;
- no capability-shape mismatch warning appeared in the fresh post-install test
  session before the next firmware experiment.

This is sufficient to proceed with the isolated cadence experiment, but longer
high-rate runtime/reconnect testing is still required before 500000 is treated
as a reference transport.

### Diagnostics modal z-order after tray restore — 2026-09-29

A post-hibernation UI failure was reproduced while validating the high-rate
diagnostics path. The controller itself resumed successfully on the preserved
COM5 SerialPort, but opening **Connection and diagnostics** after restoring the
main window from the tray could produce this sequence:

- the diagnostics form flashed briefly and then became inaccessible;
- the main form remained visible but rejected clicks with the Windows modal
  notification sound;
- Mugen continued to treat a modal dialog as open, confirming that the
  diagnostics form had not actually closed;
- on forced application shutdown, the delayed
  `Main window restored from tray` log entry appeared only after the modal
  dialog unwound.

The root cause is WinForms message-loop re-entrancy in
`Show-MainWindowForeground`. The tray restore path temporarily raised the main
form to `TopMost`, then called `Application.DoEvents()` before clearing that
state. A fast diagnostics click could therefore be delivered *inside* the
restore call. `ShowDialog($form)` then blocked that nested callback while the
owner was still TopMost, allowing the disabled main form to sit above its own
modal child.

Fix committed in:

`e3263139194b2ab9325a4d6a924c2865d2396dc4`
(`fix: keep diagnostics modal above restored main window`)

The fix:

- removes `Application.DoEvents()` from the main-window restore path;
- clears the temporary owner `TopMost` state before opening diagnostics as a
  defensive guard;
- gives the diagnostics form one explicit foreground/z-order pulse when shown,
  then immediately returns it to normal owned-modal behavior;
- does not pump another nested message loop;
- adds diagnostics open/shown/closed log markers, including owner visibility,
  owner TopMost state and tray-transition state.

**Acceptance status: TRAY REGRESSION PASS; HIBERNATION RETEST PENDING.**
CI #13 from the exact fix was installed and exercised on hardware.

Observed in the captured session:

- diagnostics opened three times and every open produced the new
  `Connection diagnostics shown and activated` marker;
- two dialogs were explicitly closed with `result=Cancel`; the third remained
  open only because the log was captured while it was still on screen;
- a direct `hide to tray -> restore -> immediately open diagnostics` regression
  test passed;
- the diagnostics owner was logged as visible and non-TopMost with no tray
  transition in progress;
- the main application remained responsive after closing the modal dialogs.

The exact post-hibernation path still needs one final retest on CI #13:
hide Mugen to tray -> hibernate -> resume -> restore Mugen -> immediately open
Connection and diagnostics.

True start-to-start heartbeat experiment:

- commit `e77a89e6c8bbf3fbe53cd07465e1f7b566eac25c`
  (`firmware: schedule 10 ms adaptive heartbeat start-to-start`);
- `PACKET_INTERVAL_MS` remains 10;
- the heartbeat timestamp is now recorded immediately **before**
  `sendAdaptivePacket()`, so serialization time counts inside the 10 ms frame
  period instead of adding on top of it;
- E2 still accumulates locally and does not force an immediate packet;
- direct E1, button and toggle changes retain their existing immediate packet
  behavior, so the 10 ms target describes the regular heartbeat cadence rather
  than a hard global minimum between every possible event-driven packet.

**True 10 ms acceptance status: SHORT HARDWARE PASS.** With CI #13
desktop installed and the 500000-baud true start-to-start firmware flashed:

- diagnostics typically reported roughly **92-98 Hz**, with brief excursions
  above 100 Hz observed during active testing;
- the controller remained Adaptive `5/28/2/2` at 500000 baud;
- firmware debounce diagnostics remained `6 ms / filtered=0 / rapid=0`;
- the captured session contained **3139 Encoder 1 movement records** and
  **1038 Encoder 2 movement records** during deliberate stress;
- no capability-shape mismatch warning occurred in the session;
- no serial-loss warning occurred in the session;
- no contained main-UI timer failure occurred in the session;
- repeated diagnostics-window use did not interrupt serial processing.

The occasional displayed rate above 100 Hz is not itself an error. The 10 ms
setting defines the regular heartbeat target; direct E1/button/toggle changes
can still request additional event-driven snapshots, and the desktop rate
display is a moving measurement rather than a hard firmware clock.

This is sufficient to treat 500000 baud / 10 ms start-to-start as a successful
experimental latency result. A controlled physical-detent count and longer
runtime/reconnect/resume soak are still required before making it the public
reference/default transport.

Do not promote 500000 to the accepted 2.0 reference firmware/default transport
from this result alone; keep it experimental until the controlled-count test
and broader stability/reconnect checks pass.


### 2026-09-29 release-prep follow-up

Two small desktop/UI follow-ups were validated after the earlier 500000-baud /
10 ms hardware work.

**Diagnostics wording — CI #15**

- source commit:
  `1541b08b48d0095669aa4d6f4330229557266175`;
- workflow: `Build release packages`;
- run: **#15**, run ID `36510087674`;
- artifact: `Mugen-Deej-packages-15`, artifact ID `11009116699`;
- Setup SHA-256:
  `eacba742c9cc1334fd67f27a281859cfd63b26cd5133c1ed9d354910dc7f17f2`.

The diagnostics freshness line is now human-readable instead of looking like a
raw metric label. Russian uses wording such as
`16 мс назад · Частота: ~98,0 Гц`; English uses
`16 ms ago · Rate: ~98.0 Hz`. Timing calculations themselves were not
changed.

A visual backward-compatibility spot check also passed with the old controller:
the same desktop build detected **Legacy / 9600 / 5 sliders / 0 buttons /
0 toggles / 0 encoders**, while the experimental controller still detected
Adaptive `5/28/2/2` at 500000. The diagnostics wording remained correct in
both cases.

**Fast encoder indicator lane — CI #16**

- source commit:
  `1d414f6d5a0f5eeccc3ec7e9519e1a4e04e02efd`;
- workflow: `Build release packages`;
- run: **#16**, run ID `36563600572`;
- artifact: `Mugen-Deej-packages-16`, artifact ID `11031355287`;
- Actions artifact digest:
  `sha256:5fd4d9a9f1a7bd4bc9d7b3b5524676a26bd00342a1ac21e1cf8e703e6899edb4`;
- Setup SHA-256:
  `a779cee723ba5f5b9519d6f334110891203c3b4c48407eaa1fec787a2c7129a4`.

The desktop now gives Adaptive encoder indicators a dedicated **10 ms**
input/paint lane while leaving the rest of the dashboard and audio-slider work
on the existing main cadence. Only changed encoder position labels/28x28 knob
indicators are forced to paint immediately. The implementation iterates the
detected encoder-indicator collection rather than assuming exactly two
encoders, so it is compatible with the planned future two- and four-encoder
layouts.

Real-hardware observations from the CI #16 test:

- controller detected as Adaptive `5/28/2/2` at 500000 baud;
- deliberate rapid E1/E2 rotation remained responsive in both directions;
- the visual encoder lag was noticeably reduced;
- aggressive back-and-forth stress produced accumulated deltas such as
  `+2`/larger values instead of requiring one desktop packet per detent;
- no capability-shape mismatch warning, serial-loss warning, or
  `Fast encoder UI lane failed` marker occurred in the captured CI #16
  session;
- the operator observed at most roughly one-detent disagreement only when
  intentionally spinning/reversing the encoder far faster than normal use.
  This is **not** a controlled detent-count result, so the known-count test
  remains useful before the matrix/multiplexer encoder design becomes a public
  hardware reference.

The application was also observed returning to normal use after a hibernation
cycle during this test period. The captured CI #16 log did not contain a new
explicit suspend/resume marker for that observation, so this is recorded as an
operator usability pass rather than replacing the exact diagnostics regression
test below.

The exact historical diagnostics regression remains narrowly defined as:
hide to tray -> hibernate -> resume -> restore -> immediately open Connection
and diagnostics. The tray-only form of that test already passes; the exact
post-hibernation click path can be closed the next time it is convenient.

The earlier long-run recovery containment item also remains open until a
sufficiently long normal-use/reconnect soak is accumulated. Do not manufacture
a runtime change merely to close that timer-based observation.

### Hardware vNext clean-build concept

A separate durable design note now exists at:

`docs/HARDWARE_VNEXT.md`

It records the post-2.0 clean-build direction:

- keep the cardboard/Nano controller intact as a historical/regression fixture;
- design a new enclosure in Autodesk Inventor;
- target 5 potentiometers, 28 keyboard switches, 2 illuminated toggles and
  4 push-capable EC11 encoders;
- expand matrix columns through a CD74HC4067-class 16-channel multiplexer;
- move dashboard encoders to their own row so four full-size encoder indicators
  fit cleanly below the toggle row;
- preserve native encoder Push semantics and the existing center-dot/push
  highlight behavior;
- treat the clean build as hardware vNext, **not a 2.0.0 release blocker**.

Ordered-part context is also captured there: four CD74HC4067 modules, six bare
push-capable EC11 encoders, five 10 kOhm panel potentiometers (taper still to be
verified on arrival), and seventy 3-pin linear Silver-style keyboard switches.

### Long-run controller-recovery process failure — 2026-09-28

A second launcher-level process failure was reproduced during aggressive
controller/encoder testing after more than 11 hours of uptime.

Observed sequence from the captured logs:

- Encoder 2 continued reporting valid movement in both directions.
- The controller then stopped producing valid packets for 2500 ms and ordinary
  COM5 recovery was armed.
- Multiple targeted COM5 probes failed normally without killing the app.
- COM5 later recovered successfully as Adaptive `5/28/2/2`, and Encoder 2
  movement resumed.
- A few seconds later valid packets stopped again.
- Recovery started another targeted COM5 probe.
- The Mugen runtime log ended immediately after
  `Opening COM5 for protocol probe; baud candidates=115200,9600`.
- The launcher subsequently reported PowerShell `exitCode=2` after
  approximately 11h14m33s.
- No normal `Mugen Deej stopped` line was written.

There is no explicit `exit 2` path in the runtime. The main 5/20 ms WinForms
timer callback also previously had no outer exception boundary, so an
unexpected terminating exception escaping controller recovery could terminate
the PowerShell process even though ordinary SerialPort probe errors are handled
inside `Open-And-ProbePort`.

Containment hardening was committed as:

`999d1189c341093c9dc80c13a47892f5e9c5537e`
(`fix: contain unexpected controller recovery timer failures`)

The main UI timer callback now:

- has an outer `try/catch`;
- logs the exception chain, PowerShell category/FQID and script stack when an
  unexpected callback failure escapes lower-level recovery handling;
- keeps the application alive instead of allowing the callback failure to end
  the PowerShell process;
- defers the next targeted controller recovery by two seconds to avoid a tight
  repeating exception loop.

**Acceptance status: PENDING.** Re-run aggressive unplug/replug and encoder
stress using the CI-built package from the exact hardening commit, not a locally
patched installation.

CI provenance for the stress-test build:

- source commit:
  `999d1189c341093c9dc80c13a47892f5e9c5537e`;
- workflow: `Build release packages`;
- run: **#9**, run ID `36431010952`;
- artifact: `Mugen-Deej-packages-9`, artifact ID `10974000869`;
- Actions artifact digest:
  `sha256:a5e77a2baf03eb6ef9bf502f1b2e74518c909c0ed7c356b61eeb27350f6a6005`;
- Portable SHA-256:
  `b484fb889f74f01aa36dd755a9f3a5bd73dea8e0f5d27fd58acf4c2c416a834a`;
- Setup SHA-256:
  `2bd94c6cd665d0daece194d5c1f983b77ec810d3e2f99e0f53456d99bb3de909`.

If the underlying exception recurs, the expected result is that Mugen stays
alive and the new `Main UI timer callback failed but was contained` diagnostic
identifies the exact throw site. This incident is a concrete 2.0 release blocker
until the containment/recovery behavior passes hardware stress.

### Test-build discipline from this point forward

Do not patch the installed release candidate in place for product/runtime
acceptance work. The installed copy had accumulated several UI test patches and
therefore no longer provided a reliable source baseline for literal patch
anchors.

For release-prep/runtime validation, use this chain only:

```text
feature branch source -> commit -> GitHub Actions release build
-> download/unpack artifact -> hardware test -> record result here
```

Local patch scripts may still be used for disposable UI experiments, but a
result is not considered release acceptance until the equivalent source is
committed and tested from a CI-built artifact.

### Launcher hot-unplug diagnostic incident

During continued Adaptive hardware work, unplugging the active COM5 controller
produced a launcher error dialog even though the runtime first handled the serial
loss normally and armed controller recovery. The runtime log ended shortly
after recovery began and did not contain the normal `Mugen Deej stopped`
marker.

The existing Go launcher only showed a generic error when `powershell.exe`
returned a non-zero status, but did not record the actual `cmd.Run()` error,
PowerShell exit code, or process lifetime. Its log could therefore contain only
repeated `Mugen Deej launcher start` markers, which made the incident
undiagnosable after the fact.

Commit `f31a013614736e5f28a62020edab4a506a16d0b2` adds launcher-only diagnostics:

- timestamped launcher start;
- PowerShell exit code;
- launcher-observed process error;
- process runtime before failure;
- clean-exit marker on normal shutdown.

This does **not** yet identify or fix the underlying runtime termination. Treat
the incident as an open pre-release reliability item until the diagnostic
launcher captures a recurrence or repeated unplug/replug testing proves it
non-reproducible.

### Step 1 conclusion

**PASS.** The intended 2.0 public/developer structure is now defined. No files
were deleted or moved during classification. The next step is the Adaptive v3
source-of-truth hardware/firmware audit before any Arduino reorganization, so
the current proven firmware path remains untouched until its wiring facts have
been captured.

## Step 2 — Adaptive v3 hardware/firmware source-of-truth audit

Status: **PASS / source-of-truth captured**

Goal: derive documentation from the actual hardware-proven firmware and protocol,
not from memory.

- [x] Identify the exact firmware shipped in the 2.0.0 package.
- [x] Extract its actual pin assignments and electrical assumptions.
- [x] Cross-check packet format against `docs/PROTOCOL.md`.
- [x] Cross-check intended hardware model against `docs/HARDWARE_VISION.md`.
- [x] Separate facts proven by source/firmware from physical-build details that
  require confirmation from the real controller.
- [x] Decide which older Arduino sketches are examples, experiments, or history.

### Adaptive v3 hardware source of truth

The normal 2.0 release builder explicitly packages:

`arduino/MugenDeejCardboardNanoPrototype/MugenDeejCardboardNanoPrototype.ino`

This file is therefore the current hardware-proven **Adaptive reference
firmware**, despite its historical `Cardboard...Prototype` name.

Reference topology:

`5 sliders / 28 momentary buttons / 2 latching toggles / 1 encoder with push`

Transport:

- Adaptive v3;
- 115200 baud;
- 25 ms periodic heartbeat;
- changed matrix/key/encoder state can trigger a packet before the next
  heartbeat.

### Proven Nano pin map

Classic ATmega328P Nano-class board:

| Function | Logical signal | Nano pin |
| --- | --- | --- |
| Encoder | S1 | D2 |
| Encoder | S2 | D3 |
| Encoder | KEY / push | A2 |
| Matrix | C1 | D4 |
| Matrix | C2 | **D6** |
| Matrix | C3 | **D5** |
| Matrix | C4 | D7 |
| Matrix | C5 | D8 |
| Matrix | C6 | D9 |
| Matrix | C7 | D10 |
| Matrix | C8 | D11 |
| Matrix | R1 | D12 |
| Matrix | R2 | D13 |
| Matrix | R3 | A0 |
| Matrix | R4 | A1 |
| Potentiometer | P1 wiper | A3 |
| Potentiometer | P2 wiper | A4 |
| Potentiometer | P3 wiper | A5 |
| Potentiometer | P4 wiper | A6 |
| Potentiometer | P5 wiper | A7 |
| USB serial | RX/TX | D0/D1 reserved |

Important: **C2=D6 and C3=D5 are intentionally swapped in the real proven
firmware.** The firmware comment records that this physical jumper swap removed
same-column ghost presses while preserving the original logical C1..C8 /
B1..B28 numbering. The existing Nano README still says C2=D5/C3=D6 and must be
corrected before it is used as public wiring documentation.

A6/A7 are used only as analog inputs, matching classic Nano hardware.

### Matrix logical layout

```text
        C1   C2   C3   C4   C5   C6   C7   C8
R1      B1   B2   B3   B4   B5   B6   B7   T1
R2      B8   B9   B10  B11  B12  B13  B14  T2
R3      B15  B16  B17  B18  B19  B20  B21  spare
R4      B22  B23  B24  B25  B26  B27  B28  spare
```

C8 is not part of the 28 normal-button fields. Only R1C8/R2C8 are exposed as
the two Adaptive toggle fields; R3C8/R4C8 are ignored spare cells.

Electrical/scan assumptions in source:

- columns use `INPUT_PULLUP`;
- all rows are outputs and idle HIGH;
- one row at a time is driven LOW for scanning;
- every populated matrix contact is diode-isolated;
- diode path is:
  `COLUMN -> switch -> diode anode -> diode cathode/stripe -> ROW`;
- active-row settle = 6 microseconds;
- row-release/column-recharge settle = 60 microseconds;
- the 60 microsecond recovery interval exists because the long physical wiring
  previously produced same-column ghosting.

Matrix debounce:

- stable-state debounce = 6 ms;
- diagnostic rapid-reversal window = 35 ms;
- encoder push debounce = 20 ms.

### Potentiometers

Source-proven wiring:

```text
one outer leg -> 5V
wiper/middle -> A3/A4/A5/A6/A7
other outer leg -> GND
```

The firmware reports raw 10-bit ADC values `0..1023`. It discards the first
ADC conversion after switching channels, then transmits the second reading.
There is no firmware smoothing, endpoint calibration, dead zone or remapping.

Reversing a potentiometer's two outer 5V/GND wires reverses that individual
control. Mugen 2.0 additionally remembers a whole-controller slider-inversion
setting by protocol/topology signature; this does not replace correct
per-potentiometer wiring when only one control is reversed.

### Encoder

The reference firmware assumes a ready-made module with
`S1 / S2 / KEY / 5V / GND`:

- S1 -> D2;
- S2 -> D3;
- KEY -> A2;
- module 5V -> 5V;
- module GND -> common GND.

D2/D3 are handled through CHANGE interrupts and a Gray-code transition table.
Current reference constants:

- 4 quadrature edges per reported step/detent;
- direction multiplier = +1;
- encoder position is a signed cumulative counter;
- push is active LOW and is embedded in the Adaptive encoder field.

These edge/direction assumptions are proven for the current physical module but
may need adjustment for a different encoder/module.

### Adaptive packet actually emitted by the reference firmware

Each state line is:

```text
v3
| five s fields
| twenty-eight b fields
| two t fields
| one ePOSITION:PUSH field
| one d... diagnostic field
```

The optional diagnostic token is:

```text
d<debounceMs>:<filteredCount>:<filteredMaskHex>:<rapidCount>:<rapidMaskHex>
```

Current desktop 2.0 parser explicitly accepts this token, stores it separately
from the physical controls and excludes it from controller topology/signature
matching. The public `docs/PROTOCOL.md` currently omits this implemented
diagnostic token and must be updated.

### Documentation discrepancies found by the audit

1. **Nano README C2/C3 mapping is stale/wrong.**
   It says C2=D5/C3=D6; proven firmware is C2=D6/C3=D5.
2. `docs/HARDWARE_VISION.md` still describes the panel as an untested Uno
   bring-up with first-class toggle/encoder semantics not yet implemented.
   That section is pre-2.0 history and must be rewritten or moved to history.
3. `docs/PROTOCOL.md` has stale implementation-status language from before
   Adaptive actions/layers and current real-hardware acceptance.
4. `docs/PROTOCOL.md` does not document the implemented optional `d...`
   firmware diagnostics token.
5. The current proven reference has 28 normal buttons; some older fixtures/docs
   intentionally use 29 synthetic buttons. Public docs must clearly distinguish
   the **reference hardware 5/28/2/1** from the **Adaptive topology test fixture**.

### Hardware-proven illuminated toggle wiring

The physical reference build now also has working illumination in both
automotive-style 12 V toggle switches without adding any GPIO pins.

Observed internal switch behavior:

- each switch has two main contact terminals plus a separate LED negative
  terminal;
- the internal LED positive is tied to one of the two main switch terminals;
- therefore the switch must be oriented so that the **LED-positive/contact
  terminal is on the ROW/diode side**, while C8 connects to the opposite main
  terminal;
- each LED negative terminal connects to common GND.

The matrix wiring remains:

```text
+5V
 |
325 ohm
 |
C8 / D11
 |
+---- switch T1 ---- LED+ node ---- matrix diode ---- R1
|                         |
|                         +---- internal LED ---- GND
|
+---- switch T2 ---- LED+ node ---- matrix diode ---- R2
                          |
                          +---- internal LED ---- GND
```

The external 1N4148 matrix diodes keep their existing orientation:
**contact -> diode anode -> diode cathode/stripe -> ROW**.

The added **325 ohm pull-up from +5 V to C8/D11** is hardware-tested with both
illuminated toggles ON simultaneously.

Measured on the current Nano build:

- Nano supply: approximately **4.88 V**;
- C8/D11 with one illuminated toggle ON and ~500 ohm pull-up: approximately
  **3.71-3.73 V**;
- C8/D11 with both illuminated toggles ON and ~500 ohm pull-up: approximately
  **3.16-3.17 V**;
- C8/D11 with both illuminated toggles ON and **325 ohm pull-up**:
  approximately **3.43-3.44 V**.

Functional hardware test with the final 325 ohm pull-up:

- both switch LEDs illuminate only in the ON state;
- both toggles continue to report correctly through Adaptive v3;
- buttons were exercised across all four matrix rows, individually and in
  groups, with the illuminated toggle wiring active; no false matrix
  activations were observed;
- the captured runtime log also showed a clean Adaptive 5/28/2/1 reconnect with
  firmware debounce diagnostics filtered=0 / rapid=0, and correctly preserved
  simultaneous held states for B21 and B28 until release.

This illumination arrangement is specific to the tested three-terminal switch
construction. Public wiring docs must tell builders to identify which main
terminal is internally tied to LED+ before soldering; other illuminated switch
types may use different internal wiring.

### Facts not derivable from firmware alone

Do not invent these in public BOM/wiring docs:

- exact potentiometer resistance/value and mechanical model;
- exact commercial encoder-module model;
- exact toggle-switch product/terminal numbering;
- wire gauge, connector family and enclosure dimensions;
- final 3D enclosure mounting dimensions.

The electrical interface can be documented without those details. If a
reproducible MakerWorld/BOM package is produced later, those physical part
details should come from the actual build or CAD model, not inference.

### Older Arduino sketches after source audit

- `MugenDeejController`: current Extended reference firmware.
- `MugenDeejCardboardNanoPrototype`: current proven Adaptive reference,
  pending rename/reorganization.
- `MugenDeejUnoAdaptiveTest`: developer topology regression fixture.
- `MugenDeejUnoTransportTest`: developer transport/auto-baud fixture.
- `MugenDeejCardboardUnoPrototype`: historical bring-up predecessor.
- `MugenDeejPanelPrototype`: obsolete pre-Adaptive design/history.

Deliverable: **PASS**. A reviewed factual wiring/pin-map source is now captured.
Step 3 can build the public Adaptive docs/diagram from these facts without
guessing.

## Step 3 — Adaptive v3 public documentation

Status: **IN PROGRESS / TEXTUAL DOCS COMPLETE**

Target public docs:

- [x] `docs/ADAPTIVE_V3.md` — protocol/capability overview and reference scope.
- [x] `docs/ADAPTIVE_V3_WIRING.md` — proven Nano pin map, matrix/diode rules,
  illuminated-toggle wiring and text diagrams.
- [x] `docs/ADAPTIVE_V3_BUILD.md` — flash/build/smoke-test instructions.
- [ ] add a polished graphical wiring diagram/image; the factual text diagram
  and pin tables are now present, so this is presentation work rather than a
  missing electrical fact.
- [x] link the Adaptive docs from both English and Russian README files.
- [x] clearly distinguish the tested reference controller from Adaptive's
  dynamic/non-hardcoded topology.
- [x] update `docs/PROTOCOL.md` for the implemented optional `d...`
  diagnostics token, current implementation status and 500000-baud experimental
  desktop support.

The accepted public reference remains **5/28/2/1 at 115200 baud / 25 ms**.
The experimental 5/28/2/2, 500000-baud and 10 ms work is intentionally not
presented as the required/reference firmware in the public build instructions.

## Step 4 — public README/release-facing polish

Status: **PASS / RELEASE-FACING TEXT AUDITED**

- [x] Read `README.md` top-to-bottom as a first-time user.
- [x] Read `README_RU.md` top-to-bottom as a first-time user.
- [x] remove stale release-branch wording where it implied 2.0 was already
  published; historical firmware directory names are now explained instead of
  pretending they are new product names.
- [x] ensure Legacy / Extended / Adaptive v3 are explained consistently.
- [x] ensure Setup vs Portable and unsigned-build/SmartScreen guidance is clear.
- [x] record current signing status. As of 2026-09-29 there is no Authenticode
  signing path available for this release; README/BUILDING/release-note wording
  now explains Unknown publisher/SmartScreen without treating it as a security
  verdict.
- [x] verify `THIRD_PARTY_NOTICES.md`, `SECURITY.md`, `CONTRIBUTING.md`,
  `BUILDING.md` and `CHANGELOG.md` against 2.0.0.
- [x] update `docs/BUILDING.md` for the .NET 10/HIDMaestro build dependency
  and actual virtual-gamepad/reference-firmware package contents.
- [x] audit `config.example.json` against config schema 9; add
  `baudRateMode`, `lastWorkingBaudRate` and
  `invertSlidersByController`.

A final publication-date/version-link sanity pass still belongs in Step 7
because README must continue to say 1.0.0 is the latest *published* release
until 2.0.0 is actually published.

## Step 5 — development archaeology cleanup

Status: **NOT STARTED**

Do not delete anything until classified in Step 1.

- [ ] classify all historical RC patch scripts under `tools/`.
- [ ] decide whether historical patch-chain material should be deleted, moved
  under a history area, or retained with an explicit archived marker.
- [ ] review both virtual-gamepad workflows.
- [ ] review `dev/virtual-gamepad`.
- [ ] review old Arduino prototypes/tests.
- [ ] verify no cleanup change alters the canonical 2.0 runtime or normal release
  builder.

## Step 6 — release publication preparation

Status: **IN PROGRESS / RELEASE BODY DRAFTED**

- [x] draft `docs/RELEASE_NOTES_2.0.0.md` / GitHub Release body in English
  and Russian.
- [x] prepare upgrade notes from 1.0.0.
- [x] prepare Setup/Portable checksum presentation with explicit FINAL/TBD
  placeholders so an older CI checksum cannot accidentally be published.
- [ ] incorporate code signing only if a real signing path becomes available.
- [x] document the current unsigned publisher / SmartScreen expectation without
  implying a security failure.
- [ ] run the final release builder from the final pre-merge source state.
- [ ] replace release-note checksum placeholders with the final artifact hashes.
- [ ] hardware-smoke any newly signed/repackaged/final artifacts if their binary
  contents differ from the accepted build.

## Step 7 — pre-merge cleanup

Status: **NOT STARTED**

Before creating/merging the final PR:

- [ ] delete **this file**: `docs/PRE_MERGE_2_0_CHECKLIST.md`.
- [ ] decide/remove any internal handoff/state material that should not ship to
  `main`.
- [ ] ensure no temporary consolidation workflow remains.
- [ ] ensure historical RC workflow/tooling disposition is intentional.
- [ ] verify `git diff main...feature/virtual-gamepad-ui` contains only intended
  2.0 product/source/docs/history changes.
- [ ] run normal release workflow from the final pre-merge branch state.
- [ ] record final artifact SHA-256 values.
- [ ] one final sanity review of README/version/changelog/license/notices.

Only after this checklist is complete:
**PR -> review -> merge -> tag `v2.0.0` -> GitHub Release.**

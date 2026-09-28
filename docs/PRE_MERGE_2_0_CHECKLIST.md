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

Status: **NOT STARTED**

Target public docs (names can be adjusted during the audit):

- [ ] `docs/ADAPTIVE_V3.md` — what Adaptive v3 is, capabilities, protocol role.
- [ ] `docs/ADAPTIVE_V3_WIRING.md` — board/pin table, wiring rules, inversion note.
- [ ] `docs/ADAPTIVE_V3_BUILD.md` — flash/build/test instructions.
- [ ] add a clear wiring diagram/image after the factual pin map is confirmed.
- [ ] link these docs from both English and Russian README files where useful.
- [ ] ensure wording clearly distinguishes the tested reference controller from
  the protocol's dynamic/non-hardcoded topology.

## Step 4 — public README/release-facing polish

Status: **NOT STARTED**

- [ ] Read `README.md` top-to-bottom as a first-time user.
- [ ] Read `README_RU.md` top-to-bottom as a first-time user.
- [ ] remove stale RC/prototype/experimental wording.
- [ ] ensure Legacy / Extended / Adaptive v3 are explained consistently.
- [ ] ensure Setup vs Portable and unsigned-build/SmartScreen guidance is clear.
- [ ] add code-signing wording only after SignPath status is known.
- [ ] verify `THIRD_PARTY_NOTICES.md`, `SECURITY.md`, `CONTRIBUTING.md`,
  `BUILDING.md` and `CHANGELOG.md` are consistent with 2.0.0.

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

Status: **NOT STARTED**

- [ ] draft `docs/RELEASE_NOTES_2.0.0.md` / GitHub Release body.
- [ ] prepare upgrade notes from 1.0.0.
- [ ] prepare Setup/Portable checksum presentation.
- [ ] incorporate SignPath/code-signing workflow if approved and available.
- [ ] if signing is not available in time, document the unsigned publisher /
  SmartScreen expectation without implying a security failure.
- [ ] run final release builder again if signing or package contents change.
- [ ] hardware-smoke any newly signed/repackaged final artifacts if their binary
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

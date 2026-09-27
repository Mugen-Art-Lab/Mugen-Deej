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

### Step 1 conclusion

**PASS.** The intended 2.0 public/developer structure is now defined. No files
were deleted or moved during classification. The next step is the Adaptive v3
source-of-truth hardware/firmware audit before any Arduino reorganization, so
the current proven firmware path remains untouched until its wiring facts have
been captured.

## Step 2 — Adaptive v3 hardware/firmware source-of-truth audit

Status: **NOT STARTED**

Goal: derive documentation from the actual hardware-proven firmware and protocol,
not from memory.

- [ ] Identify the exact firmware shipped in the 2.0.0 package.
- [ ] Extract its actual pin assignments and electrical assumptions.
- [ ] Cross-check packet format against `docs/PROTOCOL.md`.
- [ ] Cross-check intended hardware model against `docs/HARDWARE_VISION.md`.
- [ ] Separate facts proven by source/firmware from physical-build details that
  require confirmation from the real controller.
- [ ] Decide which older Arduino sketches are examples, experiments, or history.

Deliverable: a reviewed factual wiring/pin-map source from which public docs and
a diagram can be produced.

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

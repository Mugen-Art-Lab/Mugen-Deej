# Mugen Deej — living project state

Last updated: 2026-09-26

This is the authoritative short handoff for active development. Detailed prototype history is in `docs/VIRTUAL_CONTROLLER_TEST_LOG.md`; current product-integration work is in `docs/VIRTUAL_GAMEPAD_INTEGRATION.md`.

## Stable baseline

- Public release: `v1.0.0`
- Stable branch: `main`
- Stable squash commit: `214273e0c845ba9932544521da856af4a7a4fe24`
- Release page: `https://github.com/Mugen-Art-Lab/Mugen-Deej/releases/tag/v1.0.0`
- Runtime: Windows PowerShell 5.1 + small Go launcher.
- Stable v1.0.0 stays frozen while virtual-controller work is developed in a feature branch.

Hardware-tested stable behavior:

- Legacy: 5 sliders / 0 buttons — PASS.
- Extended: 5 sliders / 6 buttons — PASS.
- Real audio control, Extended button actions, Setup, backup/restore and release packaging — PASS.

## Active branch

`feature/virtual-gamepad-ui`

### Current active milestone

Integrated **#229** is the current hardware-tested baseline.

Integrated **#229** has passed the real-machine backup-restore/restart regression on the Adaptive 5/28/2/1 controller. After restart the first accepted topology was Adaptive 5/28/2/1, with no temporary Legacy 1-slider lock and no 2500 ms timeout/recovery loop.

Backup-dialog UI note: the restore confirmation still exposes technical topology text (`Adaptive v3 — 5/28/2/1`) and uses a light treatment while the post-restore restart dialog follows the dark app theme. Keep this queued with the #227 UI review rather than mixing it into the probe fix.

Integrated **#247** remains the last hardware-reviewed UI baseline. **2.0.0-rc1 / run #251** is now the current release-candidate package: Prototype identity removed, production Windows-startup behavior restored, first-run wording polished, `Продолжить / Continue` replaces the old close-guide wording, and controllers with sliders get a direction-inversion hint. CI/package: PASS; RC1 real-machine acceptance is pending.

Recent accepted chain:
- **#214**: 5 ms low-latency active-XInput serial drain and cached effective profile/layer resolution;
- **#216**: rapid-repeat hot-path hardening removes avoidable synchronous logging/debounce work from virtual Xbox mappings;
- **#218**: Cardboard Nano matrix debounce reduced to 6 ms with firmware diagnostics; real-game responsiveness and diagnostic review passed on the test panel;
- **#219**: backup schema v3 restores Adaptive layers plus virtual-controller state, and layer Xbox mapping can auto-enable XInput when explicitly configured;
- **#220**: Physical button actions hot-unplug hardening isolates editor state under `$buttonEditorState` and pauses its 25 ms live-selection timer while disconnected.

#220 has passed the real-machine regression that originally crashed: with the optimized Physical button actions dialog left open on the Extended 5-slider / 6-button controller, repeated USB unplug/replug cycles no longer produce the `LastButtons` WinForms/PowerShell exception. The application survives disconnect/recovery and physical input resumes after COM10 is detected again.

Stable `main` / v1.0.0 remains untouched. Detailed run/artifact hashes and the chronological development record live in `docs/CURRENT_HANDOFF.md`.

Goal: keep Mugen Deej a generic low-cost DIY controller router while adding optional game-controller output on the PC side.

```text
physical DIY hardware
        |
        v
Mugen serial protocol
        |
        v
Mugen Deej routing / profiles
   |          |           |
   v          v           v
audio      actions     virtual controller
```

The microcontroller should remain simple. The same physical hardware should be reusable without reflashing when the user changes what controls mean.

## Protocol / future hardware facts

Extended packets are dynamic, e.g.:

```text
s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1
```

The current parser accepts at most 64 total fields.

Planned matrix prototype:

- 5 analog controls;
- 5×6 switch matrix = 30 buttons;
- 35 total packet fields, within the parser limit;
- Arduino Nano-class hardware;
- 1N4148 diodes for the switch matrix.

5+30 is **NOT hardware-tested yet**.

Bandwidth warning: a roughly 115–120 byte full-state packet needs about 120 ms at 9600 baud with 8N1, so the current 60 ms cadence cannot be reused unchanged. Before final matrix firmware, add configurable/higher baud or deliberately lower the full-state cadence.

## Virtual controller architecture

Virtual output is optional and must be OFF by default for existing users.

Semantics:

- ordinary Mugen button actions are press-edge-triggered;
- virtual buttons are stateful (press + hold + release);
- virtual axes are continuous.

Cleanup requirement: disconnect, app exit, bridge failure, backend failure, profile switch and hard-close must never leave stuck input or an orphaned gamepad. Reboot as a normal recovery path is unacceptable.

Planned user-facing modes:

- `Xbox 360 / XInput` — compatibility-first, fixed Xbox control set;
- `Generic / DirectInput` — arbitrary DIY shapes, many buttons and custom axes.

Current backend: HIDMaestro 1.8.0.

Why it is currently accepted for development:

- active project;
- MIT license;
- user-mode UMDF2;
- built-in Xbox 360 profile;
- supports XInput/DirectInput/GameInput/WGI/SDL visibility;
- SDK can create custom HID layouts.

Pinned HIDMaestro release archive SHA-256:

`1e5f5019c20e4be8f922c7aa5a86ee87eb01f7aa851fe38daea14d0ce4fd8240`

Windows elevation is required for the virtual HID operations, so Mugen keeps its UI unelevated and uses an elevated helper connected by a named pipe. A UAC prompt may or may not be visible depending on the Windows/UAC configuration.

Current Xbox display label:

`Mugen Deej Virtual Gamepad`

The label is presentation only and must not be used as internal identity; HIDMaestro's OEM-name override is VID:PID-scoped.

## Prototype 0 — backend proof

**PASS / COMPLETE ENOUGH FOR PRODUCT INTEGRATION.**

Real hardware: existing Extended 5-control / 6-button controller on COM10.

Hardware-proven:

- Extended detection;
- elevated helper startup;
- Xbox/XInput virtual device creation;
- `joy.cpl` enumeration;
- display name `Mugen Deej Virtual Gamepad`;
- neutral axes/triggers/POV;
- stateful press/hold/release;
- simultaneous button combinations;
- emergency live orphan cleanup without reboot;
- hard-close / bridge-loss cleanup without reboot;
- normal Q/Esc teardown without reboot;
- HardwareTester recognition as XInput / standard mapping;
- real-game recognition/input in `Cult of the Lamb`.

Important commits:

- `487592fe3a23986bfb3a9be63754a92a651e5ef2` — explicit neutral axes.
- `540648f6680cc2b37667cb7fe95b83ea71112ad7` — crash-safe display-name lifecycle.
- `e887e4ac857c40f53566dd82e3ed0ad7c1b4a09e` — safe normal teardown using proven bridge-disconnect cleanup.

Latest validated standalone prototype:

- workflow run `35118021710`, run #11;
- artifact ID `10456900609`;
- CI PASS;
- normal Q teardown hardware PASS.

The standalone harness is now a development fixture, not the intended product UI.

## Integrated product milestone 1 — current work

Status: **PARTIAL REAL-HARDWARE PASS / NONBLOCKING TEARDOWN HARDWARE RE-TEST PENDING.**

The integrated development build routes the proven Xbox backend through the actual Mugen Deej Button Settings/runtime while leaving the stable source/release untouched.

Hardware/UI proven so far:

- virtual output defaults to `Off`;
- Button Settings exposes `Virtual controller: Off / Xbox 360 / XInput`;
- Xbox buttons are assigned through a dedicated visual picker;
- virtual mappings survive reopening Button Settings and controller capability re-detection;
- stateful virtual button output works through the real integrated runtime;
- one helper is launched instead of the original reentrant helper storm;
- COM10 stays connected while virtual output starts;
- first virtual-controller creation is nonblocking: the UI remains responsive during the roughly 16.6-second HID/PnP creation window;
- main-window virtual status row is bilingual and only appears while virtual output is enabled;
- status transitions `connecting -> connected` were visually verified in RU and EN;
- dev builds suppress Windows startup registration so they cannot steal the stable app's HKCU Run path.

The first integrated attempt exposed and fixed two major bugs:

1. helper startup reentrancy spawned many elevated helpers and starved COM processing;
2. the stable action normalizer rejected `virtual:xbox:*` and rewrote mappings to `none`.

Important integration fixes:

- `aafb1c85784568228023e659bbeae4c0543e5fe1` — single-start guard;
- `d255724b6e75e980289ad03cab38591b0690ff6a` — preserve virtual mappings through normalization;
- `7308b73f2507d795cb1a0fd4c43dce11bb8ea5cc` — nonblocking virtual-controller startup;
- `049e5d1a88ee4437897e5356a64fc5bf5dbe7117` — conditional main-window virtual-controller status;
- `e3eadbfa70db0c078f6149e7f07ddc19014629dd` / `c39f4fb31a259905d99a63fb1e7c3d29d2ef497f` — dev-stage nonblocking teardown overlay and packaging.

### Current teardown finding

Disabling virtual output and exiting Mugen still froze the UI for about 10.3 seconds in run 12. Logs proved the delay is real HIDMaestro/controller disposal, not the final orphan sweep:

- disable at `00:54:58.362`;
- helper `STOP` at `00:54:58.368`;
- `OEM_NAME_CLEARED` at `00:55:08.630`;
- `EXIT_SWEEP_DONE` at `00:55:08.645`;
- Mugen returned from stop at `00:55:08.678`.

Normal app exit showed the same ~10.3-second wait.

The visible freeze was caused by Mugen synchronously calling `WaitForExit(30000)` while the helper performed cleanup. Run 14 replaces that UI-thread wait with background helper reaping. It also prevents a new virtual controller from starting until the previous helper finishes cleanup, avoiding a create/remove race if the user toggles the feature quickly.

A secondary helper-log issue remains: after successful cleanup, disposing an already-broken pipe writer can log `System.IO.IOException: Pipe is broken` as `FATAL`. Cleanup has already completed, so this is log noise rather than evidence of an orphan, but it should be cleaned up before release.

Latest integration CI:

- run #14 `35138005925`: **PASS**;
- head: `c39f4fb31a259905d99a63fb1e7c3d29d2ef497f`;
- Windows PowerShell 5.1 parse check: PASS;
- nonblocking startup/teardown static checks: PASS;
- helper publish/smoke: PASS;
- launcher build/package: PASS;
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-14`;
- artifact ID: `10463797250`;
- inner dev ZIP SHA-256: `4581329c6065f14f7de08704ef9006650d9c413527d25549f290692e9b267ddb`.

Do not call nonblocking teardown a hardware PASS until run #14 is exercised on the physical Extended controller.

Implementation files:

- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.ps1`
- `src/virtual-gamepad-integration/MugenDeej.VirtualGamepad.AsyncStop.ps1` — temporary dev-stage teardown override;
- `tools/Build-VirtualGamepad-Integration.ps1`
- `tools/Harden-VirtualGamepad-DevRuntime.ps1`
- `.github/workflows/build-virtual-gamepad-integration.yml`

The build-time patcher/overlay is temporary. Once the integrated path is hardware-proven, consolidate it into normal source before any release/merge, then remove the experimental patch chain.

Detailed current test plan: `docs/VIRTUAL_GAMEPAD_INTEGRATION.md`.

## Profiles — planned architecture

Terminology:

- **Profile** = complete user configuration for a connected control surface.
- **Preset** = optional template used to create a profile, e.g. Xbox Gamepad, Arcade Pad, 30-button DirectInput, Streaming.

Planned UI concept:

```text
Profile: [ Desktop v ]  [ Manage... ]
```

Profile management:

- New;
- Duplicate;
- Rename;
- Delete;
- select from dropdown.

A permanent `Default` profile must preserve migrated 1.0.0 behavior.

Eventually a profile owns:

- ordinary button actions;
- analog destinations;
- virtual controller enabled/type;
- virtual button/axis mappings;
- controller-shape metadata;
- optional safe display-name settings.

Hardware mismatch must degrade gracefully: a 5+30 profile used with 5+6 hardware skips unavailable mappings; extra physical controls default unassigned.

Manual profile switching comes first. Automatic switching by game/process is deferred.

## Next steps

1. Hardware-test run #14: disable virtual output and confirm Save returns immediately while the gamepad disappears in the background.
2. Exit Mugen with the virtual gamepad active and confirm the Mugen window/process closes promptly while helper cleanup continues independently.
3. Re-enable immediately after disabling once and verify the new controller waits for old HID cleanup rather than racing it.
4. Confirm no orphaned gamepad remains after the background cleanup and no reboot is required.
5. Clean up the helper's expected broken-pipe disposal being logged as `FATAL`.
6. Reopen/reconnect and confirm saved virtual mappings remain intact.
7. Re-check a real XInput game from the integrated runtime.
8. After milestone 1 PASS, consolidate integration into normal source and remove temporary runtime patchers/overlays.
9. Add analog control → virtual axis routing.
10. Introduce Profiles and move virtual config/mappings into them.
11. Add Generic / DirectInput.
12. Build/test the future 5+30 matrix controller.

## Deferred

- automatic game/profile switching;
- telemetry back to LEDs/displays;
- bidirectional simulator panels;
- force feedback;
- custom Mugen driver;
- layers/pages;
- OLED/LCD per-key displays;
- plugin marketplace;
- matrix-layout designer.

## Design principles

- Do not break stable Legacy behavior.
- Extended stays auto-detected.
- Hardware stays cheap/simple; intelligence lives in Mugen Deej.
- Static/custom keycaps or printed labels remain preferred for the low-cost deck idea.
- Do not call theoretical/code-inspection support a PASS.
- Experimental work stays off `main` until real-hardware smoke tests pass.
- Keep this file and the integration/test notes current so a new chat can resume from the repository.
- Cardboard Uno prototype matrix hardware PASS: after correcting the row wiring to parallel shared buses (one diode per switch, no series-chained row diodes), all 28 momentary buttons register correctly in Mugen. The prior C5..C8 failure was physical matrix wiring, not Uno pins or desktop parsing.

- Full digital cardboard-panel smoke test PASS: 28 buttons, 2 toggles, and encoder/push work on real Uno hardware; a >20-button simultaneous hold also registered cleanly. Five slider channels remain software placeholders pending real potentiometers.


## Current hardware-review build — Integrated #142

#134's Adaptive-only XInput policy passed the first real protocol-switch check: Legacy correctly hid the XInput controls and the virtual HID cleanup completed. The same test exposed a broader COM hotplug recovery issue: Windows could briefly enumerate the returning Adaptive COM port while `SerialPort.Open()` still reported that the port did not exist. Mugen treated that as an ordinary failed open and imposed a 60-second cooldown.

#142 treats only that explicit "enumerated but not openable yet" condition as transient. It retries after 2 seconds, while true access-denied/busy ports retain the existing long backoff. COM enumeration is also deduplicated so transient Windows duplicates do not leak into recovery state/logs.

Run #142 (ID `35530843054`) succeeded at head `7a2045c2b6769756b3717781af5ea4e47f286481`; artifact ID `10611700235`; outer digest `sha256:1f3fb32de042297ab442512c6f213c454e3211ff3a8b0b5b41e9be8f631e3859`; inner ZIP SHA-256 `fd87ce0a51ab5521ba9772b50f40cfc8c5ba7f8d7ba8bfbc9b83e27b624137a1`.

#142 is CI PASS. Real-machine acceptance is the same stress sequence that exposed the bug: Adaptive/XInput ON -> Legacy -> Adaptive. If Windows publishes the returning COM name before it is ready, the expected log is `transient hotplug state ... retry in 2 s`, followed by prompt reconnection rather than the previous ~60-second stall. The #134 Legacy/Extended XInput hiding policy must remain unchanged.


## Integrated #144 — persistent slider advanced-toggle guard + working Nano column swap

Real-machine follow-up showed two independent details:

- after physically swapping Nano matrix column jumpers C2/C3, the same-column ghost presses disappeared; only logical button ordering became swapped, so the Nano firmware now maps logical C2/C3 to physical D6/D5 and preserves normal B1..B28 numbering without rewiring the working state again;
- Integrated #143's slider Advanced-settings debounce still flickered because the timestamp was assigned inside a PowerShell event-handler invocation scope and was not reliably persistent across Click events. #144 stores the last-click timestamp on the control itself (`AccessibleDescription`) and ignores duplicate Click events within 500 ms; diagnostic log lines were added for accepted/ignored events.

Workflow:
- run **#144**, run ID `35752416093` — SUCCESS;
- built app code head `d069a42b54817a56b95e2645715825d6d4af6a16`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-144`, ID `10707050564`;
- outer Actions digest `sha256:17fc5312d07b393990f34c67c27630bc028279a76cc3f8254a1f62f5391f2e8d`;
- inner program ZIP SHA-256 `a14e26af6e73fcde8ee73ce092fc85dc1dc5ede9af9912687eb09c5f7ad112b8`;
- CI staging, Windows PowerShell 5.1 parse/runtime checks, launcher/helper build, packaging and upload: PASS.

Nano firmware head after the app build also includes the logical C2/C3 remap for the user's currently working jumper arrangement.


## Current hardware-review build — Integrated #146

Integrated #144 reached the real slider Advanced-settings Click handler but crashed because it used `[Environment]::TickCount64`, an API absent from Windows PowerShell 5.1's .NET Framework runtime. #146 keeps the persistent duplicate-click guard but uses `[DateTime]::UtcNow.Ticks` plus `[TimeSpan]::TicksPerMillisecond`, and CI now explicitly rejects `Environment.TickCount64` from the staged runtime.

Run #146 (ID `35754260071`) succeeded at code head `d5586e9683017bb92f5c125c973b869f316d67b2`; artifact ID `10706049321`; outer digest `sha256:c8c29131d2a7c552e4f56786c6df56dfd3c170d033364903f3d4a3767721c244`; inner ZIP SHA-256 `4972469509232231df23b2e8746bca0eb2140bd4d1db346f0729c14a4bfbd47b`.

Immediate real-machine check: open slider settings, expand/collapse Advanced settings several times, enable global slider inversion, Save, and confirm all five physical pots now move in the preferred direction. If duplicate Clicks still exist, the log should now contain accepted/ignored advanced-panel diagnostics instead of throwing a JIT exception.

The Nano test wiring currently keeps physical C2/C3 swapped (C2=D6, C3=D5), while the firmware logically remaps them back to normal B1..B28 numbering. The observed B23 whole-column ghost set disappeared in the post-swap test.


## Current hardware-review build — Integrated #149

#146 still showed the slider Advanced section disappearing even though the click-timing guard no longer crashed. The real-machine log showed every accepted click as `visible=True` and never `False`, revealing that the deferred Click handler was binding to the wrong `$advancedPanel` variable. Both the main window and the slider dialog used that name.

#149 gives the slider dialog its own named `SliderAdvancedPanel` and resolves it from `$sender.FindForm().Controls.Find(...)` inside the Click handler. The inversion checkbox and responsiveness combo are likewise resolved from the dialog on Save. The staging patcher and CI checks were updated accordingly.

Run #149 (ID `35755453514`) succeeded at code head `5b57c295fd02df5cb80a8a93574a823d56ee66e8`; artifact ID `10708695236`; outer digest `sha256:9f85ce880986c82c32e927338b88c9f71781f4c5d450d034702c1d53e31799c9`; inner ZIP SHA-256 `d4437f6ce1cd1710b0ea190c17e4ff3bdf9f5e3a9ce2959a7965ce0da42f3a7e`.

Real-machine acceptance for this build: Advanced settings must remain visible after expansion, collapse/reopen normally, and Save must persist global slider inversion for the five physical Nano potentiometers.


## Current hardware-review build — Integrated #152

#149 fixed the wrong-panel binding and the slider Advanced section now expands/collapses against the correct dialog. Real-machine Save then exposed a separate StrictMode error: the Save handler used `$sender.FindForm()` without declaring `param($sender, $eventArgs)`. #152 binds the WinForms event parameters explicitly and retains dialog-scoped lookup for the inversion/responsiveness controls.

The expanded slider Advanced card is also moved farther below the section toggle and the Save/Cancel row is moved below the card, with a slightly taller base dialog so the normal five-slider layout no longer overlaps.

Run #152 (ID `35756930169`) succeeded at code head `25145a413f17123852dd99d8dbba0315f3d7d8cd`; artifact ID `10708472819`; outer digest `sha256:e0c20d32e33b7b1803f28351c1a0556f3fb121735e85456b7262387ba10991ea`; inner ZIP SHA-256 `fee9cc30c4c6496d644d89b61be871c53adc26f2dfba6a90efa18c1f9adef527`.

Real-machine acceptance: Advanced settings should remain cleanly laid out, Save with global slider inversion must close normally, inversion must persist on reopen, and all five real Nano pots should move in the preferred direction.


## Current hardware-review build — Integrated #155

#152 passed the functional slider-settings test on the real Nano panel: global inversion saved without a JIT exception and the five physical potentiometers subsequently reported live values in the preferred direction. The remaining defect was visual overlap in the expanded Advanced section.

#155 replaces the two independently positioned top-level Advanced controls with one `SliderAdvancedHost`: the toggle is fixed at host-relative `(0,0)`, the content panel at `(0,46)`, and only the host is moved by dynamic topology/layout code. The normal five-slider dialog no longer enables unnecessary Form.AutoScroll.

Run #155 (ID `35757909957`) succeeded at code head `53e469ac6a2daf63df6626e5777b5fe4535161d9`; artifact ID `10708579398`; outer digest `sha256:36584e85d675d9b0bec5267cb9650c9363879de18b1cbac6ea4e600e85033724`; inner ZIP SHA-256 `d39ce76bba887f30827a902741e7f22bf1518cd2aca2234883e5782bd3848d14`.

Real-machine acceptance for #155 is now mostly visual/regression: Advanced controls must render below the section toggle, collapse/reopen normally, and the already-working inversion + five live Nano pots must remain intact.


## Current hardware-review build — Integrated #160

The real Nano analog path is functionally working: all five physical potentiometers are live and the global inversion setting saves successfully. #155 still had a purely UI initialization defect where the collapsible Advanced-settings button could flash briefly and disappear when the slider dialog opened.

#160 removes that collapsible mechanism. Slider Advanced settings are now permanently visible in a dedicated card below the slider rows: inversion, responsiveness/help and Open config are always present. Dynamic topology moves that card as a unit, and normal five-slider layout does not enable unnecessary AutoScroll.

Run #160 (ID `35759260556`) succeeded at code head `081751cda7395c232f45bd6c78471660f1ebc969`; artifact ID `10709081360`; outer digest `sha256:50ff2c5988aa4f59e10d10b7790d9489af715df7ed766381aaf1879df98dcdca`; inner ZIP SHA-256 `866891dd1422284d228e0e5187945e422d2e83c3bab16aa4415505ff3101d645`.

Real-machine acceptance: opening slider settings must immediately show the Advanced card without any transient arrow/show-hide control, inversion must remain persisted, and the five real Nano potentiometers must continue reporting correctly.


## Hardware PASS — Integrated #160 + Nano five-pot prototype

Integrated #160 has now passed real-machine validation for the completed physical analog path. The user's Nano controller is detected as Adaptive `5 / 28 / 2 / 1` at 115200, all five real potentiometers produce live UI values, global inversion persists, the always-visible analog Advanced card renders correctly, and Save is stable with no JIT exception.

The same test session also showed normal encoder movement/push events and clean sampled button events, including B23 after the earlier C2/C3 jumper/remap fix.

This closes the original five-slider-placeholder gap: the prototype now has five actual analog controls feeding Mugen end-to-end. Remaining future work is no longer basic analog acquisition; it is higher-level behavior such as calibration/filtering decisions from measured hardware behavior and analog-to-XInput mapping.


## Current hardware-review candidate — Integrated #175

Integrated #175 adds Adaptive-only toggle-driven control layers. Two physical toggles can select Base, T1, T2, or T1+T2. Buttons and encoder CW/CCW/push can inherit the base mapping or provide a layer-specific override, including per-application profile contexts.

Compatibility is intentionally gated: Legacy/Extended return layer index 0 and retain the existing flat/profiled mapping path. The new layer configuration is stored separately in `adaptive-layers.json`. Adaptive layer transitions are also fed into the virtual-Xbox context boundary logic so held virtual controls are neutralized/suppressed across a layer change.

Run #175 (ID `35766695670`) succeeded at code head `09a69e734b7014235de653c17f7ba6632d01c2cc`; artifact ID `10712008968`; outer digest `sha256:185870016e0f3d575c0bcee5895d5be4fc1f5843e35cea9a1b1746c15b30d1b2`; inner ZIP SHA-256 `868ac0da396ae63413e411078e1850632a613d1d7586dcb427c7fdb68daed6fa`.

#160 remains the last hardware-passed baseline. #175 is the next real-machine candidate and must pass Adaptive layer tests plus Legacy/Extended regressions before replacing that status.


## Current layer hardware-review candidate — Integrated #180

#175 opened the new Adaptive Control-layers dialog but exposed a PowerShell deferred-event scope collision: both the parent toggle/encoder settings window and the nested button-layer editor used `$state`. The parent 50 ms live timer then resolved `$state` to the nested object and failed because that object has `LastButtons` rather than `LastToggles`.

#180 isolates the nested editor as `$layerButtonState`. It also cleans the parent typed-settings layout by placing the profile explanation on a full-width row and moving **Control layers…** into a dedicated row with explanatory text, then shifting the main editor groups and action buttons down.

Legacy/Extended compatibility remains explicitly gated: they do not resolve Adaptive layers and retain the pre-layer flat/profiled action path.

Run #180 (ID `35773465992`) succeeded at code head `8041ee5319027db959b2e99e4c356578d558845a`; artifact ID `10714269507`; outer digest `sha256:aec2a91ff587389d01332dc60910fae965ce9f4e8c47f8627431d3f0e8fc7ad1`; inner ZIP SHA-256 `dc8eebd5e5418a8e165c82fe9f99bcffcb7e817d11c9537126ab8e052dd941e7`.

Hardware acceptance should first confirm the Control-layers dialog opens without JIT errors and the parent layout is clean, then exercise Base/T1/T2/T1+T2 button mappings and layered encoder CW/CCW/push. #160 remains the last fully hardware-passed baseline until that succeeds.


## Current layer hardware-review candidate — Integrated #183

#183 extends the Adaptive T1/T2 layer system with persistent user-visible names for all four states: Base, T1, T2 and T1+T2. Defaults remain localized when unchanged; user-defined names are stored as optional fields in the existing version-1 `adaptive-layers.json`, preserving compatibility with files created by #170-#180.

The configured names are propagated through the button-layer editor, layered encoder editor, live active-layer status and layer-transition diagnostics. Legacy/Extended still do not enter Adaptive layer resolution.

Run #183 (ID `35776040340`) succeeded at code head `6459579e4bc9236debd0ba76f48b996d2d3630d8`; artifact ID `10716281843`; outer digest `sha256:2c65daa50e159679442c5e04ccde7c97390d0fe184cf957737edff5489e24372`; inner ZIP SHA-256 `755c88d3763695cbea3b9869269093d590ca70b64dd459ec7c091fbcd3e9d6f9`.

Hardware acceptance should verify name persistence and propagation together with the still-pending #180 layer behavior tests. #160 remains the last fully hardware-passed baseline until those checks pass.


## Current layer hardware-review candidate — Integrated #185

#185 adds an Adaptive-only layer-change OSD with multi-monitor placement. The popup is non-activating, can be topmost, is positioned against the selected monitor's working area, supports nine anchors and configurable duration, and displays the user's custom layer name. A Test notification action is available in the layer notification settings.

Run #185 (ID `35855451141`) succeeded at code head `45c6bf29b18bc317fa3a4393889164fd1fe08199`; artifact ID `10747820174`; outer digest `sha256:399c6be1de6ec50dcab428c653642f91ff0e044e0c98e5fb11d6b88c4a3df93d`; inner ZIP SHA-256 `977cd9f3e936d9881f29c640c4a1bb842ce60dc56ef7b75ca8dd7c1a936ba60a`.

Hardware acceptance should validate monitor selection, each relevant anchor, timing, custom-name display and no-focus-steal behavior. Legacy/Extended remain outside the layer and layer-notification path.


## Current layer hardware-review candidate — Integrated #188

#185 proved that the physical T1 modifier path itself works on the real Nano controller: Toggle 1 was detected, its ordinary ON/OFF action was suppressed in modifier mode, and the active layer switched between the custom names Основной and Тест. The remaining findings were UI clarity/placement defects.

#188 separates the active layer into its own main-status row, disables and explains normal ON/OFF mappings in the typed-control editor whenever the selected toggle is a modifier, and moves Notifications into the actual Control layers dialog instead of the accidentally recursive/clipped notification dialog.

Run #188 (ID `35858096113`) succeeded at code head `c479c70fc6074ebfb23e4c2ab2f0797c224ce1f7`; artifact ID `10747704178`; outer digest `sha256:5cc358b5c8655f78735c3ac5c9ab889729f05a94180a776b66822134db7485e5`; inner ZIP SHA-256 `c16c815acffd86f858287a2d5cf9693c22335ea4d83fe40ec96c6bf513c4f393`.

Hardware acceptance should now verify the repaired UI plus the notification OSD. #160 remains the last broad hardware-passed baseline until the complete layer feature set passes.


## Current layer hardware-review candidate — Integrated #190

#188 introduced a startup regression under PowerShell StrictMode because the new `$script:LayerStateLabel` was read before it had ever been declared. #190 initializes that label plus the layer-popup form/timer state to `$null` at startup and adds CI guards for the declarations.

Run #190 (ID `35859809283`) succeeded at code head `495a1c2965f46a57cb4247c18187dc2d854f091b`; artifact ID `10749991039`; outer digest `sha256:ce28b06ca8b26536ecb35f4e18fd11ad892ea9333f5dec6107bc210b330995b8`; inner ZIP SHA-256 `10f2beb33467d76ec816ab8c6c9aa5e6217de256e0798d2f897b617a2d831419`.

Hardware acceptance: startup must succeed, then re-run the #188 layer UI and notification checks. #160 remains the last broad hardware-passed baseline until the layer feature set completes real-machine acceptance.


## Current layer hardware-review candidate — Integrated #194

#190 real-machine testing confirmed working T1/T2 layer transitions with custom names, visible multi-monitor notification settings/Test popup, modifier-toggle suppression UI, and physical-button auto-selection in the Control layers editor. Remaining findings were cosmetic: popup corner artifacts, clipped owner-drawn combo borders, no held-button visual feedback, and awkward typed-control guidance.

#194 clips the popup Form to rounded geometry, moves the MugenComboBox stroke inside the native client bounds, adds live held/selected button-tile states in the layer editor, and tightens toggle/encoder wording.

Run #194 (ID `35862946664`) succeeded at code head `0e284a1dc4f43c87802bec8b3de7ede571388d77`; artifact ID `10750703940`; outer digest `sha256:88239ee2abba4fa1ab62e2bd8df541c7027ce2bd059b4a8ef64cfbcbec7e3f85`; inner ZIP SHA-256 `406514d6ad5b02055f6877e96a5d7c0a033dfc3b424b04e11fd1d18f27a5a594`.

#160 remains the last broad hardware-passed baseline; #194 is the current layer-feature review build.


## Current layer hardware-review candidate — Integrated #196

Real-machine review of #194 exposed three remaining UI defects: the live selected/pressed button tile in Control layers flickered, MugenComboBox borders were still visually asymmetric, and a valid maximum-length custom layer name could be truncated by the fixed-width layer popup.

#196 addresses those without changing protocol/mapping behavior:
- cache each layer button tile's visual state so the 40 ms live timer does not repaint unchanged controls;
- replace ComboBox `DrawRectangle` border painting with four exact 1 px client-edge strips;
- preserve the 24-character custom layer-name limit but size the layer popup from measured text, bounded by the selected monitor's working area.

Run #195 (ID `35865272887`) failed only on an over-specific CI regex for the new repaint-cache marker after staging succeeded. Commit `fffb929ed4a1064438b21bba5475a79558d18817` corrected the assertion. Run #196 (ID `35866181491`) then succeeded at that head; artifact ID `10752389211`; outer digest `sha256:4de8f0fa73e62f8a5a496311a714aa4b47e1815e268bcf16988ae87cb1ded669`; inner ZIP SHA-256 `f384a3fc9f4f1aa75b78178a5f249aebbedfee25abaaf6fca426dc0aacc2a335`.

All integration stages passed, including Windows PowerShell 5.1 parsing/runtime assertions, launcher/helper build, package and artifact upload.

#160 remains the last broad hardware-passed baseline. #196 is the current layer-feature review build.

Development workflow rule: do not hand a new test package to the user until its integration workflow is green and the artifact has been fetched/verified. Keep real-machine findings plus intermediate failed runs and green replacements documented here and in `docs/CURRENT_HANDOFF.md`.


## Current layer hardware-review candidate — Integrated #200

#196 real-machine testing confirmed the rounded popup fix but found four follow-ups: Toggle/Encoder help text clipped, owner-drawn ComboBox borders remained asymmetric, layer override hold behavior was unclear, and mapped side effects could still execute while a physical control was being used inside a settings dialog.

The supplied #196 test log shows the Nano itself preserving physical holds correctly, so the reported apparent release is not a raw serial/button-state failure. Mugen Deej's normal actions are press-edge/one-shot mappings; Virtual Xbox mappings are stateful and should follow the physical hold.

#200:
- shortens the typed-control guidance to fit;
- explicitly explains one-shot regular actions vs held Virtual Xbox layer mappings;
- adds a modal Mugen-dialog action-safety gate for buttons plus Adaptive toggles/encoders while keeping raw input/editor selection live;
- neutralizes XInput during modal settings and suppresses controls that remain physically held until they are released after the dialog closes;
- repaints the MugenComboBox through the full native window DC rather than client-only `CreateGraphics()`, targeting the remaining uneven native-rim artifacts.

CI progression:
- #197 (`35868866613`) failed only because a Cyrillic CI string became invalid mojibake under Windows PowerShell 5.1;
- #198 (`35869316188`) failed a misplaced module/static assertion;
- #199 (`35869532155`) failed because the integration-module marker was checked before `$integrationText` was loaded;
- #200 (`35869727173`) succeeded at head `297de89bfaf38c41d0f2df895f2edae2c8bcba20`.

Artifact ID `10754665659`; outer digest `sha256:9a4bf995fa7eb243f318e43d3ebd175ebae20dc1035db2b6208474d7ebe7d0ba`; inner ZIP SHA-256 `3d0688e7830de4c94c5d350095d8f7aa494a0e3e69672fc08bd2c42f0f9de7e1`.

All integration stages passed. #160 remains the last broad hardware-passed baseline; #200 is the current focused layer/UI candidate.


## Current layer hardware-review candidate — Integrated #202

A clarification after #200 established that the short flash was not the mapping's one-shot action semantics. The same physical button stayed visibly held in the normal button editor but only flashed in Control layers. Therefore the defect was isolated to the layer editor's live button visualization.

#202 removes the #196 derived visual-state cache and instead recalculates desired tile colors from the raw held state on every 40 ms tick. To avoid restoring the old flicker, each color property is assigned only when its actual value differs. Selection remains an independent accent border; held state remains an accent fill for the full physical hold.

Run #201 (`35872122953`) failed only because old CI still asserted the removed cache. Run #202 (`35872128306`) succeeded at head `c4969766a82e352d9d65dc5b1d46c87d06e73e97`; artifact ID `10755203600`; outer digest `sha256:a08846faa88115b3a67a3948a5e19c234269601f987960fe575206b67209d54b`; inner ZIP SHA-256 `4fb97c45235f38f46386ad6cd49d11d853d0f303e224985630268c5353ebc138`.

#160 remains the last broad hardware-passed baseline; #202 is the current focused layer/UI candidate.


## Current layer hardware-review candidate — Integrated #203

#202 still flickered in Control layers: both the selected button border and the full pressed fill visibly alternated on the real machine. Therefore timer-side BackColor/ForeColor/BorderColor synchronization was not sufficient.

#203 moves selected/pressed presentation into `MugenButtonTile` itself. The layer editor now supplies semantic selected/pressed state to `ApplySemanticStateTheme`, and the tile's own `OnPaint` renders the correct fill/text/border. The method invalidates only when semantic state or palette changes, so the 40 ms polling timer no longer mutates/repaints the control continuously. External WinForms repaints should now preserve the semantic state rather than fighting it.

Run #203 (`35873511506`) succeeded at head `d027a7ef974e387677dccc2d315512e61353d7ef`; artifact ID `10756505480`; outer digest `sha256:ff88663a62c1989a647b2ca398c3cf53cc427536f86439ef76794607214d1e63`; inner ZIP SHA-256 `a892a715c26187402ffb47381c39753ee89bfc84780acbc5d4cbcc72c43ae93e`.

#160 remains the last broad hardware-passed baseline; #203 is the current focused layer/UI candidate.


## Current layer hardware-review candidate — Integrated #204

#203 real-machine testing passed the selected/held Control-layers visual behavior. The same session also validated actual Button 1 routing through Base, T1, T2 and T1+T2 mappings.

The remaining issue was parent UI freshness: after saving T1/T2 modifier roles in Control layers, the already-open Toggle/Encoder settings dialog could temporarily keep stale enabled ON/OFF ComboBoxes until another interaction caused `$refreshEditor` to run.

#204 refreshes the parent editor and assignment list immediately after the Control layers child dialog closes. Modifier-role UI should therefore be correct the instant control returns to the parent.

Run #204 (`35876423203`) succeeded at head `b586958580b862d49f45510ba6bceeaff7eefb68`; artifact ID `10756289241`; outer digest `sha256:d14c328aaef1f43c67580a3fda6a8c24892ab85cadeb56d19f7800b87b1841c9`; inner ZIP SHA-256 `d5c3951089f0dd3dae10fd1a80a0710a439a4267a089c13c9141f0abc33f9ba1`.

#160 remains the last broad hardware-passed baseline; #204 is the current focused layer/UI candidate.


## Layer OSD opacity follow-up — Integrated #207/#208

Layer-change OSD now has persisted opacity control. Missing/old configs default to 50%; range is 20..100%, and Test notification previews the unsaved setting. Popup uses native WinForms `Form.Opacity`.

#207 is the explicitly completed green integration run for the 50% default: run `35877598863`, head `482e4c8d8cfbd0e6b8873b521b17e5cbd2540d6a`, artifact `10759821067`, inner ZIP SHA-256 `17d072f22fc62c5b6af69e7ec69e9a40d93150d2f045e906ed8b34021df4c226`.

#208 (`35878075515`, head `d9292a028ae4aeee5923096b3fef0968d434dad5`) only changes the Russian label from the ambiguous «Прозрачность» to «Непрозрачность». Its build job completed successfully and artifact `10759491804` was downloaded/verified (inner SHA-256 `7a1447112b49996e4ce678380aeb9da3ccdfaf098654d1a93a50167895f2e104`), although the connector's top-level run object still lagged as `in_progress` when recorded.

#160 remains the last broad hardware-passed baseline; the layer feature continues focused hardware/UI review.


## Current layer OSD geometry candidate — Integrated #209

50% opacity revealed that the previous Form + child card + WinForms Region design produced binary/jagged rounded clipping. #209 replaces the OSD with a true per-pixel-alpha layered window rendered through `UpdateLayeredWindow` from a premultiplied-alpha bitmap.

The OSD no longer relies on `Set-RoundedControlRegion` or child controls. Rounded surface, border and text are rendered in one anti-aliased bitmap; 20..100% user opacity is applied with `SourceConstantAlpha`, retaining smooth edge alpha.

Run #209 (`35880032475`) succeeded at head `1b162367504b07b0fb4c3fea4eb62c2a2fa9e661`; artifact ID `10759249744`; outer digest `sha256:acafbd660d3a7fcfde5068de6fda8809c03765a5b5df60fef6f0c64949e12369`; inner ZIP SHA-256 `d1301f857322f29275a69f174db61d3f05852a5d82a48c4d926b3b2cde2d40ce`.

#160 remains the last broad hardware-passed baseline; #209 is the current focused OSD/UI candidate.


## Current layer OSD UX candidate — Integrated #210

#209 passed the real-machine smooth-corner test at 50% opacity. The remaining UX issue was the fixed 340 px minimum width plus left-aligned caption/name, which made short layer names look lost inside a large notification card.

#210 sizes the OSD from the measured caption/name content, lowers the minimum width to 170 px, reduces height to 88 px and centers both caption and layer name. Long custom names still grow the popup up to the existing maximum/monitor bound.

Run #210 (`35881369823`) succeeded at head `99364f9384f84a841f9174976ee4172d7356e127`; artifact ID `10760957127`; outer digest `sha256:539409753bf18a1fc45485fc9bb5aafc17c3262ad4e8f410379caa98fbf202b5`; inner ZIP SHA-256 `bd68f313d3b111ff7e2d0f5b5f4fbcbf3e0441e7f66049cfaef0bb0389ef1922`.

#160 remains the last broad hardware-passed baseline; #210 is the current focused OSD/UI candidate.


## #210 adaptive OSD layout — real-machine PASS

Real-machine screenshots confirmed both ends of the adaptive layout: short names collapse to a compact centered OSD, while long names expand horizontally with centered text and smooth layered-window corners. #210 adaptive sizing/centering is accepted.


## Current layer-editor candidate — Integrated #213

#213 adds a persistent right-side assignment summary to Control layers. It lists only explicit overrides for the currently selected profile/layer, updates live when mappings change, and lets a row navigate directly to its physical button. This addresses the real-machine UX issue where existing layer assignments were otherwise visible only one button at a time.

The Control layers dialog is widened to 1160 px to keep the existing button grid/editor intact while adding the sidebar. Xbox wording is also normalized to “virtual Xbox gamepad / виртуальный геймпад Xbox” across the layer action selector and virtual-gamepad picker.

CI #211 and #212 were intermediate assertion-only failures after successful staging; #213 (`35886574832`) succeeded at code head `b667aaac87552ab8a1cc6044b4f47fb41bd61dba`. Artifact ID `10762888728`; outer digest `sha256:857fbe0326dd5c6716cb935a35b685c7bbbadb5ca9796597cb7e8e255a6e4cad`; inner ZIP SHA-256 `9f1c943c5023d78e9d94baf38323ef4f11e8b8948de242653bb5b313fa94ee93`.

#160 remains the last broad hardware-passed baseline; #213 is the current focused layer/UI candidate.


## Low-latency virtual gamepad candidate — Integrated #214

#214 is the first dedicated gameplay-latency pass for the Adaptive/XInput path. While the virtual Xbox gamepad is active, the desktop serial-drain timer targets 5 ms instead of 20 ms; foreground application/layer button mappings are cached outside the physical button hot path; and gameplay `state` messages to the elevated HID helper are one-way instead of waiting for an acknowledgement after every input transition. Lifecycle/control commands keep their synchronous acknowledgements.

This is intentionally a conservative architecture step rather than a serial-thread rewrite: normal non-XInput Mugen behavior retains the 20 ms loop, profile identity is still refreshed every 200 ms, and the existing modal/profile neutralization safety rules remain intact.

Integrated #214 (run `35888990574`) succeeded at code head `0ff5ed1e9cf88c92d912e439eefd9ad08b0cc875`. Artifact ID `10763283919`; outer artifact ZIP SHA-256 `73bf6eb49d09c175aba2eb155d55ec45971054f539ee563ed2b51509092a35ad`; inner development ZIP SHA-256 `38a584eecf2fcff3693a8def5470256aac7278aceda276c114ed83765f39e563`.

#160 remains the last broad hardware-passed baseline; #213 remains the accepted layer-editor/UI candidate; #214 is the current focused virtual-gamepad latency candidate pending real-machine gameplay testing.


## Current backup candidate — Integrated #215

Backup audit found that schema v2 predated Control layers. #215 introduces schema v3 and now covers all active prototype configuration families, including `adaptive-layers.json` and `virtual-controller.json`.

Schema v3 preserves layer modifier roles, layer names, button/encoder overrides and OSD preferences, plus the virtual Xbox enabled/type setting. v1/v2 remain readable; restoring an old backup preserves newer settings that did not exist in that schema.

Run #215 (`35890261732`) succeeded at code head `b54f8fa40daa91971622968966a5366ada86741d`; artifact ID `10764074848`; inner ZIP SHA-256 `efd321fa0a57a67668f409a22506af124164951bb6c073580d9d69a091fec860`.

#214 low-latency gameplay changes are included in #215; #215 is the current combined latency + backup-fix candidate pending real-machine review.


## Current gameplay candidate — Integrated #216

#214 established the low-latency XInput path and real-machine testing reported a night-and-day reduction in perceived lag. Rapid-repeat testing still exposed occasional empty-feeling presses. #216 removes synchronous physical-edge log writes from active XInput and bypasses the legacy 80 ms one-shot debounce/log path for virtual Xbox mappings after layer/profile resolution.

This keeps button timing semantics unchanged while reducing UI-thread/file-I/O jitter during spam. If real-machine testing still loses repeated actions, the next targeted step is explicit repeat-edge shaping/queueing near the helper rather than another broad polling change.

Run #216 (`35891904212`) succeeded at code head `1d362e9f68b82328b98e095e16a2d03b342a2645`; artifact ID `10765317130`; inner ZIP SHA-256 `4904646210c93ff10d0e201ae11f9a9295d062e3cedb5df77c59d1716174ae44`.


## Current firmware latency candidate — Integrated #218

#218 tests a **6 ms** Cardboard Nano matrix debounce instead of 18 ms to close the remaining feel gap during very fast left/right alternation. The matching Adaptive-v3 desktop parser accepts cumulative firmware diagnostics and logs contact names when bounce counters change.

Two counters distinguish filtered raw chatter from potentially escaped rapid accepted reversals (<35 ms). This lets the real-machine test decide whether 6 ms is safe instead of tuning by feel alone.

Run #218 (`35895588926`) succeeded at code head `4693b969237506ad1810aab4ea665b2454cafab9`; artifact ID `10766931651`; inner ZIP SHA-256 `2b631327b0a37426084749ec7e81a106948f74f98ff2338171aa93c9bb24ffdc`.

The dev ZIP now bundles the exact matching firmware sketch under `firmware\MugenDeejCardboardNanoPrototype`.


## #218 responsiveness — real-machine PASS; bounce safety pending log

After flashing the 6 ms Cardboard Nano firmware, Cult of the Lamb rapid left/right alternation was reported to feel effectively instantaneous and comparable to the real gamepad. The remaining responsiveness gap seen with the older 18 ms firmware is therefore closed subjectively.

Keep #218 diagnostics enabled until a gameplay log is reviewed; `rapid` counter behavior is still needed before declaring 6 ms electrically safe for the tested panel.

## Current combined candidate — Integrated #219

#219 keeps the #218 firmware/latency behavior and fixes the Control layers UX trap where Xbox mappings could be saved while XInput stayed Off. Saving a newly configured virtual gamepad layer action now auto-enables XInput, but unrelated edits respect an explicit manual Off.

Run #219 (`35897242734`) succeeded at code head `9015586d6900a1e1f01951576e05edf0386d5f5b`; artifact ID `10766763919`; inner ZIP SHA-256 `c4cbb599765206e7bcbfcb765292ec971c4cd0092a05d08603b073b9899f7e9a`.


## #218 6 ms matrix debounce — hardware diagnostics PASS

Real-machine gameplay plus the returned #218 log now support keeping the 6 ms matrix debounce on the tested Cardboard Nano panel. Diagnostics started at `filtered=0; rapid=0` and never logged a counter change during the captured session, while rapid left/right gameplay felt gamepad-fast.

A single early post-connect packet-shape mismatch was safely rejected and did not recur; track it separately from debounce tuning.

#219 remains the current combined desktop candidate, with the same accepted 6 ms firmware plus Auto XInput-on-mapping UX.


## #219 schema v3 restore — real-machine PASS

A full delete/restore test was repeated twice. Schema v3 restored Adaptive layers and `virtualController.enabled=True`; after restart the helper started automatically and the restored Game layer was usable without manually re-enabling XInput.

This is distinct from #219's new mapping-save auto-enable behavior: restore starts XInput because the backup itself persisted it as enabled.

Latest firmware diagnostics connected at cumulative `filtered=11; rapid=3` and did not increase during the restore cycles. Keep 6 ms as the current hardware-tested debounce; the non-zero cumulative counters are observations, not currently correlated with any visible gameplay fault.


## #219 encoder responsiveness — real-machine observation

Rapid encoder rotation produced dense, orderly detent updates (often roughly 11–30 ms apart) and repeated push press/release events without visible loss. No new firmware debounce diagnostics were logged during the test.

The improved encoder feel is consistent with the active-XInput 5 ms desktop serial-drain cadence introduced in the low-latency path; encoder firmware itself was not changed by the 6 ms matrix debounce experiment.


## #219 per-app encoder profile switching — hardware PASS

Real-machine test verified foreground-app routing for Encoder 1: Global volume mappings switch to Firefox mouse-wheel mappings when Firefox gains focus, then return to Global after focus leaves. Fast rotation remains responsive in both profiles.


## Current combined candidate — Integrated #220

#220 keeps the accepted #219/#218 behavior and hardens the optimized Physical button actions dialog against controller USB hot-unplug while the modal editor is open.

The live 25 ms physical-button auto-selection timer now uses isolated `$buttonEditorState` instead of generic `$state` and pauses topology inspection while disconnected. This targets the real-machine JIT exception `LastButtons property not found` seen with the 6-button Extended controller.

Run #220 (`35906698320`) succeeded at code head `167fa38b5dc60eb651fe859d9ef679ef2e9634ea`; artifact ID `10771134280`; inner ZIP SHA-256 `6fdf609888e1166206a7f4bd0760d158a71d4c0b876d21ff6bd78a516c42306d`.

Hardware retest pending: unplug/replug Extended while Physical button actions remains open.

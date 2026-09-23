# Mugen Deej — living project state

Last updated: 2026-09-19

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

Integrated **#101** is the current hardware-review build. Foreground application profiles cover ordinary momentary buttons plus Adaptive toggles/encoders, and physical buttons can now act as stateful digital Xbox stick directions (left/right stick, four cardinal directions each). Release returns the virtual axis to center; opposite directions cancel to center; Xbox buttons and stick directions are submitted as one coherent state.

Profile switching is based on the **effective profile**. A dedicated game profile -> unprofiled window transition becomes Game -> Global and neutralizes state. Moving between two unprofiled applications remains Global -> Global and does not reset merely because the foreground process changed. Any physical input held across a real profile boundary is suppressed until release so it cannot become a synthetic action in the new profile. This explicitly covers multi-monitor borderless-fullscreen workflows where focus changes by mouse click as well as Alt+Tab/Win+Tab.

Backward compatibility remains deliberate: Legacy has no buttons and is unchanged; Extended and Adaptive can use the same PC-side button/profile layer without firmware changes; `button-actions.json` remains Global; old #89/#90 profiles without `buttons` inherit Global; backup v1 and older v2 shapes remain accepted. Digital stick mappings are stored as ordinary button-action strings, so #101 does not require a backup schema bump.

See `docs/CURRENT_HANDOFF.md` for #101 run/artifact hashes and the exact real-machine test sequence.

The first large physical cardboard panel is now wired for Uno bring-up as a 4x8 matrix: 28 momentary buttons, 2 matrix toggles, and a separate S1/S2/KEY encoder module. A dedicated Adaptive v3 sketch exposes 5 temporary software sliders + 28 buttons + 2 toggles + 1 encoder/push at 115200. Hardware validation is pending before the same wiring is migrated to Nano and real potentiometers.

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

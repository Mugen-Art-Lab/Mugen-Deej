# Mugen Deej — current development handoff

Last updated: 2026-09-18

This is the short resume point for the active `feature/virtual-gamepad-ui` branch. Stable `main` / v1.0.0 remains untouched.

## Protocol generations

- **Legacy** — numeric-only analog packets.
- **Extended** — typed `s` + `b` packets without an explicit version marker.
- **Adaptive v3** — packet begins with `v3` and may contain any supported combination of `s`, `b`, `t`, and `e` fields.

Adaptive is self-describing. The current 5 sliders / 29 buttons / 2 toggles / 1 encoder Uno fixture is one regression topology, not a hardcoded product shape. A valid Adaptive controller may have zero sliders, zero buttons, zero toggles, or zero encoders as long as at least one typed input field follows `v3`.

Encoder transport uses cumulative signed position so missed packets do not permanently lose detents.

## Real hardware status before #31

Current Uno regression fixture on COM14 at 115200:

`adaptive; sliders=5; buttons=29; toggles=2; encoders=1`

**PASS** on the real machine for:

- Adaptive autodetection/transport;
- five analog values;
- 29-button compact live grid;
- toggle 1 and toggle 2 state changes;
- encoder movement in both directions;
- encoder push press/release;
- compact combined input card;
- separate diagnostics dialog;
- flicker-free toggle/encoder owner drawing.

Integrated #30 was the hardware-proven baseline for this shape.

## Integrated #31 — Adaptive topology hardening

Workflow run:

- run number: **#31**
- run ID: `35266429253`
- built code head: `23dce0c6e8c77c440dfa66aa891a18d53d825c2c`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-31`
- artifact ID: `10517152015`
- outer Actions digest: `sha256:4bb28114b993b262f68cc3d1ceda29fc368b246be397de359684898b4056b603`
- inner program ZIP SHA-256: `199d8a0becdde9a6b1a2f2f24cf3ff8f7b817f90ff670212f92b5aa861c962b1`
- Windows PowerShell 5.1 parse check: PASS
- launcher/package: PASS

The branch may be ahead of the built SHA because documentation commits after #31 do not trigger the workflow.

### What #31 changes

New final-stage patcher:

`tools/Harden-AdaptiveTopologyUi.ps1`

It is applied after the existing compact #30 UI revision during staging.

Implemented behavior:

1. **Zero-slider Adaptive is valid.** `v3` packets no longer require an `s` field. Shape checking remains strict after capabilities are discovered.
2. **No fabricated sliders.** Connected status uses the actual detected Adaptive counts instead of falling back to the old configured expected-slider count.
3. **Capability-driven slider UI.** If Adaptive reports zero sliders, regulator status and `Configure controls` disappear and the main layout collapses. If it reports fewer sliders, only those rows are shown.
4. **Dynamic slider settings count.** The regulator editor uses the detected slider count while connected and can scroll for larger counts.
5. **Dormant slider mappings are preserved.** Editing while a smaller controller is attached does not truncate saved configuration for absent higher-index controls.
6. **Bounded main summary.** Arbitrarily large community topologies cannot grow the main window without limit. The compact summary is capped and an overflow `Показать все… / Show all…` affordance opens a full controller-state window.
7. **Expanded diagnostics.** The separate diagnostics dialog now includes COM port, protocol generation, active baud, auto/manual mode, counts for sliders/buttons/toggles/encoders, latest-packet age, and approximate packet rate.
8. **Packet-rate tracking.** Accepted controller packets are sampled so the diagnostics view can show an approximate update frequency.

### Main-summary limits in #31

The current compact budget is intentionally conservative:

- buttons: at most two compact rows (34 controls at the current width);
- toggles: up to 6 in the main summary;
- encoders: up to 2 in the main summary;
- original regulator card: up to the existing 5 visual rows; additional sliders are accessible through the full-state overflow view and dynamic settings editor.

These are presentation limits only, not protocol limits.

## Multi-topology Uno fixture

`arduino/MugenDeejUnoAdaptiveTest/MugenDeejUnoAdaptiveTest.ino` now samples D8/D9 once at boot/reset:

- D8 open / D9 open -> `5 / 29 / 2 / 1` current regression fixture;
- D8 GND / D9 open -> `0 / 8 / 4 / 2` zero-slider mixed topology;
- D8 open / D9 GND -> `2 / 0 / 0 / 0` two sliders only;
- D8 GND / D9 GND -> `0 / 0 / 12 / 6` large typed topology.

D2..D7 keep their original live-test meaning where the selected profile contains that family. Profile pins must be set before reset/power-up.

## Integrated #31 real-machine multi-topology result

Alternate Adaptive topology handling is now **hardware PASS** for the primary layout/capability cases on the real Uno fixture.

Observed screenshots from the real machine confirm all four boot profiles:

1. `5/29/2/1` — no regression from #30: five regulators, 29 buttons, two toggles and one encoder render correctly.
2. `0/8/4/2` — the regulator card and regulator-settings button disappear completely; eight buttons, four toggles and two encoders remain in the compact input card.
3. `2/0/0/0` — exactly two regulator rows remain; the discrete-input card and button settings disappear.
4. `0/0/12/6` — the main window stays compact, shows a bounded toggle/encoder summary, and exposes `Показать все… (+10)` rather than growing indefinitely.

This materially validates the capability-driven Adaptive UI: connected hardware topology, not a fixed 5/29/2/1 assumption, controls what appears in the main window.

One minor UX observation remains from the profile-switch sequence: while the controller is physically resetting/reconnecting, the transient disconnected state can still show the old/default five empty regulator rows and the regulator-settings affordance. Once the new Adaptive profile reconnects, the correct capability-driven layout replaces it. Treat this as a polish item, not a topology-detection failure.

Still useful to recheck separately after further UI changes: RU/EN switching, diagnostics live values, full-state overflow-window contents, and repeated disconnect/reconnect cycles.

Legacy regression spot-check after #31 also passed on real hardware: COM5 auto-detected as `Legacy` at 9600 baud with 5 sliders and 0 buttons/toggles/encoders. The main window stayed in the expected Legacy shape (slider card + regulator settings only), and diagnostics reported the same topology plus live packet freshness/rate. This is useful confirmation that Adaptive hardening did not regress Legacy autodetection or UI composition.

Extended regression spot-check after #31 also passed on real hardware: COM10 auto-detected as `Extended` at 9600 baud with 5 sliders and 6 momentary buttons, 0 toggles and 0 encoders. The main window showed the five regulator rows, six-button status card, both regulator/button settings buttons, and no Adaptive-only typed controls. Diagnostics reported the same topology and a live packet rate of roughly 33 Hz. This closes the basic post-#31 regression sweep across Legacy, Extended, and multiple Adaptive shapes.

Real-machine UI review after opening both #31 auxiliary windows:

- diagnostics is visually successful and reports the expected live values for the `0/0/12/6` profile: COM14, Adaptive v3, 115200, automatic mode, 0 sliders, 0 buttons, 12 toggles, 6 encoders, packet age around tens of milliseconds, and packet rate around 40 Hz;
- the overflow/full-state window is functionally correct and scrollable, but its current monospace text-dump presentation is a first-pass utility view rather than the intended final polished UI;
- next polish should reuse the normal button/toggle/encoder visual language in a scrollable full-state form, hide empty control-family sections instead of showing `—`, and keep live updates without inflating the main window.

## Integrated #35 — full-state polish + first-class typed mappings

Workflow run:

- run number: **#35**
- run ID: `35299035854`
- built code head: `e02fe882b561ce636f6c27b0f880a5794dc25c2f`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-35`
- artifact ID: `10528883469`
- outer Actions digest: `sha256:e9633103176a1bd8e53308b2a0ef19b9923e160830e24e97589d789a1d636cdf`
- inner program ZIP SHA-256: `b4efd85faf3f99cbab55bd82ad1f46eafd87c19888631c15885b66adebba0b10`
- Windows PowerShell 5.1 parse check: PASS
- launcher/package: PASS

New final-stage patcher:

`tools/Add-AdaptiveControlMappings.ps1`

It runs after #31 topology hardening and before the final UTF-8 BOM normalization.

### Full controller-state UI

The old Consolas/TextBox developer dump has been replaced by a live visual Mugen-styled window:

- only control families that actually exist are created;
- sliders use names, normal Mugen progress bars, and percentages;
- momentary buttons use numbered live button tiles;
- toggles reuse the switch metaphor;
- encoders reuse the rotary-knob metaphor and highlight on push;
- sections wrap/scroll in a dedicated window instead of inflating the main window;
- toggle/encoder owner drawing is invalidated only when live state actually changes.

### First-class toggle / encoder actions

A new main-window `Настроить переключатели / Configure switches / encoders` button appears only when toggles or encoders exist.

New `adaptive-actions.json` keeps typed mappings independently of momentary `button-actions.json` and preserves dormant higher-index mappings when a smaller topology is connected.

Mapping model:

- toggle: separate **ON** and **OFF** actions;
- encoder: **CW**, **CCW**, and **push** actions;
- encoder actions execute once per recovered detent from the cumulative position, with a 32-action-per-packet safety cap;
- encoder push fires on the press transition only.

The first typed-action milestone reuses standard Mugen actions: slider mute/unmute, media actions, Windows volume actions, custom hotkeys, launch program/file, open folder, run command, and open URL. Virtual Xbox mapping remains momentary-button-only for now.

The typed settings dialog is transactional: edits apply only after Save, and moving/pressing a physical typed control can select it in the editor for easier identification.

### Universal backup schema v2

Portable backup creation now writes `schemaVersion = 2` and includes:

- existing main config;
- existing momentary button actions;
- typed toggle/encoder actions;
- informational source protocol/topology metadata.

Restore still accepts schema v1. A v1 restore preserves the current typed mappings because v1 never contained that family. A v2 restore includes typed mappings. Topology mismatch remains informational rather than a hard restore lock, and the emergency pre-restore backup/rollback path now also contains typed mappings.

### #35 real-machine review

Integrated #35 has now been launched on the real machine.

Observed PASS / accepted visually:

- the new typed settings dialog opens correctly for the 5/29/2/1 fixture and exposes T1, T2 and E1;
- toggle editor presents separate ON/OFF action rows;
- encoder editor presents CW/CCW/push rows;
- Save writes typed mappings successfully (`Adaptive actions saved: toggles=2; encoders=1` in the runtime log);
- the polished full controller-state window is visually preferred over the old monospace dump;
- the 0/0/12/6 profile reconnects and the full-state window shows all 12 toggles and 6 encoders;
- RU -> EN -> RU switching completed without an exception in the observed session.

Still **not hardware PASS** for actual mapped-action execution: the supplied log shows mappings being saved but does not show a configured toggle/encoder action firing. Backup schema v2 restore also still needs an explicit real-machine exercise.

User UI feedback from this review:

- the new main `Настроить переключатели` button looked typographically lighter than the existing settings buttons;
- the regulator-settings button being the only blue/primary Configure action looked inconsistent once three peer settings buttons existed;
- the compact 0/0/12/6 summary visibly has room for at least one more encoder before overflow.


Recommended first look:

1. Use Adaptive `5/29/2/1` and inspect the three-button settings row plus the new typed settings editor.
2. Assign harmless actions to Toggle 1 ON/OFF and Encoder 1 CW/CCW/push, Save, then exercise D3/D5/D6/D7.
3. Use `0/0/12/6`, open `Показать все…`, and inspect scrolling/live switch/knob visuals.
4. Create a backup with typed mappings, inspect restore confirmation with another topology attached, and verify dormant mappings survive.
5. Recheck Legacy/Extended briefly because the settings-row layout changed.

## Integrated #39 — settings-row polish

Workflow run:

- run number: **#39**
- run ID: `35335088427`
- built code head: `c82956f922e8a8b4ba500c11712dd73fd798729e`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-39`
- artifact ID: `10542641813`
- outer Actions digest: `sha256:2c321d17c6c6c8854b78db400bd5f92a6f6e2456934449715ccfe1df42b59ef6`
- inner program ZIP SHA-256: `a338f9817274888b03c20e3a23a345df91a6443f11b0a42a08e103f966381bdf`
- Windows PowerShell 5.1 parse check: PASS
- launcher/package: PASS

Changes based directly on the #35 screenshots:

1. `Настроить переключатели / Configure switches / encoders` now explicitly uses Segoe UI Semibold 10, matching the other main Configure buttons.
2. `Настроить регуляторы / Configure controls` is no longer the sole blue primary action; the three Configure buttons are visual peers.
3. The bounded main Adaptive summary now shows up to **3 encoders** instead of 2. For the synthetic 12-toggle/6-encoder profile this reduces overflow by one while retaining the bounded-height design.

The first #38 attempt failed during staging because the patch script accidentally interpolated `$settingsButton` under StrictMode. This was fixed by literal quoting; #39 is the green replacement build.

## Integrated #44 — capability-driven first run + encoder push cues

Workflow run:

- run number: **#44**
- run ID: `35336270794`
- built code head: `14c533f604f7e8111ddc2b7fde120b65d23efa8e`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-44`
- artifact ID: `10543417835`
- outer Actions digest: `sha256:c8807cf7cd3e8fabdab61c978541db535c36317e00b937e7aa15df7badae8433`
- inner program ZIP SHA-256: `3012021287a4ca9ed24b88b476ea680180bbfa6cf91aaea53a7449ec695c4b35`
- Windows PowerShell 5.1 parse check: PASS
- launcher/package: PASS

### First-run onboarding fix

A real first-run test with the `0/0/12/6` Adaptive profile exposed a stale Legacy-era assumption: the wizard always showed five analog-control bars and offered `Настроить регуляторы`, which could open an empty slider editor even though the detected controller had zero sliders.

The first-run wizard is now capability-driven:

- when connected, it shows detected protocol/COM and live counts for sliders/buttons/toggles/encoders;
- it offers only configuration shortcuts for control families that actually exist;
- a zero-slider controller cannot be routed from the wizard into an empty slider-settings dialog;
- the direct slider-settings entry point also has a zero-slider guard;
- if no controller has been detected yet, the guide asks for USB and updates after discovery instead of assuming knobs/faders.

The supplied real-machine log confirmed the bug condition before the fix: first-run state remained incomplete while COM14 was detected as Adaptive with 0 sliders, 0 buttons, 12 toggles and 6 encoders.

### Encoder push-capability cues

The synthetic `0/0/12/6` profile also made a useful distinction visible: E1 advertises push while E2-E6 are rotation-only.

#44 makes this persistent rather than discoverable only by trying to press the encoder:

- push-capable encoder knobs have a small permanent center dot;
- rotation-only knobs remain plain;
- an actual push still highlights the whole knob;
- the full-state window uses the same visual language;
- typed-settings selector tiles append `•` to push-capable encoders (for example `E1•`);
- the selected encoder heading explicitly says `с нажатием / push-capable` or `только вращение / rotation only`;
- the settings hint explains what the dot means.

This is **CI PASS but not yet real-machine visual PASS**; inspect both the first-run wizard and E1-vs-E2 encoder cues on hardware before freezing the visuals.

## Integrated #48 — first-run wording + encoder cue geometry

Workflow run:

- run number: **#48**
- run ID: `35337955633`
- built code head: `3ca5540d70637c8d33bb7543a1ae50a3b6870d4c`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-48`
- artifact ID: `10543039373`
- outer Actions digest: `sha256:be1620c3b03a23642c9d70b63e65ba97442179f31747566a6b33e15d00e6cc8b`
- inner program ZIP SHA-256: `45b32792c38d9857d61ee91aefa6ffcdbccda49966e417a6971cb858a094141d`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

Real-machine review of #44 covered fresh-start onboarding on all three protocol generations:

- Adaptive `0/0/12/6`: first-run guide offered only switch/encoder settings;
- Adaptive `5/29/2/1`: first-run guide offered regulator, button and switch/encoder settings;
- Legacy `5/0/0/0`: first-run guide offered regulator settings only;
- Extended `5/6/0/0`: first-run guide offered regulator and button settings only.

The supplied log independently confirms clean fresh-config detection for those runs: Adaptive 0/0/12/6 at COM14/115200, Adaptive 5/29/2/1 at COM14/115200, Legacy 5/0/0/0 at COM5/9600, and Extended 5/6/0/0 at COM10/9600. No application exception was observed during the sweep.

User feedback from #44:

1. The push-capability cue on encoder knobs was useful, but the tiny filled center dot looked visually off-center/awkward.
2. The first-run identity line (`Adaptive v3 · COM14`, etc.) was too implementation-oriented for a new user because `Legacy / Extended / Adaptive` were not labeled as protocol names.
3. The explanatory prose in the first-run dialog still sounded like tester/developer copy rather than welcoming user-facing onboarding.

#48 changes:

- encoder knob geometry now uses an exact integer center shared by outer circle and pointer;
- push-capable encoders use a centered **inner ring** instead of a floating filled dot; an active push can still fill the cue while the whole knob highlights;
- the same cue geometry is used in compact main status and full-state view;
- first-run connection identity is explicit, e.g. `Порт: COM5    Протокол: Legacy    Скорость: 9600 бод` / `Port: COM5    Protocol: Legacy    Baud: 9600`;
- first-run wording was rewritten to sound like onboarding rather than a diagnostic/test instruction: `Ваш контроллер`, `Контроллер найден и готов к работе`, and simpler next-step copy.

The first #47 run failed only because CI was still looking for the superseded English onboarding sentence; the staged runtime itself passed parsing. The CI marker was updated and #48 is the green replacement build.

## Integrated #54 — first-run alignment + compact settings labels

Workflow run:

- run number: **#54**
- run ID: `35339733663`
- built code head: `ddd6b3384e9064167da3f3ac0d46026710f64fd9`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-54`
- artifact ID: `10543824892`
- outer Actions digest: `sha256:41d841d85826cec3f038b3c3118bc46fe31fe6ee6e77401edb3e7d8f3cbcefb0`
- inner program ZIP SHA-256: `3085b83224db8b606cadbad6d18e502d37339e5ab5db44724264e80ade502b45`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

User review of #48 found three remaining polish issues:

1. In the first-run controller card, the section title and the connection details did not share a clean left edge.
2. `Порт / Протокол / Скорость` being entirely green made the row look like a diagnostic dump; the requested hierarchy is neutral field names with only their values highlighted.
3. The first-run text used wrapped labels with visibly inconsistent line spacing, and `Настроить переключатели / Configure switches / encoders` was both semantically incomplete (it also configures encoders) and clipped in English.

#54 changes:

- first-run intro/help copy is split into explicit single-line rows with fixed 22 px vertical rhythm instead of relying on automatic wrapping;
- the controller summary uses a `MugenCardPanel` plus its own title label so `Ваш контроллер / Your controller` and every detail line share the same left edge;
- Port / Protocol / Speed field names use the normal theme text color;
- COM / protocol / baud values alone use the green connected-state accent;
- disconnected first-run state keeps its own waiting text and automatically refreshes after controller discovery;
- the three peer settings buttons now use short category labels everywhere:
  - RU: `Регуляторы`, `Кнопки`, `Тумблеры и энкодеры`;
  - EN: `Analog controls`, `Buttons`, `Toggles & encoders`.
  This avoids clipping and makes all three buttons parallel rather than mixing long `Configure...` phrases.

Runs #50-#53 were development-only failures caused by staging/CI marker mistakes introduced while implementing this polish (duplicate here-string terminator and unsafe/overstrict CI regexes). The staged runtime itself reached a valid PowerShell parse by #51; the checks were then corrected. #54 is the clean green replacement build.

## Integrated #55 — first-run copy fit + typed settings title

Workflow run:

- run number: **#55**
- run ID: `35342499359`
- built code head: `dbf9506bc93abe0bae62da8ce4af768c0838e5aa`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-55`
- artifact ID: `10545980085`
- outer Actions digest: `sha256:75be74c2d40222e0837c8ae6773b79e94e58cf5eab7ed1d9c40ad10479ed436b`
- inner program ZIP SHA-256: `5d977dd4913093e01b28892d4484dc4c40c84083cc24bc3e852150dab58109d5`
- Windows PowerShell 5.1 parse/runtime check: PASS
- launcher/package: PASS

User review of #54 found two final copy/title inconsistencies:

- the second Russian onboarding line still clipped at the right edge;
- the toggle/encoder settings window title and main heading described actions, but did not explicitly say this was a settings screen like the regulator and button editors do.

#55 changes:

- first-run second line is shorter and language-neutral in structure:
  - RU: `Проверьте органы управления — их состояние сразу видно в главном окне.`
  - EN: `Try the controls — their state appears immediately in the main window.`
- typed settings window title is now `Настройка тумблеров и энкодеров — Mugen Deej` / `Toggle and encoder settings — Mugen Deej`;
- the large in-window heading is now `Настройка тумблеров и энкодеров` / `Toggle and encoder settings`.

## Integrated #57 — Adaptive mouse-wheel actions

Workflow run:

- run number: **#57**
- run ID: `35346766213`
- built code head: `1825dfd24929d992c52d7348ac211511740c212a`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-57`
- artifact ID: `10546848410`
- outer Actions digest: `sha256:31521c57568a86f92255dc704743ece124024434b9690f109fa95833a02ace30`
- inner program ZIP SHA-256: `687466f2b341175b1bfa1cc43c4264967c07d6fae1a1b545efdc1c675f0863c5`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

This build starts the editor/creative-app experiment discussed after #55. Adaptive toggle/encoder actions can now emit mouse-wheel input through Win32 `SendInput`.

Added actions:

- vertical wheel up/down;
- native horizontal wheel left/right;
- Ctrl + wheel up/down;
- Shift + wheel up/down;
- Alt + wheel up/down.

The implementation adds a dedicated `MugenMouseWheel` helper to the staged C# runtime. One encoder detent maps to one standard 120-unit Windows wheel notch, so the existing cumulative-position recovery still preserves missed detents up to the existing 32-action packet safety cap.

The actions are available in the existing Adaptive action dropdowns for toggle ON/OFF and encoder CW/CCW/push. They are persisted in `adaptive-actions.json` and accepted by the existing safe-action validator / universal backup flow.

**CI PASS only for the new mouse-wheel transport.** Real-machine testing still needed, ideally with E1 CW/CCW mapped to wheel actions and verified in one or more apps (browser, Photoshop, Premiere, etc.). Do not call Photoshop/Premiere behavior PASS until actually exercised because applications differ in which modifier + wheel combinations they consume.

## Integrated #59 — first-run resume/disconnect hardening

Workflow run:

- run number: **#59**
- run ID: `35360200014`
- built code head: `2790354d86959142b79eb215bc30685a50e7dee0`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-59`
- artifact ID: `10554397964`
- outer Actions digest: `sha256:8ce1d60216103bb38d808d6f1e0e6944ff0c68c545645f5da71b5f3bba5a77b6`
- inner program ZIP SHA-256: `bd8f9a420a876ee29a653a4415434c4f9717e6e70044a7387a017f8b6ff282ae`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

A real-machine hibernation/resume test with the first-run wizard still open exposed an unhandled WinForms timer exception. The JIT dialog reported PowerShell trying to set a missing `Visible` property from `System.Windows.Forms.Timer.OnTick`. The application log shows the machine suspended with COM14 open, resumed over two hours later with the preserved SerialPort reporting closed, then failed the 15-second preserve window and cleaned up the controller connection.

The stale first-run wizard was switching connected/disconnected detail labels one-by-one from its 150 ms timer. During the resume-driven connection-state transition that path could surface the `Visible` RuntimeException and leave the card half-updated (disconnected intro text with stale COM/protocol/capability details still visible).

#59 changes:

- connected controller details are hosted in one dedicated panel;
- disconnected/waiting details are hosted in a separate panel;
- the timer now switches the two panels atomically instead of toggling `Visible` on an array of individual labels;
- the first-run timer refresh is wrapped so a helper-refresh failure is logged and that helper timer stops instead of surfacing a .NET JIT exception;
- CI verifies the atomic panel path and the guarded timer refresh.

This is **CI PASS; hibernation/resume real-machine retest still required**. Reproduce with first-run wizard open, hibernate, then resume with the controller present and/or absent. Expected result: no .NET JIT dialog, and the wizard card should transition coherently to its waiting/disconnected state if the controller is not restored.

## Backup rule

Backups are universal Mugen Deej settings snapshots, not controller-specific files. A backup made with one topology may be restored while a different topology or no controller is connected.

Rules:

- live hardware discovery decides which controls currently exist;
- saved mappings for absent controls stay dormant instead of fabricating UI or being deleted;
- a smaller attached controller must not truncate a larger saved mapping set;
- future topology metadata in a newer backup schema is informational/warning data, not a hard restore lock;
- existing emergency pre-restore backup and rollback behavior remains required.

See `docs/BACKUP_COMPATIBILITY.md`.

## Virtual Xbox integration

The optional HIDMaestro-backed Xbox/XInput path remains staged. Previously hardware-proven items include device creation, joy.cpl visibility, neutral axes, button press/hold/release, simultaneous combinations, mapping persistence, nonblocking startup, bilingual status, and real-game recognition in Cult of the Lamb.

Nonblocking teardown has CI coverage but its final real-hardware re-test remains pending; do not silently mark that item PASS.

## Immediate next work

Hardware-review Integrated #59. The #44 capability filtering across Legacy, Extended, and two Adaptive topologies is real-machine PASS. Re-test hibernation/resume with the first-run wizard open to verify the #59 atomic connected/waiting card switch and absence of a .NET JIT dialog. Then exercise the #57 mouse-wheel actions on a real encoder. Actual mapped toggle/encoder action execution and backup schema v2 restore still require explicit real-machine tests.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- CI/code inspection is not a hardware PASS.
- Preserve Legacy and Extended behavior.
- Adaptive controls remain first-class types; do not flatten toggles/encoders into fake momentary buttons.
- Do not hardcode 5/29/2/1 into generic Adaptive behavior.
- For any build-triggering change: wait for the workflow result, fix/rebuild if red, then hand the ready inner program ZIP directly rather than making the tester hunt through Actions.
- Keep this handoff current after meaningful code, CI, UI, or hardware observations.

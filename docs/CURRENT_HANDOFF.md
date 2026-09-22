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

Real-machine retest is now **PASS** for both important resume branches while the first-run wizard remained open:

- successful preserve path: after hibernation the existing COM14 SerialPort resumed without Close/Open after ~13.6 s, with no JIT dialog and the wizard/main UI remaining coherent;
- failed preserve path: after a later hibernation the preserved COM14 handle stayed closed past the grace window, the app cleaned it up and moved the wizard atomically into its waiting/disconnected state, again with no JIT dialog;
- a subsequent manual reconnect found COM14/Adaptive v3 at 115200 and restored the full 5/29/2/1 topology.

This closes the first-run wizard resume/disconnect crash found before #59.

## Integrated #61 — same-COM auto-reconnect after failed resume

Workflow run:

- run number: **#61**
- run ID: `35363894999`
- built code head: `cda7e383a27cc21534b1d86a57a85df39c6f0c84`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-61`
- artifact ID: `10554993462`
- outer Actions digest: `sha256:aa6db83aa660e59b0b65157ff591e5ee72d12f792a45f82b6557dfca7b5425b7`
- inner program ZIP SHA-256: `56fe6324dbfc04456f05cd3853a7c47f0e5eb346b0d5749d6fd69e9d98ee0677`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

The #59 real-machine resume retest exposed a second, separate recovery issue after the JIT crash itself was fixed. On the failed-preserve branch the UI correctly moved to `Жду контроллер...`, but physically reconnecting the controller on the same COM14 did not reconnect automatically. The log shows cleanup completed at 21:35:05, then no automatic probe occurred for roughly two minutes; only the user's manual `Найти и подключить заново` at 21:37:05 reopened COM14 and detected Adaptive v3.

Root cause: failed resume intentionally enabled `ResumeAutoReconnectSuppressed` and the reconnect loop only woke for a **newly appeared COM number**. Because COM14 remained in `KnownPorts`, a fast unplug/replug that reused COM14 could look unchanged to the 500 ms port snapshot and remain suppressed forever.

#61 changes:

- after a failed preserved-SerialPort resume, the previous controller port is explicitly removed from the in-memory known-port snapshot;
- its probe cooldown/state is reset and the next port snapshot is forced immediately;
- therefore the same COM number receives one fresh targeted auto-reconnect opportunity even if Windows reused it too quickly for an observed remove/add pair;
- ordinary suppression remains in place after that one attempt, so the app does not spin in repeated port-open loops if the controller still cannot be reached.

This is **CI PASS; real-machine same-COM replug retest still required**. Reproduce the failed-preserve branch, leave the first-run wizard open, unplug/replug the Arduino so Windows gives it COM14 again, and do not press manual reconnect. Expected result: Mugen should detect COM14 automatically and the wizard should leave `Жду контроллер...` on its own.

## Integrated #63 — remove first-run inner gray fill

Workflow run:

- run number: **#63**
- run ID: `35365077964`
- built code head: `7529db0da6467e08d8a52e4972e9b230f01d899b`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-63`
- artifact ID: `10556445112`
- outer Actions digest: `sha256:49aef880d2c71f76713502d94784a6104512c31e6f1810853ebfead7ae0ea5be`
- inner program ZIP SHA-256: `856c0bef7950955662ceb3b9fe0ab661cdfcd7bb72294f4176b8531a36a87d3e`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

The #61 first-run screenshot revealed an unintended gray rectangle inside the `Ваш контроллер / Your controller` card. This was not a design choice: #59 introduced standard WinForms child panels to make connected/waiting state switching atomic, but those panels kept their default opaque Control background.

#63 sets both the connected-details and waiting-state child panels to transparent so the underlying Mugen card paints the whole area consistently while preserving the atomic resume/disconnect switching introduced in #59.

This is **CI PASS; visual real-machine check still required**.

## Integrated #65 — retry the freshly reappeared COM after Windows hotplug race

Workflow run:

- run number: **#65**
- run ID: `35365708384`
- built code head: `84b27a8f5c4c886ab59e8f5bd1ec0e01207b764c`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-65`
- artifact ID: `10556038509`
- outer Actions digest: `sha256:40cd824b2e9fca49726db8d90f63f37c8e9d66d0c1c10e68749bf8d274f48d44`
- inner program ZIP SHA-256: `c993cfa06e38c4efc229342226283c0902e835c0aa98d8327d9a30347cb81b41`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

The first real-machine test of #61 reproduced the exact same-COM resume path, but exposed a Windows hotplug timing race:

- after failed preserved-handle recovery, #61 correctly forgot COM14 and armed fresh detection;
- ~650 ms later the Windows port enumeration reported COM14 as new;
- Mugen immediately tried only COM14, but `SerialPort.Open()` still returned `Port 'COM14' does not exist`;
- Device Manager already showed Arduino Uno (COM14), so Windows had published the device identity before the COM endpoint was fully openable;
- because the one fresh attempt failed, resume suppression remained active and the wizard stayed on `Жду контроллер...`.

#65 adds one short second chance only for this resume-hotplug case:

- `ResumeHotplugRetrySeconds = 2`;
- if the freshly reappeared preferred resume port is detected but the immediate targeted open fails, Mugen schedules one more targeted attempt two seconds later;
- that delayed attempt reuses the existing resume-reconnect path, which ignores the temporary probe cooldown and only touches the preferred COM port;
- if the second attempt also fails, normal suppression remains, so there is still no repeated COM hammering.

This is **CI PASS; real-machine retest required**. Reproduce hibernate -> unplug Arduino -> resume -> wait for `Жду контроллер...` -> reconnect Arduino on COM14 and do not press diagnostics. Expected log sequence after the first too-early open failure includes `scheduling one targeted retry in 2 s`, followed by a successful COM14/115200 detection.

## Integrated #69 — first-run card surface fix

Workflow run:

- run number: **#69**
- run ID: `35366820483`
- built code head: `a2e1469246f45850a053390e7c9ea03fea55e93f`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-69`
- artifact ID: `10556487335`
- outer Actions digest: `sha256:1dbc7d50746cfd268228eddb116a6e17cb24c7cdf04cd032bb94434f5021102a`
- inner program ZIP SHA-256: `e0580c1d2a14aa2b84ff7f3d894e7d4c8796559485fec910e7390603305bda53`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

The transparent-panel attempt from #63 did not visually remove the gray inner rectangle. Root cause: recursive theme application later overwrote the child panels' transparent BackColor because ordinary borderless WinForms panels are intentionally themed with `palette.Window`. The card itself uses `palette.Surface`, so the nested panels were repainted gray after being created transparent.

#69 fixes the cause rather than the symptom:

- first-run connected/waiting atomic panels are tagged `MugenCardInner`;
- generic theme application recognizes that tag and gives those panels the same `palette.Surface` as the surrounding Mugen card;
- atomic connected/waiting switching from #59 is preserved;
- #65 resume-hotplug targeted retry is also included.

Real-machine visual check is now **PASS**: the first-run `Ваш контроллер / Your controller` card renders as one continuous surface with no unintended gray inner rectangle.

## Integrated #73 — persistent targeted reconnect after resume

Workflow run:

- run number: **#73**
- run ID: `35368593829`
- built code head: `b317c87c611cf09385b0b1c3c96f340e863f0701`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-73`
- artifact ID: `10556434630`
- outer Actions digest: `sha256:dd5c37d060a389d0ac0e82b1ff473b5f962b2cb8d09b147275b108c468f9ae08`
- inner program ZIP SHA-256: `e0fd65a59a803cdb1a02f409dd0b2f5231e880470557c404cc362ee33ad15f00`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

The #69/#65 real-machine hibernate test showed that one delayed retry was still insufficient. The log sequence was:

- preserved COM14 handle failed after the 15 s resume grace period;
- fresh COM14 enumeration was noticed;
- immediate targeted open failed with `Port 'COM14' does not exist`;
- the scheduled +2 s targeted retry also failed with the same Windows IO error;
- Mugen then suppressed automatic reconnect indefinitely and remained on `Жду контроллер...`, even after the user physically replugged USB several times.

#73 changes the recovery policy:

- first, keep the fast targeted retry cadence every 2 s for a short readiness window;
- after that fast window expires, do **not** suppress forever;
- continue a low-frequency targeted retry every 10 s, only against the previously working COM port;
- no broad COM scanning is added;
- any manual reconnect action cancels the pending resume retry schedule;
- success clears the resume retry state immediately.

This deliberately favors eventual recovery over a permanent stale waiting state. The low-frequency phase exists specifically for Windows cases where the COM name remains enumerated while the underlying endpoint is not yet openable, or where unplug/replug reuses the same COM identity without producing a useful port-list edge.

Real-machine retest is now **PASS**. In the hibernate -> unplug Arduino -> resume -> replug Arduino scenario, Windows kept enumerating COM14 while SerialPort.Open still returned `Port 'COM14' does not exist` for multiple attempts. #73 kept retrying the preferred port every 2 s during the fast readiness window; COM14 finally became openable near the end of that window, Adaptive v3 5/29/2/1 was detected at 115200, and the targeted resume recovery completed automatically without any diagnostics/manual reconnect action.

## Integrated #75 — generic same-COM recovery after runtime serial loss

Workflow run:

- run number: **#75**
- run ID: `35371512251`
- built code head: `0f8ee60ade18abc11b4650dbceec0fdcb145eb51`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-75`
- artifact ID: `10558298742`
- outer Actions digest: `sha256:f97000aa26e014e9aadf4624cd046bee0434c3ae0c7dffeaba16cc6d200afc0e`
- inner program ZIP SHA-256: `190e3b1c4177c4f70de97a8c2e0c949a95c3249005889de5917e2c16a1e2fb4d`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

A runtime hardware test after the #73 resume work exposed the same class of Windows same-COM problem outside suspend/resume. The active Adaptive controller stopped producing valid packets after a physical pin interaction. Mugen correctly declared the serial connection lost after the 2500 ms data timeout, then immediately reopened COM14 but could not detect the protocol. That negative probe put COM14 on the ordinary long cooldown path. Subsequent physical USB replug(s) reused COM14 and did not produce a reliable remove/add edge, so Mugen kept scanning unrelated COM ports and the UI remained on `Связь с контроллером потеряна. Переподключаемся...`.

Relevant real-machine log sequence:

- `Serial connection lost: No valid controller packets received for 2500 ms`;
- COM14 reopened and probed at 115200/9600, but no Mugen protocol was detected;
- COM1 was then probed, while unrelated COM4/COM13 entered growing busy-port cooldowns;
- no successful COM14 retry occurred before the supplied log ended.

The Adaptive fixture itself defines D7 only as the first encoder's synthetic CCW detent, so D7 is not intentionally a protocol-disconnect input. The exact physical event that stopped packets is therefore not established by the log; it may have been a transient reset/brownout/contact mishap. The client must recover either way.

#75 generalizes the robust recovery policy beyond resume:

- when an established controller connection is lost, capture the last known-good COM port before cleanup;
- arm a targeted recovery loop for only that last known-good port;
- retry every 2 s for the first 20 s, then every 10 s at low frequency;
- every targeted attempt resets that port's probe cooldown, so one early protocol miss cannot suppress recovery for five minutes;
- same-COM unplug/replug no longer depends on Windows exposing a clean port-list edge;
- successful controller detection clears the generic recovery schedule immediately;
- manual reconnect and suspend paths cancel the ordinary recovery schedule so they can take ownership cleanly.

Real-machine runtime-loss retest is now **PASS**. Two separate disconnect/replug cycles on COM14 recovered automatically without using diagnostics/manual reconnect. In each case the first immediate targeted open could hit Windows' transient `Port 'COM14' does not exist` state, then the next targeted retry opened COM14, detected Adaptive v3 5/29/2/1 at 115200, and restored the controller. After recovery, encoder CCW/CW movement, encoder push press/release, and both toggles continued producing valid live events.

## Integrated #79 — typed-action summary + user-facing encoder help

Workflow run:

- run number: **#79**
- run ID: `35374426906`
- built code head: `b5a52c3e315999d442d47864f1b0a7a355d12473`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-79`
- artifact ID: `10558854378`
- outer Actions digest: `sha256:108b430b03729e53c653322d5533b9dfffc4e2d16cd2c203fa58c56597327922`
- inner program ZIP SHA-256: `13ff44a6bedcff28e875c1d2036d89c0674dc55ad65c7c1fa2715afa72034f44`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

User review of #75 found a usability mismatch: button settings had a summary list of assignments, while toggle/encoder settings required opening each control individually to remember what was mapped. The encoder help text was also written in implementation language (detent, serial packet recovery, 32-action packet cap) that was useful for development but not for ordinary users.

#79 changes:

- toggle/encoder settings now include an assignment summary table with columns for control, event, and action;
- the summary defaults to assigned actions only and can switch to all available action slots;
- a counter shows assigned slots versus total available slots;
- action names in the summary use the same user-facing labels as the action selectors, including mouse-wheel actions and configured hotkeys/files/folders/commands/URLs;
- the technical encoder paragraph is replaced with a simple explanation: each encoder step runs the selected action once, and the dot means the encoder can also be pressed;
- the main typed-settings hint is rewritten in plain language;
- the dialog is taller to make room for the summary without compressing the editor.

The first implementation attempt (#77) corrupted the staged patch because JavaScript string replacement interpreted PowerShell regex text ending in `
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

Hardware-review **Integrated #114** on the real 5 / 28 / 2 / 1 cardboard controller.

#113 real-machine findings are now:

- **PASS:** the XInput-enabled UI/encoder lag is gone;
- **PASS:** RU <-> EN switching updates the physical status row, virtual status row and XInput button;
- **PASS:** the visible second-row name remains generic `Виртуальный геймпад / Virtual gamepad` after connection;
- **needs polish:** the long physical-controller summary still wraps because #113 shares its first row with the XInput button;
- **new startup bug:** while the virtual controller is still in `connecting`, Windows Snipping Tool's selection cursor can drift up-left; the drift stops once the gamepad reaches `connected`.

#114 has two focused fixes to test:

1. the physical-controller summary gets the full first status row, while the XInput button moves to the virtual-controller row; confirm the 5/28/2/1 summary stays on one line in RU and EN;
2. before HIDMaestro exposes the xbox-360-wired device during PnP setup, Mugen best-effort pre-seeds the pinned v1.8.0 XUSB/GIP shared-memory stick bytes to neutral (0x7FFF) instead of the SDK's temporary all-zero startup state. Reproduce the Snipping Tool test specifically during `connecting` and confirm the cursor no longer walks up-left.

Keep testing mapping persistence, joy.cpl OEM naming, digital-stick mappings, and effective-profile transition safety after these two checks.

#114 is CI PASS only until the real-machine startup/drift test is completed.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- CI/code inspection is not a hardware PASS.
- Preserve Legacy and Extended behavior.
- Adaptive controls remain first-class types; do not flatten toggles/encoders into fake momentary buttons.
- Do not hardcode 5/29/2/1 into generic Adaptive behavior.
- For any build-triggering change: wait for the workflow result, fix/rebuild if red, then hand the ready inner program ZIP directly rather than making the tester hunt through Actions.
- Keep this handoff current after meaningful code, CI, UI, or hardware observations.
`; #78 rebuilt the patch safely but its new Cyrillic CI literals were not Windows PowerShell 5.1-safe in the workflow command encoding. #79 uses ASCII-safe CI checks and is fully green.

Mouse-wheel action hardware status is now **PASS** based on the user's #75 test session:

- ordinary vertical wheel up/down actions fired from encoder CW/CCW;
- native horizontal wheel left/right actions fired from encoder CW/CCW;
- Ctrl + wheel up/down fired from encoder CW/CCW;
- the user confirmed scrolling and Ctrl+scroll behavior worked in practice.

Real-machine visual review of the new typed assignment table is still required.

## Integrated #81 — typed assignment list consistency

Workflow run:

- run number: **#81**
- run ID: `35375288992`
- built code head: `22045f4b4707ca29bd53542ef6ec246e63d39cb7`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-81`
- artifact ID: `10560195400`
- outer Actions digest: `sha256:183c420639e82a4aa2122571a53d22b4271e7ddf7d30a30bdf9152d573b3a86a`
- inner program ZIP SHA-256: `06acfc13c619328fa8c1104c64b872887407caf37f91ef5b0d390fe1e7112f0c`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

User review of #79 showed the new toggle/encoder assignment summary looked inconsistent and visually broken in dark mode because it used a DataGridView, unlike the already-good button editor summary.

#81 changes:

- replaced the typed assignment DataGridView with the same ListView-style summary used by the large-button editor;
- dark-theme body rendering now follows the existing ListView theme path;
- filter wording changed from “Все действия / All actions” to “Все назначения / All mappings” so it describes the list contents correctly;
- summary caption now matches the button editor wording: “Назначения: X из Y / Assignments: X of Y”;
- clicking a typed assignment row selects the corresponding toggle or encoder in the editor, matching the button editor interaction model.

Horizontal mouse-wheel hardware/application behavior is now **PASS**. In #81 the user mapped E1 CCW to `mouse:hwheelright` and CW to `mouse:hwheelleft`, then confirmed visible left/right scrolling in Excel. The log also shows matching per-step Adaptive action dispatch in both directions.

## Integrated #89 — first foreground-application profiles

Workflow run:

- run number: **#89**
- run ID: `35380437192`
- built code head: `0a94dba1d58579a0ca8694c48c4488867883e63f`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-89`
- artifact ID: `10561764168`
- outer Actions digest: `sha256:1a67b5eaff5e427f8f89626f9be120c1a92fbf16d83b23bb37ae47de9663b728`
- inner program ZIP SHA-256: `1eddc02de6714ef60a6246a494f8b921b5efb4c6a6645062cb7bedb72f407900`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

#89 is the first deliberately narrow application-profile prototype. It profiles **Adaptive toggles and encoders only**; momentary buttons and analog slider assignments remain global for this milestone so the foreground-selection model can be hardware-tested before broadening it.

Implemented behavior:

- Win32 foreground-window process detection is exposed through `MugenDeejWindowing.Foreground.GetForegroundProcessName()`;
- typed settings now contain an `Action profile / Профиль действий` selector;
- `Global / Общий` remains the fallback mapping for applications without their own profile;
- `Добавить… / Add…` lists currently running user applications and creates a new profile as a copy of the current Global typed mappings;
- the editor is transactional across profile switches: changing profiles inside the dialog keeps per-profile drafts in memory, Save commits all of them, Cancel discards them;
- profiles are stored in `adaptive-profiles.json` with process name plus toggle/encoder mappings;
- at action time, toggle/encoder mapping lookup resolves the foreground process and uses its saved profile when present, otherwise Global;
- profile actions preserve dormant higher-index mappings just like Global typed mappings.

The intended first real-machine test is:

1. create an Excel profile and map E1 CW/CCW to horizontal scroll;
2. create a browser profile and map E1 CW/CCW to Ctrl+wheel zoom;
3. Save;
4. focus Excel and verify E1 scrolls horizontally;
5. focus the browser and verify the same E1 zooms;
6. focus an unrelated application and verify E1 falls back to the Global mapping.

No firmware changes are required for this test.

Universal backup schema remains user-facing **v2**. Current v2 snapshots now carry an optional versioned `adaptiveProfiles` payload. Older v2 backups created before application profiles existed remain valid and preserve the current profiles when restored. Current emergency pre-restore snapshots and rollback also include/restore the profile payload.

This is **CI PASS; foreground profile switching still requires real-machine testing**.

## Integrated #90 — single typed-control collection fix

Workflow run:

- run number: **#90**
- run ID: `35420391673`
- built code head: `1bd9a3871e4bde1291c075ff8b48e3a6e97fce6b`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-90`
- artifact ID: `10577322181`
- outer Actions digest: `sha256:30ff95007351022d1d81f4f59d32ceb9df28787f4010884cae99cd8ca6f0ce9c`
- inner program ZIP SHA-256: `a748a7553a71d24af8006fde7f9e604e950ec6590ee3962faa68fa5a228309bc`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

The first real-machine exercise of #89 exposed a regression immediately when the single Adaptive encoder changed state. Mugen successfully parsed and logged the encoder movement (and likewise encoder push), then the runtime threw `Property "Count" cannot be found on this object`. The generic serial error path interpreted that exception as a lost controller connection, closed COM14, and armed the normal same-COM recovery loop. Recovery then rediscovered the same Adaptive 5/29/2/1 controller at 115200 and the new cumulative encoder position was visible after reconnect.

This was not an Uno reset or protocol loss. The #89 foreground-profile lookup selected its mapping source through a PowerShell `if` expression. PowerShell 5.1 pipeline unrolling turns a one-element result into the element itself rather than an array. With the current fixture there are two toggles but only one encoder, so the encoder source could become a single PSCustomObject and `$source.Count` then failed.

#90 fixes the source selection by wrapping the complete conditional result in an array expression for **both** typed families:

- toggle profile/global source -> always an array;
- encoder profile/global source -> always an array.

The toggle path was fixed defensively too, so a future one-toggle topology cannot hit the same failure.

Real-machine retest required before marking this hardware PASS:

1. E1 CW;
2. E1 CCW;
3. E1 push press/release;
4. confirm COM14 stays connected with no false recovery cycle;
5. then continue the #89 foreground-profile test: Excel -> horizontal scroll, browser -> Ctrl+wheel zoom, unrelated app -> Global fallback.

One separate `Serial port is no longer open` event appeared once during the #89 test session after a recovery cycle. Treat it separately from the deterministic `Count` regression. Re-investigate only if it still occurs after #90.

## Integrated #99 — button application profiles across protocol generations

Workflow run:

- run number: **#99**
- run ID: `35422370013`
- built code head: `5484ff86b7251142af968f2f7996ab2a146c18e3`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-99`
- artifact ID: `10577809511`
- outer Actions digest: `sha256:92689ee58fa4af55cdca486347f48ed090b4c9140077a6d288b17aa32ddc07b2`
- inner program ZIP SHA-256: `ff9197a870b8853fdd14734801c00f5a4a372651b29cac2b90b94d948c4db270`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- launcher/package: PASS

The interrupted #91-#98 development chain extended the foreground-profile model from typed controls to ordinary momentary buttons. Intermediate red runs were fixed before handoff; #98 was the first fully green Adaptive-button implementation, and #99 generalizes that implementation so the profile layer is a PC-side feature rather than an Adaptive-firmware feature.

Current behavior:

- `button-actions.json` remains the **Global** button mapping store and therefore preserves the established v1.0.0/Legacy/Extended compatibility path;
- per-application button overrides are optional `buttons` arrays inside the existing versioned `adaptive-profiles.json` profile objects;
- profiles created by #89/#90 have no `buttons` member; missing/empty button payload therefore inherits Global instead of erasing old mappings;
- Legacy controllers expose no momentary buttons, so the new button-profile layer is inert for Legacy;
- Extended and Adaptive controllers with buttons can both use Global plus foreground-application overrides without firmware changes;
- the button settings editor now exposes the same `Global / application` selector for any connected button-capable controller;
- profile editing remains transactional: profile switches keep drafts in memory; Save commits Global plus all edited application profiles; Cancel discards them;
- ordinary button actions resolve the foreground profile at the press edge;
- stateful virtual Xbox buttons are profile-switch safe: when the foreground profile changes, the old virtual mask is released and any physical button already held across the switch is suppressed until its real release, preventing a stuck old virtual button or a synthetic press in the new profile.

The typed-settings visual report from #90 is also included in this build: the Russian `Профиль действий:` label has more room, the dialog has extra vertical space, and Save/Cancel no longer sit flush against the lower edge. This still needs real-machine visual confirmation.

Compatibility decisions for old users/backups:

- no profile file -> behavior is exactly Global, using the existing button mapping/config files;
- old #89/#90 profile files without button mappings -> typed mappings keep working and buttons inherit Global;
- old backup schema v1 -> existing global config/button mappings restore normally; setting families that did not exist in v1 (typed mappings/application profiles) are preserved rather than interpreted as empty;
- older schema v2 files without `adaptiveProfiles` -> current application profiles are preserved;
- older schema v2 files with application profiles but without per-profile `buttons` -> those profiles remain valid and inherit restored Global button mappings;
- source controller topology remains informational only, so restoring a backup made with Legacy/Extended/Adaptive hardware does not fabricate controls or require the same firmware generation to be connected.

Hardware review required:

1. repeat E1 CW / CCW / push and confirm #90's false `Count` disconnect is gone;
2. visually confirm the typed-settings clipping fix in Russian and English;
3. on the current Adaptive fixture, create two application profiles and verify one physical button changes action with foreground application while an unrelated app uses Global;
4. repeat the same button-profile smoke test with an Extended controller/firmware when convenient;
5. if virtual Xbox mapping is enabled, hold a mapped physical button while changing foreground app and confirm the old virtual button releases and the held input does not re-fire until physically released;
6. perform an explicit restore test from an old v1.0.0 backup; later also exercise current schema v2 restore with application profiles.

## Integrated #101 — digital virtual-stick mappings and effective-profile state boundaries

Workflow run:

- run number: **#101**
- run ID: `35435916767`
- built code head: `76554c9f51d9b90dad241be0fffa6095e7932ee4`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-101`
- artifact ID: `10581899812`
- outer Actions digest: `sha256:a2d56c715060343c05589dff7261001669bec756f27e60c4c7dfd6b3ee785ff1`
- inner program ZIP SHA-256: `eae035fe056cbc9652e6b0759600a1a98b2cba12026deb42df88cd3bd87eaf1c`
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- HIDMaestro helper build: PASS
- launcher/package: PASS

#101 extends the stateful virtual Xbox output layer from buttons to digital stick axes. A physical Mugen button can now be mapped to any cardinal direction of either Xbox stick:

- left stick ← / → / ↑ / ↓;
- right stick ← / → / ↑ / ↓.

Behavior is intentionally digital and stateful:

- press/hold -> the selected virtual stick axis goes to full deflection;
- release -> that axis returns to center;
- multiple physical buttons mapped to the same direction keep the direction active until all are released;
- opposite directions on the same axis cancel to center;
- button and stick outputs are submitted together as one virtual-controller state so mixed mappings stay coherent.

The elevated helper now accepts a combined `state <mask> <LX> <LY> <RX> <RY>` command. Stick components are signed `-1 / 0 / +1` on the Mugen side and are normalized to HIDMaestro's `0.0 / 0.5 / 1.0` axis range by the helper. The old `buttons <mask>` command remains accepted for compatibility, and `release` now neutralizes both buttons and axes.

The virtual-control picker is now a general Xbox-control picker rather than button-only UI. Existing Xbox button mappings remain available and the two stick-direction rows were added beneath them. This does **not** add analog slider->axis routing yet; #101 is the digital button->axis slice only.

Foreground safety is based on the **effective action profile**, not on Alt+Tab or on every foreground process change:

- if Game.exe has its own profile and focus moves to an unprofiled app, the effective profile changes Game -> Global, so state is neutralized;
- if focus moves between two unrelated unprofiled apps, both resolve to Global, so there is no artificial reset;
- if a physical button is already held across an effective-profile change, the old virtual button/stick state is released/centered and that physical input is suppressed until its real release;
- therefore a held control cannot become a synthetic press or stick deflection in the newly selected profile.

This covers multi-monitor borderless-fullscreen use: clicking OBS, chat, browser, Explorer, taskbar-driven windows, Win+Tab, Alt+Tab, etc. all feed the same foreground-process resolver. Unprofiled processes simply use Global.

#100 was red only because an older CI marker still searched for the pre-#101 log wording `Virtual gamepad button profile changed`. The implementation/staging step had already passed, including the helper compile. #101 updates the guard to the new generalized output-profile marker and is fully green.

Compatibility remains deliberate:

- no profile file -> Global behavior only, as before;
- Legacy -> no button inputs, so the new digital-axis mapping layer is inert;
- Extended and Adaptive -> both can use button->Xbox-button and button->stick-direction mappings with no firmware changes;
- old profile objects without `buttons` -> inherit Global;
- old backup schema v1 remains accepted;
- older v2 backups/profile payloads remain accepted;
- digital stick mappings are ordinary button-action strings, so no backup schema bump is required.

Real-machine review required:

1. retain the #90 regression check: E1 CW / CCW / push must not cause reconnect;
2. visually confirm the typed-settings clipping fix;
3. map four physical buttons to left-stick ← / → / ↑ / ↓ and verify press/hold/release in `joy.cpl` or a game;
4. verify opposite directions held together produce center;
5. mix an Xbox button mapping with a stick-direction mapping and verify both can be held simultaneously;
6. create an application profile with different virtual mappings, hold a mapped control, then change focus by clicking another monitor/window; old output must neutralize and the held control must not re-fire until released;
7. move between two unprofiled applications and confirm both remain Global without a needless profile-boundary reset;
8. later repeat a button-profile smoke test on Extended firmware and perform explicit old-v1/current-v2 backup restore tests.


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

Hardware-review **Integrated #113**. #108 proved the new 2.0.0 Prototype identity and standalone XInput control are visible on the real machine, but it also exposed three follow-up problems: noticeable UI/input lag while the virtual controller is enabled, a cramped two-row status card, and partial language switching in that status area.

For #113, verify:

1. with XInput enabled, rapidly rotate the encoder and press several physical buttons; the main UI should remain as responsive as it is with XInput disabled;
2. the status card should have deliberate padding and enough height for the physical-controller row plus the virtual-gamepad row, with the rest of the window shifted down rather than overlapped/cramped;
3. RU <-> EN switching should immediately update both status rows and the XInput button;
4. the user-facing second row must stay named `Виртуальный геймпад / Virtual gamepad` in waiting, connecting, connected, and error states;
5. joy.cpl must still show the OEM device name `Mugen Deej Virtual Gamepad`;
6. continue the #108 mapping-persistence checks (Save/reopen/restart/reconnect), digital-stick behavior, and effective-profile boundary tests.

#113 is CI PASS, not hardware/UI PASS until this real-machine review is complete.


## Foreground profile switching safety requirement

Application profiles are keyed to the **actual Windows foreground process**, not to Alt+Tab specifically. A profile change can therefore happen through any normal focus transition: clicking another window on another monitor, clicking OBS/chat/browser while a borderless-fullscreen game remains visible, using the taskbar/Start menu, Win+Tab, Alt+Tab, or another application bringing a window to the foreground.

For stateful virtual-controller outputs (held Xbox buttons and the digital stick-axis mappings implemented in #101), every **effective profile** transition must be treated as a state boundary:

- release the old profile's virtual button state;
- return any profile-owned virtual axes to neutral;
- suppress physical controls that were already held across the transition until they are physically released;
- do not synthesize a fresh press/axis deflection merely because the new profile maps that same held control differently.

This rule is independent of how focus changed and is driven by foreground-process identity resolved through the saved profile set. A foreground change that still resolves to the same Global profile (for example Explorer -> Notepad when neither has a dedicated profile) is not a profile boundary and must not cause a needless reset. Borderless-fullscreen multi-monitor use is a required real-world scenario.


## Physical cardboard prototype — Uno bring-up wiring

The first large real panel has now been physically assembled enough for firmware bring-up. Actual control set differs slightly from the earlier 5x6 planning sketch:

- 28 standalone momentary buttons;
- 2 latching toggles;
- one ready-made rotary encoder module with separate `S1 / S2 / KEY / 5V / GND`;
- encoder push therefore uses dedicated `KEY` instead of consuming a matrix cell;
- five potentiometers are not installed yet, so the first firmware keeps the known software placeholder values `0 / 256 / 512 / 768 / 1023`.

The panel matrix is now **4x8**:

```text
        C1  C2  C3  C4  C5  C6  C7  C8
R1      B1  B2  B3  B4  B5  B6  B7  T1
R2      B8  B9  B10 B11 B12 B13 B14 T2
R3      B15 B16 B17 B18 B19 B20 B21 spare
R4      B22 B23 B24 B25 B26 B27 B28 spare
```

Uno bring-up pin map:

- encoder: D2=S1, D3=S2, A2=KEY, plus 5V/GND;
- columns C1..C8: D4..D11;
- rows R1..R4: D12, D13, A0, A1;
- D0/D1 remain reserved for USB serial.

Every matrix position uses its own diode with the striped cathode facing the ROW bus for the firmware's active-LOW scan.

Dedicated firmware now lives at:

- `arduino/MugenDeejCardboardUnoPrototype/MugenDeejCardboardUnoPrototype.ino`
- `arduino/MugenDeejCardboardUnoPrototype/README.md`

It emits Adaptive v3 at 115200 as **5 / 28 / 2 / 1**. The 5 slider fields are temporary software placeholders until real potentiometers are fitted.

Hardware status: the complete digital set (28 buttons, 2 toggles, encoder/push) is now **hardware PASS**; only the five real analog potentiometers remain pending.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- CI/code inspection is not a hardware PASS.
- Preserve Legacy and Extended behavior.
- Adaptive controls remain first-class types; do not flatten toggles/encoders into fake momentary buttons.
- Do not hardcode 5/29/2/1 into generic Adaptive behavior.
- For any build-triggering change: wait for the workflow result, fix/rebuild if red, then hand the ready inner program ZIP directly rather than making the tester hunt through Actions.
- Keep this handoff current after meaningful code, CI, UI, or hardware observations.


### Cardboard matrix wiring hardware PASS (2026-09-20)

The real 4x8 cardboard panel matrix is now hardware-tested for all 28 momentary buttons.

A wiring mistake was found during bring-up: the first assembly accidentally chained row diodes in series along each row. That produced a characteristic failure where C1..C4 worked but C5..C8 did not, even though the column buses had continuity. Swapping C1/D4 with C5/D8 proved the Uno pin/firmware path was healthy and localized the fault to the physical matrix.

Corrected electrical rule used on the working panel:

- each switch keeps its own diode;
- COLUMN -> switch -> diode -> shared ROW bus;
- all diode cathode/striped ends for a row join one common row conductor in parallel;
- row diodes must not be chained in series.

After adding proper shared row buses, **all 28 buttons respond correctly in Mugen Deej**. This is a real hardware PASS for the momentary-button matrix portion of the 5 / 28 / 2 / 1 prototype.

Toggles/encoder remain separately testable; slider channels are still software placeholders until real potentiometers are installed.


### Full digital panel smoke test PASS (2026-09-20)

After the row-bus repair, the cardboard Uno prototype was exercised as a complete digital panel in Mugen Deej:

- Adaptive v3 discovery shows 5 sliders / 28 buttons / 2 toggles / 1 encoder at 115200;
- all 28 momentary buttons register;
- both toggles and the encoder/push were reported working by the hardware tester;
- a heavy simultaneous multi-button hold was tested successfully; the runtime log shows more than twenty distinct buttons entering pressed state before the release burst, with no apparent matrix ghosting/fan-out artifact in that test;
- the five slider channels are still deliberate software placeholders at 0 / 25 / 50 / 75 / 100 percent until real potentiometers are installed.

This upgrades the current cardboard prototype's **digital control set** from bring-up/pending to real hardware PASS. Analog potentiometers remain pending.


## Integrated #108 — virtual mapping persistence, standalone XInput power, v2 prototype identity

A real cardboard-panel test exposed a deterministic persistence bug in the button editor. After selecting a virtual stick action and pressing Save, the runtime logged the Global button array as `System.Object[]` instead of 28 action strings. The same session repeatedly reproduced that save shape.

Root causes:

- `Copy-AdaptiveProfileButtons`, `Copy-AdaptiveProfileToggles`, and `Copy-AdaptiveProfileEncoders` returned `,$copy` even though every caller already wrapped the result in `@(...)`; this created a nested array and corrupted the saved Global/profile button action shape;
- the stable 1.0.0 button normalizer still predates `virtual:xbox:*` actions, so a correctly saved virtual mapping could also be rewritten to `none` during controller capability normalization/reconnect.

#108 fixes both paths:

- profile-copy helpers now return the normal array and callers remain responsible for array capture;
- the staged integrated runtime explicitly preserves every action recognized by `Test-MugenVirtualGamepadAction`, including digital stick directions;
- the RU application-profile explanation in the large button editor now has a real two-line area instead of clipping;
- virtual-controller power is no longer presented as part of the large physical-button mapping editor;
- a dedicated main-status-card `XInput: Вкл/Выкл` / `XInput: On/Off` control owns the virtual-controller enable state;
- the dev-stage runtime now identifies itself as **Mugen Deej 2.0.0 Prototype** in title/log/backup metadata while stable `main` remains 1.0.0.

Workflow run:

- run number: **#108**
- run ID: `35474728701`
- built code head: `8baafb0d9870ff23b1b9fb82b2c2ad7ca200317c`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-108`
- artifact ID: `10593492558`
- outer Actions digest: `sha256:f5ec19d92fab5c5d7c8791d4938fcd240fdd9eb7217408a01587abcd7de4274d`
- inner program ZIP SHA-256: `607defc6e9256714ebea0ace14d1fb80922f9ff611fe0a5e38337909d63f417c`
- staging: PASS
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- helper/launcher/package/upload: PASS

Runs #102-#107 were development/CI repair iterations while introducing this slice; #108 is the first fully green package and is the only build from this sequence to hand to the hardware tester.

No backup schema bump is introduced. The action values are still ordinary strings in the existing Global/per-profile button arrays; #108 repairs their in-memory/save shape and validation rather than changing the file format.


## #108 real-machine UI review -> Integrated #113

Real-machine review of #108 confirmed the new product identity appears correctly as **Mugen Deej 2.0.0 Prototype** and the standalone XInput control is reachable from the main window. Enabling the virtual controller also successfully reached the connected state.

The same review exposed three issues:

- while XInput was enabled, the main interface became noticeably less responsive to physical input; encoder motion made the lag easiest to see;
- the 60-ish pixel status card was being forced to hold a long physical-controller status line, a second virtual-controller row, and the XInput control, producing wrapping/crowding against the card edges;
- changing language while virtual output was active could leave the physical status row in the previous language even though the rest of the main UI and virtual row had switched.

The uploaded runtime log confirms the controller itself continued delivering encoder/button events after the virtual helper became ready, so this was treated as a desktop/UI-thread workload problem rather than serial input loss.

Root performance issue found in code: every Adaptive heartbeat carries the complete physical button array, and the virtual-output bridge was resolving the foreground process/application profile on every unchanged heartbeat. With the cardboard firmware's ~25 ms stream, this meant repeated foreground-process/profile work on the WinForms thread even when no virtual button state changed.

#113 changes:

- unchanged physical button frames now take a cheap equality fast path;
- foreground-profile boundary checks move to a dedicated 200 ms timer, preserving held-button/profile-switch safety without doing process lookup on every heartbeat;
- the status card now expands to a real two-row layout when XInput is enabled and main-window content starts below the card's actual bottom instead of fixed Y=160;
- physical + virtual status localization is refreshed together after RU/EN changes;
- the user-facing virtual row is consistently `Виртуальный геймпад / Virtual gamepad` for waiting/connecting/connected/error;
- the helper's OEM display name is intentionally unchanged, so joy.cpl/DirectInput should continue to show **Mugen Deej Virtual Gamepad**.

Workflow:

- run number: **#113**
- run ID: `35491496076`
- built code head: `3623b98bab8a2e080552ae36d46ecdee7bed0d16`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-113`
- artifact ID: `10599770256`
- outer Actions digest: `sha256:813576049549fe9439725d6828cf102df47276134e71dada510ae245f9b20a09`
- inner program ZIP SHA-256: `c071a0b532ec2a9a35bb4d43058f275a489177eaa880d8f53137954072b0cca9`
- staging: PASS
- Windows PowerShell 5.1 parse/runtime marker check: PASS
- helper/launcher/package/upload: PASS

#112 failed only because a newly added Cyrillic CI literal was not safe in the Windows PowerShell 5.1 workflow command encoding. The runtime itself staged successfully. #113 replaces that CI assertion with an ASCII-safe marker and is the build to test.


## #113 real-machine PASS + transient startup drift -> Integrated #114

The real cardboard controller was tested against #113.

Confirmed on hardware/UI:

- the previously reported XInput-enabled lag is gone; encoder and physical-button feedback remain responsive after the virtual controller is ready;
- RU/EN switching now updates the complete main window status area;
- the visible connected text remains `Виртуальный геймпад: подключён / Virtual gamepad: connected`.

The runtime log shows XInput enable at 11:39:48.354, asynchronous helper start at 11:39:48.366, and READY at 11:40:05.133, so this machine exposes an approximately 16.8-second virtual-device creation window. After READY, dense encoder/button events continue normally.

Two follow-ups remained:

1. the physical status summary still wrapped because #113 reserved the right side of the first row for the XInput button;
2. during the `connecting` window, entering Windows Snipping Tool's rectangle-selection mode could make the selection cursor drift up-left. The effect stopped as soon as the virtual controller became ready.

Pinned HIDMaestro v1.8.0 source inspection explains the second symptom. `CreateController` creates the shared input mapping and exposes the Xbox/XUSB device before returning to Mugen. The SDK zero-initializes that mapping. Its XUSB/GIP stick representation is unsigned 16-bit, where centre is about 0x7FFF but zero is full negative deflection. Mugen's normal neutral `SubmitState` was already correct, but it happened only after `CreateController` returned. Therefore Windows could observe a temporary full up-left XInput state throughout PnP startup; shell UI that listens to gamepad navigation can react to it even though ordinary desktop pointer behavior may not make it obvious.

#114 work:

- status layout gives the physical-controller summary 560 px on the full first row and moves the XInput button to the second/virtual row;
- the helper best-effort reflects the pinned HIDMaestro internal `EnsureInputMapping(0)` before `CreateController` and writes neutral XUSB/GIP stick bytes (0x7FFF for LX/LY/RX/RY; triggers/buttons/hat released). SetupController then reuses the already-created mapping instead of zeroing it again;
- this workaround is deliberately guarded and diagnostic: if a future HIDMaestro internal layout changes, it logs `PRESEED_GIP_NEUTRAL_WARN` and continues rather than failing virtual-controller startup.

Workflow:

- run number: **#114**
- run ID: `35492818128`
- built code head: `5fc4722a46cc6120eb2934ef10aa1f833117c203`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-114`
- artifact ID: `10599817400`
- outer Actions digest: `sha256:eba0d17dd4322cac1f898394b6b6c032adf8c223b6833df2cd15802aa63ee58e`
- inner program ZIP SHA-256: `746b7ad9158d94cd02639df6c572a8f52b4bb5a59501497a5770a070f4823cdd`
- staging / Windows PowerShell 5.1 parse checks / helper / launcher / package / upload: PASS.

Do not call the startup-neutral workaround hardware PASS until the Snipping Tool reproduction is re-tested during the connecting phase.


## #114 real-machine regression review -> Integrated #117

The first real-machine launch of #114 was stopped before the Snipping Tool startup-neutral test because the ordinary Mugen UI became badly laggy even with XInput OFF. The screenshot also showed the attempted status-card composition was not acceptable: the physical summary was ellipsized and the XInput button floated on a mostly empty lower area.

The uploaded runtime log confirms two useful facts:

- COM14 / Adaptive v3 still detects correctly as 5 sliders / 28 buttons / 2 toggles / 1 encoder;
- during fast encoder motion there are repeated 150-800 ms holes between logged detents, consistent with UI-thread stalls rather than serial topology loss;
- switching RU -> EN saved `language=en`, but the log ends immediately after the config save and never reaches `Interface language changed to en`. The screenshot likewise shows the main UI already in English while the physical status row remains Russian, which localizes the stall to the remainder of the language-switch UI handler.

Code inspection found the #114 regression path:

- while XInput was disabled, every ~25 ms complete physical button heartbeat still called `Set-MugenVirtualGamepadUiState disabled`;
- that function repainted/re-laid-out the virtual status card even though the lifecycle state had not changed;
- #114 made that repaint heavier by setting physical-label layout/ellipsis properties on every call;
- two WinForms timers also remained permanently active while XInput was off (500 ms status refresh and 200 ms foreground-profile refresh);
- language switching still performed a synchronous `Update-DriverStatus` / PnP-CIM query before finishing the visible status localization.

Integrated #117 fixes this slice:

- identical virtual lifecycle states are ignored, so disabled heartbeats do not repaint the UI;
- status-card geometry only changes when enabled/disabled layout mode actually changes;
- the bootstrap status timer stops permanently once the integration controls have attached;
- the 200 ms foreground-profile timer exists but only runs while the virtual controller is actually ready;
- the physical connected summary is intentionally compact (for example `COM14 · 5 рег. · 28 кнопок · 2 тумбл. · 1 энкодер.`) so it fits beside the XInput button;
- XInput returns to the first physical-status row; the second row is used only for virtual lifecycle status when enabled;
- RU/EN visible status text is refreshed before any driver query, and the slow driver refresh is skipped while the diagnostics panel is hidden;
- the #114 pre-PnP neutral-XInput seed remains present and still needs its original Snipping Tool hardware test.

Workflow:

- run number: **#117**
- run ID: `35494524807`
- built code head: `f60be1ae6070e55592f34bdacc4ba20cc3ffa188`
- result: **SUCCESS**
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-117`
- artifact ID: `10600107736`
- outer Actions digest: `sha256:fb4fa564d80c8c18741a321c4de9e8f7b892771965acb9225e85aceaa4812e7d`
- inner program ZIP SHA-256: `de7cddac3f9184ebb0434f7cc5af8f16919f2c8e4814962f0fb871cb0989cb64`
- staging, Windows PowerShell 5.1 parsing/markers, launcher, package and upload: PASS.

#115 and #116 were intermediate CI repair runs and are not tester builds. #117 is the build to exercise.

Immediate #117 real-machine order:

1. leave XInput OFF and spin the encoder rapidly; ordinary UI feedback should remain smooth;
2. switch RU -> EN -> RU and confirm the physical status row changes immediately with the rest of the window;
3. confirm the compact one-row physical summary + XInput button looks intentional rather than clipped/floating;
4. only after the base UI is clean, enable XInput and retry the Snipping Tool selection during `connecting` to test the #114 startup-neutral workaround.


## #117 real-machine UI/XInput review -> Integrated #119

Real-machine review of #117 confirmed that the severe idle-status churn regression was substantially improved and the Adaptive controller still enumerates correctly as 5 sliders / 28 buttons / 2 toggles / 1 encoder on COM14 @ 115200. The user then enabled XInput successfully; the helper progressed through the visible connecting state and reached ready.

The #117 review exposed three smaller but concrete issues:

1. **Status wording scope.** Removing the redundant "Controller connected" prefix made sense for the long Adaptive four-family summary, but #117 also abbreviated nouns (`рег.`, `тумбл.`, etc.) and applied the new formatter globally. This was unnecessary. Legacy/Extended are short enough and should retain their original connected-status sentence. Adaptive should omit only the redundant prefix while keeping full words.
2. **Two-row status composition.** The physical and virtual rows were too far apart. The physical marker inherited the base 16 pt status-dot font while the virtual marker was independently created at 11 pt, so the circles visibly differed in size and baseline.
3. **Virtual stick Y orientation.** The Mugen actions are semantic directions (`left stick ↑`, `left stick ↓`), but the helper mapped semantic +Y directly to HIDMaestro normalized 1.0. In the Windows game-controller panel that means downward screen motion. The result was that the action labelled ↑ moved the virtual stick down and ↓ moved it up. This is a device-layer bug, distinct from a game's optional camera/look "invert Y" preference.

Integrated #119 fixes these items:

- Legacy/Extended restore their previous `Controller connected — ...` / `Контроллер подключён — ...` wording;
- Adaptive v3 uses a prefix-free full-word topology such as `COM14 · 5 регуляторов · 28 кнопок · 2 тумблера · 1 энкодер`;
- Adaptive Russian count labels now use proper 1/2-4/5+ noun forms in the main status formatter;
- the XInput-off card returns to the original 60 px height;
- the XInput-on card is only 68 px high, with the two rows tightly stacked;
- the virtual and physical status dots now use the same font, X coordinate, and row rhythm;
- left and right virtual-stick Y are normalized as `(1 - y) / 2`, so Mugen's semantic ↑ is visibly up in joy.cpl. Game-level invert-Y remains the game's concern.

Build:

- run **#119**, run ID `35498563298` — SUCCESS;
- code head `76c628fb2a72a0f3c6dae7647e225b6bd83054e2`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-119`, ID `10601159147`;
- outer digest `sha256:b608906c3935c264cdc2eaed00ba323351761665a0bd28b9e6a624aa36167c66`;
- inner program ZIP SHA-256 `38a627cb331fe677aaf0cd1f7af082bd38432fa99572ae7dfc2c79d42a71464a`;
- staging, Windows PowerShell 5.1 parse/marker checks, helper/launcher build, packaging and upload: PASS.

Immediate real-machine #119 checks:

1. with XInput OFF, confirm the Adaptive status uses full words and still fits on one row;
2. with XInput ON, confirm the two status rows are visually tight and both green/blue dots are identical and aligned;
3. in joy.cpl, map one physical button to left-stick ↑ and one to ↓ and verify the cross moves in the labelled direction;
4. repeat for right-stick Y if desired;
5. Legacy/Extended formatting remains to be regression-checked when those fixtures are next available.


## #119 backup/Adaptive runtime regression -> Integrated #120

Real-machine #119 review uncovered two independent runtime bugs before the visual/Y-axis checks could be completed.

1. **Valid backup restore rejected empty mapping families.** A v2 backup can legitimately contain zero Adaptive toggle/encoder assignments even when the hardware has those controls, and a fresh/pre-detection emergency snapshot can legitimately contain zero button actions. The writers used mandatory array parameters without `AllowEmptyCollection`, so PowerShell rejected `@()`. The observed restore failed on empty `Toggles`; the emergency rollback then failed independently on empty `Actions`.
2. **Adaptive status plural helper disappeared during final staging.** #119 introduced `Format-RussianControllerCount` immediately before `Get-ControllerConnectedStatusText`. The later `Add-AdaptiveControlMappings` final-stage patch intentionally rewrites the block from `Update-AdaptiveControlStates` up to the start of `Get-ControllerConnectedStatusText`, swallowing the helper definition but leaving its call sites intact. This is syntactically valid, so the previous PS5 parse check did not catch it; it failed only when the real Adaptive controller reached connected-status formatting.

#120 fixes both:

- Adaptive/button config writers explicitly accept empty collections;
- the Russian plural formatter is now local to `Get-ControllerConnectedStatusText`, outside the final-stage overwrite hazard;
- CI now rejects any staged runtime that still references the vanished external helper and asserts all three empty-collection writer annotations.

Build:

- run **#120**, run ID `35499932683` — SUCCESS;
- code head `8d3b918d7029e54f26935384bca53783cadab170`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-120`, ID `10602405485`;
- outer digest `sha256:6ac0e4a6cfc4e66b201d47a2d277ec21b8c5ff5470ae08929a4891a6a1200bd8`;
- inner program ZIP SHA-256 `32b84a9cf067b004d597f80056c0957166954f6a398efa10595c38f26332ca6a`;
- staging, Windows PowerShell 5.1 parse/marker checks, launcher/helper build, packaging and upload: PASS.

Immediate real-machine #120 order:

1. start with the same Adaptive 5/28/2/1 controller and confirm connected status appears without the JIT exception;
2. restore the same backup that failed under #119; an empty mapping family must no longer block restore;
3. accept restart and confirm the restored button/XInput mappings survive;
4. only then resume the pending #119 checks: compact two-row status alignment and corrected joy.cpl Y direction.


## #120 real-machine PASS + D-pad / backup-overwrite follow-up -> Integrated #122

Real-machine testing of #120 closed the two regressions that had blocked #119:

- **backup restore PASS:** the same schema-v2 backup that previously failed now restores successfully, creates an emergency pre-restore backup, requests restart, and comes back with all 28 button actions loaded;
- **virtual stick Y PASS:** the Windows game-controller panel now moves in the same direction as the Mugen action labels, so semantic ↑ is device-up and ↓ is device-down;
- the real Adaptive controller still detects as 5 / 28 / 2 / 1 and the virtual Xbox reaches ready normally after restore.

The #120 session log confirms restore at 14:54:22, restart at 14:54:35, post-restart load of 28 button actions, Adaptive 5/28/2/1 detection, and virtual-controller ready. Later the user saved the four left-stick and four right-stick digital direction mappings again successfully.

Two UX gaps were then identified:

1. the Xbox control picker had face/shoulder/menu/stick controls but no D-pad / крестовина;
2. SaveFileDialog's native overwrite confirmation followed the Windows shell language instead of the language selected inside Mugen.

Integrated #122 adds:

- four stateful D-pad actions: left/right/up/down;
- 8-way hat synthesis, so simultaneous perpendicular D-pad buttons produce diagonals while opposite directions on one axis cancel to centre;
- a third picker row labelled `Крестовина` / `D-pad`;
- helper state transport extended from mask+4 stick components to mask+4 stick components+2 D-pad components;
- D-pad output uses HIDMaestro `HMHat`, not fake stick movement or ordinary Xbox button bits;
- backup SaveFileDialog disables the OS overwrite prompt and uses Mugen's own themed RU/EN Yes/No warning instead. The rest of the file picker remains native Windows UI.

Workflow:

- #121 failed only because the workflow itself embedded a Cyrillic static-check literal in a Windows PowerShell 5.1 inline script; staged product code and helper build were not the reported failure;
- #122 replaced that CI assertion with an ASCII-safe marker and is **SUCCESS**;
- run ID: `35501405258`;
- code head: `bf2f31b51d62f686950415485eefd91744ec36c0`;
- artifact: `Mugen-Deej-VirtualGamepad-Integrated-122`;
- artifact ID: `10602541332`;
- outer digest: `sha256:04b2b9031e79acebf1450a16682f3f161a70ba9d1dd55a1d6ba5c56cfbcf9b7f`;
- inner program ZIP SHA-256: `1927f1b81c612b3102459089e33bbfc0655a1e7a184d208e42c168c22c448991`;
- staging, Windows PowerShell 5.1 parse/marker checks, helper/launcher build, package and upload: PASS.

Immediate #122 real-machine checks:

1. assign four physical buttons to D-pad ← → ↑ ↓ and verify the hat in joy.cpl, including at least one diagonal such as ↑+→;
2. verify opposite directions cancel cleanly (←+→ or ↑+↓);
3. save a backup over an existing filename in RU and then EN; only Mugen's themed bilingual overwrite confirmation should appear;
4. continue the pending visual review of the compact physical/virtual two-row status card.


## #122 real-machine follow-up -> Integrated #124

The #122 real-machine session confirmed the backup path remains healthy after the overwrite-localization change. The same schema-v2 backup restored, created an emergency copy, restarted through the launcher, re-detected the Adaptive controller as 5/28/2/1, and reloaded 28 button actions.

The new D-pad picker was exercised and its mappings persisted correctly. The session saved:
- button 16 -> D-pad up;
- button 22 -> D-pad left;
- button 23 -> D-pad down;
- button 24 -> D-pad right.

The localized overwrite UX is visibly correct in Russian: selecting an already-existing backup filename now produces Mugen's themed RU Yes/No dialog instead of the English native Windows overwrite prompt. The subsequent log records the backup write completing. A joy.cpl screenshot of D-pad hat output was not captured in this handoff, so assignment/persistence and overwrite UX are PASS; final D-pad HID-output acceptance remains an explicit check.

The same review identified three next-slice items:

1. **Xbox triggers were missing.** For the current physical-button mapping model, LT/RT should behave like digital stick directions: while the Mugen button is held, the trigger is driven fully to 100%; release returns it to 0%. Future analog-control -> trigger routing is a separate milestone.
2. **The two-row status card still looked composed as a first-row status plus a hanging XInput button.** The XInput toggle should visually belong to the entire card, while both text rows should share one column/rhythm.
3. **The old subtitle "Desktop audio controller / Настольный аудиоконтроллер" is no longer representative.** Mugen now handles audio, buttons, app profiles, typed controls, and virtual gamepad output.

Integrated #124 implements this slice:

- adds `virtual:xbox:lt` and `virtual:xbox:rt` actions;
- LT/RT are stateful full-press analog outputs (0 or 100%), not fake ordinary buttons;
- the helper state protocol now carries mask + four stick components + two D-pad components + LT + RT;
- the visual picker top row is now `LT | LB | RB | RT` without making the dialog taller;
- saved assignment labels explicitly show `LT (100%)` / `RT (100%)`;
- the two status text rows now use the same 444 px text column, 28 px row boxes, and consistent `·` separator wording;
- the XInput toggle is vertically centered across the two-row status card instead of being attached to row 1;
- subtitle becomes **`Настольный центр управления` / `Desktop control hub`**.

Build:

- #123 was an intermediate CI-only failure: a non-ASCII status-format literal in an inline Windows PowerShell 5.1 workflow assertion was parsed unreliably;
- run **#124**, run ID `35504754125` — SUCCESS;
- code head `f8bc133d8e41678ad9dcb3906038386e8b867f5a`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-124`, ID `10603432810`;
- outer digest `sha256:d3d286c7d8aacf8e2a6e5c1408f5d4ef3a5e6e08e35b5392ee7bec276fc1a315`;
- inner program ZIP SHA-256 `51adb7e3f7fa51a6191de06fc4bddb4a704074b61ecb3444224223f1e9693bf7`;
- staging, Windows PowerShell 5.1 parse/marker checks, helper/launcher build, packaging and upload: PASS.

Immediate #124 hardware/UI checks:

1. map two physical buttons to LT and RT; in joy.cpl each trigger must jump from released to full while held and return to zero on release;
2. press LT+RT together and verify both remain independent;
3. inspect the revised two-row status card with XInput ready/connecting and RU/EN language switching;
4. decide whether `Настольный центр управления / Desktop control hub` feels like the right product descriptor or should be renamed before consolidating the 2.0 UI;
5. if convenient, explicitly capture one D-pad cardinal/diagonal joy.cpl test to close the remaining #122 HID-output evidence gap.


## #124 picker review -> Integrated #125 spatial Xbox map

The #124 picker remained functionally complete but visually read like a configuration table rather than an Xbox controller. Real-machine review showed that even though LT/RT, bumpers, View/Menu, ABXY, sticks and D-pad could all be assigned, the flat row-by-row layout forced the user to translate labels mentally instead of recognizing the physical controller shape.

Integrated #125 changes only the picker presentation:

- window grows to 760 x 625;
- LT/LB live at the upper-left and RT/RB at the upper-right;
- View/Menu sit near the middle;
- the left stick is an actual four-direction cluster with L3 in its center;
- ABXY form the familiar Y/X-B/A diamond on the upper-right;
- the D-pad is a lower-left cross with a small non-clickable hub;
- the right stick is a lower-right four-direction cluster with R3 in its center;
- RU/EN labels identify Left stick / Face buttons / D-pad / Right stick;
- existing action semantics, saved action strings, backup schema, D-pad/trigger transport and helper behavior are unchanged.

Workflow:

- run **#125**, run ID `35508249973` — SUCCESS;
- code head `610201c1c371fde0cc69c76d729f167bdec15f58`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-125`;
- artifact ID `10604323278`;
- outer digest `sha256:618587f1a1ed01620271d001bbd8e1eb62c3f527882fb4c1ba60b09e032d7f62`;
- inner program ZIP SHA-256 `608db08f09489361390bffc67045a2430947d9b4115a3c110ae801f084a0841c`;
- staging, Windows PowerShell 5.1 parse/marker checks, helper/launcher build, packaging and upload: PASS.

Immediate #125 UI review:

1. open the picker and judge whether the controller is recognizable without reading every label;
2. verify ABXY, D-pad, L3/R3 and shoulder placement feel natural relative to the real Xbox layout;
3. confirm the wider fixed dialog still fits comfortably on the test display and no text clips in RU/EN;
4. adjust spacing/button sizes by eye from the real screenshot rather than treating #125 geometry as final.


## #125/#126 picker acceptance + status/header polish -> Integrated #129

Real-machine review of the spatial Xbox picker was positive: the user explicitly preferred the spatial map over the previous flat button table. #126 only clarified the picker hint text; geometry remained unchanged.

The next screenshot highlighted two main-window polish points:

- the physical/virtual status bullets still looked vertically displaced because they were rendered as auto-sized font glyphs with baseline-dependent metrics;
- the subtitle `Настольный центр управления / Desktop control hub` was broader than the old audio-only wording, but the question arose whether it should vary by Legacy/Extended/Adaptive firmware.

Decision for #129: **do not couple product identity to transport protocol**. Legacy, Extended and Adaptive are firmware/protocol capabilities, not separate products, and Extended already supports physical buttons/virtual gamepad behavior beyond pure audio. Use one neutral broad subtitle for all modes:

- RU: `Настольная панель управления`
- EN: `Desktop control surface`

Status bullets are now fixed-size 16 x 16 centered labels using the same typography. In the two-row XInput card their centres are aligned to the physical and virtual text-row centres; the single-row disabled card is aligned the same way. This avoids Segoe UI glyph-baseline drift and keeps both green/blue dots visually identical.

Workflow:

- #127/#128 were CI-only assertion repairs; product staging was not the underlying failure;
- run **#129**, run ID `35509790159` — SUCCESS;
- code head `bf07070a7c7a7ea33450837caecbc04c9e69a56f`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-129`, ID `10605255172`;
- outer digest `sha256:f2709b2144ec8cf46622d753a62f702bb7170ca55f5982cce6b9de7e786a68c4`;
- inner program ZIP SHA-256 `78b0948cd72430eb7a49fc801653c71c164432bd27f9ced25f0cde595582b97a`.

Immediate #129 visual check: compare both status bullets with XInput ON and OFF and judge the new universal subtitle wording in the real window.


## #129 Legacy/Extended handoff finding -> Integrated #134 Adaptive-only XInput

A real protocol-switch test exposed a product-policy mismatch. XInput had been enabled while the real Adaptive 5/28/2/1 panel was active. After that controller was unplugged and a Legacy 5-slider controller appeared on COM5, HID cleanup completed but the main window still advertised `XInput: On` / `Virtual gamepad · waiting for controller`. Returning to the Adaptive controller then created the virtual Xbox again automatically.

Product decision for the current 2.0 scope:

- Legacy and Extended keep their established audio/action roles and do **not** expose or run the virtual gamepad by default;
- Adaptive v3 is the product surface that exposes XInput;
- this is a product/UI policy, not a claim that Extended could never technically drive a virtual pad;
- if real users later request Extended virtual-gamepad support, the underlying action/backend work can be re-exposed deliberately.

Integrated #134 implements that policy without destroying the user's saved XInput preference:

- virtual-gamepad runtime startup is gated on `ControllerProtocol == adaptive`;
- when Legacy/Extended becomes the active detected protocol, any active/starting virtual controller is released and torn down through the existing nonblocking cleanup path;
- the main XInput toggle, second virtual-gamepad status row and expanded two-row status-card layout disappear on Legacy/Extended;
- the small button-settings virtual-controller section and new Xbox-control picker choices are hidden when the live protocol is not Adaptive;
- the large-button editor likewise stops offering new gamepad-control mappings outside Adaptive;
- `virtual-controller.json` keeps the user's enabled preference, so returning to Adaptive can restore XInput automatically rather than silently changing user configuration;
- async cleanup cannot restart the virtual HID after cleanup if the newly active protocol is Legacy/Extended.

Workflow:

- run **#134**, run ID `35527037157` — SUCCESS;
- built code head `f9a89202b4380a1d83cabd58fadbb8609ee4efaf`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-134`, ID `10610021853`;
- outer Actions digest `sha256:62f8c025fc1ae53f1de6febb4f9cc50baa6719c2007d708c431d2e66c3cf92ca`;
- inner program ZIP SHA-256 `47627fbf2024ea2a6c393ecebbc339283730b211876ad3831b7b929626606f9d`;
- staging, Windows PowerShell 5.1 parse/runtime checks, helper/launcher build, package and upload: PASS.

Immediate real-machine #134 sequence:

1. start on Adaptive with saved XInput ON and confirm the virtual Xbox reaches ready;
2. unplug Adaptive and connect Legacy: after background HID cleanup, the XInput toggle/virtual row must be absent and no Mugen virtual Xbox should remain in `joy.cpl`;
3. repeat with the Extended controller and confirm the same hidden/disabled policy while ordinary six-button actions still work;
4. open Extended Button Settings and confirm no virtual-controller enable UI or new Xbox-control picker choice is offered;
5. return to Adaptive and confirm the saved XInput preference brings the virtual controller back automatically;
6. explicitly turn XInput OFF on Adaptive, cycle through Legacy/Extended and back to Adaptive, and confirm it stays OFF.


## #134 protocol-switch recovery finding -> Integrated #142 transient COM hotplug fix

The real Adaptive -> Legacy -> Adaptive switch exposed a separate reconnect problem after the Adaptive-only XInput policy itself behaved correctly.

Observed real-machine sequence from the supplied runtime log:

- Adaptive COM14/XInput was active, then COM14 disappeared;
- Legacy COM5 appeared and connected correctly at 9600;
- after Legacy was removed, Windows continued to enumerate COM14 intermittently;
- Mugen attempted to open COM14 while Windows was in the transitional state where the name was visible but `SerialPort.Open()` returned `IOException: Port 'COM14' does not exist`;
- the ordinary failed-open path assigned a 60-second cooldown, so the valid returning Adaptive controller was not retried promptly;
- the same log also showed duplicate `COM14, COM14` entries in port snapshots.

#142 hardens general USB/COM hotplug recovery rather than special-casing firmware switching:

- `Get-PortNames` now sorts and deduplicates the Windows COM list before recovery/new-port logic consumes it;
- a new `Test-IsTransientPortOpenError` classifier recognizes the explicit Windows "port does not exist / cannot find file" hotplug transition in English/Russian exception chains;
- that specific transient state gets a 2-second cooldown instead of the ordinary 60-second failed-open cooldown;
- transient open failures reset accumulated failure state so a just-returning device is not poisoned by an earlier disappearance;
- true `UnauthorizedAccess / access denied / port busy` errors keep their existing long/exponential backoff;
- generic unknown open failures also keep the existing 60-second policy.

CI note: #135-#141 were staging-only patch-construction failures while making the new runtime patch literal-safe. One useful root cause was caught in the patcher itself: .NET regex replacement treats `$_` in replacement text as "the entire input string", so the COM-dedup patch must use the literal block replacer. No failed run produced a user test artifact.

Workflow:

- run **#142**, run ID `35530843054` — SUCCESS;
- built code head `7a2045c2b6769756b3717781af5ea4e47f286481`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-142`, ID `10611700235`;
- outer Actions digest `sha256:1f3fb32de042297ab442512c6f213c454e3211ff3a8b0b5b41e9be8f631e3859`;
- inner program ZIP SHA-256 `fd87ce0a51ab5521ba9772b50f40cfc8c5ba7f8d7ba8bfbc9b83e27b624137a1`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, helper/launcher build, packaging and upload: PASS.

Immediate real-machine #142 check:

1. reproduce the previous switch: Adaptive/XInput ON -> Legacy -> remove Legacy -> return Adaptive;
2. if Windows again briefly reports COM14 but refuses `Open()`, the log should say `transient hotplug state ... retry in 2 s`, not `retry in 60 s`;
3. Adaptive should reconnect on the next short retry without the previous roughly one-minute stall;
4. port lists in recovery diagnostics should not contain duplicate COM names;
5. verify Legacy/Extended still hide and tear down XInput exactly as #134 intended.


## Five real potentiometers fitted -> Nano full-analog prototype

The cardboard controller now has five physical potentiometers fitted. The existing Uno wiring remains useful as the digital-regression fixture, but with the proven 4x8 matrix + encoder pinout the Uno has only A3/A4/A5 free, so it cannot read all five real pots without rewiring already-proven controls.

A dedicated classic Nano firmware was added instead:

- `arduino/MugenDeejCardboardNanoPrototype/MugenDeejCardboardNanoPrototype.ino`
- `arduino/MugenDeejCardboardNanoPrototype/README.md`

The Nano keeps the working digital wiring unchanged and uses:

- P1 -> A3
- P2 -> A4
- P3 -> A5
- P4 -> A6
- P5 -> A7

The firmware exposes the same Adaptive v3 shape, `5 / 28 / 2 / 1` at 115200, but replaces the five software slider placeholders with raw 10-bit ADC reads from the real potentiometers. It intentionally does not smooth or calibrate them yet; first hardware validation should measure real endpoints and idle jitter. The ADC helper discards one conversion after channel switching to reduce mux carry-over without hiding actual pot behavior.

Next hardware check:

1. migrate the proven panel wiring Uno -> classic Nano;
2. wire all pot outer legs to shared 5V/GND and wipers to A3..A7;
3. flash the Nano sketch;
4. confirm Adaptive 5/28/2/1 detection;
5. sweep every pot end-to-end and record min/max plus direction;
6. leave all pots untouched and inspect jitter;
7. exercise pots simultaneously with buttons/toggles/encoder to confirm the full physical panel.


## Nano full-analog first run follow-up -> Integrated #143 slider advanced-toggle guard

The first real Nano + five-potentiometer run reached Adaptive `5 / 28 / 2 / 1` at 115200 successfully. The real analog controls, toggles and encoder were visible to Mugen. Two follow-up findings were separated:

1. all five potentiometers were physically wired in the opposite direction from the user's preferred UI direction; Mugen already has a global `behavior.invertSliders` setting, so no resoldering is required when all channels share the same orientation;
2. the slider-settings `Advanced settings / Дополнительные настройки` section could appear for only a fraction of a second and immediately collapse again on a real machine. The section toggle now rejects duplicate Click events within 350 ms so one physical click cannot open and immediately close the panel.

Workflow:
- run **#143**, run ID `35750634372` — SUCCESS;
- code head `9fdbe72dc5e510359d11ad6f603079d7148ffaa7`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-143`, ID `10705031107`;
- outer Actions digest `sha256:35054aeb7fcdf6fed02256a0df08b962ab7e0d7a20fa0e6bc348ba841b894964`;
- inner program ZIP SHA-256 `3abac4d469c1ebc681f4a4b179eafe530adf3f8389f0729f648bb6740a3400f9`;
- staging, Windows PowerShell 5.1 parse/runtime checks, helper/launcher build, packaging and upload: PASS.

The same hardware session exposed a separate matrix issue around B23: pressing/holding B23 (R4C2) can also appear as B2/B9/B16, i.e. every row in the same C2 column. A first firmware-only row-release settle increase did not eliminate the observed behavior. Do not hide this in desktop software because legitimate same-column multi-key presses are allowed. Next physical check should compare B23 against known-good B24 on the same R4 row and verify B23's local switch/diode/row connection, especially that the diode striped side really reaches R4/A1 and the branch is not accidentally tied to GND. If hardware checks clean, use a dedicated matrix diagnostic sketch before changing generic scan semantics again.


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


## Integrated #146 — PS5-compatible slider Advanced-settings click guard

Real-machine #144 exposed an unhandled WinForms click exception when opening slider Advanced settings. The crash dialog identified the exact cause: `[Environment]::TickCount64` is not available in the Windows PowerShell 5.1 / .NET Framework runtime used by Mugen. The CI parse step could not catch this because the syntax is valid and the missing API is reached only when the Click handler executes.

Fix:
- keep the duplicate-click guard state on the control itself;
- replace `Environment.TickCount64` with `[DateTime]::UtcNow.Ticks`;
- convert elapsed ticks through `[TimeSpan]::TicksPerMillisecond`;
- keep the 500 ms duplicate-click rejection and diagnostics;
- add a CI regression assertion that rejects `Environment.TickCount64` in the staged Windows PowerShell runtime and requires the PS5-compatible DateTime tick path.

Workflow:
- run **#146**, run ID `35754260071` — SUCCESS;
- built code head `d5586e9683017bb92f5c125c973b869f316d67b2`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-146`, ID `10706049321`;
- outer Actions digest `sha256:c8c29131d2a7c552e4f56786c6df56dfd3c170d033364903f3d4a3767721c244`;
- inner program ZIP SHA-256 `4972469509232231df23b2e8746bca0eb2140bd4d1db346f0729c14a4bfbd47b`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

Hardware note from the same session: after the C2/C3 jumper swap plus logical firmware remap, B22/B23 no longer produced the previous whole-column ghost set during the observed test. Treat that as promising real-machine behavior, not a broad matrix redesign; the original matrix itself had already passed on Uno.

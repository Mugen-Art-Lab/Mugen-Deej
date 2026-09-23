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


## Integrated #149 — bind slider Advanced panel to the correct dialog

Real-machine #146 proved that the duplicate-click timer itself was now executing correctly, but the slider Advanced section still visually disappeared. The diagnostic log was decisive: every accepted click reported `visible=True`, never `False`, even across repeated clicks. That means the handler was not toggling the same visible panel the user was looking at.

Root cause: the main window and the slider-settings dialog both used a PowerShell variable named `$advancedPanel`. Because WinForms Click handlers execute later, deferred PowerShell variable resolution could bind the slider Click handler to the main-window diagnostics panel instead of the slider dialog's panel.

Fix:
- rename the slider dialog's panel to `$sliderAdvancedPanel`;
- assign it WinForms name `SliderAdvancedPanel`;
- in the Click handler, resolve the target through `$sender.FindForm().Controls.Find('SliderAdvancedPanel', $true)` rather than a shared PowerShell variable;
- similarly give the slider inversion checkbox and responsiveness combo stable control names and resolve those from the dialog when Save is clicked;
- update the Adaptive topology staging patcher to recognize the renamed slider panel;
- add CI assertions for the named panel and dialog-scoped lookup.

Workflow:
- runs #147/#148 were staging-only failures because the Adaptive topology patcher still expected the old `$advancedPanel.Location` literal; no user artifact from those runs;
- run **#149**, run ID `35755453514` — SUCCESS;
- built code head `5b57c295fd02df5cb80a8a93574a823d56ee66e8`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-149`, ID `10708695236`;
- outer Actions digest `sha256:9f85ce880986c82c32e927338b88c9f71781f4c5d450d034702c1d53e31799c9`;
- inner program ZIP SHA-256 `d4437f6ce1cd1710b0ea190c17e4ff3bdf9f5e3a9ce2959a7965ce0da42f3a7e`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

Immediate hardware/UI check:
1. open slider settings;
2. expand Advanced settings once and confirm its controls stay visible;
3. collapse and reopen it;
4. enable global slider inversion and Save;
5. confirm all five real pots now move in the preferred direction.


## Integrated #152 — fix slider Save crash and separate Advanced layout

Real-machine #149 finally kept the slider Advanced section open, confirming the dialog-scoped panel lookup fix. Two follow-up issues remained:

1. clicking Save after enabling global slider inversion threw `Variable "$sender" cannot be retrieved because it has not been set`;
2. the expanded Advanced controls sat too tightly against the section toggle/action row and looked visually overlapped/crooked.

Root cause of the Save crash: #149 changed Save to resolve named Advanced controls through `$sender.FindForm()`, but the `$saveButton.Add_Click` scriptblock had no `param($sender, $eventArgs)` declaration. Under StrictMode the deferred WinForms handler therefore had no `$sender`.

Fix:
- bind `param($sender, $eventArgs)` explicitly in the slider Save Click handler;
- keep dialog-scoped lookup for `SliderInvertAllCheck` and `SliderResponseCombo`;
- move the expanded Advanced card to `$advancedY + 46` (12 px below the 34 px toggle);
- move the action row to `$advancedY + 172`, leaving a clean gap below the 112 px Advanced card;
- increase the base slider-settings dialog height so the normal five-slider layout fits without the panel/action overlap;
- update the Adaptive topology staging patcher to the new source anchors;
- add CI assertions for Save sender binding and the expanded-layout geometry.

Workflow:
- runs #150/#151 were intermediate branch builds while the source and staging patcher were being aligned;
- run **#152**, run ID `35756930169` — SUCCESS;
- built code head `25145a413f17123852dd99d8dbba0315f3d7d8cd`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-152`, ID `10708472819`;
- outer Actions digest `sha256:e0c20d32e33b7b1803f28351c1a0556f3fb121735e85456b7262387ba10991ea`;
- inner program ZIP SHA-256 `fee9cc30c4c6496d644d89b61be871c53adc26f2dfba6a90efa18c1f9adef527`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

Immediate real-machine check:
1. open slider settings;
2. expand Advanced settings and confirm the card is visually separated from the toggle and Save/Cancel row;
3. enable global slider inversion;
4. click Save — no JIT exception;
5. reopen slider settings and confirm inversion remained checked;
6. verify all five physical Nano potentiometers now move in the preferred direction.


## Integrated #155 — slider Advanced layout host

Real-machine #152 confirmed the functional part of the analog-settings path:

- the Advanced section opens;
- global slider inversion saves successfully;
- reopening/running the app shows the five physical Nano potentiometers moving in the preferred direction.

The remaining issue was visual: the Advanced controls were rendered underneath/behind the section toggle, even though their calculated top-level coordinates were intended to be below it. The normal five-slider dialog also still enabled Form.AutoScroll through the dynamic topology patcher, which was unnecessary and made this nested layout more fragile.

#155 changes the structure rather than adding another coordinate tweak:

- add a single top-level `SliderAdvancedHost` panel;
- parent the Advanced toggle at `(0,0)` inside that host;
- parent `SliderAdvancedPanel` at `(0,46)` inside the same host;
- move only the host as a unit after the dynamic slider rows;
- keep the action row at `advancedY + 172`;
- enable Form.AutoScroll only when more than five analog controls are actually present;
- update the Adaptive topology staging patcher and CI assertions to enforce this parent/child structure.

Workflow:
- run **#155**, run ID `35757909957` — SUCCESS;
- built code head `53e469ac6a2daf63df6626e5777b5fe4535161d9`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-155`, ID `10708579398`;
- outer Actions digest `sha256:36584e85d675d9b0bec5267cb9650c9363879de18b1cbac6ea4e600e85033724`;
- inner program ZIP SHA-256 `d39ce76bba887f30827a902741e7f22bf1518cd2aca2234883e5782bd3848d14`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

Immediate real-machine check:
1. open slider settings;
2. expand Advanced settings;
3. verify the checkbox, responsiveness selector/help and config button are visibly below the section toggle rather than underneath it;
4. collapse/reopen once;
5. confirm the already-proven slider inversion setting remains saved and the five live pot readings remain correct.


## Integrated #160 — always-visible slider Advanced card

Real-machine #155 exposed that the collapsible Advanced control itself was still unstable: on opening the slider settings dialog, the Advanced arrow/button could appear briefly and then disappear before it was usable. The run log showed no Advanced click event at all, confirming this was a layout/visibility problem during dialog initialization rather than another duplicate-click issue.

The analog editor only has three secondary controls (global inversion, responsiveness, open config), so the collapsible UI was removed entirely instead of adding more timing/layout special cases.

#160:
- removes the Advanced show/hide toggle and its click debounce path;
- renders a permanent `MugenCardPanel` named `SliderAdvancedPanel` below the physical-slider rows;
- shows global inversion, responsiveness, hint text and Open config inside that card at all times;
- keeps Save using dialog-scoped named lookup for the inversion/responsiveness controls;
- dynamic topology code moves the card as one unit below however many slider rows are detected;
- Save/Cancel sit below the card;
- normal five-slider layout avoids unnecessary AutoScroll;
- obsolete collapse-related CI assertions were removed and replaced with checks for the permanently visible card.

Workflow:
- runs #156-#159 were intermediate CI/staging assertion failures while removing the old collapsible contract; no user test artifact should be used from them;
- run **#160**, run ID `35759260556` — SUCCESS;
- built code head `081751cda7395c232f45bd6c78471660f1ebc969`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-160`, ID `10709081360`;
- outer Actions digest `sha256:50ff2c5988aa4f59e10d10b7790d9489af715df7ed766381aaf1879df98dcdca`;
- inner program ZIP SHA-256 `866891dd1422284d228e0e5187945e422d2e83c3bab16aa4415505ff3101d645`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

Immediate real-machine check:
1. open slider settings;
2. the Advanced card must already be visible — no arrow/button and no show/hide animation;
3. confirm inversion remains checked from the prior successful save;
4. verify the five live pot positions still update;
5. Save once more and reopen to confirm persistence/regression.


## #160 real-machine PASS — five live Nano potentiometers + stable analog settings UI

Real-machine validation on 2026-09-22 passed the #160 analog-settings milestone.

Observed on the user's physical cardboard Nano controller:

- Adaptive controller detected as `5 sliders / 28 buttons / 2 toggles / 1 encoder` at 115200;
- all five real potentiometers report live positions in the slider settings UI;
- the always-visible Advanced settings card renders correctly below the five slider rows;
- global slider inversion is persisted and active;
- Save completes normally with no JIT/StrictMode exception;
- reopening/saving slider settings remained stable in the recorded session;
- encoder rotation and push events continued to register during the same session;
- button events remained clean in the sampled matrix pass, including the formerly problematic B23 path.

This is the first real-machine PASS where the five Adaptive slider channels are backed by physical potentiometers rather than software placeholder values.

Keep #160 as the current hardware-reviewed application build. The Nano firmware with the working C2/C3 physical jumper arrangement remains the active prototype firmware.


## Integrated #175 — Adaptive T1/T2 control layers candidate

The first implementation of toggle-driven layers is now packaged for real-machine testing.

Feature scope:
- Adaptive v3 only;
- T1/T2 can independently be enabled as layer modifiers;
- layer states: Base, T1, T2, T1 + T2;
- button mappings can override the base action per layer, with explicit Inherit and Do nothing choices;
- encoder CW / CCW / push can also be overridden per layer;
- application-profile context remains part of layer resolution, so overrides can be Global or profile-specific;
- active layer is shown in the live Adaptive toggle status when modifier mode is enabled;
- modifier toggles suppress their ordinary ON/OFF action while acting as modifiers.

Compatibility contract:
- Legacy/Extended do not enter layer resolution; their existing flat/profiled button path is preserved;
- Adaptive packet processing updates toggle state before same-packet button/encoder edges so a newly selected layer is used immediately;
- virtual Xbox output treats a layer switch as a profile/context boundary so held virtual mappings are neutralized and suppressed until release rather than morphing into the new layer;
- layer data is stored separately in `adaptive-layers.json`, leaving the established button action/profile files intact.

Build history:
- #161-#169 were staging/anchor failures while fitting the new layer patch into the current patch chain;
- #170 reached green CI for button layers;
- #171-#175 extended the same layer model to encoder CW/CCW/push and hardened the editor event state;
- run **#175**, run ID `35766695670` — SUCCESS;
- built code head `09a69e734b7014235de653c17f7ba6632d01c2cc`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-175`, ID `10712008968`;
- outer Actions digest `sha256:185870016e0f3d575c0bcee5895d5be4fc1f5843e35cea9a1b1746c15b30d1b2`;
- inner program ZIP SHA-256 `868ac0da396ae63413e411078e1850632a613d1d7586dcb427c7fdb68daed6fa`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

This is a CI candidate, not a hardware PASS yet. Real-machine testing should explicitly include Adaptive layer behavior plus Legacy and Extended regression checks.


## Integrated #180 — fix nested layer-dialog state collision + typed-settings layout

Real-machine #175 exposed a WinForms timer exception when opening **Control layers** from the toggle/encoder settings dialog:

- `PropertyNotFoundException: LastToggles`;
- the parent toggle/encoder settings timer expected its own state object with `LastToggles`;
- the nested layer editor also used a generic PowerShell variable named `$state`;
- deferred WinForms event execution resolved the parent's timer against the nested button-layer state object, which only had `LastButtons`.

Fix:
- rename the nested layer editor state to `$layerButtonState` throughout the layer dialog so it cannot shadow the parent typed-control editor state;
- keep the already-isolated layered-encoder dialog event state;
- rework the toggle/encoder settings header layout:
  - profile explanation gets its own full-width row;
  - **Control layers…** becomes a separate feature row below the profile controls rather than being glued beneath **Add…**;
  - add a short layer-purpose hint beside the button;
  - shift the physical-control selector/editor groups and Save/Cancel down together;
  - enlarge the fixed dialog height accordingly.

Compatibility remains unchanged:
- toggle layers are still hard-gated to Adaptive v3;
- Legacy/Extended retain the established flat/profiled mapping path and do not enter layer resolution.

CI history:
- #176 built the runtime fix successfully;
- #177-#179 were CI-assertion-only failures while hardening checks for the new layout (runtime staging itself was successful);
- run **#180**, run ID `35773465992` — SUCCESS;
- built code head `8041ee5319027db959b2e99e4c356578d558845a`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-180`, ID `10714269507`;
- outer Actions digest `sha256:aec2a91ff587389d01332dc60910fae965ce9f4e8c47f8627431d3f0e8fc7ad1`;
- inner program ZIP SHA-256 `dc8eebd5e5418a8e165c82fe9f99bcffcb7e817d11c9537126ab8e052dd941e7`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#180 is a hardware-review candidate; #160 remains the last full hardware-passed baseline until layer behavior is exercised on the real panel.


## Integrated #183 — custom names for Adaptive control layers

Adaptive layer names are now user-editable instead of being fixed to Base/T1/T2/T1+T2.

Behavior:
- Control layers dialog contains a dedicated **Layer names / Имена слоёв** section;
- Base, T1, T2 and T1+T2 each have an editable name (24 characters max);
- unchanged defaults remain localization-aware instead of being permanently written as translated strings;
- custom names persist in the existing version-1 `adaptive-layers.json` as an optional `names` object, so older layer files without names still load unchanged;
- custom names are used by the button-layer selector, live layer preview, modifier-toggle labels, main live toggle status, transition logs, and the layered encoder selector;
- encoder layer settings opened before Save receive the current unsaved names from the parent layer dialog;
- Legacy/Extended remain hard-gated out of Adaptive layer resolution and are unaffected.

Workflow:
- #181 successfully built the feature implementation;
- #182 failed only on an over-specific CI localization assertion;
- run **#183**, run ID `35776040340` — SUCCESS;
- built code head `6459579e4bc9236debd0ba76f48b996d2d3630d8`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-183`, ID `10716281843`;
- outer Actions digest `sha256:2c65daa50e159679442c5e04ccde7c97390d0fe184cf957737edff5489e24372`;
- inner program ZIP SHA-256 `755c88d3763695cbea3b9869269093d590ca70b64dd459ec7c091fbcd3e9d6f9`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#183 is the next hardware-review candidate. Suggested first naming test: Base=Основной, T1=Стрим, T2=Игра, T1+T2=Система; Save, reopen, then verify the same names appear in button layers, encoder layers and the live active-layer label.


## Integrated #185 — multi-monitor popup on Adaptive layer changes

Adaptive control layers can now show a non-activating popup when T1/T2 changes the active layer.

Notification settings are stored in the existing optional Adaptive layer config and include:
- enabled/disabled;
- show above other windows;
- target monitor by stable WinForms device name;
- nine working-area anchors (top/middle/bottom × left/center/right);
- duration from 0.5 to 10 seconds;
- a Test notification action.

Implementation details:
- a dedicated `MugenLayerPopupForm` uses `ShowWithoutActivation` plus `WS_EX_NOACTIVATE` / `WS_EX_TOOLWINDOW`, so the layer OSD should not steal focus from the active application;
- positioning uses `Screen.AllScreens` and the selected display's `WorkingArea`, avoiding taskbars;
- if the saved display disappears, the popup falls back to the primary display;
- switching layers replaces any existing popup instead of stacking multiple OSDs;
- the popup shows the configured custom layer name (or the localized default when no custom name exists);
- the notification settings dialog is opened from the Control layers window and uses that dialog's working config, so Cancel/Save semantics stay consistent with the rest of layer editing;
- actual notifications are still Adaptive-only because the layer-transition path is hard-gated away from Legacy/Extended.

Workflow:
- run **#185**, run ID `35855451141` — SUCCESS;
- built code head `45c6bf29b18bc317fa3a4393889164fd1fe08199`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-185`, ID `10747820174`;
- outer Actions digest `sha256:399c6be1de6ec50dcab428c653642f91ff0e044e0c98e5fb11d6b88c4a3df93d`;
- inner program ZIP SHA-256 `977cd9f3e936d9881f29c640c4a1bb842ce60dc56ef7b75ca8dd7c1a936ba60a`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, windowing Add-Type compilation, launcher/helper build, packaging and upload: PASS.

#185 is a hardware/UI review candidate. Real-machine acceptance should test the popup on each connected display, at several anchors, with a custom layer name, and verify that it does not take focus from a foreground application.


## Integrated #188 — layer UI clarity + notification entry point repair

Real-machine #185 exposed three UI/UX issues while the underlying layer runtime itself was working:

1. the active layer name was appended to the narrow **Toggles / Тумблеры** label in the compact main status card, causing the text to wrap/clip and visually displace the heading;
2. a toggle configured as a layer modifier still looked like a normal toggle with editable ON/OFF mappings in the typed-control settings, even though runtime intentionally suppresses those ordinary actions while modifier mode is enabled;
3. the new Notifications button was accidentally inserted into the notification-settings dialog itself (and clipped off-screen) instead of into the Control layers dialog, so the user had no visible entry point.

The real-machine log confirmed the intended modifier semantics: Toggle 1 ON/OFF transitions were detected, ordinary actions were explicitly suppressed, and the layer changed Основной -> Тест -> Основной.

#188 fixes:
- main status now keeps **Тумблеры / Toggles** untouched and creates a separate full-width **Активный слой / Active layer** row in the physical-input card;
- the compact main layout reserves 24 px for that row only while Adaptive layers are enabled;
- typed toggle settings detect modifier toggles, disable their ordinary ON/OFF action combos, and explicitly explain that the toggle is being used as a layer modifier;
- live state text also marks a selected modifier toggle as such;
- encoder selection restores the normal encoder help text and enabled action controls;
- **Уведомления… / Notifications…** now exists exactly once, in the Control layers dialog header;
- the accidental recursive/clipped button inside the notification-settings dialog was removed.

Compatibility remains unchanged: all layer/modifier UI and behavior are Adaptive-only; Legacy/Extended stay on the established flat/profiled path.

Workflow:
- run **#188**, run ID `35858096113` — SUCCESS;
- built code head `c479c70fc6074ebfb23e4c2ab2f0797c224ce1f7`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-188`, ID `10747704178`;
- outer Actions digest `sha256:5cc358b5c8655f78735c3ac5c9ab889729f05a94180a776b66822134db7485e5`;
- inner program ZIP SHA-256 `c16c815acffd86f858287a2d5cf9693c22335ea4d83fe40ec96c6bf513c4f393`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#188 is the next hardware/UI review candidate. Check main active-layer row, modifier-toggle explanation/disabled ON/OFF mappings, visible Notifications entry point, and popup positioning/focus behavior.


## Integrated #190 — fix startup StrictMode regression from active-layer status UI

Real-machine #188 failed immediately at startup under StrictMode with:
`Variable "$script:LayerStateLabel" cannot be retrieved because it has not been set.`

Root cause:
- #188 added a new script-scoped active-layer status label and checked it during initial UI layout;
- under StrictMode, reading an undeclared variable is an immediate fatal error even when the code only intends to compare it with `$null`;
- the same latent problem also existed for the new layer-popup form/timer variables, which would have failed on the first notification close/show path.

#190 fixes the runtime-state contract by initializing all new script-scoped layer UI state up front:
- `$script:LayerStateLabel = $null`;
- `$script:AdaptiveLayerPopupForm = $null`;
- `$script:AdaptiveLayerPopupTimer = $null`.

CI now explicitly asserts those declarations exist in the staged runtime so future optional UI state does not regress under StrictMode.

Workflow:
- run **#190**, run ID `35859809283` — SUCCESS;
- built code head `495a1c2965f46a57cb4247c18187dc2d854f091b`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-190`, ID `10749991039`;
- outer Actions digest `sha256:ce28b06ca8b26536ecb35f4e18fd11ad892ea9333f5dec6107bc210b330995b8`;
- inner program ZIP SHA-256 `10f2beb33467d76ec816ab8c6c9aa5e6217de256e0798d2f897b617a2d831419`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#190 is a hardware/UI review candidate. First acceptance is simply that the app starts normally; then resume #188 checks for active-layer row, modifier-toggle explanation, Notifications entry point, and popup behavior.


## Integrated #194 — layer UI polish after #190 real-machine review

Real-machine #190 confirmed that the layer feature is now broadly alive on the physical Nano panel:

- Adaptive controller remained detected as 5 sliders / 28 buttons / 2 toggles / 1 encoder;
- T1/T2 modifier roles persisted;
- custom layer names appeared in the editor;
- physical toggle transitions selected the expected layers (including combined T1+T2);
- the multi-monitor notification settings dialog opened and Test notification rendered on the selected display;
- the typed toggle editor correctly disabled ordinary ON/OFF actions for modifier toggles;
- physical button presses in the Control layers dialog auto-selected the corresponding button editor.

The same review exposed cosmetic/usability issues:
- black rectangular corners remained behind the rounded layer popup;
- several owner-drawn combo boxes visually lost the left/top border;
- physical button presses changed the selected editor button but the tile itself did not light up while held;
- toggle/encoder guidance text remained wordy/awkward.

#194 fixes:
- clip the notification Form itself to the same 14 px rounded geometry as the popup card;
- draw MugenComboBox borders one pixel inside the native client area so left/top strokes are not half-clipped by Win32;
- add live physical-button tile feedback in Control layers: held button = accent fill; current editor selection = accent border/subtle hover fill;
- shorten/clarify modifier-toggle and encoder help text;
- clarify the top Toggle/Encoder settings hint with distinct normal-toggle, modifier-toggle and encoder roles.

The MugenComboBox change is visual-only and shared by all protocols; no mapping/protocol logic changed. Adaptive layer behavior remains hard-gated away from Legacy/Extended.

Workflow:
- run **#194**, run ID `35862946664` — SUCCESS;
- built code head `0e284a1dc4f43c87802bec8b3de7ede571388d77`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-194`, ID `10750703940`;
- outer Actions digest `sha256:88239ee2abba4fa1ab62e2bd8df541c7027ce2bd059b4a8ef64cfbcbec7e3f85`;
- inner program ZIP SHA-256 `406514d6ad5b02055f6877e96a5d7c0a033dfc3b424b04e11fd1d18f27a5a594`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, windowing Add-Type compilation, launcher/helper build, packaging and upload: PASS.

#194 is the current layer hardware/UI review candidate. Recheck popup corners, combo borders, held-button highlighting and the revised typed-control text.


## Integrated #196 — stabilize layer button feedback, combo borders and popup sizing

Real-machine review of #194 on 2026-09-23 found three follow-up UI defects while the underlying Adaptive controller path remained healthy:

- the currently selected / physically pressed button tile in **Control layers** visibly flickered;
- owner-drawn MugenComboBox borders still appeared uneven from different sides, including the layer notification settings dialog;
- the 24-character layer-name limit was acceptable, but a legal long name could still be ellipsized by the fixed-width layer popup.

The supplied runtime log for that review showed the Nano prototype detected cleanly as Adaptive `5 sliders / 28 buttons / 2 toggles / 1 encoder` on COM5 at 115200, with normal press/release pairs and no application exception in the captured session.

#196 changes:

1. **Layer button tiles no longer repaint on every 40 ms timer tick.** A per-tile visual-state cache now reapplies theme only when the tile actually changes between normal / selected / pressed, or when the effective application theme changes. This targets the #194 flicker directly.
2. **MugenComboBox borders now use four exact 1 px filled edge strips** instead of `DrawRectangle`. This avoids half-stroke clipping/asymmetry from the native Win32 ComboBox client boundary.
3. **Layer popup width is measured from the accepted display name.** The existing 24-character input/storage limit is intentionally preserved, but the popup now grows to fit legal long names within a bounded width and the selected monitor's working area.

CI history:

- run **#195**, run ID `35865272887` — FAILED only in the new static repaint-cache assertion; staging itself succeeded. The runtime change was present, but the regex incorrectly represented the two literal quote characters in `@('')`.
- commit `fffb929ed4a1064438b21bba5475a79558d18817` fixes that CI assertion quoting without changing the intended runtime behavior.
- run **#196**, run ID `35866181491` — **SUCCESS**;
- built code head `fffb929ed4a1064438b21bba5475a79558d18817`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-196`, ID `10752389211`;
- outer Actions digest `sha256:4de8f0fa73e62f8a5a496311a714aa4b47e1815e268bcf16988ae87cb1ded669`;
- inner program ZIP SHA-256 `f384a3fc9f4f1aa75b78178a5f249aebbedfee25abaaf6fca426dc0aacc2a335`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#196 is the current layer UI hardware-review candidate. Recheck:
- selected and held button tiles for flicker;
- combo-box edge consistency in both Control layers and Notifications;
- a maximum-length custom layer name in the popup;
- popup rounded corners and no-focus-steal behavior from the prior review.

### Development handoff convention

For this branch, user-facing test builds should only be handed over after the corresponding GitHub Actions integration run finishes green and the built artifact is downloaded/verified. Continue recording each meaningful real-machine finding, failed/intermediate CI run, green replacement build, artifact ID and hashes in `docs/CURRENT_HANDOFF.md` and `docs/PROJECT_STATE.md` so a fresh chat can resume from the repository alone.


## Integrated #200 — modal input safety + typed-control/layout follow-up after #196

Real-machine review of #196 on 2026-09-23 confirmed the layer notification popup itself is now correctly rounded, but exposed another set of UI/behavior findings:

- the two-line explanatory text at the top of **Toggle and encoder settings** was too long for its fixed label and clipped on the right;
- **Notifications…** in Control layers shows an ellipsis. This is intentional Windows-style UI punctuation because the button opens a separate dialog, consistent with other Mugen Deej buttons such as Add… and Layered encoder…;
- the **Layer** and notification-settings MugenComboBox controls still showed visibly uneven edge/border thickness despite the #196 1 px client-edge strips;
- layer button override testing gave the impression that a held physical button was being released. The supplied log does *not* show a physical-input fault: Button 1, Button 2 and Button 3 each remain physically down for substantial intervals before a single release edge. This means the Nano/serial input is preserving held state. Ordinary mapped actions in Mugen Deej are intentionally one-shot on the press edge; virtual Xbox/XInput mappings are the stateful mappings that must remain held with the physical button. The layer editor now states this explicitly so the two semantics are not confused;
- a more important safety issue was identified: pressing controls while an assignment/settings dialog is open must be allowed to select/show the physical control in the editor, but must **not** simultaneously execute the already assigned hotkey/program/command/etc.

The review log again detected the physical Nano cleanly as Adaptive on COM5 at 115200 with topology `5 sliders / 28 buttons / 2 toggles / 1 encoder`.

#200 changes:

1. **Modal input-action safety gate**
   - added `Test-MugenInputActionsSuspended`, which reports true while a modal Mugen Deej form is open;
   - ordinary physical button actions now stop at the dispatch boundary while such a dialog is open, while raw button state and editor auto-selection continue updating;
   - Adaptive toggle/encoder mapped actions use the same safety gate;
   - this intentionally does not freeze analog slider positions: those remain live, matching the existing physical-input UI contract.

2. **Stateful virtual Xbox safety**
   - while a modal Mugen dialog is open, XInput output is neutralized and no held virtual button/axis state is emitted;
   - any physical buttons still held when the dialog closes remain suppressed until their physical release, preventing a control used to select an item in the editor from suddenly firing when the window closes;
   - after the modal window closes, normal XInput state reconciliation resumes.

3. **Toggle/encoder explanatory copy**
   - shortened the top help text to a compact two-line form that fits the existing layout;
   - no dialog-size growth was needed.

4. **Layer override semantics**
   - the layer editor now explicitly distinguishes regular actions (one execution per press) from Virtual Xbox mappings (state follows the physical hold).

5. **MugenComboBox border rendering**
   - #196 painted exact 1 px strips through `CreateGraphics()`, but that only addressed the ComboBox client DC while Windows could still leave pieces of the native non-client rim visible;
   - #200 now paints the complete native ComboBox window surface through `GetWindowDC` / `ReleaseDC` after native WM_PAINT / WM_NCPAINT, then draws the same exact 1 px border strips. This is the next real-machine test for the uneven-edge defect.

CI history for this change set:

- run **#197**, run ID `35868866613`, head `50477ec33a26392e80ca67d8fea7f321e668f339` — FAILED after staging because a newly added CI assertion embedded Cyrillic UI text in a Windows PowerShell 5.1 workflow script and was mojibaked into invalid syntax. Runtime source was not the cause.
- run **#198**, run ID `35869316188`, head `a4fd0c4e23f700ebc4dfa258b60258abd9025846` — FAILED a static assertion because the modal XInput marker was incorrectly checked in staged runtime text instead of the virtual-gamepad integration module.
- run **#199**, run ID `35869532155`, head `e620db0cad3e5ded3a00ba1556af4a29f5cef558` — FAILED the same static assertion because `$integrationText` was checked before that module had been loaded by the workflow.
- run **#200**, run ID `35869727173` — **SUCCESS**;
- built code head `297de89bfaf38c41d0f2df895f2edae2c8bcba20`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-200`, ID `10754665659`;
- outer Actions digest `sha256:9a4bf995fa7eb243f318e43d3ebd175ebae20dc1035db2b6208474d7ebe7d0ba`;
- inner program ZIP SHA-256 `3d0688e7830de4c94c5d350095d8f7aa494a0e3e69672fc08bd2c42f0f9de7e1`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and artifact upload: PASS.

#200 is the current layer/UI hardware-review candidate.

Real-machine acceptance for #200:
- verify the compact Toggle/Encoder explanation is fully visible;
- recheck ComboBox border thickness on the Control layers **Layer** selector and all notification-settings combos;
- confirm **Notifications…** continues to open the separate notification dialog (ellipsis is intentional);
- while Button/Toggle/Encoder settings or Control layers is open, press controls that already have side-effect assignments and confirm they still select/update the UI but do not launch programs, send hotkeys, run commands, or produce XInput;
- close a dialog while a physical button is still held and confirm the held control does not fire immediately on close; it should become eligible again only after release and a new press;
- for a layer button mapped to Virtual Xbox, confirm that outside settings it stays held for exactly as long as the physical button; ordinary non-Xbox actions are expected to execute once on the press edge.


## Integrated #202 — held physical button now remains visibly held in Control layers

A follow-up clarification after #200 isolated the reported "button releases itself" symptom to the **Control layers editor UI**, not to action execution or the physical input state:

- in the normal physical-button action editor, pressing a hardware button selects it and the tile stays accent-filled for the entire physical hold;
- in Control layers, the same physical press selected the button but the accent fill only flashed briefly, then disappeared even while the button was still physically held.

This distinction is important: it confirms the raw `$script:LatestButtons` held state is available and the defect is specifically in the layer editor's visual refresh path.

Root cause/fix direction:
- #196 introduced a derived per-tile visual-state cache to stop the earlier 40 ms repaint flicker;
- that cache could remain at a logical `pressed` key even after another WinForms/theming repaint had restored the tile's visible colors, so subsequent timer ticks skipped the repaint and the held indication appeared to vanish;
- #202 removes that derived visual-key cache;
- each 40 ms layer-editor tick now derives the desired fill/text/border directly from the current raw physical state and selected index;
- to avoid reintroducing the old flicker, it changes a tile property only when the actual color differs from the desired color. Thus the refresh remains idempotent while a held button is continuously revalidated.

Expected layer-editor behavior now matches the normal button editor:
- physical hold => accent fill remains for the entire hold;
- selected button => accent border remains independently of held state;
- release => fill returns to normal while selection border stays on the selected button.

CI:
- run **#201**, run ID `35872122953`, head `b36ec287b31947f6acdd4edf57bbaa7c84c8f26b` — FAILED only because the previous CI still required the now-removed visual-state cache; staging succeeded;
- run **#202**, run ID `35872128306` — **SUCCESS**;
- built code head `c4969766a82e352d9d65dc5b1d46c87d06e73e97`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-202`, ID `10755203600`;
- outer Actions digest `sha256:a08846faa88115b3a67a3948a5e19c234269601f987960fe575206b67209d54b`;
- inner program ZIP SHA-256 `4fb97c45235f38f46386ad6cd49d11d853d0f303e224985630268c5353ebc138`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#202 supersedes #200 as the current focused layer/UI hardware-review candidate. The immediate acceptance check is simply to open Control layers, press and hold several physical buttons, and confirm each selected tile remains accent-filled until the physical release without flickering.


## Integrated #203 — move Control-layers button state into MugenButtonTile painting

Real-machine review of #202 showed that its property-level fix still did not eliminate the visual race in **Control layers**:

- the last selected button's accent border continued to flicker;
- while a physical button was held, the full accent-filled pressed state also flickered;
- screenshots captured both the selected-only state and the pressed accent-fill state, confirming the editor was alternating visual presentation rather than losing button selection entirely.

#202 had already removed the stale derived-state cache and only changed BackColor/ForeColor/BorderColor when their actual values differed. That was still not robust enough because those public control colors can be repainted/reset independently of the layer editor's semantic selected/pressed state.

#203 changes the model instead of trying another timer-side repaint workaround:

1. `MugenButtonTile` now has an internal semantic-state renderer for selected/pressed tiles.
2. The Control-layers editor feeds the raw `$script:LatestButtons` held state plus the selected index into `ApplySemanticStateTheme(...)`.
3. `MugenButtonTile.OnPaint` chooses fill/text/border from that internal semantic state:
   - normal = normal control surface;
   - selected = normal fill + accent border;
   - pressed = accent fill + accent text + accent border.
4. `ApplySemanticStateTheme` invalidates only when the semantic state or palette actually changes. The 40 ms polling timer can therefore call it continuously without forcing a repaint every tick.
5. Because the semantic state is owned by the tile's painter rather than inferred from mutable BackColor/BorderColor values, unrelated WinForms invalidations can repaint the control without temporarily losing the selected/pressed appearance.

Workflow:
- run **#203**, run ID `35873511506` — **SUCCESS**;
- built code head `d027a7ef974e387677dccc2d315512e61353d7ef`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-203`, ID `10756505480`;
- outer Actions digest `sha256:ff88663a62c1989a647b2ca398c3cf53cc427536f86439ef76794607214d1e63`;
- inner program ZIP SHA-256 `a892a715c26187402ffb47381c39753ee89bfc84780acbc5d4cbcc72c43ae93e`;
- downloaded artifact hash matches the packaged `.sha256` file;
- staging, Windows PowerShell 5.1 parse/runtime assertions, windowing C# compilation, launcher/helper build, packaging and upload: PASS.

#203 supersedes #202 as the current focused layer/UI review candidate.

Immediate acceptance check:
- open Control layers and leave a button selected without touching hardware: its accent border must remain perfectly steady;
- press and hold that or another hardware button for several seconds: the accent-filled pressed state must remain perfectly steady for the entire hold;
- release: the fill returns to normal and the selected button's accent border remains steady.


## Integrated #204 — refresh parent Toggle/Encoder editor immediately after layer-role save

Real-machine review of #203 confirmed the semantic tile-painting fix: **Control layers button selection and physical hold indication now behave correctly without the previous border/fill flicker.**

The same test also validated the actual four-layer button-routing path with one physical button:
- Base mapping executed the Slider 1 action;
- T1 / custom layer “Стрим” executed the Slider 2 action;
- T2 / custom layer “Игры” executed the Slider 3 action;
- T1+T2 / custom layer “Разработка” executed the Slider 4 action;
- returning modifiers to OFF restored the Base mapping.
The runtime log also shows modifier toggles suppressing their ordinary ON/OFF actions while changing the active layer.

A small parent-dialog synchronization bug remained:
1. Open **Toggle and encoder settings**.
2. Open **Control layers…**.
3. Enable T1/T2 as layer modifiers and click Save.
4. Return to the parent Toggle/Encoder editor.
5. For a short time the selected toggle could still show enabled ON/OFF action ComboBoxes and its old non-modifier description; another interaction later refreshed it and disabled those controls.

The layer config itself was already applied immediately by `Show-AdaptiveLayerSettings`; only the parent editor was stale. The injected Control-layers button handler previously called only `Show-AdaptiveLayerSettings`, while the modifier-aware state of the parent is recalculated by its `$refreshEditor` closure.

#204 fix:
- after the Control layers child dialog closes, the parent handler now immediately runs `$refreshEditor` and `$refreshAssignmentList`;
- therefore a newly enabled modifier should instantly show its modifier heading/role text and disabled ordinary ON/OFF ComboBoxes on return to the parent window;
- disabling a modifier should likewise restore the ordinary action controls immediately;
- no save/persistence semantics were changed: Control layers continues to save its own layer config when its Save button is pressed.

CI:
- run **#204**, run ID `35876423203` — **SUCCESS**;
- built code head `b586958580b862d49f45510ba6bceeaff7eefb68`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-204`, ID `10756289241`;
- outer Actions digest `sha256:d14c328aaef1f43c67580a3fda6a8c24892ab85cadeb56d19f7800b87b1841c9`;
- inner program ZIP SHA-256 `d5c3951089f0dd3dae10fd1a80a0710a439a4267a089c13c9141f0abc33f9ba1`;
- downloaded artifact digest and packaged inner `.sha256` agree;
- integration staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#204 is the current focused UI candidate. Immediate acceptance:
- from Toggle/Encoder settings open Control layers;
- change T1/T2 modifier checkboxes and Save;
- on returning to the parent window, the currently selected toggle must immediately switch between ordinary ON/OFF editing and modifier-role disabled controls without requiring any extra click, physical toggle movement, profile change, or timer-triggered selection.


## Integrated #208 — configurable layer-popup opacity

User requested a transparency control for the layer-change OSD and then chose **50% as the default**.

Implementation:
- notification config now persists `opacityPercent`;
- default for configs that do not yet contain the field is **50**;
- accepted range is **20..100%**, step 5 in the NumericUpDown UI;
- WinForms popup applies it through `Form.Opacity = opacityPercent / 100.0`;
- the notification settings dialog exposes the value on the same row as the Test notification button;
- Test notification reads the current unsaved opacity value, so opacity can be previewed before Save;
- existing notification configs remain compatible: missing `opacityPercent` normalizes to the new 50% default;
- Russian UI label was clarified to **«Непрозрачность, %»** so 100% unambiguously means fully opaque / 50% means half-transparent.

Build progression:
- #205, run ID `35877362618`, head `e288bc23cece65562cd72315d1cd8fd9df413195`: initial opacity implementation, initially used 100% default; SUCCESS.
- #206, run ID `35877591036`, head `d80dc80b1e989c14e647c4b20e6c1bd0297edf5c`: changed runtime default to 50%; SUCCESS.
- #207, run ID `35877598863`, head `482e4c8d8cfbd0e6b8873b521b17e5cbd2540d6a`: CI expectation updated to 50%; **SUCCESS**. Artifact ID `10759821067`, outer digest `sha256:fc7124106536870b4eab5a1410b361d9cb72cd334b2ad3dcbc9b8882207865c5`, inner ZIP SHA-256 `17d072f22fc62c5b6af69e7ec69e9a40d93150d2f045e906ed8b34021df4c226`.
- #208, run ID `35878075515`, head `d9292a028ae4aeee5923096b3fef0968d434dad5`: cosmetic RU label clarification only. The workflow job reported `completed/success`, packaged/uploaded artifact ID `10759491804`, outer digest `sha256:795ef56682845abb633b923851e1d8c3aa97687d169433890b2aba35b253314d`; downloaded inner ZIP hash `7a1447112b49996e4ce678380aeb9da3ccdfaf098654d1a93a50167895f2e104` matches the package's own SHA-256 file. The connector's top-level run object was still lagging at `in_progress` while the job and artifact were already complete, so preserve that distinction in future handoffs rather than claiming a top-level conclusion that was not observed.

Current source head includes the opacity feature plus the clarified label. For real-machine review verify:
- a pre-existing layer config with no opacity field opens at 50%;
- 20%, 50% and 100% visibly correspond to strongly transparent, half-transparent and opaque OSD;
- Test notification reflects the value before Save;
- Save/reopen persists the selected opacity;
- rounded popup geometry remains intact at partial opacity.


## Integrated #209 — rebuild layer OSD as true per-pixel-alpha window

Real-machine review of the new 50% OSD opacity exposed that the old rounded geometry was only superficially smooth at full opacity. At partial opacity the popup corners/edge became visibly clipped/jagged ("обкусанная"): the previous implementation combined a normal WinForms form, a rounded child card, `Form.Opacity`, and a hard `Region` clip. The alpha setting made the aliased native Region edge obvious.

This mirrors an earlier Mugen Deej UI lesson: repeated Region/clipping patches are not a stable way to get smooth modern rounded geometry.

#209 therefore replaces the layer popup architecture rather than adding another Region tweak:

- `MugenLayerPopupForm` now uses `WS_EX_LAYERED` and Win32 `UpdateLayeredWindow`;
- each OSD frame is rendered into a `Format32bppPArgb` bitmap with GDI+ anti-aliased rounded geometry, border and text;
- the bitmap itself carries per-pixel alpha at the rounded edge, so the desktop shows through smoothly outside the curve instead of being chopped by a binary WinForms Region;
- configured 20..100% opacity is applied through `BLENDFUNCTION.SourceConstantAlpha`, preserving the anti-aliased edge alpha;
- the popup no longer creates a child `MugenCardPanel` or child Labels and no longer calls `Set-RoundedControlRegion` for the OSD;
- no-activate / tool-window behavior, dynamic width, monitor placement, TopMost and timer lifetime are preserved;
- theme colors and localized caption/name are passed into the layered renderer directly.

CI:
- run **#209**, run ID `35880032475` — **SUCCESS**;
- built code head `1b162367504b07b0fb4c3fea4eb62c2a2fa9e661`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-209`, ID `10759249744`;
- outer Actions digest `sha256:acafbd660d3a7fcfde5068de6fda8809c03765a5b5df60fef6f0c64949e12369`;
- inner program ZIP SHA-256 `d1301f857322f29275a69f174db61d3f05852a5d82a48c4d926b3b2cde2d40ce`;
- downloaded inner ZIP matches the packaged `.sha256`;
- staging and Windows PowerShell 5.1 runtime/C# parse checks passed, including compilation of the new layered-window renderer; launcher/helper build, packaging and upload also passed.

#209 supersedes #208 as the current OSD geometry review candidate.

Real-machine acceptance:
- test OSD at 50% first, because that exposed the defect most clearly;
- inspect all four rounded corners and the 1 px outline against both light and dark desktop/game content;
- compare 20%, 50% and 100% for consistent geometry (only alpha should change);
- verify the OSD still does not steal focus and still closes on its configured timer;
- verify dynamic width and long custom layer names still render correctly.


## Integrated #210 — compact content-sized centered layer OSD

Real-machine review of #209 passed the important geometry change: the new per-pixel-alpha layered-window OSD is now visually smooth, including at 50% opacity.

The follow-up UX observation was compositional rather than technical: although the popup was smooth, the short layer name “Основной” still appeared inside a large 340 px-wide card with both the caption and name aligned to the left. The result looked more like a generic notification panel than a compact layer OSD.

#210 makes the popup visually adaptive to its content:

- popup width is now calculated from the larger of the measured localized caption and measured layer-name width;
- minimum width is reduced from 340 px to 170 px, while the existing 620 px maximum and monitor working-area bound remain;
- horizontal content padding is 44 px, so short names produce a compact card and long custom names expand the card automatically;
- popup height is reduced from 104 px to 88 px;
- both “Active layer / Активный слой” and the layer name are centered in the layered renderer;
- long names still use the same single-line ellipsis fallback only if they exceed the bounded maximum width;
- per-pixel alpha, rounded geometry, opacity, positioning, no-focus-steal, TopMost and timer behavior are unchanged.

Expected examples:
- T1 / T2 / short names stay near the 170 px minimum;
- “Основной”, “Стрим”, “Игры” produce a compact balanced OSD;
- “Разработка” and longer custom names grow horizontally as needed instead of leaving large unused space.

CI:
- run **#210**, run ID `35881369823` — **SUCCESS**;
- built code head `99364f9384f84a841f9174976ee4172d7356e127`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-210`, ID `10760957127`;
- outer Actions digest `sha256:539409753bf18a1fc45485fc9bb5aafc17c3262ad4e8f410379caa98fbf202b5`;
- inner program ZIP SHA-256 `bd68f313d3b111ff7e2d0f5b5f4fbcbf3e0441e7f66049cfaef0bb0389ef1922`;
- downloaded inner ZIP matches the packaged `.sha256`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, layered-window C# compilation, launcher/helper build, packaging and upload: PASS.

#210 supersedes #209 as the current OSD UX review candidate.

Real-machine acceptance:
- compare short layer names (T1, T2, “Стрим”, “Игры”) and longer names (“Разработка”, maximum custom length);
- confirm short names produce a compact centered card rather than the previous wide left-heavy card;
- confirm long names expand the card rather than clipping prematurely;
- confirm smooth rounded corners at 50% opacity remain unchanged.


## Real-machine acceptance — Integrated #210 adaptive OSD layout

User review of #210 confirmed the adaptive OSD composition works as intended on the real machine:

- short custom layer name (“Стрим”) produces a compact centered popup;
- long layer name (“Основной длинный текст!!”) expands the popup horizontally;
- caption and layer name remain centered in both cases;
- rounded per-pixel-alpha geometry remains smooth while resizing.

This closes the #210 adaptive-size/centering UX check as PASS.


## Integrated #213 — persistent layer-assignment sidebar + Xbox gamepad wording

Real-machine feedback after #210/#211 highlighted an editing UX problem in **Control layers**: while configuring a layer such as “Game”, the editor showed a button's override only after that button was selected/pressed. There was no persistent overview of what had already been assigned across the layer.

#213 adds a dedicated right-hand **Layer assignments / Назначения слоя** sidebar:

- Control layers dialog is widened to 1160 px client width; the existing button grid and per-button editor remain unchanged on the left/middle;
- a persistent right sidebar lists every button whose current layer override differs from `inherit`;
- each row shows physical button number and the normal human-readable action text (including `none` / “Do nothing” as an intentional override);
- the sidebar title shows the currently selected layer name and the count of layer assignments;
- changing profile, layer, selected button or action refreshes the list immediately;
- clicking a sidebar row selects the corresponding physical button in the editor, so the summary doubles as navigation;
- an empty layer shows a “No overrides / Нет переопределений” placeholder rather than a blank panel;
- the sidebar intentionally lists **layer overrides**, not inherited base-profile mappings, to avoid turning the list into 28 rows of noise.

The same integrated source also carries the wording cleanup from the previous local test package:
- `Виртуальный Xbox…` → `Виртуальный геймпад Xbox…`;
- English equivalent → `Virtual Xbox gamepad…`;
- picker heading/hint now consistently refer to an Xbox **gamepad**, not a bare Xbox console;
- one-shot-vs-held explanatory copy uses the same terminology.

CI progression:
- run **#211**, run ID `35886112291`, head `ef5ae4a4704e03d47f48f92ffcdc05a40110e63a` — staging succeeded, but Parse-check failed on a new static assertion containing a Unicode ellipsis; runtime feature code was staged.
- run **#212**, run ID `35886364893`, head `bfba94c16d717241d179342d42abf110cce9932e` — staging succeeded; the next static assertion still expected the Notifications button at its old x=650 location after the dialog was widened.
- run **#213**, run ID `35886574832` — **SUCCESS**;
- built code head `b667aaac87552ab8a1cc6044b4f47fb41bd61dba`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-213`, ID `10762888728`;
- outer Actions digest `sha256:857fbe0326dd5c6716cb935a35b685c7bbbadb5ca9796597cb7e8e255a6e4cad`;
- inner program ZIP SHA-256 `9f1c943c5023d78e9d94baf38323ef4f11e8b8948de242653bb5b313fa94ee93`;
- downloaded inner ZIP matches the packaged `.sha256`;
- staging, Windows PowerShell 5.1 parse/runtime assertions, launcher/helper build, packaging and upload: PASS.

#213 is the current focused layer-editor UI candidate.

Real-machine acceptance:
- open a layer with several overrides and confirm the right sidebar shows all of them at once without pressing the physical buttons;
- change one assignment and confirm the sidebar updates immediately;
- switch T1/T2/T1+T2 and profiles and confirm the sidebar follows the selected editor context;
- click a sidebar row and confirm the corresponding numbered button becomes selected;
- verify long human-readable gamepad/hotkey/program actions remain usable in the list (scroll/truncation is acceptable; content must not map to the wrong button).


## Integrated #215 — universal backup schema v3 includes layers + virtual controller

User noticed that a backup created from the #210-era prototype did not preserve the newly added Control layers configuration. Audit confirmed the backup schema was still v2 from before the layer subsystem existed.

Persistent prototype settings are split across these active files:
- `config.json`
- `button-actions.json`
- `adaptive-actions.json`
- `adaptive-profiles.json`
- `adaptive-layers.json`
- `virtual-controller.json`

Before #215, backup v2 already covered the first four families but omitted `adaptive-layers.json` and `virtual-controller.json`.

#215 upgrades the universal backup to **schema v3**:
- saves/restores the complete normalized Adaptive layer config, including modifier toggle roles, Base/T1/T2/T1+T2 names, per-profile/per-layer button overrides, per-layer encoder mappings, OSD enable/screen/position/duration/opacity settings;
- saves/restores the virtual-controller config (`enabled`, `xbox360` type);
- emergency pre-restore snapshots and rollback now include the same v3 families;
- schema v1 and v2 backups remain readable;
- restoring v2 deliberately preserves the current layers and virtual-controller setting because those older backups never contained them;
- restoring v1 preserves all Adaptive-era setting families it never knew about.

CI:
- run **#215**, run ID `35890261732` — **SUCCESS**;
- built code head `b54f8fa40daa91971622968966a5366ada86741d`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-215`, ID `10764074848`;
- outer Actions digest `sha256:6835b86ff4ba2c66cdc982aecd2ce22def05740e85415ecd8be8b9b184905c86`;
- inner program ZIP SHA-256 `efd321fa0a57a67668f409a22506af124164951bb6c073580d9d69a091fec860`;
- downloaded package hash matches the packaged `.sha256`;
- staged runtime explicitly contains schemaVersion 3, adaptiveLayers, virtualController, v3 restore logic, and v2 compatibility-preserve logic.

Important: backups created by #210/#213/#214 are still schema v2 and therefore do **not** contain layer configuration. They are still valid for the older setting families. Current on-disk `adaptive-layers.json` remains the source of the user's existing layer setup until a new #215+ backup is created.


## Integrated #216 — rapid-repeat XInput hot-path hardening

Real-machine Cult of the Lamb testing of #214 showed a major latency improvement, but very fast repeated actions could still occasionally feel like an empty press. The captured #214 log showed no virtual-controller bridge failures; it did show a rapid Button 10 sequence where a new press arrived only ~20 ms after release and the legacy press-only dispatcher emitted `Button 10 action suppressed by debounce (60 ms)`.

The stateful XInput frame is submitted before the one-shot dispatcher, so that legacy debounce was not the authoritative virtual-gamepad state gate. However, the active 5 ms gameplay loop was still synchronously writing every physical press/release to `mugen-deej.log`, and virtual mappings still entered the legacy one-shot dispatcher far enough to hit its 80 ms debounce/log path. Both are avoidable filesystem/UI-thread work during rapid input.

#216 therefore:
- keeps per-edge `Add-Content` logging out of the active XInput gameplay path;
- returns virtual Xbox mappings from the press-only dispatcher immediately after effective profile/layer action resolution, before the legacy 80 ms debounce and its logging;
- leaves non-XInput button behavior and logging unchanged;
- keeps the #214 5 ms serial drain, cached profile/layer resolution and one-way helper state transport;
- includes the #215 backup schema v3 work.

CI run **#216** (run ID `35891904212`) succeeded at code head `1d362e9f68b82328b98e095e16a2d03b342a2645`. Artifact `Mugen-Deej-VirtualGamepad-Integrated-216`, ID `10765317130`; outer artifact digest `sha256:2c1095abcedfe726bb7020b08b904755cb5a2459d4664994cd039a385e507232`; inner program ZIP SHA-256 `4904646210c93ff10d0e201ae11f9a9295d062e3cedb5df77c59d1716174ae44`.

#216 is a conservative rapid-repeat candidate. It deliberately does not yet stretch or queue XInput button pulses, because the first step is to remove avoidable hot-path stalls without changing gameplay button timing semantics.


## Integrated #218 — 6 ms matrix debounce experiment with firmware bounce diagnostics

After #214/#216 real-machine gameplay testing, general XInput latency was reported as dramatically improved and attack spam behaved correctly. The remaining feel difference versus a real gamepad was fastest left/right direction alternation. The current Cardboard Nano firmware still used an 18 ms matrix debounce, which becomes visible when every direction change must wait for another accepted matrix edge.

#218 is a controlled firmware-side latency experiment:
- Cardboard Nano matrix debounce is reduced from **18 ms to 6 ms**;
- the normal 25 ms full-state heartbeat remains unchanged, but accepted matrix changes still force an immediate packet as before;
- firmware now tracks two cumulative debounce diagnostics without changing the 28-button/toggle mapping:
  - **filtered** = a pending raw transition returned to the accepted state before the 6 ms debounce completed;
  - **rapid** = an accepted matrix state reversed again within 35 ms, which is a candidate for bounce that escaped the shortened debounce window;
- diagnostic contact mask maps bits 0..27 to B1..B28 and bits 28/29 to T1/T2;
- Adaptive v3 accepts an optional diagnostic token `d<debounceMs>:<filteredCount>:<filteredMaskHex>:<rapidCount>:<rapidMaskHex>`;
- diagnostics do not participate in capability/signature matching;
- the desktop logs diagnostic activation and only logs later when counters change, including the affected contact names;
- the exact matching Cardboard Nano sketch is bundled in the dev package at `firmware\MugenDeejCardboardNanoPrototype\MugenDeejCardboardNanoPrototype.ino`.

CI:
- run **#218**, run ID `35895588926` — **SUCCESS**;
- built code head `4693b969237506ad1810aab4ea665b2454cafab9`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-218`, ID `10766931651`;
- outer Actions digest `sha256:b629779765e7a4bf4962e6b1735995b2dd64b4a2d2f262c7c57be26f32ec4c4f`;
- inner program ZIP SHA-256 `2b631327b0a37426084749ec7e81a106948f74f98ff2338171aa93c9bb24ffdc`;
- staged runtime/PowerShell 5.1 checks, launcher/helper build, packaging and upload: PASS.

Real-machine test:
1. flash the bundled #218 Cardboard Nano sketch;
2. launch the matching #218 desktop build;
3. confirm the log contains `Firmware debounce diagnostics active: matrixDebounce=6 ms`;
4. play normally and deliberately alternate left/right rapidly;
5. send the resulting Mugen log back for review;
6. `filtered` increasing mildly means the shorter debounce is actively filtering contact chatter; `rapid` increasing repeatedly on the same contact is the more important warning that 6 ms may be too aggressive.

#216 remains the accepted desktop rapid-repeat/low-latency basis; #218 changes the firmware debounce experiment and parser diagnostics on top of it.


## Real-machine result — #218 6 ms matrix debounce feels gamepad-fast

User flashed the #218 Cardboard Nano firmware and tested it in Cult of the Lamb. Subjective gameplay result: the remaining directional latency gap disappeared; rapid left/right alternation now feels effectively instantaneous and can be spammed at real-gamepad speed.

This is a real-machine **responsiveness PASS** for the 6 ms matrix-debounce experiment.

Bounce-safety acceptance is still pending the matching #218 diagnostic log. The firmware counters remain the deciding signal:
- `filtered` may increase mildly without indicating a gameplay fault;
- repeated growth of `rapid`, especially on the same B1..B28/T1/T2 contact, would indicate that 6 ms is too aggressive.

## Integrated #219 — auto-enable XInput after configuring a layer gamepad action

A UX issue was found while reconfiguring layers after backup restore: Control layers allowed Xbox mappings to be assigned while XInput remained Off, so the mapping looked correct but produced no virtual-gamepad output until the user separately remembered to enable XInput.

#219 fixes that flow:
- if the user actually configures an Xbox virtual-gamepad action during the current Control layers editing session and saves, XInput is automatically enabled;
- the saved layer state is immediately reconciled through `Sync-MugenVirtualGamepadState`;
- unrelated layer edits do not re-enable XInput after the user explicitly turned it Off, because auto-enable is guarded by a per-session `VirtualMappingConfigured` intent flag;
- the #218 6 ms firmware/diagnostics remain unchanged and are bundled in the package.

CI run **#219** (run ID `35897242734`) succeeded at code head `9015586d6900a1e1f01951576e05edf0386d5f5b`. Artifact `Mugen-Deej-VirtualGamepad-Integrated-219`, ID `10766763919`; outer digest `sha256:1c27fd12212953c3042a39d5e9eedb98ef27462b06ef0a5f5f2a9334461d6d28`; inner ZIP SHA-256 `c4cbb599765206e7bcbfcb765292ec971c4cd0092a05d08603b073b9899f7e9a`.


## #218 6 ms debounce — real-machine diagnostics PASS

User returned the #218 desktop/firmware logs after the Cult of the Lamb test where rapid left/right alternation felt effectively identical to a real gamepad.

The matching firmware diagnostic channel initialized successfully at `matrixDebounce=6 ms; filtered=0; rapid=0`. Across the rest of the captured session there were no subsequent `Firmware debounce diagnostic:` counter-change records, so neither the filtered raw-reversal counter nor the accepted rapid-reversal counter increased during the test.

Acceptance:
- responsiveness: PASS;
- filtered bounce activity: 0 observed;
- rapid accepted reversals (<35 ms): 0 observed;
- no evidence in this session that 6 ms is too aggressive for the tested panel.

One isolated startup warning reported a mismatched Adaptive packet shape (`expected=adaptive:5:28:2:1; got=adaptive:5:45:4:2`). It occurred shortly after connection/probe, was rejected by the existing shape guard, did not disconnect the controller, and did not recur during the gameplay interval. Treat as a separate protocol-startup robustness observation rather than a debounce failure.

The 6 ms Cardboard Nano matrix debounce is now the current hardware-tested value for this panel.


## #219 backup schema v3 + restored XInput — real-machine PASS

User performed a destructive restore test on #219 twice: first restoring into a fresh/default configuration, then deleting settings and restoring the same backup again.

Both runs confirmed schema v3 behavior on the real machine:
- Adaptive layer config restored with `contexts=1` and the expected modifier role;
- virtual-controller config restored with `enabled=True; type=xbox360`;
- after the mandatory restart, `adaptive-layers.json` loaded before controller use;
- the virtual-controller helper started automatically because the restored backup had XInput enabled;
- switching into the Game layer then used the restored layer context as expected.

Important nuance: in this restore case XInput does not need the #219 “mapping-save auto-enable” fallback. Schema v3 restores the persisted `enabled=True` setting, so the helper starts during normal post-restore startup. #219’s auto-enable path remains useful for a different case: the user manually has XInput Off and then configures a new virtual Xbox mapping in Control layers.

The same log also showed firmware debounce counters at `filtered=11; rapid=3` on connection. Those values remained unchanged across the subsequent restart/restore cycles. Because the counters are cumulative from firmware boot, these events happened earlier in the MCU session; no new debounce diagnostic events were observed during the two restore checks. Gameplay had already been reported as clean and gamepad-fast, so this does not currently indicate an observed input fault.


## #219 real-machine control responsiveness — encoder/toggles observation

User stress-tested the restored #219 configuration by rapidly rotating and pressing the encoder and toggling controls.

Observed log behavior:
- encoder detents were reported in dense sequences, commonly about 11–30 ms apart during fast rotation, with direction reversals preserved cleanly;
- encoder push press/release events were also reported consistently during repeated taps;
- no new firmware debounce diagnostic counter-change records occurred during this test; the cumulative `filtered=11; rapid=3` values seen at connection remained unchanged;
- layer modifier toggles continued to switch Base/Game cleanly and XInput profile neutralization followed those changes.

This matches the user's subjective report that the encoder now feels much more immediate. The likely reason is the #214+ active-XInput 5 ms desktop serial-drain cadence: although the firmware matrix debounce change applies only to matrix buttons/toggles, the faster desktop drain consumes all Adaptive packets, including encoder position/push updates.


## #219 application-profile encoder switching — real-machine PASS

User tested Encoder 1 with different foreground-application mappings:
- Global profile: CW/CCW = system volume up/down;
- Firefox profile: CW/CCW = mouse wheel up/down.

The real-machine log confirms the mapping switches with foreground focus. Before Firefox becomes active, encoder detents dispatch `system:volumeup` / `system:volumedown`. After foreground context changes to `firefox`, the same encoder immediately dispatches `mouse:wheelup` / `mouse:wheeldown`; when focus leaves Firefox, context returns to `__global__`.

Fast detent sequences remain orderly across both mappings, so profile switching does not appear to degrade the low-latency encoder behavior.


## Integrated #220 — physical-button settings hot-unplug hardening

Real-machine bug discovery on #219:
- Extended controller (6 buttons) was connected and the optimized Physical button actions dialog was open;
- physical-button auto-selection worked by pressing the controller buttons;
- unplugging the controller from USB while that modal dialog remained open caused an unhandled WinForms/PowerShell exception:
  `RuntimeException: property "LastButtons" cannot be found for this object`;
- the exception originated from a `System.Windows.Forms.Timer.OnTick` callback.

The serial/recovery path itself behaved correctly: the log recorded `Serial connection lost`, armed targeted recovery, removed the COM port, and continued probing/recovery. The crash was isolated to the modal button editor's 25 ms live-selection timer.

Root cause/fix:
- the optimized editor used a very generic captured local variable named `$state` for `LastButtons`, selection state, and action-map state;
- under nested WinForms timer/event execution during hot-unplug, the live timer could resolve a different dynamic `$state` object that did not expose `LastButtons`;
- all editor state references are now isolated under the unique `$buttonEditorState` name;
- the live-selection timer now explicitly short-circuits while `$script:IsConnected` is false, clears only its local button snapshot, leaves the modal editor open, and automatically resumes physical-button selection after reconnect;
- CI rejects staged runtimes that still contain `$state.LastButtons` and verifies the hot-unplug guard.

CI:
- run **#220**, run ID `35906698320` — **SUCCESS**;
- built code head `167fa38b5dc60eb651fe859d9ef679ef2e9634ea`;
- artifact `Mugen-Deej-VirtualGamepad-Integrated-220`, ID `10771134280`;
- outer Actions digest `sha256:b8c624bcd298d8afebc8dbb24f7843f0034ab3c80e6d2c5ee3d5c17e77a2456f`;
- inner program ZIP SHA-256 `6fdf609888e1166206a7f4bd0760d158a71d4c0b876d21ff6bd78a516c42306d`.

Real-machine acceptance pending: reproduce the same Extended-controller scenario, leave Physical button actions open, unplug USB, then reconnect. Expected result is no JIT dialog; editor remains open/inert while disconnected and live button selection resumes after reconnect.

## #220 real-machine hot-unplug acceptance — PASS

Integrated #220 has now been exercised on the real Extended 5-slider / 6-button controller with the optimized Physical button actions dialog left open.

Real-machine procedure/result:
- physical-button live selection was confirmed before disconnect;
- USB was unplugged and reconnected repeatedly while the modal button editor remained open;
- no WinForms/.NET JIT exception appeared and the editor did not crash;
- the application stayed alive through disconnect/recovery;
- after COM10 returned, the Extended 5/6 topology was detected again and physical button input resumed;
- the user repeated the unplug/replug cycle and again observed no crash.

The captured runtime log corroborates the important recovery path: COM10 is lost while the large button-settings dialog is open, targeted recovery remains active, COM10 later reappears, the same Extended 5/6 topology is rediscovered, and button events resume. A later second disconnect is also present before the supplied log ends.

Acceptance: **PASS**.

#220 is now the hardware-tested baseline for Physical button actions hot-unplug behavior. Preserve the isolated `$buttonEditorState` and disconnected-timer short-circuit in subsequent editor/UI changes.

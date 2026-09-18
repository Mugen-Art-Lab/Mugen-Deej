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

## Next larger feature after #31 validation

Once alternate Adaptive topologies are hardware-proven, move to first-class mappings/configuration for toggles and encoders (ON/OFF actions, CW/CCW behavior, encoder push). That work is also the natural point for a future backup schema bump that stores those new mapping families.

## Working rules

- Stable `main` stays untouched until feature work is hardware-proven.
- CI/code inspection is not a hardware PASS.
- Preserve Legacy and Extended behavior.
- Adaptive controls remain first-class types; do not flatten toggles/encoders into fake momentary buttons.
- Do not hardcode 5/29/2/1 into generic Adaptive behavior.
- For any build-triggering change: wait for the workflow result, fix/rebuild if red, then hand the ready inner program ZIP directly rather than making the tester hunt through Actions.
- Keep this handoff current after meaningful code, CI, UI, or hardware observations.

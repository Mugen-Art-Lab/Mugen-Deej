# UI scaling — test log and handoff (2.0 feature branch)

This is a **development/test record**, not a promise of release readiness.
Keep it updated after each verified hardware test. Russian conversation remains
the source of UX approval. Do not silently alter RU/EN copy.

## 2026-10-09 — CI #27 (dialogs-only experiment)

- 100% regulator settings window measured **1112×845 px**.
- 80% same window measured **890×682 px**.
- Confirmed on real HD Ready 1366×768 display: all five regulator rows and
  **Save/Cancel** accessible, no off-screen bottom.
- Main dashboard intentionally unscaled in this experiment.
- Tested hardware: Adaptive v3, 5/28/2/2 at 500000 baud. No claim about
  6+ regulator scrolling; still a separate task.

## 2026-10-09 — CI #28 (Auto / 80% / 100%, main dashboard)

- New UI logic: `config.app.uiScaleMode = auto|manual` and `uiScale = 0.8|1.0`.
  Automatic choice uses `Screen.WorkingArea`.
- Windows CI #28 was green (compile / packaging only).
- **HARDWARE/UI REGRESSION FOUND — NOT ACCEPTED.**
- In the running app, manual 80% triggers repeated back-and-forth resizing
  and visibly broken/overlapping main-screen controls (user provided two
  screenshots). One frame shows two sets of headers and controls, sections
  cutting into one another and window at reference width while selector is 80%.
  Another frame shows the intended smaller dashboard.
- Runtime log for the incident has one saved mode change at 2026-10-09
  21:33:37.215, `auto -> manual; factor 1.00 -> 0.80`.
  No corresponding PowerShell exception. Physical controller remains
  detected at Adaptive v3 5/28/2/2; no evidence of a protocol failure.
- **Likely UI issue:** `Set-MainButtonLayout` repeatedly restores the full
  100% geometry, including top-level window dimensions, then scales it back
  to 80% while normal UI paints are enabled. The main card/typed controls
  update dynamically; this is unsafe without atomic redraw and redundant
  rebuild suppression. Re-evaluate once implemented — root cause not yet
  confirmed solely by runtime logs.
- Previous CI #27 test install should be used if dashboard stability needed.

## 2026-10-09 — CI #29 (repaint/rebuild fix candidate)

- Runtime commit: `c0d38e201a0c3f83b249296440dceb799602e5be`.
- Workflow: [Build release packages #29](https://github.com/Mugen-Art-Lab/Mugen-Deej/actions/runs/37953827010) — **green CI** on the organization's self-hosted Windows runner.
- Fix candidate: suspend native redraw while returning to the 100% reference
  layout and applying the selected scale; suppress nested and identical
  dashboard rebuilds. Record layout signature/size in the diagnostic log.
- Tested artifact: `Mugen-Deej-2.0.0-Setup-CI29.zip`, Setup SHA-256
  `66db99ee61dfe26d314d9a665f00746bdbcce70319ce1e9c39ade8bd3f3fac1b`
  verified against the workflow's release checksum.
- **UI/hardware regression test PENDING.** Green CI does not prove that
  the live main-window oscillation is fixed. Test 100% -> 80% -> 100% ->
  Auto while Adaptive 5/28/2/2 is active; check restarts and tray restore.
  If the problem remains, inspect `Main UI layout applied` DEBUG entries
  for repeated identical or alternating layout signatures.

## 2026-10-09 — CI #29 real-device test (FAILED) and CI #30 candidate

- **CI #29 hardware/UI test FAILED.** Repeated back-and-forth resizing is
  resolved, but after an Auto/80%/100% transition with controller attached
  the main input card (28 button indicators, toggle and encoder indicators)
  and its two settings buttons disappear. A large blank space remains where
  the input card should be. One screenshot shows a normal five-slider panel,
  one `Regulators` button and the disconnected-looking empty card space,
  while the status line still correctly reports 5/28/2/2.
- Supplied log around 2026-10-09 22:08 shows `Main UI layout applied`
  with `signature=True|True|5|28|2|2|28|2|2|False|False|False|68|1|ru`.
  Counts and indicator objects exist, **settings visibility flags are wrong**.
  No PowerShell crash is evident.
- Identified cause in code: WinForms `Control.Visible` getter describes
  **effective** visibility, inherited from parent form. With start-minimized
  the main form is hidden, so reading `.Visible` while computing button
  arrangement returns false even for controls logically enabled by the
  controller. The CI #29 layout cache can retain this wrong arrangement.
- **CI #30 fix candidate** (runtime commit `b6940caf4f75d999da6d95c7aa190c2a2933bdbd`):
  calculate settings visibility/signature from actual detected capabilities,
  explicitly set required card/button visibility, and force a single redraw
  after the main form is shown from the tray. Retain CI #29 atomic redraw
  protection. Windows CI [#30](https://github.com/Mugen-Art-Lab/Mugen-Deej/actions/runs/37957458571)
  **passed** on self-hosted `Mugen-Builder`. Setup EXE SHA-256:
  `8560db245d802df750670d76e2971074044ba7639653be9eda5636ff5855ac82`;
  test ZIP `Mugen-Deej-2.0.0-Setup-CI30.zip` contains that verified EXE.
- **Real-device result PENDING**: reopen from tray, Auto/80/100 transitions,
  compare all 28 button tiles, two toggle/encoder indicators and three
  settings buttons. Also repeat with a fresh visible launch. Do not promote
  until this passes.


## 2026-10-09 — CI #31 to #35: crash dialog, toggles and Xbox status card

**#31** — launcher crash dialog fix: `c3adf68cb3789a459945391ad4dc48134b751cad`,
[CI #31](https://github.com/Mugen-Art-Lab/Mugen-Deej/actions/runs/37959864210), SUCCESS.
- Prior real-machine incident on 2026-10-09: the PowerShell process exited
  with code 2 after about 22 seconds, around a virtual-Xbox disable event.
  The available logs do **not** prove that virtual-Xbox teardown caused it.
  Independently, the launcher error dialog dumped thousands of bytes of old
  launcher history and stretched below the desktop.
- #31 bounded crash-dialog contents to recent, truncated application/launcher
  lines and retained paths to complete on-disk logs. The crash **root cause
  remains unknown**; the dialog improvement is not a crash fix.

**#32/#33** — Xbox-status rescale and narrow toggle-row candidates.
- #32 `1a803aa4c6f59a2e2e9752cd4155d1db5cc64818` changed the status
  card height comparison to account for dashboard scaling.
- #33 `a55a86bd200573656cbbc716e428f4915fcb3b86`,
  [CI #33](https://github.com/Mugen-Art-Lab/Mugen-Deej/actions/runs/37962077211),
  SUCCESS, additionally narrowed the compact toggle indicator hosts
  (96 -> 92 reference px) so two switches fit next to two encoders at 80%.
- **Real-device result of #33: FAILED overall.** Two toggles now visibly fit,
  but the top physical + virtual-Xbox status card becomes vertically crushed
  **at both 100% and 80%**, with overlapping/clipped content (two screenshots).
  Therefore do not endorse #33 on green CI alone.
- Root-cause analysis: the virtual-gamepad module changed
  `statusPanel.Size` and child bounds directly in 100% coordinates, even
  while the main form was already at 80% and the cached layout signature
  assumed a stable card height. Separate owners of geometry caused
  compaction and incorrect status-card bounds.

**#34/#35** — status geometry integration.
- #34 `da4b5a2e482aecd462d444e671c8965b411963ae` introduced
  `Set-MugenVirtualGamepadStatusLayoutLogical` and stopped status-update
  calls from changing the already-scaled bounds.
- #35 `5d126bb6ffc35ce885139795250c5564bff23ee3`,
  [CI #35](https://github.com/Mugen-Art-Lab/Mugen-Deej/actions/runs/37964157556),
  **SUCCESS**, artifact `Mugen-Deej-packages-35`, ID `11633430248`.
  `Set-MainButtonLayout` now owns status-card geometry at the 100% logical
  stage after restoring baseline bounds and before scaling. The main-layout
  signature uses the expected logical status height (68 for Adaptive/XInput
  status availability, otherwise 60), instead of measuring an existing scaled
  WinForms control. The compact two-toggle width fix remains included.
- **Real-device result of #35: PENDING**. Package was shared in conversation
  as `Mugen-Deej-CI35.zip`. No screenshots/confirmation yet. Windows CI
  green means compile/package success, not verified GUI behavior.

**Immediate next test:** use #35 on the real Adaptive 5/28/2/2 at 500000 baud.
Check intact two-row physical/virtual-Xbox card and both toggles at 100%,
80%, back to 100%, then Auto; enable/disable XInput several times, restore
from tray, and watch for window resize oscillation, black/blank trailing
windows or overlaps. Check log for repeated identical
`Main UI layout applied` signatures. If the card is still broken, investigate
baseline restoration and whether the virtual-gamepad status children are
created after the baseline snapshot; do not change transport or HID code
without evidence.

## Intended architecture / acceptance before merge

- Exactly two tested reference scales (80% and 100%), plus Auto **default**.
- Use logical Windows work area and taskbar, not nominal resolution alone.
- Changing mode live must settle once with no flicker or oscillation; 80% must
  remain 80% after controller topology changes, XInput helper readiness,
  tray/restore, theme/language change and repeated opens.
- All dashboard widgets (5 sliders, 28 buttons, 2 toggles, 2 encoders),
  title, dropdowns, settings buttons, audio bar and launcher status should
  be intact and in correct order. No duplicates, overlap or clipped items.
- Recheck scaling on HD Ready 1366×768 and Full HD 1920×1080, light/dark
  themes, RU/EN, 0/1/2/5 and eventually 6+ sliders; Legacy/Extended/Adaptive.
- Fix must not change UART packets, audio volume logic, XInput behavior,
  or translations beyond an approved scale selector label.
- No "successful feature" claim based solely on Windows CI.
- Keep logs, user screenshots and specific CI commit/run provenance in
  this note; update **only after hardware observations**.

See [ROADMAP.md](ROADMAP.md) for approved follow-up work (scrollable 6+
regulator editor and optional Xbox backend download).

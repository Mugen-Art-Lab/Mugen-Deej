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

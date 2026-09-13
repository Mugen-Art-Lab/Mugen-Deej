# Mugen Deej 0.9.0 UI polish history

The internal 0.9.0 line was not only a controller/button feature branch. A large part of the work was spent bringing the new surfaces back to the visual and interaction quality of the established Friendly UI.

## Why this matters for 1.0.0

The dev25 soak build is the visual baseline for the first 1.0.0 release. Backup/restore and migration work must preserve the established layout, spacing, bilingual behavior, theme behavior and owner-drawn control repaint fixes unless a change is required for the new backup UI itself.

## Main UI refinement stages

- dev2-dev3: introduced button-aware UI, live state tiles/cards and dynamic layouts; fixed initialization/layout timing and theme inheritance problems.
- dev4-dev8: repeated spacing, rounded-card, focus, background and interaction refinements until the button controls visually matched the rest of the application instead of looking bolted on.
- dev13: fixed the brief empty-window flash when hiding to tray by switching to a hide-first sequence.
- dev16-dev19: polished the hotkey capture and dynamic button-action editors while keeping the main settings flow compact.
- dev20: replaced the legacy folder dialog with the modern native Windows folder picker.
- dev23: added the explicit amber reminder that button actions become live only after Save.
- dev24: fixed stale localized text in owner-drawn `MugenButton` and `MugenGroupBox` controls by invalidating on `Text` changes. Before this fix, switching RU/EN could leave old-language text visible until mouse hover.
- dev25: added the matching amber Save/live-position explanation to slider settings and adjusted the layout so the notice, headers, rows, advanced section and Save/Cancel controls all fit cleanly.

## Preservation rule

The current dev25 interface is considered intentional, not provisional. In particular:

- do not casually reflow the main window while adding backup/restore;
- keep the backup entry as a compact secondary/service control next to `Connection and diagnostics`;
- keep RU/EN parity and immediate repaint on language switching;
- keep Light/Dark/Auto behavior and existing custom-control geometry;
- avoid global `Refresh()` workarounds when a control-level invalidation fix is appropriate;
- preserve the distinction between settings that apply only after Save and physical control positions that update live.

The 1.0.0 release should feel like the same finished dev25 application with safe migration/backup infrastructure added, not a new UI redesign.

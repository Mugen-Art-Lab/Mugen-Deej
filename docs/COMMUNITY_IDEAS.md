# Mugen Deej — community ideas backlog

This document keeps useful community requests visible without silently turning
them into release commitments. Ideas below are **not implemented** unless
marked otherwise. Discuss scope and approve changes before editing runtime,
hardware firmware, or public UI wording.

## 2026-10-09 — Independent system-sounds volume control

**Status:** Proposed / investigate after the 2.0.0 release blockers.

A user of Mugen Deej 1.0.0 asked for the ability to control **Windows system
sounds** with a dedicated analog slider/potentiometer, as in the original deej.
Specifically, the user wants to keep USB connect/disconnect and notification
sounds audible but at a much lower level while listening to music through an
amplifier.

- This means **adjustable system-sounds volume**, not master-volume control
  and not only a mute/unmute action.
- The existing button action for system-sounds mute/unmute does not replace
  this request.
- Investigate how Windows exposes the special System Sounds audio session
  through the audio backend, including cases where the session is absent,
  re-created, or changes output device.
- If feasible, offer System Sounds as a selectable audio target alongside
  existing targets; preserve portable/Legacy compatibility.
- Acceptance would include independent music/system-sound volumes, a real
  notification/USB-sound test, reconnect/restart behavior and RU/EN UI review.

**No implementation decision or release date yet.**

## 2026-10-09 — Resistor-ladder button inputs for Adaptive hardware

**Status:** Proposed hardware/firmware input method; no new wire-protocol
field required for the initial design.

A user building a controller with limited MCU I/O reports using a **resistor
ladder for 10 physical buttons**, with **four pins** used in their particular
setup. The user has since described and shown the working firmware arrangement:
**one digital input for hard mute, one digital input for a separate button,
and two independent analog inputs for four buttons each** (1 + 1 + 4 + 4).
Each ADC input classifies one button from distinct reading ranges, separated
by deliberately unused gaps; the firmware then maps the decoded states to
ordinary Extended button fields. Their Mugen Deej 1.0.0 screenshot shows
**6 controls / 10 buttons**, and the user reports all ten buttons and six
sliders operate correctly.

Simultaneous presses **between independent groups** are possible according
to the builder; decoding more than one key **within the same resistor group**
was deliberately not required and should not be advertised as supported.
The user described the parallel-resistor behavior for that case, but a full
electrical schematic and controlled multi-key measurements are not on file.
These are community hardware observations, not yet a Mugen reference-firmware
validation.

The useful architectural distinction:

- **Physical readout:** firmware reads resistor-ladder voltage(s) through ADC
  input(s), classifies button states with calibrated thresholds and
  debouncing.
- **Logical control:** each identified momentary button can continue to be
  reported as an ordinary Adaptive v3 `b0` (pressed) / `b1` (released)
  field. Matrix-scanned buttons and ladder-scanned buttons can coexist in one
  discovered `buttons` capability count.
- **No need to invent a separate button family** merely because the electrical
  wiring differs. Revisit the protocol only if a real use case requires new
  semantics not representable by current logical button states.
- **Known electrical caveat:** a basic single-ADC resistor ladder may not
  distinguish simultaneous presses reliably. Measure actual voltages,
  resistor tolerances, ADC noise, transitions, switch bounce and power-supply
  variation before promising multi-key combinations.
- Useful prototype tests: individual button identity, press/release,
  rapid/repeated presses, cross-talk, simultaneous presses (or explicitly
  documented limitations), mixed slider/encoder traffic, reboot and
  autodetected Adaptive topology.

Potential future work: optional DIY firmware example for a compact controller
where MCU input pins are scarce. Ask for the user's schematic or decoding
algorithm **only if they wish to share it**; do not assume their exact design.

**Not a 2.0.0 feature or reference-hardware requirement.**

## 2026-10-09 — Adjustable application UI scale / compact and large displays

**Status:** Proposed experiment; user-requested first approach, not implemented.

A small-screen hardware test on an HD Ready laptop with **5 sliders and
6 buttons** reproduced the UI problem visually: the main window is usable,
but the fixed-height **Configure controls** dialog extends below the Windows
taskbar, hiding its Save/Cancel buttons. A separate community report reproduced
a similar failure with **6 sliders at 1366 x 768 / 100% Windows scaling**.
The original screenshots are held in the project conversation, not committed
to this repository.

The user agreed to trial **two reference scale profiles only**: compact for
HD Ready (nominally 720p) and normal for Full HD (1080p). The owner can test
these on real hardware. **1440p/"2K" and 4K are explicitly deferred** because
there is currently no suitable display for visual verification.

Current implementation facts (release branch, no change made here):

- the app uses WinForms with fixed pixel coordinates and multiple custom
  controls; it does **not** yet have an application-level scale setting;
- the slider dialog starts at `ClientSize = 1110 x 775` and
  `MinimumSize = 1126 x 814`, then shifts content and extends form height
  by another **38 px** for the Save warning; more slider rows can move
  buttons still further down;
- several other dialogs also exceed 768 px in height, so this must be tested
  across more than one page;
- `Ensure-FormVisible` checks whether some part of a form is within a
  monitor's `WorkingArea`, not whether its entire content and actions fit.

Potential direction for an **approved** prototype:

- start with a **single 100% reference layout** and a smaller compact
  scale (e.g. 80%, provisional), applying a consistent one-time scale per
  form rather than maintaining two unrelated pixel-coordinate layouts;
- choose/offer the two profiles based on the user's preference and **usable
  screen working area**; take Windows DPI scaling into account and avoid
  applying a second scale on top of automatic OS scaling;
- preserve layout proportions, font legibility, button hit targets and
  custom-control appearance; verify actual WinForms scaling rather than
  assuming a single `Scale()` call solves all fixed coordinates;
- keep primary dialog actions accessible; a scrollable settings-content area
  with anchored Save/Cancel may still be necessary even with compact scaling;
- retain existing 100% appearance as an explicit compatibility baseline,
  offer a way to reset an unusable scale setting and avoid affecting
  controller protocol, audio, or serial timing.

Suggested immediate test matrix: **1366x768/100%** (confirmed failure) and
**1920x1080**, both physically available to the owner. Include 5 and 6+
sliders, advanced settings, keyboard navigation, long Russian/English labels,
and a complete Save/Cancel path. Defer 1440p/4K validation and profiles.

Possible persistence: optional `config.app.uiScale` with a default of `1.0`
for existing configurations. The current backup contains the complete
configuration, so the scale value should be included automatically; check
restore normalization and backward compatibility instead of introducing a
new backup schema solely for this setting.

**UI layout/scale change requires separate user review and approval.**

## 2026-10-09 — Dynamic analog-control count across protocols

**Status:** UI behavior review requested, not a new serial protocol feature.

Users can build **Legacy**, **Extended** or **Adaptive v3** controllers with
different numbers of physical analog controls (e.g. 1, 2, 5, 6 or 10). Detect
the actual count from the connected protocol packet; never redefine the
controller as a "five-slider device" just because five is the historical
reference panel.

Separate **detected/functional controls** from **visible preview rows**:

- 1 or 2 sliders: show 1 or 2 live rows and shrink unused dashboard space.
- Around 5 sliders: preserve the familiar normal dashboard layout.
- 6 or 10 sliders: do **not** make the entire main form ten rows taller.
  Show a deliberately bounded preview and provide an obvious accessible
  path to all live controls, e.g. the already implemented "Show all" scrollable
  controller-state dialog. Consider embedded scrolling only if approved.
- The Configure controls dialog must still allow every physical slider to be
  named, mapped and monitored, with Save/Cancel reachable on small displays.
  This interacts with the separate HD Ready / Full HD scale experiment.
- A device with zero analog controls must not display an invented slider
  section (important for Adaptive v3).

Current branch observation: the main preview widgets are created with a
five-iteration loop, but `Update-SliderCapabilityUi` already limits visible
rows to the detected count and shows "Show all… (+N)" for overflow.
`Show-FullControllerStateWindow` already creates one indicator per detected
slider inside a scrollable panel. The requirement is to review these
existing behaviors and finish their UX/test coverage, not accidentally
rewrite working topology discovery.

Suggested tests: Legacy 1/2/5/6/10; Extended 1/2/5/6/10 with buttons;
Adaptive 0/1/2/5/6/10 where representable; repeated reconnects and switching
controllers of different sizes; changing settings, saving, restoring and
showing live values; both approved display scales. Keep this scoped to actual
supported parser limits and avoid asserting unlimited hardware capacity.

**No runtime changes or UX approval yet.**

## Related 2.0.0 issues (separate from these ideas)

The same early community test identified two concrete release-prep checks:

1. **Analog control count / main UI:** 1.0.0 detects six sliders and can use
   the sixth after manual configuration, but the main dashboard shows only
   five. The 2.0.0 branch already hides unused preview rows for 1-4 sliders
   and offers **"Show all… (+N)"** for >5; the full controller-state window
   renders the actual detected count in a scrolling area. Nevertheless, the
   dashboard preview controls themselves are still constructed from exactly
   five fixed slots. Review/test this presentation explicitly before release
   rather than claiming the sixth slider has no display path at all.
2. **Small-screen settings window:** on **1366 x 768 at 100% Windows display
   scaling**, the bottom controls of the slider settings window may be hidden
   behind the taskbar when six rows are shown. The project owner independently
   reproduced the hidden Save/Cancel area on an HD Ready laptop even with
   **5 sliders / 6 buttons**. Investigate the approved scale-setting experiment,
   while also verifying that essential actions remain reachable regardless of
   scale. Do not alter the normal five-slider layout silently.

The user's backup was a valid 1.0.0 schema-v1 JSON snapshot containing
`expectedSliders=6` and six slider entries. The user reported that the earlier
backup/JSON parse issue came from manually editing it and that later saves
completed successfully. Do not classify that resolved manual-editing problem
as a verified application bug without new evidence.

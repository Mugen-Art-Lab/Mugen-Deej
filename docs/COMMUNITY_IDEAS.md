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

The user proposed a **manual UI-scale selector** as the initial experiment,
with convenient small/normal/large display presets (conceptually 720p,
1080p, 1440p/"2K", and 4K). The goal is **both directions**: make dialogs
smaller on low-resolution laptop screens, and avoid tiny windows/controls
on large high-resolution monitors.

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

- provide meaningful scale presets, e.g. Auto / Compact / 100% / 125% /
  150% / 200%, with the exact list and labels agreed before coding;
- determine an initial automatic choice from **usable screen working area**
  and Windows DPI scaling, rather than treating nominal pixel resolution
  as a guaranteed physical size; avoid double-scaling with OS DPI;
- preserve layout proportions, font legibility, button hit targets and
  custom-control appearance; verify actual WinForms scaling rather than
  assuming a single `Scale()` call solves all fixed coordinates;
- keep primary dialog actions accessible; a scrollable settings-content area
  with anchored Save/Cancel may still be necessary even with compact scaling;
- retain existing 100% appearance as an explicit compatibility baseline,
  offer a way to reset an unusable scale setting and avoid affecting
  controller protocol, audio, or serial timing.

Suggested test matrix: 1366x768/100% (confirmed failure), 1920x1080,
2560x1440 and 3840x2160 at representative Windows DPI settings. Include
5 and 6+ sliders, advanced settings expanded, keyboard navigation, long
Russian/English labels, and a complete Save/Cancel path.

**UI layout/scale change requires separate user review and approval.**

## Related 2.0.0 issues (separate from these ideas)

The same early community test identified two concrete release-prep checks:

1. **Sixth analog control:** 1.0.0 detects six serial sliders and can use the
   sixth after manual configuration, but the main window still has five
   hardcoded indicator rows. The current 2.0.0 feature branch also has this
   five-row UI limit. Fix/test dynamic main-window display before release.
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

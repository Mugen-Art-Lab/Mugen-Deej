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
setup. The circuit topology and how it handles simultaneous presses have not
yet been supplied or independently verified.

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

## Related 2.0.0 issues (separate from these ideas)

The same early community test identified two concrete release-prep checks:

1. **Sixth analog control:** 1.0.0 detects six serial sliders and can use the
   sixth after manual configuration, but the main window still has five
   hardcoded indicator rows. The current 2.0.0 feature branch also has this
   five-row UI limit. Fix/test dynamic main-window display before release.
2. **Small-screen settings window:** on **1366 x 768 at 100% Windows display
   scaling**, the bottom controls of the slider settings window may be hidden
   behind the taskbar when six rows are shown. Test resize/scroll/work-area
   handling without affecting the normal five-slider layout.

The user's backup was a valid 1.0.0 schema-v1 JSON snapshot containing
`expectedSliders=6` and six slider entries. The user reported that the earlier
backup/JSON parse issue came from manually editing it and that later saves
completed successfully. Do not classify that resolved manual-editing problem
as a verified application bug without new evidence.

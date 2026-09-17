# Adaptive UI rules

Adaptive v3 is capability-driven. The desktop must render only the control families actually reported by the connected firmware; the current 5 analog / 29 button / 2 toggle / 1 encoder Uno fixture is a regression topology, not a hardcoded product shape.

## Main-window visibility

For a connected Adaptive controller:

- `DetectedSliderCount > 0`: show regulator live state and the regulator-settings entry; render exactly the reported analog-control count.
- `DetectedSliderCount == 0`: hide the regulator live-state block and regulator-settings entry completely, and reclaim their vertical space.
- `DetectedButtonCount > 0`: show momentary-button live state and button settings.
- `DetectedButtonCount == 0`: hide momentary-button state/settings.
- `DetectedToggleCount > 0`: show toggle live state.
- `DetectedToggleCount == 0`: hide toggle state.
- `DetectedEncoderCount > 0`: show encoder live state.
- `DetectedEncoderCount == 0`: hide encoder state.

The combined input card should only contain families that exist. Its title/layout must adapt to the visible families rather than assuming buttons are present.

Legacy and Extended compatibility must remain unchanged. Adaptive detection still comes from the leading `v3` marker, not from the presence of any particular family; an Adaptive packet may legally contain no `s` fields, no `b` fields, or only a subset of `s/b/t/e`.

## Size policy

Small and medium control counts wrap dynamically in the compact main window. Arbitrary firmware must not be allowed to grow the main window without bound. Large topologies should use a bounded summary plus an overflow/full-controller-state view.

## Diagnostics

Connection and diagnostics should report the discovered topology explicitly, including zero counts, e.g. `analog=0, buttons=12, toggles=8, encoders=4`.

## Current implementation note

Integrated #30 already makes momentary buttons, toggles and encoders capability-driven in the combined input card. Analog/regulator visibility has not yet been converted to the same capability-driven rule and should be handled in the next UI revision before arbitrary Adaptive topologies are considered complete.

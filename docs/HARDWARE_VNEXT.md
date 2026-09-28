# Mugen Deej — hardware vNext clean-build concept

> Work in progress. This document records the next hardware revision so the
> design context survives repository cleanup and the 2.0 release process.
>
> **This is not a Mugen Deej 2.0.0 release blocker.**
> The hardware-accepted 2.0 reference remains the existing cardboard/Nano
> controller. The clean-build panel is a follow-up hardware revision.

## Why a clean build

The current cardboard controller has become valuable as a historical and
hardware-validation prototype. Rather than dismantling it for parts, the next
panel should be built from new components in a purpose-designed enclosure.

The cardboard build should remain intact as the physical record of the first
large Adaptive controller and as a regression/debug fixture.

The new enclosure is intended to be designed in Autodesk Inventor and may
eventually be published as a printable/open DIY build (for example on a maker
model-sharing site) together with Mugen Deej firmware/wiring documentation.

## Two enclosure/reference variants

The printable clean-build hardware should intentionally support **two enclosure
variants**, not only the maximum CD74HC4067 build.

### Base / Direct Nano variant — no multiplexer

This variant preserves the topology already proven on the cardboard controller
and is intended for builders who want the simplest wiring and firmware path.

Target topology:

```text
5 analog controls
28 momentary buttons
2 illuminated latching toggles
2 rotary encoders
  E1 = CW / CCW / Push
  E2 = CW / CCW (no Push)
```

This corresponds to the already hardware-proven experimental
`adaptive:5:28:2:2` arrangement:

- C1..C7 carry the 28 buttons;
- R1C8 / R2C8 carry the two illuminated toggles;
- R3C8 / R4C8 carry E2 A/B;
- E1 remains on the direct encoder pins and keeps its dedicated Push input;
- no CD74HC4067 is required.

The clean enclosure for this variant should therefore provide physical mounting
for **two encoders** and should be usable with essentially the tested direct-Nano
architecture.

This is the low-complexity DIY option: fewer parts, less wiring, no multiplexer
bring-up, and a topology already demonstrated on real hardware.

### Expanded / 4067 variant — four Push encoders

The larger clean-build variant adds the CD74HC4067-expanded column path and
targets:

```text
5 analog controls
28 momentary buttons
2 illuminated latching toggles
4 rotary encoders, each with CW / CCW / Push
```

This variant is for builders who want the full control-surface concept and are
comfortable with the additional multiplexer wiring and firmware.

### Shared mechanical family

Where practical, both enclosures should share the same design language and as
many dimensions/components as possible:

- same 4 x 7 key grid;
- same five-potentiometer top row;
- same illuminated-toggle placement;
- same keycaps/switch plate geometry;
- same Nano/USB/service strategy.

The right-side encoder area can then have two mechanical configurations:

- **Base:** two encoder positions;
- **Expanded:** four encoder positions.

If the CAD model permits it cleanly, prefer a common lower enclosure plus
swappable/top-panel variants rather than maintaining two completely unrelated
cases. Final feasibility depends on real component measurements and internal
clearance after the ordered parts arrive.

## Current physical concept

The current hand sketch places:

- **5 potentiometers** across the top;
- **28 keyboard-style momentary buttons** in a 4 x 7 main grid;
- **2 illuminated latching toggles** at the upper-right;
- **4 rotary encoders** at the lower-right.

All four encoders are intended to be **push-capable**. Push is part of the
encoder capability, not flattened into a generic user-visible button.

Target physical capability set:

```text
5 analog controls
28 momentary buttons
2 illuminated latching toggles
4 rotary encoders, each with CW / CCW / Push
```

The existing Adaptive protocol already models encoder push as an optional
capability on each encoder:

```text
e<position>:<push>   # encoder with push
e<position>          # encoder without push
```

The existing dashboard already reflects that capability: a push-capable
encoder is drawn with a center dot and the indicator reacts visually while the
encoder is pressed.

## Dashboard direction

The dashboard should no longer force toggles and encoders into one shared row.

Preferred layout:

```text
Buttons:   existing B1..B28 grid
Layer:     existing active-layer line

Toggles:   T1 ... T2 ...
Encoders:  E1 ... E2 ... E3 ... E4 ...
```

Design intent:

- toggles have their own row;
- encoders have a separate row immediately below;
- the encoder row is designed for at least four indicators without shrinking
  section labels or values;
- all four push-capable encoders retain the existing center-dot/push highlight
  behavior;
- the main window should preferably keep its current width.

The experimental 5/28/2/2 build proved that multiple encoders already work
through Adaptive and the desktop parser. The next UI step is therefore a layout
change, not a new encoder data model.

## Matrix expansion with CD74HC4067

The current Nano build spends eight MCU pins directly on matrix columns C1..C8.
The planned clean build introduces a **CD74HC4067 16-channel analog
multiplexer** for column selection.

Conceptual MCU cost:

```text
direct C1..C8:      8 MCU pins

CD74HC4067:
  S0
  S1
  S2
  S3
  SIG
                    5 MCU pins
```

This changes the practical matrix ceiling from 4 x 8 to as much as 4 x 16:

```text
4 rows x 16 columns = 64 addressable matrix cells
```

The exact final pin map is intentionally **not frozen yet**. It must be
validated against the selected MCU board and the real CD74HC4067 module after
the ordered parts arrive.

The four-row structure is attractive because one additional matrix column gives
exactly four cells. Two encoder quadrature pairs therefore consume one column:

```text
        one column
R1      encoder A
R2      encoder B
R3      encoder A
R4      encoder B
```

For the final four push encoders, the matrix budget is still comfortable:

- 28 momentary buttons = 28 cells;
- 2 toggles = 2 cells;
- 4 encoders x (A + B + Push) = 12 cells;
- total = **42 cells**;
- theoretical 4 x 16 matrix capacity = **64 cells**;
- remaining theoretical capacity = **22 cells**.

This is a capacity calculation, not yet a hardware acceptance result.

### Encoder scan requirement

Quadrature phases must not pass through the ordinary 6 ms
button/toggle debounce.

The experimental second encoder already proved the intended approach:

- scan the encoder A/B matrix cells as raw phase inputs;
- decode them with a Gray-code transition table;
- apply separate encoder step handling;
- keep ordinary switch debounce for buttons/toggles/push contacts.

With several matrix-backed encoders and a multiplexer, scan cadence must be
measured on real hardware. Fast manual rotation must not lose or invent steps.
This is a required acceptance test before the multiplexer design becomes
reference hardware.

## Illuminated toggles

The current cardboard prototype has already hardware-proven illuminated
automotive-style toggles while keeping them in the matrix.

Current proven facts:

- each tested toggle has two main switch terminals and a separate LED-negative
  terminal;
- the internal LED positive is tied to one main switch terminal;
- the switch must be oriented so the LED-positive/contact terminal is on the
  ROW/diode side;
- LED negative connects to common GND;
- C8/D11 currently has a **325 ohm pull-up to +5 V**;
- with both illuminated toggles ON, the measured C8/D11 level was approximately
  **3.43-3.44 V**;
- buttons across all four rows were exercised with the illumination active and
  no false matrix activations were observed.

The clean-build wiring should preserve the electrical behavior, but the exact
interaction with the CD74HC4067 column path must be re-tested rather than
assumed.

## Ordered parts for the clean build

As of 2026-09-28, the following parts have been ordered.

### CD74HC4067 modules

- **4 modules** ordered;
- 16-channel analog multiplexer breakout;
- intended first use: replace direct matrix-column pins and make a larger
  matrix practical.

Only one module is expected to be needed for the first panel. Extra modules are
spares/experimentation stock.

### Rotary encoders

- **6 bare EC11-style encoders** ordered;
- push-capable;
- no breakout/module electronics;
- knurled/ridged round shaft;
- approximately **20 mm shaft length** as shown by the listing;
- listing advertises **20 detents / 20 pulses**;
- threaded bushing + nut for panel mounting.

Planned use:

- 4 encoders in the clean panel;
- 2 spare/test units.

A bare encoder is preferred because Mugen's matrix design controls its own
pull-ups, diode isolation and scan/debounce behavior.

### Potentiometers

- **5 potentiometers** ordered;
- 16K1 / RK161-style panel form factor;
- nominal resistance confirmed by the listing as **10 kOhm**;
- approximately 300-degree mechanical travel;
- 6 mm-style shaft/panel-mount construction shown in the listing.

Important unresolved item:

- the listing screenshots confirm 10 kOhm, but do **not** confirm the taper
  marking;
- verify the delivered parts are linear (ideally marked **B10K**) before
  treating them as the final reference potentiometers.

The Mugen/Nano analog reference wiring remains:

```text
outer leg -> +5 V
wiper     -> ADC input
outer leg -> GND
```

### Keyboard switches

- **70 Silver-style mechanical keyboard switches** ordered;
- **3-pin**;
- linear;
- advertised actuation force **45 +/- 10 gf**;
- full travel **4.0 mm**;
- actuation travel **1.6 mm**;
- advertised lifetime **50 million presses**;
- advertised as quiet/silent.

Planned use:

- 28 switches in the panel;
- the remaining switches are spares/future hardware stock.

Electrical use is simply a normally-open momentary contact in the matrix. The
final enclosure/plate dimensions must be measured against the real delivered
switches before the print is finalized; do not rely on marketplace artwork as a
manufacturing drawing.

## Enclosure / mechanical direction

The clean enclosure should be modeled around the real parts after arrival,
rather than forcing nominal internet dimensions onto the final print.

Current visual concept:

```text
+-------------------------------------------------------------+
| P1       P2       P3       P4       P5                      |
|                                                             |
| [B1] [B2] [B3] [B4] [B5] [B6] [B7]      [ T1 ]   [ T2 ]   |
| [B8] [B9] [B10][B11][B12][B13][B14]                        |
| [B15][B16][B17][B18][B19][B20][B21]      E1       E2       |
| [B22][B23][B24][B25][B26][B27][B28]      E3       E4       |
+-------------------------------------------------------------+
```

This drawing is conceptual. Actual spacing must account for:

- switch plate tolerances;
- keycap dimensions and finger spacing;
- encoder bushing/nut clearance;
- encoder knob diameter;
- potentiometer body and knob clearance;
- illuminated toggle body depth;
- CD74HC4067 board placement;
- Nano/MCU board placement;
- USB connector access;
- serviceability and wiring channels.

The goal is a maintainable DIY controller, not a permanently sealed sculpture.

## Current prototype vs hardware vNext

### Keep as accepted/history fixture

The existing cardboard/Nano device currently demonstrates:

- Adaptive dynamic topology;
- 5 real analog controls;
- 28 matrix buttons;
- 2 illuminated latching toggles;
- one direct encoder with Push;
- one experimental matrix encoder without Push;
- hardware-proven `adaptive:5:28:2:2`;
- virtual Xbox/XInput routing through Mugen.

Do not dismantle it merely to recover components for the clean build.

### vNext work

The clean panel may become the next documented reference controller only after
it passes real hardware tests.

Expected future bring-up sequence:

1. measure the delivered components and finish the Inventor enclosure;
2. bench-test one CD74HC4067 with the existing matrix scan conventions;
3. validate buttons/toggles through the multiplexer;
4. validate multiple raw matrix encoder phase pairs at slow and fast rotation;
5. add/validate Push for every encoder;
6. update the dashboard to a dedicated four-encoder row;
7. validate Adaptive topology and action configuration;
8. repeat virtual-controller and reconnect/hot-unplug tests;
9. only then decide whether this replaces or supplements the current Adaptive
   reference build.

## Release boundary

Mugen Deej 2.0.0 was already hardware-accepted before this clean-build concept
was created.

Do **not** delay or redefine 2.0.0 merely to wait for the new enclosure,
multiplexer, switches, potentiometers or encoders.

Treat this document as hardware-vNext design continuity while 2.0 repository
cleanup, signing decisions and release preparation continue independently.

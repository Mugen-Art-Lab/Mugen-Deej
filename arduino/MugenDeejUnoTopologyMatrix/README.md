# Mugen Deej — Uno topology matrix (16 synthetic profiles)

**Developer fixture, not production panel firmware.** Use a bare Arduino Uno and up to four jumper wires to test how Mugen Deej renders 1, 2, 5, 6, 8, 10, or 12 sliders across Legacy, Extended, and Adaptive v3.

**Full pin-to-profile table and setup instructions:** [README_RU.md](README_RU.md).

Quick selector rule: D8, D9, D10, and D11 are INPUT_PULLUP inputs, read once during boot. Short a selector pin **to GND** for a binary 1; leave it open for 0. D8 is bit 0, D11 bit 3. Profile numbers are hexadecimal 0–F. **Reset the Uno after changing jumpers.** No jumper should connect to +5V. D0/D1 are reserved for USB Serial.

The table below mirrors the source and Russian guide:

| Hex | GND jumpers | Protocol | Sliders | Buttons | Toggles | Encoders |
|---|---|---|---:|---:|---:|---:|
| 0 | none | Legacy | 1 | 0 | 0 | 0 |
| 1 | D8 | Legacy | 2 | 0 | 0 | 0 |
| 2 | D9 | Legacy | 5 | 0 | 0 | 0 |
| 3 | D8+D9 | Legacy | 6 | 0 | 0 | 0 |
| 4 | D10 | Legacy | 10 | 0 | 0 | 0 |
| 5 | D8+D10 | Extended | 1 | 1 | 0 | 0 |
| 6 | D9+D10 | Extended | 5 | 6 | 0 | 0 |
| 7 | D8+D9+D10 | Extended | 6 | 6 | 0 | 0 |
| 8 | D11 | Extended | 8 | 12 | 0 | 0 |
| 9 | D8+D11 | Extended | 12 | 28 | 0 | 0 |
| A | D9+D11 | Adaptive | 0 | 8 | 4 | 2 |
| B | D8+D9+D11 | Adaptive | 2 | 0 | 0 | 0 |
| C | D10+D11 | Adaptive | 5 | 28 | 2 | 2 |
| D | D8+D10+D11 | Adaptive | 6 | 28 | 2 | 2 |
| E | D9+D10+D11 | Adaptive | 10 | 28 | 2 | 2 |
| F | D8+D9+D10+D11 | Adaptive | 0 | 0 | 12 | 6 |

Only valid controller packets are emitted; no debug banners. Legacy and Extended transmit at 9600 baud (100/200 ms respectively), Adaptive at 115200 baud (25 ms). Slider values are deterministic, evenly distributed across 0–1023 (or 512 when only one slider). Buttons are released, toggles OFF, and encoders still.

Optional temporary GND test jumpers: D2 = button 1 pressed, D3 = toggle 1 ON, D4 = encoder 1 CW detent, D5 = encoder 1 CCW detent, D6 = encoder 1 push. These have no effect unless the profile includes the relevant control family.

Open MugenDeejUnoTopologyMatrix.ino in Arduino IDE, select Arduino Uno, upload, set selector jumpers, press RESET, then connect via Mugen Deej auto COM/baud. Close Arduino Serial Monitor first. Test dashboard, scale 80/100/Auto, controls editor, overflow behavior, and optional virtual gamepad UI.

**Safety note:** synthetic sliders can still change the real Windows/app audio levels when mapped. Prefer a clean separate portable installation and back up your normal settings before testing; mapped button or toggle actions may also fire if you use optional input jumpers.

This matrix complements, and does not replace, ../MugenDeejUnoAdaptiveTest/.

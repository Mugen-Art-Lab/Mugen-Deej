// Mugen Deej reference controller sketch
//
// Extended serial protocol:
//   s512|s123|s900|s42|s777|b1|b0|...
//
// Sliders/knobs use raw ADC values (0..1023).
// Buttons use INPUT_PULLUP by default, so:
//   0 = pressed
//   1 = released
//
// This sketch deliberately avoids Arduino String construction in the hot loop.
// Fields are written directly to Serial to keep RAM usage predictable.

#include <Arduino.h>

// -----------------------------------------------------------------------------
// Hardware configuration
// -----------------------------------------------------------------------------

const uint8_t SLIDER_PINS[] = {A0, A1, A2, A3, A4};
const size_t NUM_SLIDERS = sizeof(SLIDER_PINS) / sizeof(SLIDER_PINS[0]);

// Set to 0 for a controls-only Mugen Deej build.
#define MUGEN_DEEJ_HAS_BUTTONS 1

#if MUGEN_DEEJ_HAS_BUTTONS
const uint8_t BUTTON_PINS[] = {9, 8, 7, 6, 5, 4};
const size_t NUM_BUTTONS = sizeof(BUTTON_PINS) / sizeof(BUTTON_PINS[0]);
#endif

const unsigned long SERIAL_BAUD = 9600;
const unsigned long FRAME_INTERVAL_MS = 10;

// -----------------------------------------------------------------------------
// Runtime state
// -----------------------------------------------------------------------------

int sliderValues[NUM_SLIDERS];

#if MUGEN_DEEJ_HAS_BUTTONS
uint8_t buttonValues[NUM_BUTTONS];
#endif

unsigned long lastFrameAt = 0;

// -----------------------------------------------------------------------------
// Setup
// -----------------------------------------------------------------------------

void setup() {
  for (size_t i = 0; i < NUM_SLIDERS; ++i) {
    pinMode(SLIDER_PINS[i], INPUT);
  }

#if MUGEN_DEEJ_HAS_BUTTONS
  for (size_t i = 0; i < NUM_BUTTONS; ++i) {
    pinMode(BUTTON_PINS[i], INPUT_PULLUP);
  }
#endif

  Serial.begin(SERIAL_BAUD);
}

// -----------------------------------------------------------------------------
// Input sampling
// -----------------------------------------------------------------------------

void sampleInputs() {
  for (size_t i = 0; i < NUM_SLIDERS; ++i) {
    sliderValues[i] = analogRead(SLIDER_PINS[i]);
  }

#if MUGEN_DEEJ_HAS_BUTTONS
  for (size_t i = 0; i < NUM_BUTTONS; ++i) {
    buttonValues[i] = static_cast<uint8_t>(digitalRead(BUTTON_PINS[i]));
  }
#endif
}

// -----------------------------------------------------------------------------
// Protocol output
// -----------------------------------------------------------------------------

void writeSeparator(bool &firstField) {
  if (!firstField) {
    Serial.print('|');
  }
  firstField = false;
}

void sendFrame() {
  bool firstField = true;

  for (size_t i = 0; i < NUM_SLIDERS; ++i) {
    writeSeparator(firstField);
    Serial.print('s');
    Serial.print(sliderValues[i]);
  }

#if MUGEN_DEEJ_HAS_BUTTONS
  for (size_t i = 0; i < NUM_BUTTONS; ++i) {
    writeSeparator(firstField);
    Serial.print('b');
    Serial.print(buttonValues[i]);
  }
#endif

  Serial.println();
}

// -----------------------------------------------------------------------------
// Main loop
// -----------------------------------------------------------------------------

void loop() {
  const unsigned long now = millis();

  if (now - lastFrameAt < FRAME_INTERVAL_MS) {
    return;
  }

  lastFrameAt = now;
  sampleInputs();
  sendFrame();
}

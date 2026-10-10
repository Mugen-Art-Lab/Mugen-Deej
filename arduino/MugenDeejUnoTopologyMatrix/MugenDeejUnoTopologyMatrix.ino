/*
  Mugen Deej Uno topology matrix — bare-board UI regression fixture

  Select one of 16 controller shapes using D8..D11 -> GND, then press RESET.
  OPEN = bit 0, connected to GND = bit 1.  D8 is the low bit.

  Hex  Protocol   Sliders Buttons Toggles Encoders  Baud
   0  Legacy       1       0       0       0       9600
   1  Legacy       2       0       0       0       9600
   2  Legacy       5       0       0       0       9600
   3  Legacy       6       0       0       0       9600
   4  Legacy      10       0       0       0       9600
   5  Extended     1       1       0       0       9600
   6  Extended     5       6       0       0       9600
   7  Extended     6       6       0       0       9600
   8  Extended     8      12       0       0       9600
   9  Extended    12      28       0       0       9600
   A  Adaptive     0       8       4       2     115200
   B  Adaptive     2       0       0       0     115200
   C  Adaptive     5      28       2       2     115200
   D  Adaptive     6      28       2       2     115200
   E  Adaptive    10      28       2       2     115200
   F  Adaptive     0       0      12       6     115200

  No pots, buttons, encoders, or resistors required. Synthetic slider values
  are evenly distributed from 0 to 1023 (one slider is fixed at 512).
  All buttons default to released; toggles default to OFF; encoders to zero.

  OPTIONAL live test inputs (also INPUT_PULLUP, connect briefly to GND):
    D2: button 1 pressed while grounded
    D3: toggle 1 ON while grounded
    D4: one encoder-1 +1 step for each falling edge
    D5: one encoder-1 -1 step for each falling edge
    D6: encoder-1 push pressed while grounded

  No diagnostic/banner text is sent to Serial: only valid protocol packets.
  This developer fixture is NOT the hardware reference firmware.
*/

#include <Arduino.h>

enum Generation : uint8_t {
  LEGACY = 0,
  EXTENDED = 1,
  ADAPTIVE = 2
};

struct Profile {
  uint8_t generation;
  uint8_t sliders;
  uint8_t buttons;
  uint8_t toggles;
  uint8_t encoders;
};

const Profile PROFILES[16] = {
  { LEGACY,    1,  0,  0, 0 }, // 0
  { LEGACY,    2,  0,  0, 0 }, // 1
  { LEGACY,    5,  0,  0, 0 }, // 2
  { LEGACY,    6,  0,  0, 0 }, // 3
  { LEGACY,   10,  0,  0, 0 }, // 4
  { EXTENDED,  1,  1,  0, 0 }, // 5
  { EXTENDED,  5,  6,  0, 0 }, // 6
  { EXTENDED,  6,  6,  0, 0 }, // 7
  { EXTENDED,  8, 12,  0, 0 }, // 8
  { EXTENDED, 12, 28,  0, 0 }, // 9
  { ADAPTIVE,  0,  8,  4, 2 }, // A
  { ADAPTIVE,  2,  0,  0, 0 }, // B
  { ADAPTIVE,  5, 28,  2, 2 }, // C
  { ADAPTIVE,  6, 28,  2, 2 }, // D
  { ADAPTIVE, 10, 28,  2, 2 }, // E
  { ADAPTIVE,  0,  0, 12, 6 }  // F
};

// Selector bits sampled ONCE at startup, not during normal transmission.
const uint8_t SELECTOR_PINS[4] = { 8, 9, 10, 11 };
const uint8_t BUTTON1_PIN = 2;
const uint8_t TOGGLE1_PIN = 3;
const uint8_t ENCODER_CW_PIN = 4;
const uint8_t ENCODER_CCW_PIN = 5;
const uint8_t ENCODER_PUSH_PIN = 6;

const unsigned long LEGACY_HEARTBEAT_MS = 100;
const unsigned long EXTENDED_HEARTBEAT_MS = 200;
const unsigned long ADAPTIVE_HEARTBEAT_MS = 25;
const unsigned long ENCODER_EDGE_DEBOUNCE_MS = 45;

Profile activeProfile;
unsigned long packetIntervalMs = LEGACY_HEARTBEAT_MS;
unsigned long lastPacketMs = 0;
unsigned long lastCwEdgeMs = 0;
unsigned long lastCcwEdgeMs = 0;
long firstEncoderPosition = 0;

uint8_t lastButton = HIGH;
uint8_t lastToggle = HIGH;
uint8_t lastPush = HIGH;
uint8_t lastCw = HIGH;
uint8_t lastCcw = HIGH;

uint16_t syntheticSliderValue(uint8_t index, uint8_t count) {
  if (count <= 1) {
    return 512;
  }
  // Spread synthetic bars across the full ADC range without reading any ADC.
  return (uint16_t)(((uint32_t)index * 1023UL +
                     (uint32_t)(count - 1) / 2UL) / (count - 1));
}

void separator(bool &first) {
  if (!first) {
    Serial.print('|');
  }
  first = false;
}

void sendPacket(uint8_t button, uint8_t toggle, uint8_t push) {
  bool first = true;

  if (activeProfile.generation == ADAPTIVE) {
    Serial.print(F("v3"));
    first = false;
  }

  for (uint8_t i = 0; i < activeProfile.sliders; ++i) {
    separator(first);
    if (activeProfile.generation != LEGACY) {
      Serial.print('s');
    }
    Serial.print(syntheticSliderValue(i, activeProfile.sliders));
  }

  for (uint8_t i = 0; i < activeProfile.buttons; ++i) {
    separator(first);
    Serial.print('b');
    Serial.print((i == 0 && button == LOW) ? 0 : 1);
  }

  if (activeProfile.generation == ADAPTIVE) {
    for (uint8_t i = 0; i < activeProfile.toggles; ++i) {
      separator(first);
      Serial.print('t');
      Serial.print((i == 0 && toggle == LOW) ? 1 : 0);
    }

    for (uint8_t i = 0; i < activeProfile.encoders; ++i) {
      separator(first);
      Serial.print('e');
      Serial.print(i == 0 ? firstEncoderPosition : 0L);
      if (i == 0) {
        Serial.print(':');
        Serial.print(push == LOW ? 0 : 1);
      }
    }
  }

  Serial.println();
}

void setup() {
  for (uint8_t i = 0; i < 4; ++i) {
    pinMode(SELECTOR_PINS[i], INPUT_PULLUP);
  }
  pinMode(BUTTON1_PIN, INPUT_PULLUP);
  pinMode(TOGGLE1_PIN, INPUT_PULLUP);
  pinMode(ENCODER_CW_PIN, INPUT_PULLUP);
  pinMode(ENCODER_CCW_PIN, INPUT_PULLUP);
  pinMode(ENCODER_PUSH_PIN, INPUT_PULLUP);

  // Let internal pullups settle before reading the selector jumpers.
  delay(5);
  uint8_t profileIndex = 0;
  for (uint8_t i = 0; i < 4; ++i) {
    if (digitalRead(SELECTOR_PINS[i]) == LOW) {
      profileIndex |= (uint8_t)(1U << i);
    }
  }
  activeProfile = PROFILES[profileIndex];

  unsigned long baud = 9600;
  if (activeProfile.generation == ADAPTIVE) {
    baud = 115200;
    packetIntervalMs = ADAPTIVE_HEARTBEAT_MS;
  } else if (activeProfile.generation == EXTENDED) {
    packetIntervalMs = EXTENDED_HEARTBEAT_MS;
  }
  Serial.begin(baud);

  lastButton = digitalRead(BUTTON1_PIN);
  lastToggle = digitalRead(TOGGLE1_PIN);
  lastPush = digitalRead(ENCODER_PUSH_PIN);
  lastCw = digitalRead(ENCODER_CW_PIN);
  lastCcw = digitalRead(ENCODER_CCW_PIN);

  // Send the first VALID packet immediately, without a startup banner.
  lastPacketMs = millis() - packetIntervalMs;
}

void loop() {
  const unsigned long now = millis();
  const uint8_t button = digitalRead(BUTTON1_PIN);
  const uint8_t toggle = digitalRead(TOGGLE1_PIN);
  const uint8_t push = digitalRead(ENCODER_PUSH_PIN);
  const uint8_t cw = digitalRead(ENCODER_CW_PIN);
  const uint8_t ccw = digitalRead(ENCODER_CCW_PIN);

  bool changed = false;
  if (activeProfile.buttons > 0 && button != lastButton) {
    changed = true;
  }
  if (activeProfile.toggles > 0 && toggle != lastToggle) {
    changed = true;
  }
  if (activeProfile.encoders > 0 && push != lastPush) {
    changed = true;
  }

  if (activeProfile.encoders > 0) {
    if (lastCw == HIGH && cw == LOW &&
        (unsigned long)(now - lastCwEdgeMs) >= ENCODER_EDGE_DEBOUNCE_MS) {
      ++firstEncoderPosition;
      lastCwEdgeMs = now;
      changed = true;
    }
    if (lastCcw == HIGH && ccw == LOW &&
        (unsigned long)(now - lastCcwEdgeMs) >= ENCODER_EDGE_DEBOUNCE_MS) {
      --firstEncoderPosition;
      lastCcwEdgeMs = now;
      changed = true;
    }
  }

  lastButton = button;
  lastToggle = toggle;
  lastPush = push;
  lastCw = cw;
  lastCcw = ccw;

  if (changed || (unsigned long)(now - lastPacketMs) >= packetIntervalMs) {
    sendPacket(button, toggle, push);
    lastPacketMs = millis();
  }
}

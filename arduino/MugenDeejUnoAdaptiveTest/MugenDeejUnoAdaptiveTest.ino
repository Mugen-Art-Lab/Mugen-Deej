/*
  Mugen Deej Uno Adaptive v3 topology test
  ========================================

  Bare-Arduino fixture for exercising multiple self-described Adaptive v3
  controller shapes without rewiring a real panel.

  Select one topology with D8/D9 BEFORE reset/power-up (INPUT_PULLUP):

    D8   D9   Profile
    ---  ---  --------------------------------------------
    OPEN OPEN 5 sliders / 29 buttons / 2 toggles / 1 encoder
    GND  OPEN 0 sliders / 8 buttons / 4 toggles / 2 encoders
    OPEN GND  2 sliders / 0 buttons / 0 toggles / 0 encoders
    GND  GND  0 sliders / 0 buttons / 12 toggles / 6 encoders

  The first profile remains the existing regression fixture. D2..D7 retain
  their original live-test meaning where that input family exists:

    D2 -> first momentary button
    D3 -> first toggle
    D4 -> second toggle
    D5 -> first encoder push
    D6 -> first encoder synthetic CW detent (+1)
    D7 -> first encoder synthetic CCW detent (-1)

  Extra controls in the larger profiles are deterministic idle controls. The
  point is topology/UI validation, not pretending a bare Uno has that much
  physical panel hardware attached.
*/

const unsigned long SERIAL_BAUD = 115200;
const unsigned long PACKET_INTERVAL_MS = 25;
const unsigned long STEP_DEBOUNCE_MS = 35;

const uint8_t BUTTON_PIN = 2;
const uint8_t TOGGLE1_PIN = 3;
const uint8_t TOGGLE2_PIN = 4;
const uint8_t ENCODER_PUSH_PIN = 5;
const uint8_t ENCODER_CW_TEST_PIN = 6;
const uint8_t ENCODER_CCW_TEST_PIN = 7;
const uint8_t PROFILE_A_PIN = 8;
const uint8_t PROFILE_B_PIN = 9;

struct FixtureProfile {
  uint8_t sliders;
  uint8_t buttons;
  uint8_t toggles;
  uint8_t encoders;
};

const FixtureProfile PROFILES[4] = {
  { 5, 29,  2, 1 },
  { 0,  8,  4, 2 },
  { 2,  0,  0, 0 },
  { 0,  0, 12, 6 }
};

const uint16_t FIXED_ANALOG_VALUES[5] = {
  0,
  256,
  512,
  768,
  1023
};

uint8_t selectedProfile = 0;
FixtureProfile activeProfile = PROFILES[0];

unsigned long lastPacketAt = 0;
unsigned long lastCwStepAt = 0;
unsigned long lastCcwStepAt = 0;

uint8_t lastButtonState = HIGH;
uint8_t lastToggle1State = HIGH;
uint8_t lastToggle2State = HIGH;
uint8_t lastEncoderPushState = HIGH;
uint8_t lastCwTestState = HIGH;
uint8_t lastCcwTestState = HIGH;

long encoderPositions[6] = { 0, 0, 0, 0, 0, 0 };

void setup() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(TOGGLE1_PIN, INPUT_PULLUP);
  pinMode(TOGGLE2_PIN, INPUT_PULLUP);
  pinMode(ENCODER_PUSH_PIN, INPUT_PULLUP);
  pinMode(ENCODER_CW_TEST_PIN, INPUT_PULLUP);
  pinMode(ENCODER_CCW_TEST_PIN, INPUT_PULLUP);
  pinMode(PROFILE_A_PIN, INPUT_PULLUP);
  pinMode(PROFILE_B_PIN, INPUT_PULLUP);

  const uint8_t profileA = digitalRead(PROFILE_A_PIN);
  const uint8_t profileB = digitalRead(PROFILE_B_PIN);
  selectedProfile = (profileA == LOW ? 1 : 0) | (profileB == LOW ? 2 : 0);
  activeProfile = PROFILES[selectedProfile];

  Serial.begin(SERIAL_BAUD);

  lastButtonState = digitalRead(BUTTON_PIN);
  lastToggle1State = digitalRead(TOGGLE1_PIN);
  lastToggle2State = digitalRead(TOGGLE2_PIN);
  lastEncoderPushState = digitalRead(ENCODER_PUSH_PIN);
  lastCwTestState = digitalRead(ENCODER_CW_TEST_PIN);
  lastCcwTestState = digitalRead(ENCODER_CCW_TEST_PIN);

  const unsigned long now = millis();
  lastPacketAt = now - PACKET_INTERVAL_MS;
}

void loop() {
  const unsigned long now = millis();

  const uint8_t buttonState = digitalRead(BUTTON_PIN);
  const uint8_t toggle1State = digitalRead(TOGGLE1_PIN);
  const uint8_t toggle2State = digitalRead(TOGGLE2_PIN);
  const uint8_t encoderPushState = digitalRead(ENCODER_PUSH_PIN);
  const uint8_t cwTestState = digitalRead(ENCODER_CW_TEST_PIN);
  const uint8_t ccwTestState = digitalRead(ENCODER_CCW_TEST_PIN);

  bool stateChanged = false;
  if (activeProfile.buttons > 0 && buttonState != lastButtonState) {
    stateChanged = true;
  }
  if (activeProfile.toggles > 0 && toggle1State != lastToggle1State) {
    stateChanged = true;
  }
  if (activeProfile.toggles > 1 && toggle2State != lastToggle2State) {
    stateChanged = true;
  }
  if (activeProfile.encoders > 0 && encoderPushState != lastEncoderPushState) {
    stateChanged = true;
  }

  if (
      activeProfile.encoders > 0 &&
      lastCwTestState == HIGH &&
      cwTestState == LOW &&
      (unsigned long)(now - lastCwStepAt) >= STEP_DEBOUNCE_MS
  ) {
    ++encoderPositions[0];
    lastCwStepAt = now;
    stateChanged = true;
  }

  if (
      activeProfile.encoders > 0 &&
      lastCcwTestState == HIGH &&
      ccwTestState == LOW &&
      (unsigned long)(now - lastCcwStepAt) >= STEP_DEBOUNCE_MS
  ) {
    --encoderPositions[0];
    lastCcwStepAt = now;
    stateChanged = true;
  }

  lastButtonState = buttonState;
  lastToggle1State = toggle1State;
  lastToggle2State = toggle2State;
  lastEncoderPushState = encoderPushState;
  lastCwTestState = cwTestState;
  lastCcwTestState = ccwTestState;

  const bool periodicPacketDue =
      (unsigned long)(now - lastPacketAt) >= PACKET_INTERVAL_MS;

  if (stateChanged || periodicPacketDue) {
    sendStatePacket(
        buttonState,
        toggle1State,
        toggle2State,
        encoderPushState
    );
    lastPacketAt = now;
  }
}

void sendStatePacket(
    const uint8_t buttonState,
    const uint8_t toggle1ElectricalState,
    const uint8_t toggle2ElectricalState,
    const uint8_t encoderPushState
) {
  Serial.print("v3");

  for (uint8_t i = 0; i < activeProfile.sliders; ++i) {
    Serial.print('|');
    Serial.print('s');
    Serial.print(FIXED_ANALOG_VALUES[i % 5]);
  }

  for (uint8_t i = 0; i < activeProfile.buttons; ++i) {
    Serial.print('|');
    Serial.print('b');
    if (i == 0) {
      Serial.print(buttonState == LOW ? 0 : 1);
    }
    else {
      Serial.print(1);
    }
  }

  for (uint8_t i = 0; i < activeProfile.toggles; ++i) {
    Serial.print('|');
    Serial.print('t');
    if (i == 0) {
      Serial.print(toggle1ElectricalState == LOW ? 1 : 0);
    }
    else if (i == 1) {
      Serial.print(toggle2ElectricalState == LOW ? 1 : 0);
    }
    else {
      Serial.print(0);
    }
  }

  for (uint8_t i = 0; i < activeProfile.encoders; ++i) {
    Serial.print('|');
    Serial.print('e');
    Serial.print(encoderPositions[i]);

    // Only encoder 1 advertises a push switch on this bare-fixture sketch.
    if (i == 0) {
      Serial.print(':');
      Serial.print(encoderPushState == LOW ? 0 : 1);
    }
  }

  Serial.println();
}

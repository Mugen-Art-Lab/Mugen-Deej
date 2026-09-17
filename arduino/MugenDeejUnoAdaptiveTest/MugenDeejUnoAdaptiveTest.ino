/*
  Mugen Deej Uno Adaptive v3 Test
  ================================

  PURPOSE
  -------
  Bare-Arduino fixture for validating Mugen Deej's third serial protocol
  generation: Adaptive v3.

  Adaptive v3 is explicitly versioned and self-describing by typed fields:

      v3|s...|b...|t...|e...

  This sketch deliberately needs no real panel hardware. Jumper wires are
  enough to exercise one momentary button, two latching-toggle states, encoder
  push, and synthetic clockwise/counter-clockwise encoder steps.

  Emulated logical controller shape:

      5 analog controls
      29 momentary buttons
      2 latching toggles
      1 rotary encoder with push

  Wire semantics:

      s0..1023     analog value
      b0 / b1      pressed / released (same as Extended)
      t0 / t1      OFF / ON logical toggle state
      ePOS:PUSH    cumulative signed encoder position + push state
                   PUSH uses button semantics: 0 pressed, 1 released

  Test pins (all INPUT_PULLUP):

      D2 -> button 1        open=released, GND=pressed
      D3 -> toggle 1        open=OFF,      GND=ON
      D4 -> toggle 2        open=OFF,      GND=ON
      D5 -> encoder push    open=released, GND=pressed
      D6 -> encoder CW test briefly GND once -> position +1
      D7 -> encoder CCW     briefly GND once -> position -1

  Serial speed: 115200 baud.
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

const uint8_t NUM_BUTTON_FIELDS = 29;

const uint16_t FIXED_ANALOG_VALUES[5] = {
  0,
  256,
  512,
  768,
  1023
};

unsigned long lastPacketAt = 0;
unsigned long lastCwStepAt = 0;
unsigned long lastCcwStepAt = 0;

uint8_t lastButtonState = HIGH;
uint8_t lastToggle1State = HIGH;
uint8_t lastToggle2State = HIGH;
uint8_t lastEncoderPushState = HIGH;
uint8_t lastCwTestState = HIGH;
uint8_t lastCcwTestState = HIGH;

long encoderPosition = 0;

void setup() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(TOGGLE1_PIN, INPUT_PULLUP);
  pinMode(TOGGLE2_PIN, INPUT_PULLUP);
  pinMode(ENCODER_PUSH_PIN, INPUT_PULLUP);
  pinMode(ENCODER_CW_TEST_PIN, INPUT_PULLUP);
  pinMode(ENCODER_CCW_TEST_PIN, INPUT_PULLUP);

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

  bool stateChanged = (
      buttonState != lastButtonState ||
      toggle1State != lastToggle1State ||
      toggle2State != lastToggle2State ||
      encoderPushState != lastEncoderPushState
  );

  // Falling edges on D6/D7 simulate complete encoder detents. Cumulative
  // position is intentional: if one serial frame is skipped, the next frame
  // still contains the complete position and the desktop can recover delta.
  if (
      lastCwTestState == HIGH &&
      cwTestState == LOW &&
      (unsigned long)(now - lastCwStepAt) >= STEP_DEBOUNCE_MS
  ) {
    ++encoderPosition;
    lastCwStepAt = now;
    stateChanged = true;
  }

  if (
      lastCcwTestState == HIGH &&
      ccwTestState == LOW &&
      (unsigned long)(now - lastCcwStepAt) >= STEP_DEBOUNCE_MS
  ) {
    --encoderPosition;
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

  for (uint8_t i = 0; i < 5; ++i) {
    Serial.print('|');
    Serial.print('s');
    Serial.print(FIXED_ANALOG_VALUES[i]);
  }

  // Button 1 is physical D2; buttons 2..29 stay released.
  for (uint8_t i = 0; i < NUM_BUTTON_FIELDS; ++i) {
    Serial.print('|');
    Serial.print('b');
    if (i == 0) {
      Serial.print(buttonState == LOW ? 0 : 1);
    }
    else {
      Serial.print(1);
    }
  }

  // INPUT_PULLUP electrical state is converted to logical toggle state:
  // open/HIGH = OFF = t0, grounded/LOW = ON = t1.
  Serial.print('|');
  Serial.print('t');
  Serial.print(toggle1ElectricalState == LOW ? 1 : 0);

  Serial.print('|');
  Serial.print('t');
  Serial.print(toggle2ElectricalState == LOW ? 1 : 0);

  // One first-class encoder. Position is cumulative; push preserves the
  // button convention used by Mugen: 0 pressed, 1 released.
  Serial.print('|');
  Serial.print('e');
  Serial.print(encoderPosition);
  Serial.print(':');
  Serial.print(encoderPushState == LOW ? 0 : 1);

  Serial.println();
}

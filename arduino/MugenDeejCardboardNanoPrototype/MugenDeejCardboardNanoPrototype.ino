/*
  Mugen Deej cardboard prototype — Arduino Nano full analog build
  ===============================================================

  Physical prototype:
    - 28 momentary buttons in a 4x7 visible grid
    - 2 latching toggles in matrix column C8 (R1C8 / R2C8)
    - 1 rotary encoder module with S1/S2/KEY/5V/GND
    - 5 real potentiometers on A3..A7

  Adaptive v3 topology exposed to Mugen Deej:
    5 sliders / 28 buttons / 2 toggles / 1 encoder with push

  Classic Nano pin map:
    Encoder S1 -> D2
    Encoder S2 -> D3
    Encoder KEY -> A2
    Encoder 5V -> 5V
    Encoder GND -> GND

    Matrix C1..C8 -> D4,D5,D6,D7,D8,D9,D10,D11
    Matrix R1..R4 -> D12,D13,A0,A1

    Potentiometer wipers:
      P1 -> A3
      P2 -> A4
      P3 -> A5
      P4 -> A6
      P5 -> A7

    Potentiometer outer legs:
      one side -> 5V
      other side -> GND

  A6/A7 are analog-input-only on the classic ATmega328P Nano, which is exactly
  what this build needs. D0/D1 stay reserved for USB serial.

  Matrix electrical convention:
    columns use INPUT_PULLUP
    one row at a time is driven LOW; inactive diode-isolated rows stay HIGH
    each key has its own diode:
      COLUMN -> switch -> diode anode -> diode cathode/stripe -> ROW
*/

#include <Arduino.h>

// ---------------------------------------------------------------------------
// Pin map
// ---------------------------------------------------------------------------

const uint8_t ENCODER_S1_PIN = 2;
const uint8_t ENCODER_S2_PIN = 3;
const uint8_t ENCODER_KEY_PIN = A2;

const uint8_t MATRIX_COL_PINS[8] = {
  4, 5, 6, 7, 8, 9, 10, 11
};

const uint8_t MATRIX_ROW_PINS[4] = {
  12, 13, A0, A1
};

const uint8_t POT_PINS[5] = {
  A3, A4, A5, A6, A7
};

// ---------------------------------------------------------------------------
// Transport / timing
// ---------------------------------------------------------------------------

const unsigned long SERIAL_BAUD = 115200;
const unsigned long PACKET_INTERVAL_MS = 25;
const unsigned long MATRIX_DEBOUNCE_MS = 18;
const unsigned long KEY_DEBOUNCE_MS = 20;

// Keep the raw ADC path intentionally simple for the first real-potentiometer
// test. Mugen's desktop noise threshold can be observed/tuned from real data
// before any firmware-side smoothing is added.
const uint8_t NUM_POTS = 5;

// The pictured 20-detent module is expected to produce one full quadrature
// cycle per detent. If one click later produces multiple counts or no count,
// this is the first constant to revisit.
const int8_t ENCODER_EDGES_PER_STEP = 4;
const int8_t ENCODER_DIRECTION = 1;

// ---------------------------------------------------------------------------
// Matrix layout
// ---------------------------------------------------------------------------
//
//              C1   C2   C3   C4   C5   C6   C7   C8
// R1           B1   B2   B3   B4   B5   B6   B7   T1
// R2           B8   B9   B10  B11  B12  B13  B14  T2
// R3           B15  B16  B17  B18  B19  B20  B21  spare
// R4           B22  B23  B24  B25  B26  B27  B28  spare
//
// C8 is intentionally excluded from the 28 ordinary button fields.

const uint8_t NUM_ROWS = 4;
const uint8_t NUM_COLS = 8;
const uint8_t NUM_MATRIX_CELLS = NUM_ROWS * NUM_COLS;

const uint8_t TOGGLE1_CELL = 0 * NUM_COLS + 7; // R1C8
const uint8_t TOGGLE2_CELL = 1 * NUM_COLS + 7; // R2C8

uint8_t matrixRaw[NUM_MATRIX_CELLS];
uint8_t matrixStable[NUM_MATRIX_CELLS];
unsigned long matrixRawChangedAt[NUM_MATRIX_CELLS];

uint8_t keyRaw = HIGH;
uint8_t keyStable = HIGH;
unsigned long keyRawChangedAt = 0;

// ---------------------------------------------------------------------------
// Encoder state
// ---------------------------------------------------------------------------

volatile uint8_t encoderPreviousAB = 0;
volatile int8_t encoderSubsteps = 0;
volatile long encoderPosition = 0;
volatile bool encoderPositionChanged = false;

// Gray-code transition table. Index = previousAB << 2 | currentAB.
const int8_t ENCODER_TRANSITION_TABLE[16] = {
   0, -1,  1,  0,
   1,  0,  0, -1,
  -1,  0,  0,  1,
   0,  1, -1,  0
};

unsigned long lastPacketAt = 0;

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

void setup() {
  for (uint8_t col = 0; col < NUM_COLS; ++col) {
    pinMode(MATRIX_COL_PINS[col], INPUT_PULLUP);
  }

  // Per-key diodes let inactive rows stay actively HIGH. This is especially
  // useful on D13, whose onboard LED makes it a poor floating input.
  for (uint8_t row = 0; row < NUM_ROWS; ++row) {
    pinMode(MATRIX_ROW_PINS[row], OUTPUT);
    digitalWrite(MATRIX_ROW_PINS[row], HIGH);
  }

  pinMode(ENCODER_S1_PIN, INPUT_PULLUP);
  pinMode(ENCODER_S2_PIN, INPUT_PULLUP);
  pinMode(ENCODER_KEY_PIN, INPUT_PULLUP);

  // A3..A7 are used only as ADC inputs. No pinMode is required for analogRead.
  Serial.begin(SERIAL_BAUD);

  const unsigned long now = millis();
  initializeMatrix(now);

  keyRaw = digitalRead(ENCODER_KEY_PIN);
  keyStable = keyRaw;
  keyRawChangedAt = now;

  encoderPreviousAB = readEncoderAB();
  attachInterrupt(digitalPinToInterrupt(ENCODER_S1_PIN), handleEncoderChange, CHANGE);
  attachInterrupt(digitalPinToInterrupt(ENCODER_S2_PIN), handleEncoderChange, CHANGE);

  lastPacketAt = now - PACKET_INTERVAL_MS;
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

void loop() {
  const unsigned long now = millis();

  const bool matrixChanged = updateMatrix(now);
  const bool keyChanged = updateEncoderKey(now);

  bool encoderChanged = false;
  noInterrupts();
  if (encoderPositionChanged) {
    encoderChanged = true;
    encoderPositionChanged = false;
  }
  interrupts();

  const bool heartbeatDue =
      (unsigned long)(now - lastPacketAt) >= PACKET_INTERVAL_MS;

  if (matrixChanged || keyChanged || encoderChanged || heartbeatDue) {
    sendAdaptivePacket();
    lastPacketAt = millis();
  }
}

// ---------------------------------------------------------------------------
// Matrix scan + debounce
// ---------------------------------------------------------------------------

void scanMatrix(uint8_t *states) {
  for (uint8_t row = 0; row < NUM_ROWS; ++row) {
    digitalWrite(MATRIX_ROW_PINS[row], LOW);
    delayMicroseconds(4);

    for (uint8_t col = 0; col < NUM_COLS; ++col) {
      const uint8_t index = row * NUM_COLS + col;
      states[index] = digitalRead(MATRIX_COL_PINS[col]);
    }

    digitalWrite(MATRIX_ROW_PINS[row], HIGH);
  }
}

void initializeMatrix(const unsigned long now) {
  uint8_t initial[NUM_MATRIX_CELLS];
  scanMatrix(initial);

  for (uint8_t i = 0; i < NUM_MATRIX_CELLS; ++i) {
    matrixRaw[i] = initial[i];
    matrixStable[i] = initial[i];
    matrixRawChangedAt[i] = now;
  }
}

bool updateMatrix(const unsigned long now) {
  bool changed = false;
  uint8_t scanned[NUM_MATRIX_CELLS];
  scanMatrix(scanned);

  for (uint8_t i = 0; i < NUM_MATRIX_CELLS; ++i) {
    if (scanned[i] != matrixRaw[i]) {
      matrixRaw[i] = scanned[i];
      matrixRawChangedAt[i] = now;
    }

    if (
      matrixStable[i] != matrixRaw[i] &&
      (unsigned long)(now - matrixRawChangedAt[i]) >= MATRIX_DEBOUNCE_MS
    ) {
      matrixStable[i] = matrixRaw[i];
      changed = true;
    }
  }

  return changed;
}

// ---------------------------------------------------------------------------
// Encoder push debounce
// ---------------------------------------------------------------------------

bool updateEncoderKey(const unsigned long now) {
  const uint8_t reading = digitalRead(ENCODER_KEY_PIN);

  if (reading != keyRaw) {
    keyRaw = reading;
    keyRawChangedAt = now;
  }

  if (
    keyStable != keyRaw &&
    (unsigned long)(now - keyRawChangedAt) >= KEY_DEBOUNCE_MS
  ) {
    keyStable = keyRaw;
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// Quadrature encoder
// ---------------------------------------------------------------------------

uint8_t readEncoderAB() {
  uint8_t value = 0;
  if (digitalRead(ENCODER_S1_PIN) == HIGH) {
    value |= 0x02;
  }
  if (digitalRead(ENCODER_S2_PIN) == HIGH) {
    value |= 0x01;
  }
  return value;
}

void handleEncoderChange() {
  const uint8_t currentAB = readEncoderAB();
  const uint8_t transition = (encoderPreviousAB << 2) | currentAB;
  const int8_t delta = ENCODER_TRANSITION_TABLE[transition & 0x0F];

  encoderPreviousAB = currentAB;
  if (delta == 0) {
    return;
  }

  encoderSubsteps += delta * ENCODER_DIRECTION;

  if (encoderSubsteps >= ENCODER_EDGES_PER_STEP) {
    ++encoderPosition;
    encoderSubsteps = 0;
    encoderPositionChanged = true;
  }
  else if (encoderSubsteps <= -ENCODER_EDGES_PER_STEP) {
    --encoderPosition;
    encoderSubsteps = 0;
    encoderPositionChanged = true;
  }
}

// ---------------------------------------------------------------------------
// Analog controls
// ---------------------------------------------------------------------------

uint16_t readPotentiometer(const uint8_t pin) {
  // Discard one conversion after switching ADC channels. With normal 10k-ish
  // potentiometers this is conservative and still leaves huge timing margin.
  (void)analogRead(pin);
  return (uint16_t)analogRead(pin);
}

// ---------------------------------------------------------------------------
// Adaptive v3 packet
// ---------------------------------------------------------------------------

void sendAdaptivePacket() {
  long positionSnapshot;

  noInterrupts();
  positionSnapshot = encoderPosition;
  interrupts();

  Serial.print(F("v3"));

  // Five real potentiometers, raw ATmega328P ADC range 0..1023.
  for (uint8_t i = 0; i < NUM_POTS; ++i) {
    Serial.print(F("|s"));
    Serial.print(readPotentiometer(POT_PINS[i]));
  }

  // 28 ordinary buttons: C1..C7 across each row.
  for (uint8_t row = 0; row < NUM_ROWS; ++row) {
    for (uint8_t col = 0; col < 7; ++col) {
      const uint8_t index = row * NUM_COLS + col;
      Serial.print(F("|b"));
      Serial.print(matrixStable[index] == LOW ? 0 : 1);
    }
  }

  // Latching toggles in R1C8 / R2C8.
  Serial.print(F("|t"));
  Serial.print(matrixStable[TOGGLE1_CELL] == LOW ? 1 : 0);

  Serial.print(F("|t"));
  Serial.print(matrixStable[TOGGLE2_CELL] == LOW ? 1 : 0);

  // Encoder cumulative position + direct module push switch.
  Serial.print(F("|e"));
  Serial.print(positionSnapshot);
  Serial.print(':');
  Serial.print(keyStable == LOW ? 0 : 1);

  Serial.println();
}

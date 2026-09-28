/*
  EXPERIMENTAL E2 TEST FIRMWARE — NOT THE 2.0 REFERENCE BUILD

  Mugen Deej cardboard prototype — Arduino Nano full analog build
  ===============================================================

  Physical prototype:
    - 28 momentary buttons in a 4x7 visible grid
    - 2 latching toggles in matrix column C8 (R1C8 / R2C8)
    - 1 rotary encoder module with S1/S2/KEY/5V/GND
    - 1 bare EC11 rotary encoder, rotation only, using R3C8 / R4C8
    - 5 real potentiometers on A3..A7

  Experimental Adaptive v3 topology exposed to Mugen Deej:
    5 sliders / 28 buttons / 2 toggles / 2 encoders
      E1 = direct-pin encoder with push
      E2 = matrix encoder without push

  Classic Nano pin map:
    Encoder S1 -> D2
    Encoder S2 -> D3
    Encoder KEY -> A2
    Encoder 5V -> 5V
    Encoder GND -> GND

    Matrix C1..C8 -> D4,D6,D5,D7,D8,D9,D10,D11
    Matrix R1..R4 -> D12,D13,A0,A1

    Matrix encoder E2:
      EC11 COM -> C8 / D11
      EC11 A   -> diode -> R3 / A0
      EC11 B   -> diode -> R4 / A1
      diode cathode/stripe faces the ROW, matching the rest of the matrix
      EC11 push contacts are intentionally unused

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

// Current hardware test wiring deliberately keeps the C2/C3 jumper swap
// that eliminated the same-column ghost presses:
//   C1=D4, C2=D6, C3=D5, C4..C8=D7..D11.
// The logical matrix order remains C1..C8 here, so Mugen still sees the
// original B1..B28 numbering despite the physical D5/D6 swap.
const uint8_t MATRIX_COL_PINS[8] = {
  4, 6, 5, 7, 8, 9, 10, 11
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

// High-speed transport experiment. 500000 is intentionally isolated to this
// E2 test firmware; the accepted 2.0 reference firmware remains unchanged.
const unsigned long SERIAL_BAUD = 500000;

// Adaptive v3 is a full-state snapshot, so a matrix-backed encoder must not
// force one complete serial packet per detent. E2 keeps accumulating locally;
// the normal heartbeat publishes the latest cumulative position. Direct E1 can
// still request an immediate packet because its A/B edges are interrupt-driven.
// High-rate transport follow-up: at 500000 baud, publish the regular full
// Adaptive heartbeat on a 10 ms start-to-start schedule (~100 Hz target).
// The heartbeat timestamp is recorded immediately BEFORE serialization so the
// time spent inside sendAdaptivePacket() counts toward the 10 ms frame period.
// E2 still accumulates locally between snapshots, so transport cadence remains
// decoupled from edge capture.
const unsigned long PACKET_INTERVAL_MS = 10;

// Low-latency gameplay experiment. 18 ms was intentionally conservative for
// the cardboard matrix; 6 ms should feel much closer to a real gamepad while
// the counters below tell us whether the physical contacts object.
const unsigned long MATRIX_DEBOUNCE_MS = 6;
const unsigned long MATRIX_RAPID_REVERSAL_MS = 35;
const unsigned long KEY_DEBOUNCE_MS = 20;

// With the cardboard wiring and only the ATmega's internal pull-ups, a column
// that was just pulled LOW by a held key can need more than a few microseconds
// to recover HIGH before the next row is sampled. Give the line explicit
// recovery time between rows so a held key cannot appear in every row of the
// same column (for example B23 -> B2/B9/B16/B23).
const unsigned int MATRIX_ACTIVE_SETTLE_US = 6;
const unsigned int MATRIX_RELEASE_SETTLE_US = 60;

// Keep the raw ADC path intentionally simple for the first real-potentiometer
// test. Mugen's desktop noise threshold can be observed/tuned from real data
// before any firmware-side smoothing is added.
const uint8_t NUM_POTS = 5;

// The pictured 20-detent module is expected to produce one full quadrature
// cycle per detent. If one click later produces multiple counts or no count,
// this is the first constant to revisit.
const int8_t ENCODER_EDGES_PER_STEP = 4;
const int8_t ENCODER_DIRECTION = 1;

// Experimental second EC11 lives inside the two remaining C8 matrix cells.
// It is decoded from raw matrix samples, intentionally bypassing the 6 ms
// button/toggle debounce so quick quadrature edges are not discarded.
const int8_t MATRIX_ENCODER_EDGES_PER_STEP = 4;
const int8_t MATRIX_ENCODER_DIRECTION = 1;

// ---------------------------------------------------------------------------
// Matrix layout
// ---------------------------------------------------------------------------
//
//              C1   C2   C3   C4   C5   C6   C7   C8
// R1           B1   B2   B3   B4   B5   B6   B7   T1
// R2           B8   B9   B10  B11  B12  B13  B14  T2
// R3           B15  B16  B17  B18  B19  B20  B21  E2-A
// R4           B22  B23  B24  B25  B26  B27  B28  E2-B
//
// C8 is intentionally excluded from the 28 ordinary button fields.
// E2-A / E2-B are sampled raw and are not treated as debounced buttons.

const uint8_t NUM_ROWS = 4;
const uint8_t NUM_COLS = 8;
const uint8_t NUM_MATRIX_CELLS = NUM_ROWS * NUM_COLS;

const uint8_t TOGGLE1_CELL = 0 * NUM_COLS + 7; // R1C8
const uint8_t TOGGLE2_CELL = 1 * NUM_COLS + 7; // R2C8
const uint8_t MATRIX_ENCODER_A_CELL = 2 * NUM_COLS + 7; // R3C8
const uint8_t MATRIX_ENCODER_B_CELL = 3 * NUM_COLS + 7; // R4C8

uint8_t matrixRaw[NUM_MATRIX_CELLS];
uint8_t matrixStable[NUM_MATRIX_CELLS];
unsigned long matrixRawChangedAt[NUM_MATRIX_CELLS];
unsigned long matrixStableChangedAt[NUM_MATRIX_CELLS];

// Debounce diagnostics are cumulative from boot. The bit layout is logical:
// bits 0..27 = B1..B28, bit 28 = T1, bit 29 = T2.
// R3C8/R4C8 belong to E2 and are excluded from debounce diagnostics.
//
// filtered: a pending raw transition returned to the accepted state before 6 ms.
// leaked:   an accepted state reversed again in under 35 ms (possible bounce that
//           escaped the shortened debounce window).
unsigned long matrixFilteredBounceCount = 0;
uint32_t matrixFilteredBounceMask = 0;
unsigned long matrixRapidReversalCount = 0;
uint32_t matrixRapidReversalMask = 0;

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

// E2 is scanned synchronously through the matrix, including brief extra phase
// samples while a serial packet is being emitted, so these do not need to be
// volatile. The state machine is otherwise identical to the direct-pin E1.
uint8_t matrixEncoderPreviousAB = 0;
int8_t matrixEncoderSubsteps = 0;
long matrixEncoderPosition = 0;
bool matrixEncoderPositionChanged = false;

// Gray-code transition table. Index = previousAB << 2 | currentAB.
const int8_t ENCODER_TRANSITION_TABLE[16] = {
   0, -1,  1,  0,
   1,  0,  0, -1,
  -1,  0,  0,  1,
   0,  1, -1,  0
};

unsigned long lastPacketStartedAt = 0;

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

  // initializeMatrix() captures the raw R3C8/R4C8 phase state for E2.
  matrixEncoderPreviousAB = 0;
  if (matrixRaw[MATRIX_ENCODER_A_CELL] == HIGH) { matrixEncoderPreviousAB |= 0x02; }
  if (matrixRaw[MATRIX_ENCODER_B_CELL] == HIGH) { matrixEncoderPreviousAB |= 0x01; }

  keyRaw = digitalRead(ENCODER_KEY_PIN);
  keyStable = keyRaw;
  keyRawChangedAt = now;

  encoderPreviousAB = readEncoderAB();
  attachInterrupt(digitalPinToInterrupt(ENCODER_S1_PIN), handleEncoderChange, CHANGE);
  attachInterrupt(digitalPinToInterrupt(ENCODER_S2_PIN), handleEncoderChange, CHANGE);

  lastPacketStartedAt = now - PACKET_INTERVAL_MS;
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

  // E2 is polling-based, so do not let it request an immediate full packet.
  // Its cumulative position is published by the regular heartbeat below. This
  // keeps the main loop scanning instead of spending most of a fast spin in
  // Serial.print(). Clear only the notification flag; never the position.
  if (matrixEncoderPositionChanged) {
    matrixEncoderPositionChanged = false;
  }

  const bool heartbeatDue =
      (unsigned long)(now - lastPacketStartedAt) >= PACKET_INTERVAL_MS;

  if (matrixChanged || keyChanged || encoderChanged || heartbeatDue) {
    // Record the packet START, not the end. At 500000 baud the full Adaptive
    // snapshot itself takes several milliseconds to serialize; counting that
    // work inside the frame period turns PACKET_INTERVAL_MS into a real
    // start-to-start heartbeat interval instead of "serialize, then wait 10 ms".
    lastPacketStartedAt = millis();
    sendAdaptivePacket();
  }
}

// ---------------------------------------------------------------------------
// Matrix scan + debounce
// ---------------------------------------------------------------------------

void scanMatrix(uint8_t *states) {
  for (uint8_t row = 0; row < NUM_ROWS; ++row) {
    digitalWrite(MATRIX_ROW_PINS[row], LOW);
    delayMicroseconds(MATRIX_ACTIVE_SETTLE_US);

    for (uint8_t col = 0; col < NUM_COLS; ++col) {
      const uint8_t index = row * NUM_COLS + col;
      states[index] = digitalRead(MATRIX_COL_PINS[col]);
    }

    // Release the row and let every column recharge through INPUT_PULLUP
    // before another row is driven LOW.
    digitalWrite(MATRIX_ROW_PINS[row], HIGH);
    delayMicroseconds(MATRIX_RELEASE_SETTLE_US);
  }
}

void initializeMatrix(const unsigned long now) {
  uint8_t initial[NUM_MATRIX_CELLS];
  scanMatrix(initial);

  for (uint8_t i = 0; i < NUM_MATRIX_CELLS; ++i) {
    matrixRaw[i] = initial[i];
    matrixStable[i] = initial[i];
    matrixRawChangedAt[i] = now;
    matrixStableChangedAt[i] = now;
  }
}

int8_t getDiagnosticBitForMatrixCell(const uint8_t index) {
  const uint8_t row = index / NUM_COLS;
  const uint8_t col = index % NUM_COLS;

  if (col < 7) {
    return (int8_t)(row * 7 + col); // B1..B28 -> bits 0..27
  }
  if (index == TOGGLE1_CELL) { return 28; }
  if (index == TOGGLE2_CELL) { return 29; }
  return -1;
}

void markDiagnosticContact(uint32_t &mask, const uint8_t index) {
  const int8_t bit = getDiagnosticBitForMatrixCell(index);
  if (bit >= 0) {
    mask |= ((uint32_t)1UL << (uint8_t)bit);
  }
}

bool updateMatrixEncoderAB(const uint8_t currentMatrixEncoderAB) {
  if (currentMatrixEncoderAB == matrixEncoderPreviousAB) {
    return false;
  }

  const uint8_t transition =
      (matrixEncoderPreviousAB << 2) | currentMatrixEncoderAB;
  const int8_t delta = ENCODER_TRANSITION_TABLE[transition & 0x0F];

  matrixEncoderPreviousAB = currentMatrixEncoderAB;
  if (delta == 0) {
    return false;
  }

  matrixEncoderSubsteps += delta * MATRIX_ENCODER_DIRECTION;

  if (matrixEncoderSubsteps >= MATRIX_ENCODER_EDGES_PER_STEP) {
    ++matrixEncoderPosition;
    matrixEncoderSubsteps = 0;
    matrixEncoderPositionChanged = true;
    return true;
  }

  if (matrixEncoderSubsteps <= -MATRIX_ENCODER_EDGES_PER_STEP) {
    --matrixEncoderPosition;
    matrixEncoderSubsteps = 0;
    matrixEncoderPositionChanged = true;
    return true;
  }

  return false;
}

// Serial.print() eventually waits for room in the small AVR TX buffer. E1 is
// safe during those waits because D2/D3 are interrupt-driven; E2 is not. Take
// quick phase samples between chunks of the full Adaptive packet so a fast E2
// rotation does not become invisible while UART bytes are draining.
void serviceMatrixEncoderDuringSerial() {
  uint8_t currentMatrixEncoderAB = 0;

  digitalWrite(MATRIX_ROW_PINS[2], LOW);
  delayMicroseconds(MATRIX_ACTIVE_SETTLE_US);
  if (digitalRead(MATRIX_COL_PINS[7]) == HIGH) {
    currentMatrixEncoderAB |= 0x02;
  }
  digitalWrite(MATRIX_ROW_PINS[2], HIGH);
  delayMicroseconds(MATRIX_RELEASE_SETTLE_US);

  digitalWrite(MATRIX_ROW_PINS[3], LOW);
  delayMicroseconds(MATRIX_ACTIVE_SETTLE_US);
  if (digitalRead(MATRIX_COL_PINS[7]) == HIGH) {
    currentMatrixEncoderAB |= 0x01;
  }
  digitalWrite(MATRIX_ROW_PINS[3], HIGH);
  delayMicroseconds(MATRIX_RELEASE_SETTLE_US);

  (void)updateMatrixEncoderAB(currentMatrixEncoderAB);
}

bool updateMatrix(const unsigned long now) {
  bool changed = false;
  uint8_t scanned[NUM_MATRIX_CELLS];
  scanMatrix(scanned);

  // Decode E2 immediately from raw R3C8/R4C8 samples. Both bits are encoded
  // with the same HIGH/open convention as the direct-pin E1 pull-up inputs.
  uint8_t currentMatrixEncoderAB = 0;
  if (scanned[MATRIX_ENCODER_A_CELL] == HIGH) { currentMatrixEncoderAB |= 0x02; }
  if (scanned[MATRIX_ENCODER_B_CELL] == HIGH) { currentMatrixEncoderAB |= 0x01; }

  // Deliberately do not mark the ordinary matrix state as changed when only E2
  // advances. Otherwise every detent immediately sends a full v3 snapshot,
  // creating exactly the serial blind time that makes polling lose fast edges.
  (void)updateMatrixEncoderAB(currentMatrixEncoderAB);

  for (uint8_t i = 0; i < NUM_MATRIX_CELLS; ++i) {
    // E2 phase contacts must stay raw; running them through MATRIX_DEBOUNCE_MS
    // would discard legitimate quadrature transitions during quick rotation.
    if (i == MATRIX_ENCODER_A_CELL || i == MATRIX_ENCODER_B_CELL) {
      matrixRaw[i] = scanned[i];
      matrixStable[i] = scanned[i];
      continue;
    }

    if (scanned[i] != matrixRaw[i]) {
      // A transition was pending but the raw contact returned to the currently
      // accepted state before the debounce interval completed.
      if (
        matrixRaw[i] != matrixStable[i] &&
        scanned[i] == matrixStable[i] &&
        (unsigned long)(now - matrixRawChangedAt[i]) < MATRIX_DEBOUNCE_MS
      ) {
        ++matrixFilteredBounceCount;
        markDiagnosticContact(matrixFilteredBounceMask, i);
      }

      matrixRaw[i] = scanned[i];
      matrixRawChangedAt[i] = now;
    }

    if (
      matrixStable[i] != matrixRaw[i] &&
      (unsigned long)(now - matrixRawChangedAt[i]) >= MATRIX_DEBOUNCE_MS
    ) {
      // If a just-accepted state reverses again almost immediately, the 6 ms
      // window may have let contact bounce escape into the reported state.
      if (
        (unsigned long)(now - matrixStableChangedAt[i]) < MATRIX_RAPID_REVERSAL_MS
      ) {
        ++matrixRapidReversalCount;
        markDiagnosticContact(matrixRapidReversalMask, i);
      }

      matrixStable[i] = matrixRaw[i];
      matrixStableChangedAt[i] = now;
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
  long matrixPositionSnapshot;

  noInterrupts();
  positionSnapshot = encoderPosition;
  interrupts();

  matrixPositionSnapshot = matrixEncoderPosition;

  Serial.print(F("v3"));

  // Five real potentiometers, raw ATmega328P ADC range 0..1023.
  for (uint8_t i = 0; i < NUM_POTS; ++i) {
    Serial.print(F("|s"));
    Serial.print(readPotentiometer(POT_PINS[i]));
    serviceMatrixEncoderDuringSerial();
  }

  // 28 ordinary buttons: C1..C7 across each row.
  uint8_t serializedButtonCount = 0;
  for (uint8_t row = 0; row < NUM_ROWS; ++row) {
    for (uint8_t col = 0; col < 7; ++col) {
      const uint8_t index = row * NUM_COLS + col;
      Serial.print(F("|b"));
      Serial.print(matrixStable[index] == LOW ? 0 : 1);

      ++serializedButtonCount;
      if ((serializedButtonCount & 0x03) == 0) {
        serviceMatrixEncoderDuringSerial();
      }
    }
  }
  serviceMatrixEncoderDuringSerial();

  // Latching toggles in R1C8 / R2C8.
  Serial.print(F("|t"));
  Serial.print(matrixStable[TOGGLE1_CELL] == LOW ? 1 : 0);

  Serial.print(F("|t"));
  Serial.print(matrixStable[TOGGLE2_CELL] == LOW ? 1 : 0);
  serviceMatrixEncoderDuringSerial();

  // E1 cumulative position + direct module push switch.
  Serial.print(F("|e"));
  Serial.print(positionSnapshot);
  Serial.print(':');
  Serial.print(keyStable == LOW ? 0 : 1);
  serviceMatrixEncoderDuringSerial();

  // E2 cumulative position only. No ':push' suffix is emitted, so desktop
  // capability discovery exposes CW/CCW actions but no Push action for E2.
  Serial.print(F("|e"));
  Serial.print(matrixPositionSnapshot);
  serviceMatrixEncoderDuringSerial();

  // Optional Adaptive-v3 debounce diagnostic token:
  // d<debounceMs>:<filteredCount>:<filteredMaskHex>:<rapidCount>:<rapidMaskHex>
  Serial.print(F("|d"));
  Serial.print(MATRIX_DEBOUNCE_MS);
  Serial.print(':');
  Serial.print(matrixFilteredBounceCount);
  Serial.print(':');
  Serial.print(matrixFilteredBounceMask, HEX);
  Serial.print(':');
  Serial.print(matrixRapidReversalCount);
  Serial.print(':');
  Serial.print(matrixRapidReversalMask, HEX);
  serviceMatrixEncoderDuringSerial();

  Serial.println();
}

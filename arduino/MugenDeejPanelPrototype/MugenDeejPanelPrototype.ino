/*
  Mugen Deej Panel Prototype — Nano 5A + 30-key matrix + 2 toggles + encoder
  ===========================================================================

  EXPERIMENTAL / NOT HARDWARE-TESTED
  ----------------------------------
  This sketch is the first firmware target for the larger software-defined
  Mugen control-surface prototype. It intentionally lives beside the already
  tested MugenDeejController reference sketch instead of replacing it.

  Target hardware
  ---------------
    - classic ATmega328P Arduino Nano-class board
    - 5 analog controls on A0..A4
    - 5x6 switch matrix = 30 matrix positions
      * expected use: 29 standalone buttons + encoder push on one matrix slot
    - one diode per matrix key (1N4148-class)
    - 2 latching toggles read through analog-only A6/A7
    - one quadrature rotary encoder on D2/D3
    - USB serial to Mugen Deej

  Temporary wire representation
  -----------------------------
  Mugen Deej does not yet have dedicated toggle/encoder field types. To keep
  this prototype close to the already-supported Extended s/b parser, every
  non-analog control is temporarily transported as a button state:

    s0..s4   = five analog controls
    b0..b29  = 30 matrix positions
    b30      = toggle 1
    b31      = toggle 2
    b32      = encoder clockwise synthetic pulse
    b33      = encoder counter-clockwise synthetic pulse

  Therefore the current packet looks like an Extended controller with:

    sliders = 5
    buttons = 34
    fields  = 39 total

  The encoder push switch is NOT a separate extra field. Wire it into one of
  the 30 matrix positions (the wiring note reserves matrix position 29 / R5C6),
  leaving 29 standalone panel buttons plus the push switch.

  Serial speed
  ------------
  This large full-state packet is too long for the old 9600-baud / 60-ms
  reference cadence. This prototype deliberately uses 115200 baud and a 25-ms
  heartbeat. Mugen Deej desktop support for the higher baud rate must be added
  and hardware-tested before this sketch is considered product-ready.

  Encoder semantics
  -----------------
  Rotation is decoded as quadrature detents. Until Mugen gains a dedicated
  encoder field, each detent becomes a short synthetic press/release on one of
  two temporary button fields (CW / CCW). A small queue preserves quick turns.

  This is intentionally a transport compatibility shim, not the final Mugen
  encoder model. The long-term desktop model should expose an encoder as a
  directional step source.
*/

// ---------------------------------------------------------------------------
// Pin map
// ---------------------------------------------------------------------------

const uint8_t ANALOG_PINS[] = {
  A0, A1, A2, A3, A4
};

// D2/D3 are the ATmega328P external-interrupt pins. Keeping the encoder here
// lets matrix scanning and serial writes continue without losing quick turns.
const uint8_t ENCODER_A_PIN = 2;
const uint8_t ENCODER_B_PIN = 3;

// Five matrix rows. Inactive rows are high-impedance INPUTs; the currently
// scanned row is driven LOW. D13 is safe as a row; the onboard LED may simply
// remain off during active-low scanning.
const uint8_t MATRIX_ROW_PINS[] = {
  9, 10, 11, 12, 13
};

// Six matrix columns use INPUT_PULLUP. A5 is digital-capable on classic Nano.
const uint8_t MATRIX_COL_PINS[] = {
  4, 5, 6, 7, 8, A5
};

// A6/A7 on classic Nano are analog-input-only. Each toggle therefore needs an
// external pull-up: 10 kOhm from the pin to +5 V, with the switching contact
// closing the pin to GND. The automotive switch's lamp/LED pins are NOT used.
const uint8_t TOGGLE_PINS[] = {
  A6, A7
};

// ---------------------------------------------------------------------------
// Transport / timing configuration
// ---------------------------------------------------------------------------

const unsigned long SERIAL_BAUD = 115200;

// Full-state heartbeat. With ~130-byte worst-case packets this leaves useful
// headroom at 115200 while still giving roughly 40 updates/s.
const unsigned long PACKET_INTERVAL_MS = 25;

const unsigned long MATRIX_DEBOUNCE_MS = 20;
const unsigned long TOGGLE_DEBOUNCE_MS = 25;

// Toggle inputs are rail-to-rail through an external pull-up and switch to GND.
// A hysteresis window avoids chatter if a wire/contact briefly floats.
const uint16_t TOGGLE_LOW_THRESHOLD = 300;
const uint16_t TOGGLE_HIGH_THRESHOLD = 700;

// Generic EC11-style encoders commonly produce four valid quadrature edges per
// detent. If the ordered encoder proves to produce two edges per detent, change
// this constant to 2 after observing real hardware.
const int8_t ENCODER_EDGES_PER_DETENT = 4;

// Direction can be flipped without rewiring by changing +1 to -1.
const int8_t ENCODER_DIRECTION = 1;

// Synthetic button pulse used only until the desktop protocol gains a native
// encoder-step field. Every detent gets a press packet and a release packet.
const unsigned long ENCODER_PULSE_MS = 35;
const unsigned long ENCODER_INTER_PULSE_GAP_MS = 5;

// Power-of-two-sized queue is not required, but 32 detents is plenty for a
// human-operated EC11 while remaining tiny on an ATmega328P.
const uint8_t ENCODER_QUEUE_SIZE = 32;

// ---------------------------------------------------------------------------
// Derived counts
// ---------------------------------------------------------------------------

const uint8_t NUM_ANALOG = sizeof(ANALOG_PINS) / sizeof(ANALOG_PINS[0]);
const uint8_t NUM_ROWS = sizeof(MATRIX_ROW_PINS) / sizeof(MATRIX_ROW_PINS[0]);
const uint8_t NUM_COLS = sizeof(MATRIX_COL_PINS) / sizeof(MATRIX_COL_PINS[0]);
const uint8_t NUM_MATRIX_KEYS = NUM_ROWS * NUM_COLS;
const uint8_t NUM_TOGGLES = sizeof(TOGGLE_PINS) / sizeof(TOGGLE_PINS[0]);

// 30 matrix positions + 2 toggles + 2 temporary encoder pulse fields.
const uint8_t NUM_BUTTON_FIELDS = NUM_MATRIX_KEYS + NUM_TOGGLES + 2;

// ---------------------------------------------------------------------------
// Runtime state
// ---------------------------------------------------------------------------

uint16_t analogValues[NUM_ANALOG];

uint8_t matrixRawStates[NUM_MATRIX_KEYS];
uint8_t matrixStableStates[NUM_MATRIX_KEYS];
unsigned long matrixRawChangedAt[NUM_MATRIX_KEYS];

uint8_t toggleRawStates[NUM_TOGGLES];
uint8_t toggleStableStates[NUM_TOGGLES];
unsigned long toggleRawChangedAt[NUM_TOGGLES];

unsigned long lastPacketAt = 0;

// Quadrature decoder state. Interrupt handlers only decode transitions and put
// complete detent directions into a tiny ring buffer. Packet generation remains
// in loop(), never inside an ISR.
volatile uint8_t encoderPreviousAB = 0;
volatile int8_t encoderSubsteps = 0;
volatile int8_t encoderQueue[ENCODER_QUEUE_SIZE];
volatile uint8_t encoderQueueHead = 0;
volatile uint8_t encoderQueueTail = 0;
volatile uint16_t encoderDroppedSteps = 0;

bool encoderCwPressed = false;
bool encoderCcwPressed = false;
unsigned long encoderPulseReleaseAt = 0;
unsigned long encoderNextPulseAt = 0;

enum EncoderPulsePhase : uint8_t {
  ENCODER_IDLE = 0,
  ENCODER_PRESSED = 1,
  ENCODER_RELEASE_GAP = 2
};

EncoderPulsePhase encoderPulsePhase = ENCODER_IDLE;

// Valid Gray-code transitions. Index = previousAB << 2 | currentAB.
// Sign is arbitrary and can be inverted through ENCODER_DIRECTION.
const int8_t ENCODER_TRANSITION_TABLE[16] = {
   0, -1,  1,  0,
   1,  0,  0, -1,
  -1,  0,  0,  1,
   0,  1, -1,  0
};

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

void setup() {
  for (uint8_t i = 0; i < NUM_ANALOG; ++i) {
    pinMode(ANALOG_PINS[i], INPUT);
  }

  // Matrix columns are pulled HIGH. A pressed key on the active LOW row reads
  // LOW. All rows remain high-impedance except the one currently being scanned.
  for (uint8_t col = 0; col < NUM_COLS; ++col) {
    pinMode(MATRIX_COL_PINS[col], INPUT_PULLUP);
  }

  for (uint8_t row = 0; row < NUM_ROWS; ++row) {
    pinMode(MATRIX_ROW_PINS[row], INPUT);
    digitalWrite(MATRIX_ROW_PINS[row], LOW); // make sure INPUT_PULLUP is off
  }

  // A6/A7 are analog-only; pinMode is not needed for analogRead().

  pinMode(ENCODER_A_PIN, INPUT_PULLUP);
  pinMode(ENCODER_B_PIN, INPUT_PULLUP);

  Serial.begin(SERIAL_BAUD);

  const unsigned long now = millis();

  initializeMatrixStates(now);
  initializeToggleStates(now);
  readAnalogControls();

  encoderPreviousAB = readEncoderAB();
  attachInterrupt(digitalPinToInterrupt(ENCODER_A_PIN), handleEncoderChange, CHANGE);
  attachInterrupt(digitalPinToInterrupt(ENCODER_B_PIN), handleEncoderChange, CHANGE);

  // First loop sends immediately.
  lastPacketAt = now - PACKET_INTERVAL_MS;
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

void loop() {
  const unsigned long now = millis();

  const bool matrixChanged = updateMatrix(now);
  const bool toggleChanged = updateToggles(now);
  const bool encoderChanged = updateEncoderPulse(now);

  const bool periodicPacketDue =
      (unsigned long)(now - lastPacketAt) >= PACKET_INTERVAL_MS;

  if (matrixChanged || toggleChanged || encoderChanged || periodicPacketDue) {
    readAnalogControls();
    sendStatePacket();
    lastPacketAt = millis();
  }
}

// ---------------------------------------------------------------------------
// Analog controls
// ---------------------------------------------------------------------------

void readAnalogControls() {
  for (uint8_t i = 0; i < NUM_ANALOG; ++i) {
    analogValues[i] = analogRead(ANALOG_PINS[i]);
  }
}

// ---------------------------------------------------------------------------
// 5x6 matrix scan + debounce
// ---------------------------------------------------------------------------

void scanMatrix(uint8_t *states) {
  for (uint8_t row = 0; row < NUM_ROWS; ++row) {
    // Activate exactly one row by driving it LOW.
    pinMode(MATRIX_ROW_PINS[row], OUTPUT);
    digitalWrite(MATRIX_ROW_PINS[row], LOW);

    // A few microseconds lets the column pull-ups settle after changing row.
    delayMicroseconds(3);

    for (uint8_t col = 0; col < NUM_COLS; ++col) {
      const uint8_t index = row * NUM_COLS + col;
      states[index] = digitalRead(MATRIX_COL_PINS[col]);
    }

    // Return row to high impedance before activating the next one. This avoids
    // output-to-output fights when several keys are held simultaneously.
    pinMode(MATRIX_ROW_PINS[row], INPUT);
    digitalWrite(MATRIX_ROW_PINS[row], LOW);
  }
}

void initializeMatrixStates(const unsigned long now) {
  uint8_t initial[NUM_MATRIX_KEYS];
  scanMatrix(initial);

  for (uint8_t i = 0; i < NUM_MATRIX_KEYS; ++i) {
    matrixRawStates[i] = initial[i];
    matrixStableStates[i] = initial[i];
    matrixRawChangedAt[i] = now;
  }
}

bool updateMatrix(const unsigned long now) {
  bool anyStableStateChanged = false;
  uint8_t scanned[NUM_MATRIX_KEYS];
  scanMatrix(scanned);

  for (uint8_t i = 0; i < NUM_MATRIX_KEYS; ++i) {
    if (scanned[i] != matrixRawStates[i]) {
      matrixRawStates[i] = scanned[i];
      matrixRawChangedAt[i] = now;
    }

    if (
        matrixStableStates[i] != matrixRawStates[i] &&
        (unsigned long)(now - matrixRawChangedAt[i]) >= MATRIX_DEBOUNCE_MS
    ) {
      matrixStableStates[i] = matrixRawStates[i];
      anyStableStateChanged = true;
    }
  }

  return anyStableStateChanged;
}

// ---------------------------------------------------------------------------
// Latching toggles on A6/A7
// ---------------------------------------------------------------------------

uint8_t readToggleElectricalState(const uint8_t index, const uint8_t fallback) {
  const uint16_t value = analogRead(TOGGLE_PINS[index]);

  // External 10 kOhm pull-up + contact to GND:
  //   open/OFF   -> near 1023 -> HIGH -> b1
  //   closed/ON  -> near 0    -> LOW  -> b0
  if (value <= TOGGLE_LOW_THRESHOLD) {
    return LOW;
  }

  if (value >= TOGGLE_HIGH_THRESHOLD) {
    return HIGH;
  }

  // In the hysteresis zone retain the previous raw decision rather than
  // inventing a transition from analog noise or a moving contact.
  return fallback;
}

void initializeToggleStates(const unsigned long now) {
  for (uint8_t i = 0; i < NUM_TOGGLES; ++i) {
    // Start from HIGH so an unconnected test input with the intended pull-up is
    // interpreted as released/OFF.
    const uint8_t state = readToggleElectricalState(i, HIGH);
    toggleRawStates[i] = state;
    toggleStableStates[i] = state;
    toggleRawChangedAt[i] = now;
  }
}

bool updateToggles(const unsigned long now) {
  bool anyStableStateChanged = false;

  for (uint8_t i = 0; i < NUM_TOGGLES; ++i) {
    const uint8_t rawState =
        readToggleElectricalState(i, toggleRawStates[i]);

    if (rawState != toggleRawStates[i]) {
      toggleRawStates[i] = rawState;
      toggleRawChangedAt[i] = now;
    }

    if (
        toggleStableStates[i] != toggleRawStates[i] &&
        (unsigned long)(now - toggleRawChangedAt[i]) >= TOGGLE_DEBOUNCE_MS
    ) {
      toggleStableStates[i] = toggleRawStates[i];
      anyStableStateChanged = true;
    }
  }

  return anyStableStateChanged;
}

// ---------------------------------------------------------------------------
// Quadrature encoder
// ---------------------------------------------------------------------------

uint8_t readEncoderAB() {
  uint8_t value = 0;
  if (digitalRead(ENCODER_A_PIN) == HIGH) {
    value |= 0x02;
  }
  if (digitalRead(ENCODER_B_PIN) == HIGH) {
    value |= 0x01;
  }
  return value;
}

void enqueueEncoderStepFromIsr(const int8_t direction) {
  uint8_t nextHead = encoderQueueHead + 1;
  if (nextHead >= ENCODER_QUEUE_SIZE) {
    nextHead = 0;
  }

  if (nextHead == encoderQueueTail) {
    // Queue full. Dropping is preferable to blocking or doing serial work in
    // an interrupt. This counter is kept for future diagnostics.
    ++encoderDroppedSteps;
    return;
  }

  encoderQueue[encoderQueueHead] = direction;
  encoderQueueHead = nextHead;
}

void handleEncoderChange() {
  const uint8_t currentAB = readEncoderAB();
  const uint8_t tableIndex = (encoderPreviousAB << 2) | currentAB;
  const int8_t transition = ENCODER_TRANSITION_TABLE[tableIndex];

  encoderPreviousAB = currentAB;

  if (transition == 0) {
    return;
  }

  encoderSubsteps += transition * ENCODER_DIRECTION;

  if (encoderSubsteps >= ENCODER_EDGES_PER_DETENT) {
    encoderSubsteps -= ENCODER_EDGES_PER_DETENT;
    enqueueEncoderStepFromIsr(+1);
  }
  else if (encoderSubsteps <= -ENCODER_EDGES_PER_DETENT) {
    encoderSubsteps += ENCODER_EDGES_PER_DETENT;
    enqueueEncoderStepFromIsr(-1);
  }
}

bool dequeueEncoderStep(int8_t &direction) {
  bool available = false;

  noInterrupts();
  if (encoderQueueTail != encoderQueueHead) {
    direction = encoderQueue[encoderQueueTail];

    uint8_t nextTail = encoderQueueTail + 1;
    if (nextTail >= ENCODER_QUEUE_SIZE) {
      nextTail = 0;
    }

    encoderQueueTail = nextTail;
    available = true;
  }
  interrupts();

  return available;
}

bool updateEncoderPulse(const unsigned long now) {
  if (encoderPulsePhase == ENCODER_PRESSED) {
    if ((long)(now - encoderPulseReleaseAt) >= 0) {
      encoderCwPressed = false;
      encoderCcwPressed = false;
      encoderPulsePhase = ENCODER_RELEASE_GAP;
      encoderNextPulseAt = now + ENCODER_INTER_PULSE_GAP_MS;
      return true; // force a release packet
    }

    return false;
  }

  if (encoderPulsePhase == ENCODER_RELEASE_GAP) {
    if ((long)(now - encoderNextPulseAt) < 0) {
      return false;
    }

    encoderPulsePhase = ENCODER_IDLE;
  }

  int8_t direction = 0;
  if (!dequeueEncoderStep(direction)) {
    return false;
  }

  if (direction > 0) {
    encoderCwPressed = true;
    encoderCcwPressed = false;
  }
  else {
    encoderCwPressed = false;
    encoderCcwPressed = true;
  }

  encoderPulseReleaseAt = now + ENCODER_PULSE_MS;
  encoderPulsePhase = ENCODER_PRESSED;
  return true; // force a press packet
}

// ---------------------------------------------------------------------------
// Extended s/b packet output
// ---------------------------------------------------------------------------

void sendStatePacket() {
  // Analog fields first.
  for (uint8_t i = 0; i < NUM_ANALOG; ++i) {
    if (i > 0) {
      Serial.print('|');
    }

    Serial.print('s');
    Serial.print(analogValues[i]);
  }

  // 30 physical matrix states. INPUT_PULLUP semantics are sent unchanged:
  // HIGH=1=released, LOW=0=pressed.
  for (uint8_t i = 0; i < NUM_MATRIX_KEYS; ++i) {
    Serial.print('|');
    Serial.print('b');
    Serial.print(matrixStableStates[i]);
  }

  // Two latching toggles temporarily look like stateful buttons.
  for (uint8_t i = 0; i < NUM_TOGGLES; ++i) {
    Serial.print('|');
    Serial.print('b');
    Serial.print(toggleStableStates[i]);
  }

  // Temporary encoder direction pulses.
  Serial.print('|');
  Serial.print('b');
  Serial.print(encoderCwPressed ? 0 : 1);

  Serial.print('|');
  Serial.print('b');
  Serial.print(encoderCcwPressed ? 0 : 1);

  Serial.println();
}

/*
  EXPECTED FIELD MAP
  ------------------

  s0..s4     A0..A4 analog controls

  b0..b29    5x6 matrix, row-major:
              b0  = R1C1
              ...
              b5  = R1C6
              b6  = R2C1
              ...
              b29 = R5C6  <-- recommended encoder push position

  b30        toggle on A6
  b31        toggle on A7
  b32        encoder CW pulse
  b33        encoder CCW pulse

  FIRST HARDWARE TEST
  -------------------

  Before Mugen Deej gains 115200-baud probing, validate this sketch in Arduino
  Serial Monitor at 115200:

    1. Verify a complete line is emitted roughly every 25 ms.
    2. Turn all five analog controls end-to-end.
    3. Test each matrix position individually.
    4. Test simultaneous matrix holds after all 1N4148 diodes are fitted.
    5. Toggle A6/A7 and confirm b30/b31 latch between 1 and 0.
    6. Rotate the encoder one detent at a time and confirm b32/b33 make clean
       press/release pulses in opposite directions.
    7. Press the encoder and confirm its reserved matrix field (recommended b29)
       behaves like an ordinary button.

  Do not mark this firmware hardware PASS until the real panel is assembled and
  the complete matrix, toggles and encoder have been exercised.
*/

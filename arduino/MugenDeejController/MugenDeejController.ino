/*
  Mugen Deej Reference Controller — Extended 5x6 / tested Nano profile
  ====================================================

  Purpose
  -------
  Reference firmware for a Mugen Deej controller with:
    - analog volume controls / potentiometers
    - physical momentary buttons

  Protocol
  --------
  This sketch intentionally keeps compatibility with the extended s/b protocol
  already supported and tested by Mugen Deej:

      s512|s123|s900|s456|s777|b1|b1|b0|b1|b1|b1

  sN = slider ADC value, 0..1023
  b1 = button released
  b0 = button pressed

  WHY WE KEEP THIS FORMAT
  -----------------------
  We deliberately do NOT invent a new handshake or "Mugen v2" protocol here.
  Mugen Deej already autodetects:
    - classic deej numeric-only packets
    - this extended s/b format
    - slider and button counts from the packet itself

  Keeping the wire format stable means old slider-only deej controllers and
  newer button controllers can coexist without forcing anybody to reflash
  existing hardware.

  CREDIT / COMPARISON
  -------------------
  The extended packet idea follows the Miodec deej fork.

  The Miodec reference sketch:
    - reads sliders and buttons
    - uses INPUT_PULLUP for buttons
    - sends the complete state repeatedly
    - builds each outgoing line with Arduino String
    - uses delay(10)
    - does not debounce buttons in firmware

  This Mugen reference implementation keeps the useful compatibility pieces,
  but changes the implementation for long-running robustness:

    Miodec-style                 Mugen reference
    --------------------------------------------------------------
    String packet building       Serial.print() directly
    delay(10)                    millis()-based scheduling
    raw button state             per-button debounce
    implicit serial throttling   explicit 60 ms packet cadence
    fixed example counts         counts derived from pin arrays
    full packets                 full packets (kept intentionally)

  WHY NO Arduino String
  ---------------------
  AVR boards have very little SRAM. Repeated String concatenation can fragment
  the heap during very long uptime. Mugen Deej is expected to sit connected for
  days or months, so this sketch writes fields directly to Serial and allocates
  no packet-building String in loop().

  WHY 60 ms INSTEAD OF delay(10)
  ------------------------------
  Mugen Deej keeps the classic deej baud rate of 9600 for compatibility.

  A 5-slider / 6-button extended packet is roughly 45-50 bytes. At 9600 baud,
  sending a packet every 10 ms is physically faster than the serial link can
  transmit it. Serial.print() therefore ends up blocking/throttling implicitly.

  We use an explicit 60 ms cadence (~16.7 packets/s) instead:
    - enough for human-operated knobs
    - enough headroom at 9600 baud
    - predictable serial behavior
    - no fake "100 Hz" loop rate that the wire cannot sustain

  Button changes request an immediate packet after debounce, so buttons do not
  have to wait for the next periodic interval.

  WHY FULL STATE PACKETS
  ----------------------
  We do NOT send "button pressed" events only.

  Every packet contains every slider and every debounced button state. This is
  important because Mugen Deej can:
    - discover controller capabilities from any valid packet
    - reconnect after USB changes
    - recover after sleep / hibernation
    - hot-swap legacy and extended controllers
    - initialize button state without inventing a fake press

  WHY INPUT_PULLUP / 0 = PRESSED
  ------------------------------
  Each button is wired between its input pin and GND.

      released -> HIGH -> b1
      pressed  -> LOW  -> b0

  No external pull-up resistor is required. This matches the already tested
  Mugen Deej button semantics.

  WHY DEBOUNCE IS IN FIRMWARE
  ---------------------------
  Mechanical switches can bounce between HIGH and LOW for a few milliseconds.
  A physical button in Mugen Deej can now launch a program, open a URL, send a
  hotkey or toggle mute, so one physical press must become one clean transition.

  Debounce is non-blocking: millis() is used instead of delay(), so reading and
  serial scheduling continue while a contact settles.

  WHY WE DO NOT HEAVILY FILTER SLIDERS HERE
  -----------------------------------------
  The Arduino's job is intentionally simple:
      read hardware -> debounce buttons -> report state

  We do not add aggressive smoothing, dead zones or slow interpolation to the
  potentiometers. Those can make a physical volume control feel laggy. Mugen
  Deej already handles UI-side visual stability without changing the actual
  controller value semantics.

  ---------------------------------------------------------------------------
  HARDWARE CONFIGURATION — CHECK THIS BEFORE UPLOADING
  ---------------------------------------------------------------------------

  The pin map below matches the CURRENTLY WORKING sketch from this controller:

      sliders: A0, A1, A2, A3, A4
      buttons: 9, 8, 7, 6, 5, 4

  This is intentionally different from the Miodec repository example, which
  uses A3, A2, A1, A0, A10 for its five analog inputs.

  WHY WE KEEP A0..A4 HERE
  -----------------------
  These pins are not a guess: they come from the sketch already proven on this
  physical Mugen Deej controller. Preserving the known-good wiring avoids
  changing hardware and firmware at the same time.

  It also makes this profile appropriate for common ATmega328P Nano/Uno-style
  boards where A10 is not available.

  If somebody builds another controller, only the two pin arrays below should
  normally need to change.
*/

// ---------------------------------------------------------------------------
// User hardware configuration
// ---------------------------------------------------------------------------

const uint8_t SLIDER_PINS[] = {
  A0,
  A1,
  A2,
  A3,
  A4
};

const uint8_t BUTTON_PINS[] = {
  9,
  8,
  7,
  6,
  5,
  4
};

// Keep 9600 for compatibility with classic deej / current Mugen Deej serial IO.
const unsigned long SERIAL_BAUD = 9600;

// Mechanical button must remain unchanged for this long before it becomes
// the new official state.
const unsigned long BUTTON_DEBOUNCE_MS = 25;

// See the bandwidth explanation in the header above.
const unsigned long PACKET_INTERVAL_MS = 60;

// ---------------------------------------------------------------------------
// Derived counts — normally you do not edit these.
// Add/remove pins in the arrays above and the packet changes automatically.
// Mugen Deej discovers the resulting slider/button counts from the packet.
// ---------------------------------------------------------------------------

const uint8_t NUM_SLIDERS =
    sizeof(SLIDER_PINS) / sizeof(SLIDER_PINS[0]);

const uint8_t NUM_BUTTONS =
    sizeof(BUTTON_PINS) / sizeof(BUTTON_PINS[0]);

// Mugen Deej's extended parser currently accepts up to 64 total fields.
// This reference sketch intentionally stays comfortably below that limit.

// ---------------------------------------------------------------------------
// Runtime state
// ---------------------------------------------------------------------------

uint16_t sliderValues[NUM_SLIDERS];

// Last electrical level read directly from the pin.
uint8_t buttonRawStates[NUM_BUTTONS];

// Debounced state that is actually sent to Mugen Deej.
uint8_t buttonStableStates[NUM_BUTTONS];

// When the raw electrical state last changed.
unsigned long buttonRawChangedAt[NUM_BUTTONS];

unsigned long lastPacketAt = 0;

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

void setup() {
  // Analog inputs do not strictly require pinMode() before analogRead(), but
  // setting INPUT makes the intended wiring explicit.
  for (uint8_t i = 0; i < NUM_SLIDERS; ++i) {
    pinMode(SLIDER_PINS[i], INPUT);
  }

  // INPUT_PULLUP:
  //   button released -> HIGH (1)
  //   button pressed  -> LOW  (0)
  //
  // Wire each momentary button between BUTTON_PINS[i] and GND.
  for (uint8_t i = 0; i < NUM_BUTTONS; ++i) {
    pinMode(BUTTON_PINS[i], INPUT_PULLUP);
  }

  Serial.begin(SERIAL_BAUD);

  // Initialize raw AND stable button state from the actual hardware.
  //
  // Why:
  // If a button happens to be held while USB connects, we report that real
  // state. We do not fabricate a release->press transition at startup.
  const unsigned long now = millis();

  for (uint8_t i = 0; i < NUM_BUTTONS; ++i) {
    const uint8_t state = digitalRead(BUTTON_PINS[i]);

    buttonRawStates[i] = state;
    buttonStableStates[i] = state;
    buttonRawChangedAt[i] = now;
  }

  readSliders();

  // Make the first loop send a packet immediately instead of waiting 60 ms.
  lastPacketAt = now - PACKET_INTERVAL_MS;
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

void loop() {
  const unsigned long now = millis();

  // Update button debounce continuously. No delay() is used.
  const bool buttonStateChanged = updateButtons(now);

  // Regular full-state heartbeat keeps controller discovery/reconnect simple.
  const bool periodicPacketDue =
      (unsigned long)(now - lastPacketAt) >= PACKET_INTERVAL_MS;

  if (buttonStateChanged || periodicPacketDue) {
    readSliders();
    sendStatePacket();

    lastPacketAt = now;
  }
}

// ---------------------------------------------------------------------------
// Slider reading
// ---------------------------------------------------------------------------

void readSliders() {
  for (uint8_t i = 0; i < NUM_SLIDERS; ++i) {
    // Keep the raw 10-bit ADC value.
    //
    // Deliberately no moving average here: aggressive Arduino-side smoothing
    // changes how quickly a real physical control reaches its intended value.
    sliderValues[i] = analogRead(SLIDER_PINS[i]);
  }
}

// ---------------------------------------------------------------------------
// Non-blocking button debounce
// ---------------------------------------------------------------------------

bool updateButtons(const unsigned long now) {
  bool anyStableStateChanged = false;

  for (uint8_t i = 0; i < NUM_BUTTONS; ++i) {
    const uint8_t rawState = digitalRead(BUTTON_PINS[i]);

    // Electrical contact changed. Start/restart the settle timer.
    if (rawState != buttonRawStates[i]) {
      buttonRawStates[i] = rawState;
      buttonRawChangedAt[i] = now;
    }

    // Accept the new state only if it stayed unchanged for the debounce time.
    if (
        buttonStableStates[i] != buttonRawStates[i] &&
        (unsigned long)(now - buttonRawChangedAt[i]) >= BUTTON_DEBOUNCE_MS
    ) {
      buttonStableStates[i] = buttonRawStates[i];
      anyStableStateChanged = true;
    }
  }

  return anyStableStateChanged;
}

// ---------------------------------------------------------------------------
// Extended Mugen / Miodec-compatible packet output
// ---------------------------------------------------------------------------

void sendStatePacket() {
  // Do not build a temporary Arduino String here.
  // Print fields directly to Serial to avoid long-uptime heap fragmentation.

  for (uint8_t i = 0; i < NUM_SLIDERS; ++i) {
    if (i > 0) {
      Serial.print('|');
    }

    Serial.print('s');
    Serial.print(sliderValues[i]);
  }

  for (uint8_t i = 0; i < NUM_BUTTONS; ++i) {
    // There is at least one slider in this reference protocol, so every button
    // follows an already-written field and therefore gets a leading separator.
    Serial.print('|');
    Serial.print('b');

    // INPUT_PULLUP state is intentionally sent unchanged:
    // HIGH -> 1 -> released
    // LOW  -> 0 -> pressed
    Serial.print(buttonStableStates[i]);
  }

  Serial.println();
}

/*
  EXPECTED SERIAL MONITOR EXAMPLE
  -------------------------------

  All six buttons released:

      s512|s400|s700|s1023|s0|b1|b1|b1|b1|b1|b1

  Third button pressed:

      s512|s400|s700|s1023|s0|b1|b1|b0|b1|b1|b1


  QUICK COMPARISON CHECK BEFORE FLASHING
  --------------------------------------

  This profile has already been matched to the uploaded working sketch:

      working sketch sliders -> A0, A1, A2, A3, A4
      Mugen reference        -> A0, A1, A2, A3, A4

      working sketch buttons -> 9, 8, 7, 6, 5, 4
      Mugen reference        -> 9, 8, 7, 6, 5, 4

  So the hardware mapping stays unchanged. Everything below the two pin arrays
  should normally stay untouched.

  After flashing:
  - close Arduino Serial Monitor before starting Mugen Deej
    (only one program can own the COM port)
  - Mugen Deej should detect the same controller as:
      protocol=extended
      sliders=<your slider count>
      buttons=<your button count>
  - press each button once
  - turn each slider end-to-end
  - then test USB reconnect / controller hot-swap

  If Mugen Deej notices no protocol difference, that is the desired result:
  the firmware implementation became cleaner while the tested wire contract
  stayed the same.
*/

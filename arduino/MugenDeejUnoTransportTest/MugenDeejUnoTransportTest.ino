/*
  Mugen Deej Uno Transport Test — 115200 auto-baud probe fixture
  ===========================================================================

  PURPOSE
  -------
  Minimal Arduino Uno / ATmega328P sketch used to validate the desktop client's
  automatic 9600 -> 115200 baud probing before the large-panel hardware exists.

  This is NOT the product panel firmware.

  It deliberately sends the same packet SHAPE expected from the first large
  prototype:

      5 analog-style fields + 34 button-style fields = 39 total fields

  but it needs almost no external hardware.

  Wire format:
      s0|s256|s512|s768|s1023|b... (34 button fields total)

  Test button:
      D2 uses INPUT_PULLUP and drives button field #1.
      - leave D2 open  -> b1 (released)
      - connect D2 GND -> b0 (pressed)

  The remaining 33 button fields stay released (b1).

  WHY FIXED ANALOG VALUES
  -----------------------
  A bare Uno has floating A0..A4 inputs. Reading those directly would make the
  Mugen UI bars dance randomly and add noise to a transport-only test. Fixed
  values give a visually obvious 0 / 25 / 50 / 75 / 100% pattern instead.

  EXPECTED MUGEN RESULT
  ---------------------
  The experimental desktop build should:

      1. open the COM port;
      2. fail to find valid packets at 9600;
      3. switch the already-open SerialPort to 115200;
      4. detect Extended protocol, 5 controls, 34 buttons;
      5. remember 115200 for the next connection.

  Open Arduino Serial Monitor at 115200 only for a quick sanity check, then
  CLOSE Serial Monitor before starting Mugen Deej because only one process can
  own the COM port at a time.
*/

const unsigned long SERIAL_BAUD = 115200;
const unsigned long PACKET_INTERVAL_MS = 25;

const uint8_t TEST_BUTTON_PIN = 2;
const uint8_t NUM_BUTTON_FIELDS = 34;

const uint16_t FIXED_ANALOG_VALUES[5] = {
  0,
  256,
  512,
  768,
  1023
};

unsigned long lastPacketAt = 0;
uint8_t lastTestButtonState = HIGH;

void setup() {
  pinMode(TEST_BUTTON_PIN, INPUT_PULLUP);
  Serial.begin(SERIAL_BAUD);

  lastTestButtonState = digitalRead(TEST_BUTTON_PIN);

  // Make the first loop emit immediately.
  const unsigned long now = millis();
  lastPacketAt = now - PACKET_INTERVAL_MS;
}

void loop() {
  const unsigned long now = millis();
  const uint8_t testButtonState = digitalRead(TEST_BUTTON_PIN);
  const bool buttonChanged = (testButtonState != lastTestButtonState);
  const bool periodicPacketDue =
      (unsigned long)(now - lastPacketAt) >= PACKET_INTERVAL_MS;

  if (buttonChanged || periodicPacketDue) {
    lastTestButtonState = testButtonState;
    sendStatePacket(testButtonState);
    lastPacketAt = now;
  }
}

void sendStatePacket(const uint8_t testButtonState) {
  // Five deterministic analog/control fields.
  for (uint8_t i = 0; i < 5; ++i) {
    if (i > 0) {
      Serial.print('|');
    }

    Serial.print('s');
    Serial.print(FIXED_ANALOG_VALUES[i]);
  }

  // 34 button-like fields. Field 1 is a real optional D2 test input;
  // fields 2..34 stay released so the packet shape matches the planned panel.
  for (uint8_t i = 0; i < NUM_BUTTON_FIELDS; ++i) {
    Serial.print('|');
    Serial.print('b');

    if (i == 0) {
      // INPUT_PULLUP semantics match Mugen Extended:
      // HIGH = released (1), LOW = pressed (0).
      Serial.print(testButtonState == LOW ? 0 : 1);
    }
    else {
      Serial.print(1);
    }
  }

  Serial.println();
}

#include <Adafruit_NeoPixel.h>

constexpr uint8_t POT_COUNT = 5;
constexpr uint8_t LED_COUNT = 5;
constexpr uint8_t LED_DATA_PIN = 6;

const uint8_t POT_PINS[POT_COUNT] = { A0, A1, A2, A3, A4 };
const uint8_t LED_FOR_POT[POT_COUNT] = { 0, 1, 2, 3, 4 };
const bool INVERT_POT[POT_COUNT] = { false, false, false, false, false };

const uint8_t CHANNEL_COLORS[POT_COUNT][3] = {
  {  0, 180, 255 },  // Master
  { 40, 100, 255 },  // Steam
  { 88, 101, 242 },  // Discord
  {255,   0,   0 },  // YouTube
  { 30, 215,  96 }   // Spotify
};

constexpr uint8_t MIN_LED_LEVEL = 3;
constexpr uint8_t MAX_LED_LEVEL = 70;
constexpr uint16_t UPDATE_INTERVAL_MS = 15;

Adafruit_NeoPixel pixels(LED_COUNT, LED_DATA_PIN, NEO_GRB + NEO_KHZ800);
uint16_t filteredValues[POT_COUNT];
uint32_t previousUpdateMs = 0;

void setup() {
  Serial.begin(9600);
  for (uint8_t i = 0; i < POT_COUNT; ++i) {
    pinMode(POT_PINS[i], INPUT);
    filteredValues[i] = analogRead(POT_PINS[i]);
  }

  pixels.begin();
  pixels.clear();
  pixels.show();

  // Initialization animation. The desktop client deliberately waits for Nano startup.
  for (uint8_t i = 0; i < LED_COUNT; ++i) {
    pixels.clear();
    pixels.setPixelColor(i, pixels.Color(20, 20, 20));
    pixels.show();
    delay(150);
  }
  pixels.clear();
  pixels.show();
}

void loop() {
  const uint32_t now = millis();
  if (now - previousUpdateMs < UPDATE_INTERVAL_MS) return;
  previousUpdateMs = now;

  uint16_t values[POT_COUNT];
  for (uint8_t i = 0; i < POT_COUNT; ++i) {
    const uint16_t raw = analogRead(POT_PINS[i]);
    filteredValues[i] = (filteredValues[i] * 3UL + raw) / 4UL;
    values[i] = INVERT_POT[i] ? 1023 - filteredValues[i] : filteredValues[i];
  }

  for (uint8_t i = 0; i < POT_COUNT; ++i) {
    Serial.print(values[i]);
    if (i < POT_COUNT - 1) Serial.print('|');
  }
  Serial.println();

  for (uint8_t pot = 0; pot < POT_COUNT; ++pot) {
    const uint8_t level = map(values[pot], 0, 1023, MIN_LED_LEVEL, MAX_LED_LEVEL);
    const uint8_t red = (uint16_t)CHANNEL_COLORS[pot][0] * level / 255;
    const uint8_t green = (uint16_t)CHANNEL_COLORS[pot][1] * level / 255;
    const uint8_t blue = (uint16_t)CHANNEL_COLORS[pot][2] * level / 255;
    pixels.setPixelColor(LED_FOR_POT[pot], pixels.Color(red, green, blue));
  }
  pixels.show();
}

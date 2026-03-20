/*
 * SheShield ESP32 — Bluetooth Classic (Serial)
 * ==============================================
 *
 * Components:
 *   - Push Button (Switch) → GPIO 4   (triggers SOS)
 *   - Buzzer               → GPIO 5   (alert from app)
 *   - LED                  → GPIO 2   (status indicator)
 *   - MPU6050 Accelerometer→ SDA=21, SCL=22 (shake detection)
 *
 * Broadcasts as "SheShield" via Bluetooth Classic (SPP).
 *
 * Protocol — ESP32 → App (Serial strings):
 *   "SOS\n"   → SOS button pressed
 *   "SHAKE\n" → Shake detected
 *
 * Protocol — App → ESP32 (Serial strings):
 *   "BUZZER_ON\n"  → Activate buzzer
 *   "BUZZER_OFF\n" → Stop buzzer
 *   "LED_ON\n"     → Turn LED on
 *   "LED_OFF\n"    → Turn LED off
 *
 * ⚠️ CHANGE THE PIN NUMBERS BELOW IF YOUR WIRING IS DIFFERENT!
 */

#include "BluetoothSerial.h"
#include <Wire.h>

BluetoothSerial SerialBT;

// ==================== PIN CONFIGURATION ====================
// ⚠️ CHANGE THESE TO MATCH YOUR WIRING
#define BUTTON_PIN 4 // Push button / switch
#define BUZZER_PIN 5 // Buzzer
#define LED_PIN 2    // LED (GPIO 2 = built-in on most ESP32)
#define MPU_SDA 21   // Accelerometer SDA
#define MPU_SCL 22   // Accelerometer SCL

// ==================== SHAKE DETECTION ====================
#define MPU6050_ADDR 0x68
#define SHAKE_THRESHOLD 18000  // Adjust: higher = less sensitive
#define SHAKE_COOLDOWN_MS 3000 // Min ms between shake alerts

// ==================== STATE ====================
unsigned long lastShakeTime = 0;
unsigned long lastButtonPress = 0;
bool buzzerActive = false;
int buzzerBeepCount = 0;
unsigned long buzzerTimer = 0;
String inputBuffer = "";

// ==================== MPU6050 SETUP ====================
bool mpuAvailable = false;

void setupMPU6050() {
  Wire.begin(MPU_SDA, MPU_SCL);
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x6B); // Power management
  Wire.write(0);    // Wake up
  byte error = Wire.endTransmission(true);

  if (error == 0) {
    mpuAvailable = true;
    Serial.println("✅ MPU6050 found!");
  } else {
    mpuAvailable = false;
    Serial.println("⚠️ MPU6050 not found — shake detection disabled");
  }
}

// ==================== READ ACCELEROMETER ====================
bool detectShake() {
  if (!mpuAvailable)
    return false;

  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x3B);
  if (Wire.endTransmission(false) != 0)
    return false;

  Wire.requestFrom((int)MPU6050_ADDR, 6, (int)true);
  if (Wire.available() < 6)
    return false;

  int16_t ax = Wire.read() << 8 | Wire.read();
  int16_t ay = Wire.read() << 8 | Wire.read();
  int16_t az = Wire.read() << 8 | Wire.read();

  float magnitude =
      sqrt((float)(ax * ax) + (float)(ay * ay) + (float)(az * az));
  return magnitude > SHAKE_THRESHOLD;
}

// ==================== HANDLE APP COMMANDS ====================
void handleAppCommand(String cmd) {
  cmd.trim();
  Serial.printf("📥 App command: %s\n", cmd.c_str());

  if (cmd == "BUZZER_ON") {
    buzzerActive = true;
    buzzerBeepCount = 6;
    buzzerTimer = millis();
    Serial.println("🔊 Buzzer ON");
  } else if (cmd == "BUZZER_OFF") {
    buzzerActive = false;
    noTone(BUZZER_PIN);
    Serial.println("🔇 Buzzer OFF");
  } else if (cmd == "LED_ON") {
    digitalWrite(LED_PIN, HIGH);
    Serial.println("💡 LED ON");
  } else if (cmd == "LED_OFF") {
    digitalWrite(LED_PIN, LOW);
    Serial.println("💡 LED OFF");
  }
}

// ==================== BUZZER HANDLER ====================
void handleBuzzer() {
  if (!buzzerActive || buzzerBeepCount <= 0)
    return;

  unsigned long now = millis();
  if (now - buzzerTimer > 300) {
    buzzerTimer = now;
    buzzerBeepCount--;

    if (buzzerBeepCount % 2 == 1) {
      tone(BUZZER_PIN, 2500);
    } else {
      noTone(BUZZER_PIN);
    }

    if (buzzerBeepCount <= 0) {
      buzzerActive = false;
      noTone(BUZZER_PIN);
    }
  }
}

// ==================== SETUP ====================
void setup() {
  Serial.begin(115200);
  Serial.println("\n🛡️ SheShield Band Starting...");

  // Configure pins
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);

  // Startup indicator
  digitalWrite(LED_PIN, HIGH);
  tone(BUZZER_PIN, 1000, 300);
  delay(500);
  digitalWrite(LED_PIN, LOW);

  // Initialize accelerometer
  setupMPU6050();

  // Initialize Bluetooth Classic
  SerialBT.begin("SheShield"); // Device name shown in scan
  Serial.println("✅ Bluetooth Classic started as: SheShield");
  Serial.println("🛡️ SheShield Band Ready!\n");
}

// ==================== LOOP ====================
void loop() {
  unsigned long now = millis();

  // --- Button press detection (SOS) ---
  if (digitalRead(BUTTON_PIN) == LOW) { // Active LOW with pull-up
    if (now - lastButtonPress > 1000) { // 1s debounce
      lastButtonPress = now;
      Serial.println("🚨 SOS BUTTON PRESSED!");

      // Send to app
      SerialBT.println("SOS");

      // Feedback
      digitalWrite(LED_PIN, HIGH);
      tone(BUZZER_PIN, 2000, 200);
      delay(200);
      digitalWrite(LED_PIN, LOW);
    }
  }

  // --- Shake detection ---
  if (now - lastShakeTime > SHAKE_COOLDOWN_MS) {
    if (detectShake()) {
      lastShakeTime = now;
      Serial.println("📳 SHAKE DETECTED!");

      // Send to app
      SerialBT.println("SHAKE");

      // Feedback
      digitalWrite(LED_PIN, HIGH);
      tone(BUZZER_PIN, 1500, 150);
      delay(150);
      digitalWrite(LED_PIN, LOW);
    }
  }

  // --- Read commands from app ---
  while (SerialBT.available()) {
    char c = SerialBT.read();
    if (c == '\n') {
      handleAppCommand(inputBuffer);
      inputBuffer = "";
    } else if (c != '\r') {
      inputBuffer += c;
    }
  }

  // --- Handle buzzer beeping ---
  handleBuzzer();

  // --- Status LED blink when connected ---
  if (SerialBT.hasClient()) {
    static unsigned long ledTimer = 0;
    if (now - ledTimer > 3000) {
      ledTimer = now;
      digitalWrite(LED_PIN, HIGH);
      delay(50);
      digitalWrite(LED_PIN, LOW);
    }
  }

  delay(50);
}

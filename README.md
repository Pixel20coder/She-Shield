# She Shield – Smart Safety Wearable System 🛡️

SheShield is a women's safety wearable system developed for HackHerThon 2026. It consists of a **smart safety bracelet** (ESP32 hardware) and a **Flutter mobile app** (emergency response). The bracelet detects danger via SOS button and shake/motion sensor, then triggers the phone app over **Bluetooth Classic (SPP)** to send alerts, share location, record video, and contact emergency services.

## **<ins>📹 Prototype & App Demonstration Video</ins>**

### **<ins>[▶ Click here to watch the full demo on Google Drive](https://drive.google.com/file/d/1BB_w9BKbrbSptshWBkR0CEz_fbgr8N_p/view?usp=sharing)</ins>**

---

## System Architecture

```
┌─────────────────────┐       Bluetooth Classic (SPP)       ┌─────────────────────┐
│   ESP32 Bracelet    │ ──────────────────────────────────▶ │   Flutter App       │
│                     │                                      │                     │
│  • SOS Button       │   "SOS\n"  /  "SHAKE\n"             │  • SOS Alert UI     │
│  • Accelerometer    │ ◀──────────────────────────────────  │  • SMS to Contacts  │
│  • Buzzer           │   "BUZZER_ON\n"  /  "LED_ON\n"      │  • Live Location    │
│  • LED              │                                      │  • Video Recording  │
└─────────────────────┘                                      │  • Police Stations  │
                                                             └─────────────────────┘
```

| Component | Role |
|---|---|
| **ESP32 Bracelet (Hardware)** | Trigger — SOS button, accelerometer shake, buzzer, LED |
| **Mobile App (Software)** | Response — GPS, alerts, SMS, video, maps, notifications |

---

## Features

### 🔧 ESP32 Bracelet (Trigger Device)
- 🔘 **SOS Button** — Press to send `"SOS\n"` to the app
- 📳 **Shake Detection** — MPU6050 accelerometer auto-sends `"SHAKE\n"`
- 🔊 **Remote Buzzer** — App can trigger buzzer via `"BUZZER_ON\n"`
- 💡 **Remote LED** — App controls LED via `"LED_ON\n"` / `"LED_OFF\n"`
- 📡 **Bluetooth Classic** — Broadcasts as `"SheShield"` via SPP/RFCOMM

### 📱 Mobile App (Response System)
- 🔐 **Login / Sign-Up** — Firebase email/password authentication
- 🔴 **SOS Button** — 3-second hold to prevent accidental triggers
- 📍 **Live Location** — GPS tracking with Google Maps (updates every 5s)
- 📤 **Share Location** — WhatsApp, SMS, or clipboard
- 🚔 **Nearby Police Stations** — OpenStreetMap Overpass API, sorted by distance
- 👥 **Emergency Contacts** — Add, delete, send SOS SMS to all with location link
- 📡 **Bluetooth Classic Pairing** — Connect to ESP32, persistent connection across screens
- 🎙️ **Voice Commands** — Phone mic detects "help", "bachao", "danger", "police"
- 📹 **SOS Video Recording** — Auto-records 30s video, uploads to Firebase Storage
- 🔔 **Push Notifications** — Firebase Cloud Messaging alerts
- 🗂️ **Past Emergencies** — View history of triggered SOS events

### 🔗 Persistent Bluetooth Connection
- **Singleton service** — Connection stays alive across all screens
- **Global SOS listener** — Triggers emergency from any screen
- **Only disconnects** when user explicitly taps "Disconnect"

---

## Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.0+)
- Android Studio or VS Code with Flutter plugin
- Firebase project (Auth, Firestore, Storage, FCM)
- Google Maps API key
- [Arduino IDE](https://www.arduino.cc/en/software) (for ESP32)

### 1. Install Flutter Dependencies

```bash
cd sheshield
flutter pub get
```

### 2. Firebase Setup
- Add your `google-services.json` to `android/app/`
- Enable: Authentication (Email/Password), Firestore, Storage, Cloud Messaging

### 3. Google Maps API Key
Already configured in `AndroidManifest.xml`.

### 4. ESP32 Setup
1. Open `esp32/sheshield_band.ino` in Arduino IDE
2. Install ESP32 board via Board Manager
3. **Update pin numbers** at the top if your wiring differs:

| Component | Default GPIO |
|-----------|-------------|
| Button | 4 |
| Buzzer | 5 |
| LED | 2 |
| MPU6050 SDA | 21 |
| MPU6050 SCL | 22 |

4. Upload to your ESP32

### 5. Run the App

```bash
flutter run
```

---

## Project Structure

```
sheshield/
├── lib/
│   ├── main.dart                          # App entry, auth routing, dark theme
│   ├── screens/
│   │   ├── login_screen.dart              # Email/password login & sign-up
│   │   ├── home_screen.dart               # SOS button, status, GPS, navigation
│   │   ├── location_screen.dart           # Google Maps, live tracking, share
│   │   ├── contacts_screen.dart           # Emergency contacts management
│   │   ├── nearby_police_screen.dart      # Nearby police stations map
│   │   ├── bluetooth_screen.dart          # Bluetooth Classic pairing UI
│   │   ├── past_emergencies_screen.dart   # SOS event history
│   │   └── profile_screen.dart            # User profile
│   └── services/
│       ├── bracelet_service.dart          # Bluetooth Classic singleton (persistent)
│       ├── location_service.dart          # Geolocator GPS wrapper
│       ├── sms_service.dart               # Send SOS SMS to contacts
│       ├── video_recording_service.dart   # 30s video recording + upload
│       ├── notification_service.dart      # FCM push notifications
│       ├── alert_service.dart             # Firestore SOS alerts
│       ├── places_service.dart            # OpenStreetMap police stations
│       ├── voice_trigger_service.dart     # Speech-to-text voice commands
│       └── storage_service.dart           # SharedPreferences contacts
├── esp32/
│   └── sheshield_band.ino                 # ESP32 Bluetooth Classic sketch
├── android/
│   └── app/src/main/AndroidManifest.xml
├── pubspec.yaml
└── README.md
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `firebase_core` | Firebase initialization |
| `firebase_auth` | Email/password authentication |
| `cloud_firestore` | SOS alerts & location storage |
| `firebase_storage` | Video upload |
| `firebase_messaging` | Push notifications |
| `geolocator` | GPS location access |
| `google_maps_flutter` | Map display |
| `flutter_bluetooth_serial_ble` | Bluetooth Classic (SPP/RFCOMM) |
| `speech_to_text` | Voice command detection |
| `camera` | Video recording |
| `shared_preferences` | Local contact storage |
| `permission_handler` | Runtime permissions |
| `url_launcher` | Open URLs, SMS |
| `http` | HTTP requests |

---

## ESP32 Communication Protocol

### ESP32 → App (Serial)
| Command | Trigger |
|---------|---------|
| `SOS\n` | Button pressed |
| `SHAKE\n` | Motion detected |

### App → ESP32 (Serial)
| Command | Action |
|---------|--------|
| `BUZZER_ON\n` | Activate buzzer |
| `BUZZER_OFF\n` | Stop buzzer |
| `LED_ON\n` | Turn LED on |
| `LED_OFF\n` | Turn LED off |

---

## License

Built for HackHerThon 2026 🏆

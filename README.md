# She Shield – Smart Safety Wearable System 🛡️

SheShield is a women's safety wearable system developed for HackHerThon 2026. It consists of a **smart safety bracelet** (hardware trigger) and a **Flutter mobile app** (emergency response). The bracelet detects danger via SOS button, shake/motion, and voice commands, then triggers the phone app to send alerts, share location, and contact emergency services.

## System Architecture

| Component | Role |
|---|---|
| **Bracelet (Hardware)** | Trigger device — SOS button, shake sensor, mic, camera, Bluetooth |
| **Mobile App (Software)** | Response system — GPS, alerts, contacts, maps, notifications |

## Features

### Bracelet (Trigger Device)
- 🔘 **Hidden SOS Button** — Press to trigger emergency alert
- 📳 **Shake Detection** — Violent shaking auto-triggers SOS
- 🎙️ **Voice Detection** — Keywords: "help", "bachao", "danger", "police"
- 📷 **Camera** — Records threat footage

### Mobile App (Response System)
- 🔐 **Login / Sign-Up** — Firebase email/password authentication
- 🔴 **SOS Button** — 3-second hold to prevent accidental triggers
- 📍 **Live Location** — GPS tracking with Google Maps
- 📤 **Share Location** — WhatsApp, SMS, or clipboard
- 🚔 **Nearby Police Stations** — OpenStreetMap Overpass API
- 👥 **Emergency Contacts** — Add, delete, send SOS to all
- 📡 **Bluetooth Pairing** — Connect to bracelet, receive SOS signals
- 🎙️ **Voice Commands** — Phone mic detects emergency keywords
- 📷 **Emergency Camera** — Record + upload to Firebase Storage
- 🔔 **Push Notifications** — Firebase Cloud Messaging alerts

## Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.0+)
- Android Studio or VS Code with Flutter plugin
- Firebase project with Auth, Firestore, Storage, and FCM enabled
- Google Maps API key

### 1. Install Dependencies

```bash
cd sheshield
flutter pub get
```

### 2. Firebase Setup
- Add your `google-services.json` to `android/app/`
- Enable Authentication (Email/Password), Firestore, Storage, and Cloud Messaging in Firebase Console

### 3. Google Maps API Key
Your API key is already configured in `AndroidManifest.xml`.

### 4. Run the App

```bash
flutter run
```

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
│   │   ├── bluetooth_screen.dart          # BLE pairing + simulate triggers
│   │   └── camera_screen.dart             # Record + upload threat footage
│   └── services/
│       ├── location_service.dart          # Geolocator GPS wrapper
│       ├── storage_service.dart           # SharedPreferences contacts
│       ├── notification_service.dart      # FCM push notifications
│       ├── alert_service.dart             # Firestore SOS alerts
│       ├── places_service.dart            # OpenStreetMap police stations
│       ├── voice_trigger_service.dart     # Speech-to-text voice commands
│       └── bracelet_service.dart          # BLE bracelet command listener
├── android/
│   └── app/src/main/AndroidManifest.xml
├── pubspec.yaml
└── README.md
```

## Dependencies

| Package | Purpose |
|---|---|
| `firebase_core` | Firebase initialization |
| `firebase_auth` | Email/password authentication |
| `cloud_firestore` | SOS alerts & location storage |
| `firebase_storage` | Video upload from camera |
| `firebase_messaging` | Push notifications |
| `geolocator` | GPS location access |
| `google_maps_flutter` | Map display |
| `flutter_blue_plus` | Bluetooth Low Energy |
| `speech_to_text` | Voice command detection |
| `camera` | Video recording |
| `shared_preferences` | Local contact storage |
| `url_launcher` | Open URLs, SMS |
| `permission_handler` | Runtime permissions |

## License

Built for HackHerThon 2026 🏆

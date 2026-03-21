# SheShield — System Architecture

## Overview

SheShield is a smart wearable safety system comprising a **hardware bracelet** (ESP32-based) and a **Flutter mobile app**. When an emergency is detected — via button press, shake gesture, or voice keywords — the system triggers multi-channel SOS alerts including SMS, live location sharing, push notifications, and audio/video recording.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     SHESHIELD SYSTEM                            │
├────────────────────────┬────────────────────────────────────────┤
│   HARDWARE (Bracelet)  │          SOFTWARE (Mobile App)         │
│                        │                                        │
│  ┌──────────────────┐  │  ┌──────────────────────────────────┐  │
│  │   ESP32 MCU       │◄─┼──┤  Bluetooth Classic (SPP)         │  │
│  │   (Main Brain)    │──┼─►│  BluetoothService Singleton      │  │
│  └──────┬───────────┘  │  └──────────┬───────────────────────┘  │
│         │              │             │                          │
│  ┌──────┴──────────┐   │  ┌──────────┴───────────────────────┐  │
│  │ Sensors & I/O   │   │  │  Alert Engine                     │  │
│  │ • Push Button   │   │  │  • Location Service (GPS)         │  │
│  │ • Accelerometer │   │  │  • SMS Service                    │  │
│  │ • Buzzer/Alarm  │   │  │  • Push Notifications (FCM)       │  │
│  └─────────────────┘   │  │  • Video Recording                │  │
│                        │  │  • Alert Broadcast (Firestore)     │  │
│  ┌─────────────────┐   │  └──────────────────────────────────┘  │
│  │ Power System    │   │                                        │
│  │ • Li-Po Battery │   │  ┌──────────────────────────────────┐  │
│  │ • TP4056 Charger│   │  │  Voice Trigger Engine             │  │
│  │ • USB-C Port    │   │  │  • Speech-to-Text (On-device)     │  │
│  └─────────────────┘   │  │  • Keyword Detection              │  │
│                        │  └──────────────────────────────────┘  │
│  ┌─────────────────┐   │                                        │
│  │ SIM Module      │   │  ┌──────────────────────────────────┐  │
│  │ • SIM800L GSM   │   │  │  Firebase Backend                 │  │
│  │ • SMS Fallback  │   │  │  • Auth / Firestore / Storage     │  │
│  │ • Emergency Call│   │  │  • Cloud Messaging (FCM)          │  │
│  └─────────────────┘   │  └──────────────────────────────────┘  │
└────────────────────────┴────────────────────────────────────────┘
```

---

## Hardware Architecture

### ESP32 Microcontroller (Main Brain)
| Spec | Detail |
|------|--------|
| **Chip** | ESP32-WROOM-32 |
| **Clock** | 240 MHz dual-core |
| **Flash** | 4 MB |
| **Connectivity** | Bluetooth Classic (SPP) + WiFi |
| **GPIO Used** | Button (GPIO 13), Buzzer (GPIO 25), IMU (I2C) |

### Sensors & Input/Output
| Component | Purpose | Interface |
|-----------|---------|-----------|
| **Push Button** | Manual SOS trigger | GPIO 13 (pull-up) |
| **MPU6050 Accelerometer** | Shake/impact detection | I2C (SDA/SCL) |
| **Piezo Buzzer** | Audible alarm on SOS | GPIO 25 (PWM) |
| **LED Indicator** | Connection/SOS status | GPIO 2 (built-in) |

### Power System
| Component | Specification |
|-----------|--------------|
| **Battery** | 3.7V 500mAh Li-Po (rechargeable) |
| **Charging IC** | TP4056 (1A linear charger) |
| **Charging Port** | Micro-USB / USB-C |
| **Protection** | Overcharge, over-discharge, short-circuit (DW01A + FS8205A) |
| **Voltage Regulator** | AMS1117-3.3V (stable 3.3V to ESP32) |
| **Battery Life** | ~8–12 hours (BT active, idle) |
| **Charge Time** | ~1.5 hours (0→100%) |

### SIM / GSM Module
| Component | Specification |
|-----------|--------------|
| **Module** | SIM800L GSM/GPRS |
| **Band** | Quad-band 850/900/1800/1900 MHz |
| **SIM Type** | Nano-SIM / Micro-SIM |
| **Power** | 3.4V–4.4V (separate LDO from battery) |
| **Functions** | SMS fallback, emergency call (112/100) |
| **Antenna** | PCB helical antenna |
| **Interface** | UART (TX→GPIO 16, RX→GPIO 17) |

### ESP32 Firmware Commands (sent over Bluetooth)
```
BUTTON SOS    → Button pressed, trigger SOS
MOTION SOS    → Shake/impact detected, trigger SOS
VOICE SOS     → Reserved for voice relay
ACK           → Acknowledgment
```

### Hardware Block Diagram

```
                    ┌─────────────┐
          USB-C ───►│  TP4056     │
                    │  Charger IC │
                    └──────┬──────┘
                           │ VBAT
                    ┌──────┴──────┐
                    │  Li-Po      │
                    │  3.7V 500mAh│
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │ AMS1117-3.3V│◄── Voltage Regulator
                    └──────┬──────┘
                           │ 3.3V
              ┌────────────┼────────────┐
              │            │            │
       ┌──────┴──────┐ ┌──┴───┐  ┌─────┴─────┐
       │   ESP32     │ │MPU   │  │  SIM800L   │
       │   MCU       │ │6050  │  │  GSM       │
       │             │ │(I2C) │  │  Module    │
       │  BT Classic │ └──────┘  │            │
       │  (to Phone) │           │  Nano-SIM  │
       └──┬─────┬────┘           └────────────┘
          │     │
     ┌────┘     └────┐
     │               │
┌────┴────┐   ┌──────┴──────┐
│  Button │   │   Buzzer    │
│ (GPIO13)│   │  (GPIO 25)  │
└─────────┘   └─────────────┘
```

---

## Software Architecture

### App Layer Stack

```
┌──────────────────────────────────────────┐
│              UI Layer (Screens)           │
│  HomeScreen │ SOSScreen │ BluetoothScreen│
│  LoginScreen│ ProfileScreen │ MapScreen  │
├──────────────────────────────────────────┤
│            Service Layer                  │
│  BluetoothService  │  LocationService    │
│  AlertService      │  SmsService         │
│  NotificationService│ VideoRecording     │
│  VoiceTriggerService│ PlacesService      │
├──────────────────────────────────────────┤
│            Backend (Firebase)             │
│  Auth │ Firestore │ Storage │ FCM        │
├──────────────────────────────────────────┤
│          Platform (Android)               │
│  Bluetooth SPP │ GPS │ Camera │ SMS      │
└──────────────────────────────────────────┘
```

### Key Services

| Service | File | Responsibility |
|---------|------|----------------|
| **BluetoothService** | `bluetooth_service.dart` | Singleton, auto-reconnect, command parsing, buzzer control |
| **LocationService** | `location_service.dart` | GPS tracking, live Firestore updates every 5s |
| **AlertService** | `alert_service.dart` | Writes SOS alerts to Firestore `alerts` collection |
| **SmsService** | `sms_service.dart` | Sends SMS with Google Maps link to emergency contacts |
| **NotificationService** | `notification_service.dart` | FCM push notifications to emergency contacts |
| **VideoRecordingService** | `video_recording_service.dart` | Camera recording, uploads to Firebase Storage |
| **VoiceTriggerService** | `voice_trigger_service.dart` | Continuous speech recognition, keyword matching |
| **PlacesService** | `places_service.dart` | Overpass API → nearby police stations (100km radius) |

---

## SOS Trigger Flow

```
  ┌────────────────┐     ┌────────────────┐     ┌────────────────┐
  │  BUTTON PRESS  │     │  SHAKE DETECT  │     │  VOICE KEYWORD │
  │  (Hardware)    │     │  (Hardware)    │     │  (App Mic)     │
  └───────┬────────┘     └───────┬────────┘     └───────┬────────┘
          │                      │                      │
          │  "BUTTON SOS"        │  "MOTION SOS"        │  keyword match
          └──────────┬───────────┘                      │
                     │ Bluetooth SPP                    │
                     ▼                                  ▼
          ┌──────────────────────────────────────────────────────┐
          │              BluetoothService.onCommand              │
          │                  _triggerGlobalSOS()                  │
          └──────────────────────┬───────────────────────────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
            ┌───────────┐ ┌───────────┐ ┌───────────┐
            │ Location  │ │ SMS to    │ │ FCM Push  │
            │ to Firestore│ │ Contacts │ │ Notif    │
            └───────────┘ └───────────┘ └───────────┘
                    │            │            │
                    ▼            ▼            ▼
            ┌───────────┐ ┌───────────┐ ┌───────────┐
            │ Video     │ │ Alert to  │ │ Buzzer    │
            │ Recording │ │ Firestore │ │ Activate  │
            └───────────┘ └───────────┘ └───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   Full-Screen SOS UI   │
                    │  (Flashing Red Alert)  │
                    └────────────────────────┘
```

---

## Communication Protocol

| Layer | Protocol | Details |
|-------|----------|---------|
| **Bracelet ↔ Phone** | Bluetooth Classic SPP | 9600 baud, UTF-8 newline-delimited |
| **Phone ↔ Firebase** | HTTPS / WebSocket | Firestore real-time streams |
| **Phone ↔ Contacts** | SMS (native) | Google Maps link included |
| **Phone ↔ Contacts** | FCM Push | Via Firebase Cloud Functions |
| **Bracelet ↔ Network** | GSM (SIM800L) | SMS fallback if phone disconnected |

---

## Security & Privacy

- Firebase Authentication (email/password)
- Firestore security rules (user-scoped data)
- Location data encrypted in transit (HTTPS/TLS)
- Emergency contacts stored locally (SharedPreferences)
- No data shared with third parties

---

## Tech Stack Summary

| Category | Technology |
|----------|-----------|
| **Hardware** | ESP32, MPU6050, SIM800L, TP4056, Li-Po |
| **Mobile** | Flutter (Dart) |
| **Backend** | Firebase (Auth, Firestore, Storage, FCM) |
| **Maps** | Google Maps Flutter + Overpass API |
| **Bluetooth** | flutter_bluetooth_serial_ble (Classic SPP) |
| **Speech** | speech_to_text (on-device) |
| **Camera** | camera package (auto-record on SOS) |

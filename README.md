# She Shield – Smart Safety Bracelet 🛡️

A Flutter mobile app prototype for a wearable smart safety bracelet that sends SOS alerts and shares GPS location during emergencies.

## Features

- 🔴 **SOS Emergency Button** — Large animated button with haptic feedback
- 📍 **Live Location** — Google Maps with real-time GPS tracking
- 👥 **Emergency Contacts** — Add, delete, and manage contacts (stored locally)
- 📤 **Share Location** — Send GPS coordinates to emergency contacts
- ⌚ **Bracelet Status** — Connection indicator with pulse animation

## Screenshots

The app has 3 main screens:
1. **Home** — SOS button, bracelet status, GPS card, navigation
2. **Live Location** — Map, coordinates, share button
3. **Emergency Contacts** — Contact list, add/delete, SOS to all

## Setup

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.0+)
- Android Studio or VS Code with Flutter plugin
- A Google Maps API key

### 1. Install Dependencies

```bash
cd sheshield
flutter pub get
```

### 2. Add Google Maps API Key

Open `android/app/src/main/AndroidManifest.xml` and replace:

```xml
android:value="YOUR_GOOGLE_MAPS_API_KEY_HERE"
```

with your actual [Google Maps API key](https://developers.google.com/maps/documentation/android-sdk/get-api-key).

### 3. Font Setup (Optional)

The app uses the Inter font. Either:
- Download [Inter from Google Fonts](https://fonts.google.com/specimen/Inter) and place the `.ttf` files in `assets/fonts/`
- Or remove the `fonts` section from `pubspec.yaml` to use the system default font

### 4. Run the App

```bash
flutter run
```

## Project Structure

```
sheshield/
├── lib/
│   ├── main.dart                    # App entry + dark theme
│   ├── screens/
│   │   ├── home_screen.dart         # SOS button, status, GPS, nav
│   │   ├── location_screen.dart     # Google Maps, coordinates, share
│   │   └── contacts_screen.dart     # Contact list, add/delete
│   └── services/
│       ├── location_service.dart    # Geolocator GPS wrapper
│       └── storage_service.dart     # SharedPreferences contacts
├── android/
│   └── app/src/main/AndroidManifest.xml
├── pubspec.yaml
└── README.md
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `geolocator` | GPS location access |
| `google_maps_flutter` | Map display |
| `shared_preferences` | Local contact storage |
| `share_plus` | Share location via OS share sheet |
| `permission_handler` | Runtime permissions |
| `url_launcher` | Open URLs |

## Notes

- This is a **prototype** — SOS alerts are simulated (no actual SMS sending)
- The bracelet connection status is togglable for demo purposes
- Default sample contacts (Mom, Dad, Sister) are added on first launch
- Location defaults to New Delhi if GPS is unavailable

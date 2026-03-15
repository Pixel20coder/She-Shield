import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service wrapping the Geolocator package for GPS location access
/// and Firebase Firestore for uploading location updates.
///
/// Provides SOS-triggered live tracking that writes the user's GPS
/// coordinates to the `live_locations` Firestore collection every
/// 5 seconds.
class LocationService {
  static Timer? _sosTimer;
  static bool _tracking = false;

  /// Whether the SOS live-tracking loop is currently running.
  static bool get isTracking => _tracking;

  // ---------------------------------------------------------------------------
  // Permission & single-shot location
  // ---------------------------------------------------------------------------

  /// Check and request location permissions, then get current position.
  static Future<Position> getCurrentLocation() async {
    await _ensurePermissions();

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // ---------------------------------------------------------------------------
  // Continuous stream (used by LocationScreen / Google-Maps view)
  // ---------------------------------------------------------------------------

  /// Stream of position updates (every ~5 meters of movement).
  static Stream<Position> getLocationStream() {
   return Geolocator.getPositionStream(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  ),
);
  }

  // ---------------------------------------------------------------------------
  // SOS live-tracking (Timer-based, every 5 seconds)
  // ---------------------------------------------------------------------------

  /// Start SOS live-location tracking.
  ///
  /// 1. Ensures location permissions are granted.
  /// 2. Fetches the current position immediately and writes it to Firestore.
  /// 3. Starts a periodic timer that fetches and writes the position every
  ///    5 seconds until [stopSOS] is called.
  static Future<void> startSOS(String userId) async {
    if (_tracking) return; // already running

    await _ensurePermissions();

    // Write the first location immediately.
    await _fetchAndWrite(userId);

    // Schedule subsequent writes every 5 seconds.
    _tracking = true;
    _sosTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchAndWrite(userId);
    });
  }

  /// Stop SOS live-location tracking.
  static void stopSOS() {
    _sosTimer?.cancel();
    _sosTimer = null;
    _tracking = false;
  }

  // ---------------------------------------------------------------------------
  // Firestore helpers
  // ---------------------------------------------------------------------------

  /// Fetch the current position and write it to the `live_locations` collection.
  static Future<void> _fetchAndWrite(String userId) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _writeToFirestore(userId, pos.latitude, pos.longitude);
    } catch (_) {
      // Silently ignore individual fetch/write failures so the timer
      // keeps running and retries on the next tick.
    }
  }

  /// Write a single location document to Firestore.
  static Future<void> _writeToFirestore(
    String userId,
    double lat,
    double lng,
  ) async {
    await FirebaseFirestore.instance.collection('live_locations').add({
      'userId': userId,
      'latitude': lat,
      'longitude': lng,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Send the current latitude and longitude to Firestore (`live_locations`).
  static Future<void> sendLocationToFirestore(
    double lat,
    double lng, {
    String userId = 'user_placeholder',
  }) async {
    await _writeToFirestore(userId, lat, lng);
  }

  // ---------------------------------------------------------------------------
  // Permission helper
  // ---------------------------------------------------------------------------

  /// Ensures location services are enabled and permissions are granted.
  /// Throws an [Exception] if the user denies permission or services are off.
  static Future<void> _ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable them.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied. '
        'Please enable them in settings.',
      );
    }
  }
}

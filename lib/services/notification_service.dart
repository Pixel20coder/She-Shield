import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for handling push notifications and Firestore alert storage.
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Cached FCM device token.
  static String? _fcmToken;

  /// Initialize FCM: request notification permissions and retrieve the
  /// device token. Call this once at app startup after [Firebase.initializeApp].
  static Future<void> initialize() async {
    // Request notification permissions (shows the system dialog on first launch).
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Retrieve the FCM token for this device.
      _fcmToken = await _messaging.getToken();
    }

    // Listen for foreground messages so they can be handled in-app.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  /// Handle push notifications received while the app is in the foreground.
  static void _handleForegroundMessage(RemoteMessage message) {
    // Foreground messages are silently received; the SOS dialog already
    // provides visual feedback, so no additional UI action is needed here.
  }

  /// Send an SOS alert: saves the alert to the Firestore "alerts" collection
  /// and returns the document ID.
  ///
  /// [lat] and [lng] are the user's current GPS coordinates.
  static Future<String?> sendSOSAlert({double? lat, double? lng}) async {
    try {
      final docRef = await _firestore.collection('alerts').add({
        'title': 'SOS Alert',
        'body': 'User has triggered an emergency alert.',
        'latitude': lat,
        'longitude': lng,
        'fcmToken': _fcmToken,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      // Silently fail – the SOS UI feedback is already visible to the user.
      return null;
    }
  }
}

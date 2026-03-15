import 'package:cloud_firestore/cloud_firestore.dart';
import 'storage_service.dart';

/// Service for broadcasting emergency alerts to Firestore and
/// preparing FCM notification data for emergency contacts.
class AlertService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Broadcast an emergency alert.
  ///
  /// 1. Generates a Google Maps link from [lat]/[lng].
  /// 2. Creates a Firestore document in the `alerts` collection.
  /// 3. Reads local emergency contacts and stores their info alongside the
  ///    alert so a Cloud Function can deliver FCM push notifications.
  ///
  /// Returns the Firestore document ID of the created alert, or `null` on
  /// failure.
  static Future<String?> broadcastAlert({
    required double lat,
    required double lng,
    String? userId,
  }) async {
    try {
      // 1. Generate Google Maps link.
      final mapsLink = 'https://maps.google.com/?q=$lat,$lng';

      // 2. Load emergency contacts from local storage.
      final contacts = await StorageService.loadContacts();
      final contactList = contacts
          .map((c) => {'name': c.name, 'phone': c.phone})
          .toList();

      // 3. Create the alert document.
      final docRef = await _firestore.collection('alerts').add({
        'userId': userId ?? 'anonymous',
        'latitude': lat,
        'longitude': lng,
        'mapsLink': mapsLink,
        'status': 'active',
        'contacts': contactList,
        'notificationTitle': '🚨 Emergency Alert',
        'notificationBody':
            'A user needs help.\nLive location: $mapsLink',
        'timestamp': FieldValue.serverTimestamp(),
      });

      return docRef.id;
    } catch (_) {
      return null;
    }
  }

  /// Mark an alert as resolved / cancelled.
  static Future<void> cancelAlert(String alertId) async {
    try {
      await _firestore.collection('alerts').doc(alertId).update({
        'status': 'cancelled',
      });
    } catch (_) {
      // Silently fail.
    }
  }
}

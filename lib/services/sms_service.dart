import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';

/// Service for sending SMS directly from the app (no user interaction needed).
/// Uses a platform channel to call Android's native SmsManager.
class SmsService {
  static const _channel = MethodChannel('com.sheshield/sms');

  /// Sends a raw SMS to the given phone number.
  static Future<bool> _sendSms(String phoneNumber, String message) async {
    try {
      await _channel.invokeMethod('sendSms', {
        'phone': phoneNumber,
        'message': message,
      });
      return true;
    } catch (e) {
      debugPrint('SmsService: Failed to send SMS to $phoneNumber — $e');
      return false;
    }
  }

  /// Requests SMS permission and sends an SMS directly to [phoneNumber]
  /// notifying them that they have been added as an emergency contact.
  static Future<bool> sendContactAddedSms({
    required String phoneNumber,
    required String contactName,
  }) async {
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      debugPrint('SmsService: SMS permission denied');
      return false;
    }

    final userName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'a SheShield user';

    final message =
        'Hi $contactName! You have been added as an emergency contact on '
        'SheShield by $userName. In case of an emergency, you will '
        'receive SOS alerts with a live location link. Please stay reachable. '
        '- Sent via SheShield';

    return _sendSms(phoneNumber, message);
  }

  /// Sends an SOS emergency SMS to ALL saved emergency contacts with location.
  static Future<void> sendSOSToAllContacts({
    required double lat,
    required double lng,
  }) async {
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      debugPrint('SmsService: SMS permission denied — cannot send SOS');
      return;
    }

    final contacts = await StorageService.loadContacts();
    if (contacts.isEmpty) {
      debugPrint('SmsService: No emergency contacts to send SOS to');
      return;
    }

    final userName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'A SheShield user';

    final mapLink = 'https://www.google.com/maps?q=$lat,$lng';

    final message =
        '🚨 SOS EMERGENCY ALERT!\n\n'
        '$userName has triggered an emergency SOS on SheShield.\n\n'
        '📍 Live Location: $mapLink\n\n'
        'Please respond immediately or contact emergency services. '
        '- SheShield Emergency Alert';

    for (final contact in contacts) {
      await _sendSms(contact.phone, message);
    }

    debugPrint('SmsService: SOS SMS sent to ${contacts.length} contacts');
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents an emergency contact.
class Contact {
  final String id;
  final String name;
  final String phone;

  Contact({
    required this.id,
    required this.name,
    required this.phone,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
      );
}

/// Service for persisting emergency contacts using SharedPreferences.
class StorageService {
  static const String _contactsKey = 'sheshield_contacts';

  /// Load all saved contacts.
  static Future<List<Contact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_contactsKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      // Return default sample contacts on first launch
      final defaults = [
        Contact(id: '1', name: 'Mom', phone: '+91 98765 43210'),
        Contact(id: '2', name: 'Dad', phone: '+91 98765 43211'),
        Contact(id: '3', name: 'Sister', phone: '+91 98765 43212'),
      ];
      await saveContacts(defaults);
      return defaults;
    }
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Save contacts list.
  static Future<void> saveContacts(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString(_contactsKey, jsonStr);
  }

  /// Add a new contact.
  static Future<List<Contact>> addContact(
      List<Contact> current, String name, String phone) async {
    final contact = Contact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      phone: phone,
    );
    final updated = [...current, contact];
    await saveContacts(updated);
    return updated;
  }

  /// Delete a contact by ID.
  static Future<List<Contact>> deleteContact(
      List<Contact> current, String id) async {
    final updated = current.where((c) => c.id != id).toList();
    await saveContacts(updated);
    return updated;
  }
}

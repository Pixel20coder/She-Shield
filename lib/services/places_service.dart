import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// Model representing a nearby police station.
class PoliceStation {
  final String name;
  final String vicinity;
  final double lat;
  final double lng;
  final String placeId;
  final double distanceMeters;

  PoliceStation({
    required this.name,
    required this.vicinity,
    required this.lat,
    required this.lng,
    required this.placeId,
    required this.distanceMeters,
  });

  /// Human-readable distance string.
  String get distanceText {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toInt()} m';
  }
}

/// Service for fetching nearby police stations using multiple fallback APIs.
/// Tries Overpass API first, then falls back to Nominatim search.
class PlacesService {
  /// List of Overpass API mirrors to try in order.
  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  /// Fetch police stations near the given coordinates.
  /// Uses Overpass API with automatic mirror fallback, then Nominatim as a
  /// last resort.
  static Future<List<PoliceStation>> fetchNearbyPoliceStations(
    double lat,
    double lng, {
    int radiusMeters = 5000,
  }) async {
    // --- Attempt 1: Overpass API (try each mirror) ---
    for (final endpoint in _overpassEndpoints) {
      try {
        final results = await _fetchFromOverpass(endpoint, lat, lng, radiusMeters);
        if (results.isNotEmpty) return results;
      } catch (_) {
        // Mirror failed — try next one.
      }
    }

    // --- Attempt 2: Overpass with larger radius ---
    for (final endpoint in _overpassEndpoints) {
      try {
        final results = await _fetchFromOverpass(endpoint, lat, lng, 15000);
        if (results.isNotEmpty) return results;
      } catch (_) {
        // Mirror failed — try next one.
      }
    }

    // --- Attempt 3: Nominatim reverse-geocode search as fallback ---
    try {
      final results = await _fetchFromNominatim(lat, lng);
      if (results.isNotEmpty) return results;
    } catch (_) {
      // Nominatim also failed.
    }

    // All attempts exhausted — return empty list so the UI shows
    // "No nearby police stations found" instead of an error.
    return [];
  }

  // -------------------------------------------------------------------------
  // Overpass API
  // -------------------------------------------------------------------------
  static Future<List<PoliceStation>> _fetchFromOverpass(
    String endpoint,
    double lat,
    double lng,
    int radiusMeters,
  ) async {
    final query = '''
[out:json][timeout:15];
(
  node["amenity"="police"](around:$radiusMeters,$lat,$lng);
  way["amenity"="police"](around:$radiusMeters,$lat,$lng);
);
out center body;
''';

    final uri = Uri.parse(endpoint);
    final response = await http
        .post(uri, body: {'data': query})
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Overpass returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];

    return _parseOverpassElements(elements, lat, lng);
  }

  static List<PoliceStation> _parseOverpassElements(
    List<dynamic> elements,
    double userLat,
    double userLng,
  ) {
    final stations = <PoliceStation>[];

    for (final el in elements) {
      double? stationLat;
      double? stationLng;

      if (el['type'] == 'node') {
        stationLat = (el['lat'] as num?)?.toDouble();
        stationLng = (el['lon'] as num?)?.toDouble();
      } else if (el['center'] != null) {
        stationLat = (el['center']['lat'] as num?)?.toDouble();
        stationLng = (el['center']['lon'] as num?)?.toDouble();
      }

      if (stationLat == null || stationLng == null) continue;

      final tags = el['tags'] as Map<String, dynamic>? ?? {};
      final name = tags['name'] as String? ?? 'Police Station';
      final address = tags['addr:full'] as String? ??
          tags['addr:street'] as String? ??
          '';

      final distance = Geolocator.distanceBetween(
        userLat, userLng, stationLat, stationLng,
      );

      stations.add(PoliceStation(
        name: name,
        vicinity: address,
        lat: stationLat,
        lng: stationLng,
        placeId: el['id'].toString(),
        distanceMeters: distance,
      ));
    }

    stations.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return stations;
  }

  // -------------------------------------------------------------------------
  // Nominatim fallback
  // -------------------------------------------------------------------------
  static Future<List<PoliceStation>> _fetchFromNominatim(
    double lat,
    double lng,
  ) async {
    // Nominatim search for police stations near coordinates.
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=police+station'
      '&format=json'
      '&limit=20'
      '&viewbox=${lng - 0.1},${lat + 0.1},${lng + 0.1},${lat - 0.1}'
      '&bounded=1'
      '&addressdetails=1',
    );

    final response = await http.get(
      uri,
      headers: {'User-Agent': 'SheShield-App/1.0'},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Nominatim returned ${response.statusCode}');
    }

    final results = jsonDecode(response.body) as List<dynamic>;
    final stations = <PoliceStation>[];

    for (final r in results) {
      final stationLat = double.tryParse(r['lat']?.toString() ?? '');
      final stationLng = double.tryParse(r['lon']?.toString() ?? '');
      if (stationLat == null || stationLng == null) continue;

      final name = r['display_name']?.toString().split(',').first ?? 'Police Station';
      final address = r['display_name']?.toString() ?? '';

      final distance = Geolocator.distanceBetween(
        lat, lng, stationLat, stationLng,
      );

      stations.add(PoliceStation(
        name: name,
        vicinity: address.length > 60 ? '${address.substring(0, 57)}...' : address,
        lat: stationLat,
        lng: stationLng,
        placeId: r['place_id']?.toString() ?? '',
        distanceMeters: distance,
      ));
    }

    stations.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return stations;
  }

  // -------------------------------------------------------------------------
  // Navigation URL helpers
  // -------------------------------------------------------------------------

  /// Generate a Google Maps navigation deep-link for a destination.
  static String getNavigationUrl(double destLat, double destLng) {
    return 'google.navigation:q=$destLat,$destLng&mode=d';
  }

  /// Generate a Google Maps directions web URL.
  static String getDirectionsUrl(double destLat, double destLng) {
    return 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving';
  }

  /// Generate a Google Maps web URL (fallback for devices without Google Maps).
  static String getMapsUrl(double destLat, double destLng) {
    return 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving';
  }
}

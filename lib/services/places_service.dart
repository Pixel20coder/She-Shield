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

/// Service for fetching nearby police stations via OpenStreetMap Overpass API.
/// No API key required.
class PlacesService {
  /// Fetch police stations near the given coordinates using Overpass API.
  static Future<List<PoliceStation>> fetchNearbyPoliceStations(
    double lat,
    double lng, {
    int radiusMeters = 50000,
  }) async {
    // Overpass QL query: find nodes and ways tagged amenity=police
    final query = '''
[out:json][timeout:25];
(
  node["amenity"="police"](around:$radiusMeters,$lat,$lng);
  way["amenity"="police"](around:$radiusMeters,$lat,$lng);
  relation["amenity"="police"](around:$radiusMeters,$lat,$lng);
);
out center body;
''';

    final uri = Uri.parse('https://overpass-api.de/api/interpreter');
    final response = await http.post(uri, body: {'data': query});

    if (response.statusCode != 200) {
      throw Exception('Overpass API request failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];

    final stations = <PoliceStation>[];

    for (final el in elements) {
      // Nodes have lat/lon directly; ways/relations use 'center'.
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
        lat, lng, stationLat, stationLng,
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

    // Sort by distance (closest first).
    stations.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return stations;
  }

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

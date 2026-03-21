import 'dart:async';
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

/// Service for fetching nearby police stations.
/// Races multiple APIs in parallel and returns the first successful response.
class PlacesService {
  /// Fetch police stations near the given coordinates.
  /// Fires ALL APIs simultaneously, merges results, deduplicates,
  /// and returns them sorted by distance (nearest first).
  static Future<List<PoliceStation>> fetchNearbyPoliceStations(
    double lat,
    double lng, {
    int radiusMeters = 100000,
  }) async {
    // Fire all sources in parallel and collect all results.
    final futures = await Future.wait<List<PoliceStation>>([
      _fetchFromOverpass(
        'https://overpass-api.de/api/interpreter', lat, lng, radiusMeters,
      ).catchError((_) => <PoliceStation>[]),
      _fetchFromOverpass(
        'https://overpass.kumi.systems/api/interpreter', lat, lng, radiusMeters,
      ).catchError((_) => <PoliceStation>[]),
      _fetchFromNominatim(lat, lng)
          .catchError((_) => <PoliceStation>[]),
    ]).timeout(
      const Duration(seconds: 12),
      onTimeout: () => [<PoliceStation>[], <PoliceStation>[], <PoliceStation>[]],
    );

    // Merge all results into one list.
    final allStations = <PoliceStation>[];
    for (final list in futures) {
      allStations.addAll(list);
    }

    // Deduplicate stations that are within 100m of each other.
    final unique = <PoliceStation>[];
    for (final station in allStations) {
      final isDuplicate = unique.any((existing) {
        final dist = Geolocator.distanceBetween(
          existing.lat, existing.lng, station.lat, station.lng,
        );
        return dist < 100; // within 100m = same station
      });
      if (!isDuplicate) {
        unique.add(station);
      }
    }

    // Sort by distance ascending (nearest first).
    unique.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return unique;
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
    final query = '[out:json][timeout:8];'
        'node["amenity"="police"](around:$radiusMeters,$lat,$lng);'
        'out body;';

    final uri = Uri.parse(endpoint);
    final response = await http
        .post(uri, body: {'data': query})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Overpass returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];

    final stations = <PoliceStation>[];
    for (final el in elements) {
      final stationLat = (el['lat'] as num?)?.toDouble();
      final stationLng = (el['lon'] as num?)?.toDouble();
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
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=police+station'
      '&format=json'
      '&limit=30'
      '&viewbox=${lng - 0.1},${lat + 0.1},${lng + 0.1},${lat - 0.1}'
      '&bounded=1'
      '&addressdetails=1',
    );

    final response = await http.get(
      uri,
      headers: {'User-Agent': 'SheShield-App/1.0'},
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Nominatim returned ${response.statusCode}');
    }

    final results = jsonDecode(response.body) as List<dynamic>;
    final stations = <PoliceStation>[];

    for (final r in results) {
      final stationLat = double.tryParse(r['lat']?.toString() ?? '');
      final stationLng = double.tryParse(r['lon']?.toString() ?? '');
      if (stationLat == null || stationLng == null) continue;

      final name =
          r['display_name']?.toString().split(',').first ?? 'Police Station';
      final address = r['display_name']?.toString() ?? '';

      final distance = Geolocator.distanceBetween(
        lat, lng, stationLat, stationLng,
      );

      stations.add(PoliceStation(
        name: name,
        vicinity:
            address.length > 60 ? '${address.substring(0, 57)}...' : address,
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

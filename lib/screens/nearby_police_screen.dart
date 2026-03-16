import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';

class NearbyPoliceScreen extends StatefulWidget {
  const NearbyPoliceScreen({super.key});

  @override
  State<NearbyPoliceScreen> createState() => _NearbyPoliceScreenState();
}

class _NearbyPoliceScreenState extends State<NearbyPoliceScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};

  double _lat = 28.6139;
  double _lng = 77.2090;
  bool _loading = true;
  String? _error;
  List<PoliceStation> _stations = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      // 1. Get current location.
      final pos = await LocationService.getCurrentLocation();
      _lat = pos.latitude;
      _lng = pos.longitude;

      // 2. Move camera to actual user location.
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13),
      );

      // 3. Fetch nearby stations.
      await _fetchStations();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchStations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint('Fetching police stations near $_lat, $_lng ...');
      final stations =
          await PlacesService.fetchNearbyPoliceStations(_lat, _lng);
      debugPrint('Found ${stations.length} police stations');
      if (mounted) {
        setState(() {
          _stations = stations;
          _loading = false;
          _buildMarkers();
        });
      }
    } catch (e) {
      debugPrint('Error fetching police stations: $e');
      if (mounted) {
        setState(() {
          _error = 'Unable to load police stations. Check your internet connection and try again.';
          _loading = false;
        });
      }
    }
  }

  void _buildMarkers() {
    _markers.clear();

    // User location marker.
    _markers.add(
      Marker(
        markerId: const MarkerId('user_location'),
        position: LatLng(_lat, _lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Your Location'),
      ),
    );

    // Police station markers.
    for (final station in _stations) {
      _markers.add(
        Marker(
          markerId: MarkerId(station.placeId),
          position: LatLng(station.lat, station.lng),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: station.name,
            snippet: '${station.distanceText} · Tap to navigate',
            onTap: () => _openNavigation(station),
          ),
        ),
      );
    }
  }

  Future<void> _openNavigation(PoliceStation station) async {
    // Try Google Maps navigation deep-link first.
    final navUri = Uri.parse(PlacesService.getNavigationUrl(
      station.lat,
      station.lng,
    ));

    if (await canLaunchUrl(navUri)) {
      await launchUrl(navUri);
    } else {
      // Fallback to web URL.
      final webUri = Uri.parse(PlacesService.getMapsUrl(
        station.lat,
        station.lng,
      ));
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Police Stations'),
        leading: IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: const Icon(Icons.arrow_back, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_lat, _lng),
                      zoom: 13,
                    ),
                    markers: _markers,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      // Re-center after map is ready if location already fetched
                      if (_lat != 28.6139 || _lng != 77.2090) {
                        controller.animateCamera(
                          CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 13),
                        );
                      }
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    mapType: MapType.normal,
                  ),
                  if (_loading)
                    Container(
                      color: const Color(0xCC0A0A0F),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: Color(0xFFE53935),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Finding nearby police stations…',
                              style: TextStyle(
                                color: Color(0xFF8A8A9A),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null)
                    Container(
                      color: const Color(0xCC0A0A0F),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('⚠️',
                                style: TextStyle(fontSize: 36)),
                            const SizedBox(height: 12),
                            const Text(
                              'Could not load stations',
                              style: TextStyle(
                                color: Color(0xFFF0F0F5),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchStations,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE53935),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Station list
          Expanded(
            flex: 3,
            child: _stations.isEmpty && !_loading
                ? const Center(
                    child: Text(
                      'No nearby police stations found',
                      style: TextStyle(
                        color: Color(0xFF5A5A6E),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _stations.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _buildStationCard(_stations[i]),
                  ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStationCard(PoliceStation station) {
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Animate camera to station.
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(station.lat, station.lng),
              15,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0x1F42A5F5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('🚔', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF0F0F5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          station.vicinity.isNotEmpty
                              ? station.vicinity
                              : 'Police Station',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8A8A9A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Distance badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x2600E676),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      station.distanceText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00E676),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Get Directions button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openNavigation(station),
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Get Directions'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

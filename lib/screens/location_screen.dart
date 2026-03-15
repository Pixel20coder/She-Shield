import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/location_service.dart';

class LocationScreen extends StatefulWidget {
  final double lat;
  final double lng;

  const LocationScreen({super.key, required this.lat, required this.lng});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  late double _lat;
  late double _lng;
  GoogleMapController? _mapController;
  StreamSubscription? _locationSub;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _lat = widget.lat;
    _lng = widget.lng;
    _updateMarker();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _updateMarker() {
    _markers.clear();
    _markers.add(
      Marker(
        markerId: const MarkerId('user_location'),
        position: LatLng(_lat, _lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Your Location'),
      ),
    );
  }

  void _startLocationUpdates() {
    _locationSub = LocationService.getLocationStream().listen(
      (pos) {
        if (mounted) {
          setState(() {
            _lat = pos.latitude;
            _lng = pos.longitude;
            _updateMarker();
          });
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(_lat, _lng)),
          );
        }
      },
      onError: (_) {},
    );
  }

  void _shareLocation() {
    final url = 'https://maps.google.com/?q=$_lat,$_lng';
    final text = '📍 She Shield – My Live Location\n'
        'Lat: ${_lat.toStringAsFixed(4)}°, Lng: ${_lng.toStringAsFixed(4)}°\n'
        '$url';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Share Location via',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF0F0F5),
                ),
              ),
              const SizedBox(height: 20),
              // WhatsApp
              _ShareOption(
                icon: '💬',
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () async {
                  Navigator.pop(ctx);
                  final waUrl = 'https://wa.me/?text=${Uri.encodeComponent(text)}';
                  try {
                    await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
                  } catch (_) {
                    if (mounted) _showFallback(text);
                  }
                },
              ),
              const SizedBox(height: 10),
              // SMS
              _ShareOption(
                icon: '✉️',
                label: 'Text Message (SMS)',
                color: const Color(0xFF42A5F5),
                onTap: () async {
                  Navigator.pop(ctx);
                  final smsUrl = 'sms:?body=${Uri.encodeComponent(text)}';
                  try {
                    await launchUrl(Uri.parse(smsUrl));
                  } catch (_) {
                    if (mounted) _showFallback(text);
                  }
                },
              ),
              const SizedBox(height: 10),
              // Copy
              _ShareOption(
                icon: '📋',
                label: 'Copy to Clipboard',
                color: const Color(0xFF8A8A9A),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Clipboard.setData(ClipboardData(text: text));
                  if (mounted) {
                    _showConfirmDialog(
                      '📋 Copied!',
                      'Location link copied to clipboard. Paste it in any app.',
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFallback(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showConfirmDialog(
        '📋 Copied Instead',
        'Could not open the app. Location link has been copied to clipboard.',
      );
    }
  }

  void _showConfirmDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFFF0F0F5),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF8A8A9A), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location'),
        leading: IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: const Icon(Icons.arrow_back, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Map
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 360,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            clipBehavior: Clip.antiAlias,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(_lat, _lng),
                zoom: 15,
              ),
              markers: _markers,
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              compassEnabled: false,
              mapType: MapType.normal,
            ),
          ),

          // Coordinates
          Container(
            margin: const EdgeInsets.all(16).copyWith(left: 20, right: 20),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LATITUDE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5A5A6E),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_lat.toStringAsFixed(4)}°',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF0F0F5),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LONGITUDE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5A5A6E),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_lng.toStringAsFixed(4)}°',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF0F0F5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Share Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _shareLocation,
                icon: const Text('📤', style: TextStyle(fontSize: 18)),
                label: const Text('Share Live Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF42A5F5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF0F0F5),
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

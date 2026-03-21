import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class PastEmergenciesScreen extends StatefulWidget {
  const PastEmergenciesScreen({super.key});

  @override
  State<PastEmergenciesScreen> createState() => _PastEmergenciesScreenState();
}

class _PastEmergenciesScreenState extends State<PastEmergenciesScreen> {
  List<_EmergencyItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEmergencies();
  }

  Future<void> _loadEmergencies() async {
    setState(() => _loading = true);

    final List<_EmergencyItem> items = [];

    // 1. Load alerts from Firestore
    try {
      final alertsSnap = await FirebaseFirestore.instance
          .collection('alerts')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      for (final doc in alertsSnap.docs) {
        final data = doc.data();
        final ts = data['timestamp'] as Timestamp?;
        items.add(_EmergencyItem(
          id: doc.id,
          type: 'alert',
          title: data['notificationTitle'] ?? '🚨 Emergency Alert',
          subtitle: data['mapsLink'] ?? 'Location shared',
          status: data['status'] ?? 'unknown',
          latitude: (data['latitude'] as num?)?.toDouble(),
          longitude: (data['longitude'] as num?)?.toDouble(),
          dateTime: ts?.toDate(),
          videoUrl: null,
          videoName: null,
        ));
      }
    } catch (e) {
      debugPrint('PastEmergencies: Failed to load alerts — $e');
    }

    // 2. Load video recordings from Firebase Storage
    try {
      final ref = FirebaseStorage.instance.ref('sos_recordings');
      final result = await ref.listAll();

      for (final item in result.items) {
        try {
          final meta = await item.getMetadata();
          final url = await item.getDownloadURL();
          items.add(_EmergencyItem(
            id: item.name,
            type: 'video',
            title: 'SOS Recording',
            subtitle: _formatSize(meta.size ?? 0),
            status: 'recorded',
            dateTime: meta.timeCreated,
            videoUrl: url,
            videoName: item.name,
          ));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('PastEmergencies: Failed to load videos — $e');
    }

    // Sort by newest first
    items.sort((a, b) {
      if (a.dateTime == null && b.dateTime == null) return 0;
      if (a.dateTime == null) return 1;
      if (b.dateTime == null) return -1;
      return b.dateTime!.compareTo(a.dateTime!);
    });

    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  void _openMap(double lat, double lng) async {
    final url = 'https://maps.google.com/?q=$lat,$lng';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) _showPopup('📋 Link Copied', 'Map link copied to clipboard.');
    }
  }

  void _openVideo(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) _showPopup('📋 Link Copied', 'Video link copied to clipboard.');
    }
  }

  Future<void> _deleteItem(_EmergencyItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🗑️ Delete Record?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: Text(
          item.type == 'video'
              ? 'This recording will be permanently deleted.'
              : 'This alert record will be permanently deleted.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (item.type == 'video' && item.videoName != null) {
        await FirebaseStorage.instance
            .ref('sos_recordings/${item.videoName}')
            .delete();
      } else if (item.type == 'alert') {
        await FirebaseFirestore.instance
            .collection('alerts')
            .doc(item.id)
            .delete();
      }
      setState(() => _items.remove(item));
      if (mounted) _showPopup('✅ Deleted', 'Record has been removed.');
    } catch (_) {
      if (mounted) _showPopup('⚠️ Error', 'Could not delete record.');
    }
  }

  void _showPopup(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Unknown date';
    final d = dt.toLocal();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final amPm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hour:${d.minute.toString().padLeft(2, '0')} $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Past Emergencies'),
        leading: IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.08)),
            ),
            child: const Icon(Icons.arrow_back, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE53935)))
          : RefreshIndicator(
              onRefresh: _loadEmergencies,
              color: const Color(0xFFE53935),
              child: _items.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('📋',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  'No past emergencies',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? const Color(0xFF5A5A6E)
                                        : const Color(0xFF8A8A9A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'SOS alerts and recordings will appear here',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? const Color(0xFF5A5A6E)
                                        : const Color(0xFF8A8A9A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _buildEmergencyCard(_items[i], isDark),
                    ),
            ),
    );
  }

  Widget _buildEmergencyCard(_EmergencyItem item, bool isDark) {
    final isAlert = item.type == 'alert';
    final isActive = item.status == 'active';
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? const Color(0xFFE53935).withValues(alpha: 0.3)
              : border,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isAlert
                  ? const Color(0xFFE53935).withValues(alpha: 0.12)
                  : const Color(0xFF42A5F5).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                isAlert ? Icons.warning_amber_rounded : Icons.videocam_rounded,
                color: isAlert
                    ? const Color(0xFFE53935)
                    : const Color(0xFF42A5F5),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isAlert ? 'Emergency Alert' : 'SOS Recording',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFFF0F0F5)
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFE53935).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('ACTIVE',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE53935),
                              letterSpacing: 0.5,
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(item.dateTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF8A8A9A)
                        : const Color(0xFF5A5A6E),
                  ),
                ),
                if (!isAlert)
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF5A5A6E)
                          : const Color(0xFF8A8A9A),
                    ),
                  ),
              ],
            ),
          ),
          // Action buttons
          if (isAlert && item.latitude != null && item.longitude != null)
            GestureDetector(
              onTap: () => _openMap(item.latitude!, item.longitude!),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF42A5F5).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.map_outlined,
                      color: Color(0xFF42A5F5), size: 18),
                ),
              ),
            ),
          if (!isAlert && item.videoUrl != null)
            GestureDetector(
              onTap: () => _openVideo(item.videoUrl!),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF42A5F5).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      color: Color(0xFF42A5F5), size: 20),
                ),
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _deleteItem(item),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(Icons.delete_outline,
                    color: isDark
                        ? const Color(0xFF5A5A6E)
                        : const Color(0xFF8A8A9A),
                    size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyItem {
  final String id;
  final String type; // 'alert' or 'video'
  final String title;
  final String subtitle;
  final String status;
  final double? latitude;
  final double? longitude;
  final DateTime? dateTime;
  final String? videoUrl;
  final String? videoName;

  _EmergencyItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.status,
    this.latitude,
    this.longitude,
    required this.dateTime,
    this.videoUrl,
    this.videoName,
  });
}

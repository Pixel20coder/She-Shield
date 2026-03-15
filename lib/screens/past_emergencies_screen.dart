import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class PastEmergenciesScreen extends StatefulWidget {
  const PastEmergenciesScreen({super.key});

  @override
  State<PastEmergenciesScreen> createState() => _PastEmergenciesScreenState();
}

class _PastEmergenciesScreenState extends State<PastEmergenciesScreen> {
  List<_VideoItem> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() => _loading = true);

    try {
      final ref = FirebaseStorage.instance.ref('sos_recordings');
      final result = await ref.listAll();

      final List<_VideoItem> items = [];
      for (final item in result.items) {
        try {
          final meta = await item.getMetadata();
          final url = await item.getDownloadURL();
          items.add(_VideoItem(
            name: item.name,
            url: url,
            timeCreated: meta.timeCreated,
            sizeBytes: meta.size ?? 0,
          ));
        } catch (_) {}
      }

      // Sort by newest first
      items.sort((a, b) {
        if (a.timeCreated == null || b.timeCreated == null) return 0;
        return b.timeCreated!.compareTo(a.timeCreated!);
      });

      if (mounted) {
        setState(() {
          _videos = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showPopup('⚠️ Error', 'Could not load recordings. Please check your internet connection.');
      }
    }
  }

  void _openVideo(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        _showPopup('📋 Link Copied', 'Video link copied to clipboard.');
      }
    }
  }

  Future<void> _deleteVideo(_VideoItem video) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '🗑️ Delete Recording?',
          style: TextStyle(color: Color(0xFFF0F0F5), fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: const Text(
          'This recording will be permanently deleted from the cloud.',
          style: TextStyle(color: Color(0xFF8A8A9A), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A8A9A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseStorage.instance.ref('sos_recordings/${video.name}').delete();
      setState(() => _videos.remove(video));
      if (mounted) _showPopup('✅ Deleted', 'Recording has been permanently removed.');
    } catch (_) {
      if (mounted) _showPopup('⚠️ Error', 'Could not delete recording.');
    }
  }

  void _showPopup(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(color: Color(0xFFF0F0F5), fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF8A8A9A), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
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
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final amPm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hour:${d.minute.toString().padLeft(2, '0')} $amPm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Past Emergencies'),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE53935)))
          : RefreshIndicator(
              onRefresh: _loadVideos,
              color: const Color(0xFFE53935),
              backgroundColor: const Color(0xFF14141F),
              child: _videos.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('📹', style: TextStyle(fontSize: 48)),
                                SizedBox(height: 12),
                                Text(
                                  'No emergency recordings yet',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF5A5A6E),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Recordings from the bracelet will appear here',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF5A5A6E)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      itemCount: _videos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildVideoCard(_videos[i]),
                    ),
            ),
    );
  }

  Widget _buildVideoCard(_VideoItem video) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Video icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.videocam_rounded, color: Color(0xFFE53935), size: 24),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SOS Recording',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF0F0F5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(video.timeCreated),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A9A)),
                ),
                Text(
                  _formatSize(video.sizeBytes),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF5A5A6E)),
                ),
              ],
            ),
          ),
          // Play button
          GestureDetector(
            onTap: () => _openVideo(video.url),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF42A5F5).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.play_arrow_rounded, color: Color(0xFF42A5F5), size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Delete button
          GestureDetector(
            onTap: () => _deleteVideo(video),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.delete_outline, color: Color(0xFF5A5A6E), size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoItem {
  final String name;
  final String url;
  final DateTime? timeCreated;
  final int sizeBytes;

  _VideoItem({
    required this.name,
    required this.url,
    required this.timeCreated,
    required this.sizeBytes,
  });
}

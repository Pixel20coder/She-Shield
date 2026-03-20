import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/alert_service.dart';
import '../services/voice_trigger_service.dart';
import '../services/sms_service.dart';
import '../services/video_recording_service.dart';
import 'location_screen.dart';
import 'contacts_screen.dart';
import 'nearby_police_screen.dart';
import '../services/bracelet_service.dart';
import 'bluetooth_screen.dart';
import 'past_emergencies_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _braceletConnected = true;
  double _lat = 28.6139;
  double _lng = 77.2090;
  bool _sosActive = false;
  bool _holding = false;
  late AnimationController _pulseController;
  late AnimationController _sosFlashController;
  late AnimationController _holdController;
  late Animation<double> _pulseAnimation;
  VoiceTriggerService? _voiceService;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _sosFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 3-second hold completed – trigger SOS
        setState(() => _holding = false);
        _triggerSOS();
      }
    });

    _fetchLocation();
    _initVoiceListener();
    _checkFirstLogin();

    // Listen for bracelet commands globally via singleton
    BraceletService.instance.onCommand = (cmd) {
      if (!mounted || _sosActive) return;
      _triggerSOS();
    };
  }

  /// After first sign-in, prompt user to pair the bracelet.
  Future<void> _checkFirstLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = 'paired_$uid';
    if (prefs.getBool(key) == true) return; // already prompted

    // Give UI time to render before showing the dialog
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final shouldPair = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '⌚ Pair Your Device',
          style: TextStyle(color: Color(0xFFF0F0F5), fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: const Text(
          'Welcome to SheShield! Connect your smart safety device via Bluetooth to get started.',
          style: TextStyle(color: Color(0xFF8A8A9A), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later', style: TextStyle(color: Color(0xFF8A8A9A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pair Now', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    await prefs.setBool(key, true); // don't show again

    if (shouldPair == true && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const BluetoothScreen()));
    }
  }

  Future<void> _initVoiceListener() async {
    _voiceService = VoiceTriggerService(onSosDetected: () {
      if (mounted && !_sosActive) _triggerSOS();
    });
    final available = await _voiceService!.initialize();
    if (available) {
      _voiceService!.startListening();
    }
  }

  @override
  void dispose() {
    _voiceService?.dispose();
    _pulseController.dispose();
    _sosFlashController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      final pos = await LocationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
      }
    } catch (_) {
      // Use defaults
    }
  }

  void _triggerSOS() {
    HapticFeedback.heavyImpact();
    setState(() => _sosActive = true);
    _sosFlashController.repeat(reverse: true);

    // Send push notification and save alert to Firestore.
    NotificationService.sendSOSAlert(lat: _lat, lng: _lng);

    // Broadcast emergency alert with location + contacts to Firestore.
    AlertService.broadcastAlert(lat: _lat, lng: _lng);

    // Send SOS SMS to all saved emergency contacts with location.
    SmsService.sendSOSToAllContacts(lat: _lat, lng: _lng);

    // Start 30-second video recording and upload to Firebase Storage.
    VideoRecordingService.startSOSRecording();

    // Start live location tracking (writes to Firestore every 5 s).
    LocationService.startSOS('user_placeholder');

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFFE53935).withValues(alpha: 0.12),
      builder: (ctx) => _SOSAlertDialog(
        onCancel: () {
          // Stop live location tracking.
          LocationService.stopSOS();
          // Stop video recording and upload what was captured.
          VideoRecordingService.stopAndUpload();
          setState(() => _sosActive = false);
          _sosFlashController.stop();
          _sosFlashController.reset();
          Navigator.of(ctx).pop();
          _showSnackBar('⚪ SOS alert cancelled');
          // Resume voice listening for next emergency.
          _voiceService?.resetAndRestart();
        },
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildTopBar(),
              _buildSOSSection(),
              _buildInfoCards(),
              const SizedBox(height: 16),
              _buildNavButtons(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFC62828)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('🛡️', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    letterSpacing: -0.3,
                  ),
                  children: [
                    TextSpan(
                      text: 'She',
                      style: TextStyle(color: Color(0xFFF0F0F5)),
                    ),
                    TextSpan(
                      text: 'Shield',
                      style: TextStyle(color: Color(0xFFE53935)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => _braceletConnected = !_braceletConnected);
                  HapticFeedback.lightImpact();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _braceletConnected
                        ? const Color(0x2600E676)
                        : const Color(0x26FF9800),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusDot(connected: _braceletConnected),
                      const SizedBox(width: 8),
                      Text(
                        _braceletConnected ? 'CONNECTED' : 'DISCONNECTED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: _braceletConnected
                              ? const Color(0xFF00E676)
                              : const Color(0xFFFF9800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: const Center(
                    child: Icon(Icons.person_outline, color: Color(0xFF8A8A9A), size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSOSSection() {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Pulse rings
              for (int i = 0; i < 3; i++)
                Transform.scale(
                  scale: _pulseAnimation.value + (i * 0.04),
                  child: Container(
                    width: 200 + (i * 34.0),
                    height: 200 + (i * 34.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFE53935)
                            .withValues(alpha: 0.15 - (i * 0.04)),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              // SOS Button – requires 3-second hold
              GestureDetector(
                onLongPressStart: (_) {
                  if (_sosActive) return;
                  HapticFeedback.mediumImpact();
                  setState(() => _holding = true);
                  _holdController.forward(from: 0.0);
                },
                onLongPressEnd: (_) {
                  if (_holdController.isAnimating) {
                    _holdController.reset();
                    setState(() => _holding = false);
                  }
                },
                child: Transform.scale(
                  scale: _sosActive ? 1.0 : _pulseAnimation.value * 0.97,
                  child: SizedBox(
                    width: 184,
                    height: 184,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Circular progress ring (visible while holding)
                        if (_holding)
                          AnimatedBuilder(
                            animation: _holdController,
                            builder: (context, _) {
                              return SizedBox(
                                width: 184,
                                height: 184,
                                child: CircularProgressIndicator(
                                  value: _holdController.value,
                                  strokeWidth: 5,
                                  color: Colors.white,
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                ),
                              );
                            },
                          ),
                        // Main button
                        Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.3, -0.3),
                              colors: _holding
                                  ? [const Color(0xFFFF8A80), const Color(0xFFFF5252), const Color(0xFFE53935)]
                                  : [const Color(0xFFFF5252), const Color(0xFFE53935), const Color(0xFFC62828)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE53935).withValues(alpha: _holding ? 0.55 : 0.35),
                                blurRadius: _holding ? 80 : 60,
                              ),
                              BoxShadow(
                                color: const Color(0xFFE53935).withValues(alpha: 0.15),
                                blurRadius: 120,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🚨', style: TextStyle(fontSize: 28)),
                              const SizedBox(height: 2),
                              const Text(
                                'SOS',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _holding ? 'KEEP HOLDING…' : 'HOLD FOR HELP',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _InfoCard(
            icon: '📍',
            iconBgColor: const Color(0x1F42A5F5),
            label: 'CURRENT LOCATION',
            value: '${_lat.toStringAsFixed(4)}°N, ${_lng.toStringAsFixed(4)}°E',
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF5A5A6E), size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => LocationScreen(lat: _lat, lng: _lng)),
            ),
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: '⌚',
            iconBgColor: Color(0x2600E676),
            label: 'BRACELET BATTERY',
            value: '87% — Charging',
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _NavButton(
                  icon: '🗺️',
                  iconBgColor: const Color(0x1F42A5F5),
                  label: 'Live\nLocation',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LocationScreen(lat: _lat, lng: _lng)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavButton(
                  icon: '🚔',
                  iconBgColor: const Color(0x1F42A5F5),
                  label: 'Police\nStations',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NearbyPoliceScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NavButton(
                  icon: '👥',
                  iconBgColor: const Color(0x1FE53935),
                  label: 'Emergency\nContacts',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactsScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavButton(
                  icon: '📡',
                  iconBgColor: const Color(0x1F7C4DFF),
                  label: 'Bluetooth\nPairing',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BluetoothScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NavButton(
                  icon: '📹',
                  iconBgColor: const Color(0x1FFF7043),
                  label: 'Past\nEmergencies',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PastEmergenciesScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================
// Sub-widgets
// ============================================

class _StatusDot extends StatefulWidget {
  final bool connected;
  const _StatusDot({required this.connected});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? const Color(0xFF00E676) : const Color(0xFFFF9800);
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.connected)
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                return Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 1.0 - _controller.value),
                      width: 1.5,
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String icon;
  final Color iconBgColor;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _InfoCard({
    required this.icon,
    required this.iconBgColor,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5A5A6E),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF0F0F5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String icon;
  final Color iconBgColor;
  final String label;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.iconBgColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF0F0F5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// SOS Alert Dialog
// ============================================

class _SOSAlertDialog extends StatelessWidget {
  final VoidCallback onCancel;
  const _SOSAlertDialog({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF14141F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE53935), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚨', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'SOS ALERT SENT',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE53935),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Emergency alert with your GPS location has been sent to all contacts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8A8A9A),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Cancel Alert',
                style: TextStyle(
                  color: Color(0xFFF0F0F5),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

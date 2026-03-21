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
import '../services/bluetooth_service.dart';
import 'location_screen.dart';
import 'contacts_screen.dart';
import 'nearby_police_screen.dart';
import 'bluetooth_screen.dart';
import 'past_emergencies_screen.dart';
import 'profile_screen.dart';
import 'sos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  double _lat = 28.6139;
  double _lng = 77.2090;
  bool _sosActive = false;
  bool _holding = false;
  late AnimationController _pulseController;
  late AnimationController _holdController;
  late Animation<double> _pulseAnimation;
  VoiceTriggerService? _voiceService;

  final BluetoothService _bt = BluetoothService.instance;

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

    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _holding = false);
        _triggerSOS();
      }
    });

    // Listen to Bluetooth state changes
    _bt.addListener(_onBtChanged);

    // Listen for bracelet commands globally
    _bt.onCommand = (cmd) {
      if (!mounted || _sosActive) return;
      _triggerSOS();
    };

    _fetchLocation();
    _initVoiceListener();
    _checkFirstLogin();
  }

  void _onBtChanged() {
    if (mounted) setState(() {});
  }

  /// After first sign-in, prompt user to pair the bracelet.
  Future<void> _checkFirstLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = 'paired_$uid';
    if (prefs.getBool(key) == true) return;

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final shouldPair = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '⌚ Pair Your Device',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: const Text(
          'Welcome to SheShield! Connect your smart safety device via Bluetooth to get started.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Later',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pair Now',
                style: TextStyle(
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    await prefs.setBool(key, true);

    if (shouldPair == true && mounted) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BluetoothScreen()));
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
    _holdController.dispose();
    _bt.removeListener(_onBtChanged);
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
    } catch (_) {}
  }

  void _triggerSOS() {
    if (_sosActive) return;
    HapticFeedback.heavyImpact();
    setState(() => _sosActive = true);

    // Fire all SOS services
    NotificationService.sendSOSAlert(lat: _lat, lng: _lng);
    AlertService.broadcastAlert(lat: _lat, lng: _lng);
    SmsService.sendSOSToAllContacts(lat: _lat, lng: _lng);
    VideoRecordingService.startSOSRecording();
    LocationService.startSOS('user_placeholder');

    // Activate buzzer on ESP32
    _bt.activateBuzzer();

    // Navigate to full-screen SOS
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => SOSScreen(
          onCancel: () {
            LocationService.stopSOS();
            VideoRecordingService.stopAndUpload();
            _bt.stopBuzzer();
            setState(() => _sosActive = false);
            Navigator.of(context).pop();
            _showSnackBar('⚪ SOS alert cancelled');
            _voiceService?.resetAndRestart();
          },
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleConnectTap() async {
    if (_bt.isConnected) {
      _bt.disconnect();
      _showSnackBar('🔴 Disconnected from ${_bt.deviceName}');
    } else if (_bt.deviceAddress.isNotEmpty) {
      // Has a saved device — try reconnecting
      _showSnackBar('🔗 Reconnecting to ${_bt.deviceName}…');
      final ok = await _bt.manualReconnect();
      if (ok && mounted) {
        _showSnackBar('✅ Connected to ${_bt.deviceName}');
      } else if (mounted) {
        _showSnackBar('❌ Failed to connect. Open Bluetooth Pairing.');
      }
    } else {
      // No saved device — go to pairing
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BluetoothScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildTopBar(isDark),
              const SizedBox(height: 4),
              _buildStatusCard(isDark),
              const SizedBox(height: 8),
              _buildSOSSection(),
              const SizedBox(height: 4),
              _buildSubtitle(),
              const SizedBox(height: 16),
              _buildInfoCards(isDark),
              const SizedBox(height: 16),
              _buildNavButtons(isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  TOP BAR
  // ════════════════════════════════════════════════════════

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo + title
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
                        letterSpacing: -0.5,
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
                  Text(
                    'Safety',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF5A5A6E)
                          : const Color(0xFF8A8A9A),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Profile button
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A1A2E)
                    : Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.08)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Icon(Icons.person_outline,
                  color: isDark
                      ? const Color(0xFF8A8A9A)
                      : const Color(0xFF5A5A6E),
                  size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  STATUS CARD (real Bluetooth state)
  // ════════════════════════════════════════════════════════

  Widget _buildStatusCard(bool isDark) {
    final connected = _bt.isConnected;
    final connecting = _bt.isConnecting;

    final Color statusColor = connecting
        ? const Color(0xFFFF9800)
        : connected
            ? const Color(0xFF00E676)
            : const Color(0xFFE53935);

    final String statusText = connecting
        ? 'CONNECTING…'
        : connected
            ? 'CONNECTED'
            : 'DISCONNECTED';

    final String statusSubtext = connecting
        ? 'Establishing connection to ${_bt.deviceName}…'
        : connected
            ? '${_bt.deviceName} • SOS signals active'
            : _bt.deviceAddress.isNotEmpty
                ? 'Tap to reconnect to ${_bt.deviceName}'
                : 'No device paired. Tap to connect.';

    final Color cardBg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final Color borderColor = statusColor.withValues(alpha: 0.25);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _handleConnectTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Status dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: connecting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: statusColor,
                          ),
                        )
                      : _StatusDot(connected: connected),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                        if (connected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF00E676).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF00E676),
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusSubtext,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF8A8A9A)
                            : const Color(0xFF5A5A6E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Action icon
              Icon(
                connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: statusColor.withValues(alpha: 0.6),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  SOS BUTTON
  // ════════════════════════════════════════════════════════

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
              // SOS Button
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
                        // Hold progress ring
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
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.15),
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
                                  ? [
                                      const Color(0xFFFF8A80),
                                      const Color(0xFFFF5252),
                                      const Color(0xFFE53935)
                                    ]
                                  : [
                                      const Color(0xFFFF5252),
                                      const Color(0xFFE53935),
                                      const Color(0xFFC62828)
                                    ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE53935).withValues(
                                    alpha: _holding ? 0.55 : 0.35),
                                blurRadius: _holding ? 80 : 60,
                              ),
                              BoxShadow(
                                color: const Color(0xFFE53935)
                                    .withValues(alpha: 0.15),
                                blurRadius: 120,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🚨',
                                  style: TextStyle(fontSize: 28)),
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

  Widget _buildSubtitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        'Press and hold wearable button or shake device',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF5A5A6E)
              : const Color(0xFF8A8A9A),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  INFO CARDS
  // ════════════════════════════════════════════════════════

  Widget _buildInfoCards(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _InfoCard(
            isDark: isDark,
            icon: '📍',
            iconBgColor: const Color(0x1F42A5F5),
            label: 'CURRENT LOCATION',
            value:
                '${_lat.toStringAsFixed(4)}°N, ${_lng.toStringAsFixed(4)}°E',
            trailing: Icon(Icons.chevron_right,
                color:
                    isDark ? const Color(0xFF5A5A6E) : const Color(0xFF8A8A9A),
                size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LocationScreen(lat: _lat, lng: _lng)),
            ),
          ),
          const SizedBox(height: 12),
          _InfoCard(
            isDark: isDark,
            icon: '⌚',
            iconBgColor: const Color(0x2600E676),
            label: 'BRACELET STATUS',
            value: _bt.isConnected ? 'Active • SOS Ready' : 'Not Connected',
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  NAV BUTTONS
  // ════════════════════════════════════════════════════════

  Widget _buildNavButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _NavButton(
                  isDark: isDark,
                  icon: '🗺️',
                  iconBgColor: const Color(0x1F42A5F5),
                  label: 'Live\nLocation',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            LocationScreen(lat: _lat, lng: _lng)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavButton(
                  isDark: isDark,
                  icon: '🚔',
                  iconBgColor: const Color(0x1F42A5F5),
                  label: 'Police\nStations',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NearbyPoliceScreen()),
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
                  isDark: isDark,
                  icon: '👥',
                  iconBgColor: const Color(0x1FE53935),
                  label: 'Emergency\nContacts',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ContactsScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavButton(
                  isDark: isDark,
                  icon: '📡',
                  iconBgColor: const Color(0x1F7C4DFF),
                  label: 'Bluetooth\nPairing',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BluetoothScreen()),
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
                  isDark: isDark,
                  icon: '📹',
                  iconBgColor: const Color(0x1FFF7043),
                  label: 'Past\nEmergencies',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PastEmergenciesScreen()),
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

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
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
    final color =
        widget.connected ? const Color(0xFF00E676) : const Color(0xFFE53935);
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.connected)
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                return Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 1.0 - _controller.value),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final String icon;
  final Color iconBgColor;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _InfoCard({
    required this.isDark,
    required this.icon,
    required this.iconBgColor,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
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
                child: Center(
                    child: Text(icon,
                        style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF5A5A6E)
                            : const Color(0xFF8A8A9A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFFF0F0F5)
                            : const Color(0xFF1A1A2E),
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
  final bool isDark;
  final String icon;
  final Color iconBgColor;
  final String label;
  final VoidCallback onTap;

  const _NavButton({
    required this.isDark,
    required this.icon,
    required this.iconBgColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.08);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
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
                child: Center(
                    child: Text(icon,
                        style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFFF0F0F5)
                      : const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

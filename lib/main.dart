import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/sos_screen.dart';
import 'services/notification_service.dart';
import 'services/bluetooth_service.dart';
import 'services/location_service.dart';
import 'services/alert_service.dart';
import 'services/sms_service.dart';
import 'services/video_recording_service.dart';

/// Global theme mode notifier — toggled from ProfileScreen.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved theme preference
  try {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('dark_mode') ?? true;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {}

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Notification setup
  try {
    await NotificationService.initialize();
  } catch (_) {}

  // Auto-connect to last saved Bluetooth device
  try {
    await BluetoothService.instance.tryAutoConnect();
  } catch (_) {}

  // Register global SOS listener (fires from any screen)
  BluetoothService.instance.onCommand = (cmd) {
    if (cmd == BraceletCommand.sos || cmd == BraceletCommand.shake) {
      _triggerGlobalSOS();
    }
  };

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0A0F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SheShieldApp());
}

/// Trigger SOS from any screen by pushing a full-screen alert.
void _triggerGlobalSOS() {
  final nav = BluetoothService.navigatorKey.currentState;
  if (nav == null) return;

  // Prevent duplicate SOS screens
  // Fire all SOS services
  try { LocationService.getCurrentLocation().then((pos) {
    NotificationService.sendSOSAlert(lat: pos.latitude, lng: pos.longitude);
    AlertService.broadcastAlert(lat: pos.latitude, lng: pos.longitude);
    SmsService.sendSOSToAllContacts(lat: pos.latitude, lng: pos.longitude);
  }); } catch (_) {}

  try { VideoRecordingService.startSOSRecording(); } catch (_) {}
  try { LocationService.startSOS('user_placeholder'); } catch (_) {}
  try { BluetoothService.instance.activateBuzzer(); } catch (_) {}

  HapticFeedback.heavyImpact();

  nav.push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, __, ___) => SOSScreen(
        onCancel: () {
          try { LocationService.stopSOS(); } catch (_) {}
          try { VideoRecordingService.stopAndUpload(); } catch (_) {}
          try { BluetoothService.instance.stopBuzzer(); } catch (_) {}
          nav.pop();
        },
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    ),
  );
}

class SheShieldApp extends StatelessWidget {
  const SheShieldApp({super.key});

  // ──── DARK THEME ────
  static final _darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0A0F),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFE53935),
      secondary: Color(0xFFE53935),
      surface: Color(0xFF1A1A2E),
      onSurface: Color(0xFFF0F0F5),
    ),
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0A0F),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFFF0F0F5),
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: Color(0xFFF0F0F5)),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1A2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE53935)),
      ),
      labelStyle: const TextStyle(
          color: Color(0xFF8A8A9A), fontSize: 12, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Color(0xFF5A5A6E), fontSize: 15),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  // ──── LIGHT THEME ────
  static final _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F8),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFFE53935),
      secondary: Color(0xFFE53935),
      surface: Colors.white,
      onSurface: Color(0xFF1A1A2E),
    ),
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF5F5F8),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE53935)),
      ),
      labelStyle: const TextStyle(
          color: Color(0xFF5A5A6E), fontSize: 12, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Color(0xFF8A8A9A), fontSize: 15),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'She Shield',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          navigatorKey: BluetoothService.navigatorKey,
          home: const _SplashGate(),
        );
      },
    );
  }
}

/// Shows the animated splash for at least 2.5 s, then transitions
/// to HomeScreen or LoginScreen based on Firebase auth state.
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _minTimeDone = false;
  bool _authResolved = false;
  bool? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    // Minimum splash duration
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _minTimeDone = true);
    });
    // Listen to auth
    FirebaseAuth.instance.authStateChanges().first.then((user) {
      if (mounted) {
        setState(() {
          _authResolved = true;
          _isLoggedIn = user != null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_minTimeDone && _authResolved) {
      return _isLoggedIn == true ? const HomeScreen() : const LoginScreen();
    }
    return const _SplashScreen();
  }
}

// ══════════════════════════════════════════════════════════
//  ANIMATED SPLASH SCREEN (shown during Firebase init)
// ══════════════════════════════════════════════════════════

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _rotateCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    // Pulse: logo breathes
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Rotate: glow ring spins
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Fade: everything fades in
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo with rotating glow ring ──
              SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Rotating outer glow ring
                    AnimatedBuilder(
                      animation: _rotateCtrl,
                      builder: (_, __) => Transform.rotate(
                        angle: _rotateCtrl.value * 6.2832, // 2π
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                const Color(0xFFE53935).withValues(alpha: 0.0),
                                const Color(0xFFE53935).withValues(alpha: 0.6),
                                const Color(0xFFFF7043).withValues(alpha: 0.3),
                                const Color(0xFFE53935).withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Dark inner circle (mask)
                    Container(
                      width: 155,
                      height: 155,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0A0A0F),
                      ),
                    ),
                    // Pulsing logo
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) => Transform.scale(
                        scale: _pulseAnim.value,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(60),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE53935)
                                    .withValues(alpha: 0.25 * _pulseAnim.value),
                                blurRadius: 50,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(60),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              // ── App name ──
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 30,
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
              const SizedBox(height: 8),
              const Text(
                'SMART SAFETY SYSTEM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A5A6E),
                  letterSpacing: 3.0,
                ),
              ),
              const SizedBox(height: 48),
              // ── Shimmer loading bar ──
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 120,
                  height: 4,
                  child: AnimatedBuilder(
                    animation: _rotateCtrl,
                    builder: (_, __) {
                      return CustomPaint(
                        painter: _ShimmerBarPainter(_rotateCtrl.value),
                      );
                    },
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

/// Draws a small shimmer bar that slides across.
class _ShimmerBarPainter extends CustomPainter {
  final double progress;
  _ShimmerBarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // Track
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF1A1A2E),
    );

    // Shimmer
    final shimmerWidth = size.width * 0.4;
    final left = -shimmerWidth + (size.width + shimmerWidth) * progress;
    final shimmerRect = Rect.fromLTWH(left, 0, shimmerWidth, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shimmerRect, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x00E53935),
            Color(0xFFE53935),
            Color(0x00E53935),
          ],
        ).createShader(shimmerRect),
    );
  }

  @override
  bool shouldRepaint(_ShimmerBarPainter old) => old.progress != progress;
}

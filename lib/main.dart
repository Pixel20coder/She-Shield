import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before anything else.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase init failed – app can still launch with limited functionality.
  }

  // Request notification permissions and retrieve FCM token.
  // Wrapped in try-catch so a failure here doesn't prevent the app from
  // launching (which would cause a black screen).
  try {
    await NotificationService.initialize();
  } catch (_) {
    // Notification setup failed – the app can still function without it.
  }

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

class SheShieldApp extends StatelessWidget {
  const SheShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'She Shield',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
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
            color: Color(0xFF8A8A9A),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF5A5A6E),
            fontSize: 15,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen emergency SOS alert.
///
/// Shows a flashing red overlay, large alert text, continuous
/// vibration pattern, and a cancel button. Push this screen
/// when "BUTTON SOS" or "MOTION SOS" is received.
class SOSScreen extends StatefulWidget {
  final VoidCallback onCancel;
  const SOSScreen({super.key, required this.onCancel});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen>
    with TickerProviderStateMixin {
  late AnimationController _flashController;
  late AnimationController _pulseController;
  late AnimationController _textFadeController;
  Timer? _vibrationTimer;
  int _dotCount = 0;
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();

    // Flash animation — alternates red shades
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Pulse scale for the icon
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Fade-in for text
    _textFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    // Continuous vibration
    _startVibration();

    // Animated dots for "Sending help signal..."
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _dotCount = (_dotCount + 1) % 4);
    });
  }

  void _startVibration() {
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _flashController.dispose();
    _pulseController.dispose();
    _textFadeController.dispose();
    _vibrationTimer?.cancel();
    _dotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // prevent back button
      child: AnimatedBuilder(
        animation: _flashController,
        builder: (context, child) {
          final flashValue = _flashController.value;
          return Scaffold(
            backgroundColor: Color.lerp(
              const Color(0xFFB71C1C),
              const Color(0xFFE53935),
              flashValue,
            ),
            body: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  // ── Pulsing alert icon ──
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      final scale =
                          1.0 + (_pulseController.value * 0.15);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.15),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Colors.white.withValues(alpha: 0.1 * flashValue),
                                blurRadius: 60,
                                spreadRadius: 20,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              '🚨',
                              style: TextStyle(fontSize: 56),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  // ── Title ──
                  FadeTransition(
                    opacity: _textFadeController,
                    child: const Text(
                      'EMERGENCY\nTRIGGERED',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Subtitle with animated dots ──
                  FadeTransition(
                    opacity: _textFadeController,
                    child: Text(
                      'Sending help signal${'.' * _dotCount}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _textFadeController,
                    child: Text(
                      'GPS location shared • Contacts alerted',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  // ── Info chips ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _infoChip(Icons.location_on, 'Location\nSent'),
                        _infoChip(Icons.message, 'SMS\nSent'),
                        _infoChip(Icons.videocam, 'Recording\nActive'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // ── Cancel button ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.close, size: 20),
                        label: const Text('Cancel Alert'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hold to cancel',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

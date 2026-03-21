import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Keywords that trigger the SOS alert when spoken.
const _sosKeywords = [
  'help',
  'help me',
  'emergency',
  'she shield',
  'sheshield',
  'police',
  'bachao',
  'bachaao',
  'bachaaao',
  'danger',
  'save me',
  'sos',
  'call police',
  'please help',
];

/// Service for continuous voice monitoring.
///
/// Listens for speech in the background while the app is open and invokes
/// [onSosDetected] when any keyword from [_sosKeywords] is recognised.
class VoiceTriggerService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final void Function() onSosDetected;

  bool _isInitialized = false;
  bool _sosFired = false;
  Timer? _restartTimer;
  Timer? _autoResetTimer;
  bool _disposed = false;

  VoiceTriggerService({required this.onSosDetected});

  /// Initialize the speech recogniser. Returns `true` if available.
  Future<bool> initialize() async {
    try {
      _isInitialized = await _speech.initialize(
        onStatus: _onStatus,
        onError: (error) {
          debugPrint('VoiceTrigger: Error — ${error.errorMsg}');
          _scheduleRestart();
        },
      );
      debugPrint('VoiceTrigger: Initialized = $_isInitialized');
    } catch (e) {
      debugPrint('VoiceTrigger: Init failed — $e');
      _isInitialized = false;
    }
    return _isInitialized;
  }

  /// Start continuous listening. Safe to call multiple times.
  void startListening() {
    if (!_isInitialized || _disposed) return;
    _sosFired = false;
    _stopSpeech();
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), _listen);
  }

  /// Stop listening and cancel any pending restart timers.
  void stopListening() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _stopSpeech();
  }

  /// Reset the SOS-fired flag and resume listening.
  void resetAndRestart() {
    _autoResetTimer?.cancel();
    _sosFired = false;
    _stopSpeech();
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), _listen);
  }

  /// Clean up resources.
  void dispose() {
    _disposed = true;
    _autoResetTimer?.cancel();
    stopListening();
    try { _speech.cancel(); } catch (_) {}
  }

  // ---------------------------------------------------------------------------

  void _stopSpeech() {
    try {
      if (_speech.isListening) {
        _speech.stop();
      }
    } catch (_) {}
  }

  void _listen() {
    if (_sosFired || !_isInitialized || _disposed) return;

    if (_speech.isListening) {
      _stopSpeech();
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(milliseconds: 500), _listen);
      return;
    }

    debugPrint('VoiceTrigger: Starting speech recognition…');

    try {
      _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;

          debugPrint('VoiceTrigger: Heard "$words" (final=${result.finalResult})');

          for (final keyword in _sosKeywords) {
            if (words.contains(keyword)) {
              debugPrint('VoiceTrigger: 🚨 Keyword matched: "$keyword"');
              _sosFired = true;
              stopListening();
              onSosDetected();
              // Auto-reset after 20s so voice can trigger again
              _autoResetTimer = Timer(const Duration(seconds: 20), () {
                if (!_disposed) resetAndRestart();
              });
              return;
            }
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
          partialResults: true,
          autoPunctuation: false,
        ),
      );
    } catch (e) {
      debugPrint('VoiceTrigger: Listen failed — $e');
      _scheduleRestart();
    }
  }

  void _onStatus(String status) {
    debugPrint('VoiceTrigger: Status → $status');
    if (status == 'done' || status == 'notListening') {
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (_sosFired || _disposed) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_sosFired && !_disposed) _listen();
    });
  }
}

import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Keywords that trigger the SOS alert when spoken.
const _sosKeywords = [
  'help',
  'emergency',
  'she shield',
  'sheshield',
  'police',
  'bachao',
  'bachaao',
  'bachaaao',
  'danger',
];

/// Service for continuous voice monitoring.
///
/// Listens for speech in the background while the app is open and invokes
/// [onSosDetected] when any keyword from [_sosKeywords] is recognised.
class VoiceTriggerService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final VoidCallback onSosDetected;

  bool _isInitialized = false;
  bool _sosFired = false;
  Timer? _restartTimer;
  Timer? _autoResetTimer;

  VoiceTriggerService({required this.onSosDetected});

  /// Initialize the speech recogniser. Returns `true` if available.
  Future<bool> initialize() async {
    _isInitialized = await _speech.initialize(
      onStatus: _onStatus,
      onError: (_) => _scheduleRestart(),
    );
    return _isInitialized;
  }

  /// Start continuous listening. Safe to call multiple times.
  void startListening() {
    if (!_isInitialized) return;
    _sosFired = false;
    _speech.stop();
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 300), _listen);
  }

  /// Stop listening and cancel any pending restart timers.
  void stopListening() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _speech.stop();
  }

  /// Reset the SOS-fired flag and resume listening.
  void resetAndRestart() {
    _autoResetTimer?.cancel();
    _sosFired = false;
    _speech.stop();
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 300), _listen);
  }

  /// Clean up resources.
  void dispose() {
    _autoResetTimer?.cancel();
    stopListening();
    _speech.cancel();
  }

  // ---------------------------------------------------------------------------

  void _listen() {
    if (_sosFired || !_isInitialized) return;

    if (_speech.isListening) {
      _speech.stop();
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(milliseconds: 300), _listen);
      return;
    }

    _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        for (final keyword in _sosKeywords) {
          if (words.contains(keyword)) {
            _sosFired = true;
            stopListening();
            onSosDetected();
            _autoResetTimer = Timer(const Duration(seconds: 20), () {
              resetAndRestart();
            });
            return;
          }
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 10),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        autoPunctuation: false,
      ),
    );
  }

  void _onStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (_sosFired) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_sosFired) _listen();
    });
  }
}

/// Typedef so we don't need to import Flutter in this file.
typedef VoidCallback = void Function();

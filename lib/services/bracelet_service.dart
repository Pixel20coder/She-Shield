import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

/// Commands from the ESP32 bracelet.
enum BraceletCommand { sos, shake, voice, camera }

typedef BraceletCommandCallback = void Function(BraceletCommand command);

/// **Global singleton** Bluetooth Classic service.
///
/// Connection persists across all screens. Only disconnects
/// when the user explicitly taps "Disconnect".
///
/// ESP32 sends:  "SOS\n", "SHAKE\n", "BUTTON SOS\n", "MOTION SOS\n"
/// App sends:    "BUZZER_ON\n", "LED_ON\n", etc.
class BraceletService extends ChangeNotifier {
  // ── Singleton ──
  BraceletService._();
  static final BraceletService instance = BraceletService._();

  BluetoothConnection? _connection;
  StreamSubscription? _inputSub;
  String _buffer = '';

  // ── Public state ──
  bool _isConnected = false;
  String _deviceName = '';
  String _deviceAddress = '';

  bool get isConnected => _isConnected;
  String get deviceName => _deviceName;
  String get deviceAddress => _deviceAddress;

  /// Global callback — fires from ANY screen when SOS received.
  BraceletCommandCallback? onCommand;

  /// Connect to a device via RFCOMM and start listening.
  Future<bool> connect(BluetoothDevice device) async {
    // Already connected to this device
    if (_isConnected && _deviceAddress == device.address) return true;

    // Disconnect previous if any
    if (_isConnected) disconnect();

    _deviceName = device.name ?? device.address;
    _deviceAddress = device.address;

    try {
      debugPrint('BraceletService: Connecting to $_deviceName…');
      _connection = await BluetoothConnection.toAddress(device.address);
      debugPrint('BraceletService: ✅ Connected to $_deviceName');

      _inputSub?.cancel();
      _inputSub = _connection!.input?.listen(
        _handleData,
        onDone: () {
          debugPrint('BraceletService: Connection closed by remote');
          _setDisconnected();
        },
        onError: (e) {
          debugPrint('BraceletService: Stream error — $e');
          _setDisconnected();
        },
      );

      _isConnected = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('BraceletService: Connection failed — $e');
      _setDisconnected();
      return false;
    }
  }

  /// Explicitly disconnect (user tapped "Disconnect").
  void disconnect() {
    debugPrint('BraceletService: Disconnecting…');
    _inputSub?.cancel();
    _inputSub = null;
    try { _connection?.finish(); } catch (_) {}
    _connection = null;
    _setDisconnected();
  }

  void _setDisconnected() {
    _isConnected = false;
    _buffer = '';
    notifyListeners();
  }

  /// Send a string command to ESP32.
  Future<void> send(String command) async {
    if (_connection == null || !_isConnected) return;
    try {
      _connection!.output.add(Uint8List.fromList(utf8.encode('$command\n')));
      await _connection!.output.allSent;
      debugPrint('BraceletService: Sent "$command"');
    } catch (e) {
      debugPrint('BraceletService: Write failed — $e');
    }
  }

  Future<void> activateBuzzer() => send('BUZZER_ON');
  Future<void> stopBuzzer() => send('BUZZER_OFF');
  Future<void> ledOn() => send('LED_ON');
  Future<void> ledOff() => send('LED_OFF');

  /// Parse incoming serial data line-by-line.
  void _handleData(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);

    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (line.isEmpty) continue;

      debugPrint('BraceletService: ◀ "$line"');

      BraceletCommand? cmd;
      final upper = line.toUpperCase();
      if (upper.contains('SOS')) {
        cmd = BraceletCommand.sos;
      } else if (upper.contains('SHAKE')) {
        cmd = BraceletCommand.shake;
      } else if (upper.contains('VOICE')) {
        cmd = BraceletCommand.voice;
      } else if (upper.contains('CAM')) {
        cmd = BraceletCommand.camera;
      }

      if (cmd != null) {
        debugPrint('BraceletService: 🚨 Command → $cmd');
        onCommand?.call(cmd);
      }
    }
  }

  /// For demo: fire a command without a real device.
  void simulateCommand(BraceletCommand command) {
    debugPrint('BraceletService: Simulated $command');
    onCommand?.call(command);
  }
}

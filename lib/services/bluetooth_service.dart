import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connection states exposed to the UI.
enum BtConnectionState { disconnected, connecting, connected }

/// Commands recognized from ESP32 serial data.
enum BraceletCommand { sos, shake, voice, camera }

typedef BraceletCommandCallback = void Function(BraceletCommand command);

/// **Global singleton** Bluetooth Classic service.
///
/// Features:
/// - Persistent connection across all screen navigations
/// - Auto-reconnect on connection drop (3 retries, 5 s interval)
/// - Saves last-connected device for auto-connect on app launch
/// - Exposes reactive [connectionNotifier] for UI binding
/// - Parses "BUTTON SOS", "MOTION SOS", "SHAKE" from serial stream
class BluetoothService extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────
  BluetoothService._();
  static final BluetoothService instance = BluetoothService._();

  // ── Navigator key for global SOS push ──────────────────────
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // ── Internal state ─────────────────────────────────────────
  BluetoothConnection? _connection;
  StreamSubscription? _inputSub;
  String _buffer = '';

  BtConnectionState _state = BtConnectionState.disconnected;
  String _deviceName = '';
  String _deviceAddress = '';

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectInterval = Duration(seconds: 5);

  bool _userDisconnected = false; // true when user explicitly disconnects

  // ── Public getters ─────────────────────────────────────────
  BtConnectionState get state => _state;
  bool get isConnected => _state == BtConnectionState.connected;
  bool get isConnecting => _state == BtConnectionState.connecting;
  String get deviceName => _deviceName;
  String get deviceAddress => _deviceAddress;

  /// Global callback — fires from ANY screen when a command is received.
  BraceletCommandCallback? onCommand;

  // ── Persistence keys ───────────────────────────────────────
  static const _kDeviceName = 'bt_last_device_name';
  static const _kDeviceAddress = 'bt_last_device_address';

  // ══════════════════════════════════════════════════════════
  //  AUTO-CONNECT ON APP LAUNCH
  // ══════════════════════════════════════════════════════════

  /// Call once from main(). Tries to reconnect to the last saved device.
  Future<void> tryAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_kDeviceAddress);
    final name = prefs.getString(_kDeviceName);
    if (address == null || address.isEmpty) return;

    _deviceName = name ?? address;
    _deviceAddress = address;

    debugPrint('BluetoothService: Auto-connecting to $_deviceName…');
    await _connectToAddress(address);
  }

  // ══════════════════════════════════════════════════════════
  //  CONNECT / DISCONNECT
  // ══════════════════════════════════════════════════════════

  /// Connect to a device via RFCOMM and start listening.
  Future<bool> connect(BluetoothDevice device) async {
    // Already connected to this device
    if (isConnected && _deviceAddress == device.address) return true;

    // Disconnect previous if any
    if (isConnected) disconnect();

    _userDisconnected = false;
    _deviceName = device.name ?? device.address;
    _deviceAddress = device.address;

    // Persist for auto-connect
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceName, _deviceName);
    await prefs.setString(_kDeviceAddress, _deviceAddress);

    return _connectToAddress(device.address);
  }

  Future<bool> _connectToAddress(String address) async {
    _setState(BtConnectionState.connecting);

    try {
      debugPrint('BluetoothService: Connecting to $address…');
      _connection = await BluetoothConnection.toAddress(address)
          .timeout(const Duration(seconds: 10));
      debugPrint('BluetoothService: ✅ Connected to $_deviceName');

      _inputSub?.cancel();
      _inputSub = _connection!.input?.listen(
        _handleData,
        onDone: () {
          debugPrint('BluetoothService: Connection closed by remote');
          _onUnexpectedDisconnect();
        },
        onError: (e) {
          debugPrint('BluetoothService: Stream error — $e');
          _onUnexpectedDisconnect();
        },
      );

      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _setState(BtConnectionState.connected);
      return true;
    } catch (e) {
      debugPrint('BluetoothService: Connection failed — $e');
      _setState(BtConnectionState.disconnected);
      return false;
    }
  }

  /// Explicitly disconnect (user action).
  void disconnect() {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _cleanupConnection();
    _setState(BtConnectionState.disconnected);
    debugPrint('BluetoothService: User disconnected');
  }

  void _cleanupConnection() {
    _inputSub?.cancel();
    _inputSub = null;
    try {
      _connection?.finish();
    } catch (_) {}
    _connection = null;
    _buffer = '';
  }

  // ══════════════════════════════════════════════════════════
  //  AUTO-RECONNECT
  // ══════════════════════════════════════════════════════════

  void _onUnexpectedDisconnect() {
    _cleanupConnection();
    _setState(BtConnectionState.disconnected);

    if (_userDisconnected || _deviceAddress.isEmpty) return;

    debugPrint('BluetoothService: Starting auto-reconnect…');
    _startReconnect();
  }

  void _startReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _reconnectTimer = Timer.periodic(_reconnectInterval, (timer) async {
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        debugPrint('BluetoothService: Max reconnect attempts reached');
        timer.cancel();
        return;
      }
      if (isConnected) {
        timer.cancel();
        return;
      }

      _reconnectAttempts++;
      debugPrint(
          'BluetoothService: Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts');
      final ok = await _connectToAddress(_deviceAddress);
      if (ok) timer.cancel();
    });
  }

  /// Manual reconnect trigger (e.g. from a "Reconnect" button).
  Future<bool> manualReconnect() async {
    if (_deviceAddress.isEmpty) return false;
    _userDisconnected = false;
    _reconnectAttempts = 0;
    return _connectToAddress(_deviceAddress);
  }

  // ══════════════════════════════════════════════════════════
  //  DATA PARSING
  // ══════════════════════════════════════════════════════════

  void _handleData(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);

    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (line.isEmpty) continue;

      debugPrint('BluetoothService: ◀ "$line"');

      BraceletCommand? cmd;
      final upper = line.toUpperCase();
      if (upper.contains('BUTTON SOS') || upper.contains('MOTION SOS') || upper == 'SOS') {
        cmd = BraceletCommand.sos;
      } else if (upper.contains('SHAKE')) {
        cmd = BraceletCommand.shake;
      } else if (upper.contains('VOICE')) {
        cmd = BraceletCommand.voice;
      } else if (upper.contains('CAM')) {
        cmd = BraceletCommand.camera;
      }

      if (cmd != null) {
        debugPrint('BluetoothService: 🚨 Command → $cmd');
        onCommand?.call(cmd);
      }
    }
  }

  // ══════════════════════════════════════════════════════════
  //  SEND COMMANDS TO ESP32
  // ══════════════════════════════════════════════════════════

  Future<void> send(String command) async {
    if (_connection == null || !isConnected) return;
    try {
      _connection!.output.add(Uint8List.fromList(utf8.encode('$command\n')));
      await _connection!.output.allSent;
      debugPrint('BluetoothService: Sent "$command"');
    } catch (e) {
      debugPrint('BluetoothService: Write failed — $e');
    }
  }

  Future<void> activateBuzzer() => send('BUZZER_ON');
  Future<void> stopBuzzer() => send('BUZZER_OFF');
  Future<void> ledOn() => send('LED_ON');
  Future<void> ledOff() => send('LED_OFF');

  // ══════════════════════════════════════════════════════════
  //  SIMULATE (for demos without hardware)
  // ══════════════════════════════════════════════════════════

  void simulateCommand(BraceletCommand command) {
    debugPrint('BluetoothService: Simulated $command');
    onCommand?.call(command);
  }

  // ══════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════

  void _setState(BtConnectionState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  /// Clear saved device (e.g. user wants to forget the device).
  Future<void> forgetDevice() async {
    disconnect();
    _deviceName = '';
    _deviceAddress = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeviceName);
    await prefs.remove(_kDeviceAddress);
    notifyListeners();
  }
}

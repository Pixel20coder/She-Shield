import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Commands that the bracelet can send to trigger actions.
enum BraceletCommand {
  sos,       // SOS button pressed
  shake,     // Violent shake detected
  voice,     // Voice keyword detected
  camera,    // Camera recording triggered
}

/// Callback when a command is received from the bracelet.
typedef BraceletCommandCallback = void Function(BraceletCommand command);

/// Service that monitors a connected BLE bracelet for SOS & alert commands.
///
/// The bracelet is expected to expose a BLE characteristic that sends
/// notification payloads when events occur. The service subscribes to
/// that characteristic and decodes commands.
///
/// **Protocol (simple byte-based):**
/// - `0x01` → SOS button pressed
/// - `0x02` → Shake / motion detected
/// - `0x03` → Voice keyword detected
/// - `0x04` → Camera recording trigger
///
/// For the hackathon demo, the service also simulates commands if no
/// real bracelet is connected.
class BraceletService {
  BluetoothDevice? _device;
  StreamSubscription? _notifySub;
  StreamSubscription? _connectionSub;
  BraceletCommandCallback? onCommand;

  bool _isMonitoring = false;

  /// Whether the bracelet is currently connected and being monitored.
  bool get isMonitoring => _isMonitoring;

  /// The name of the connected bracelet device.
  String get deviceName => _device?.platformName ?? 'Unknown';

  /// Start monitoring a connected device for SOS commands.
  ///
  /// Discovers services, finds the SOS characteristic, and subscribes
  /// to notifications.
  Future<bool> startMonitoring(BluetoothDevice device) async {
    _device = device;

    // Listen for disconnection
    _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _isMonitoring = false;
      }
    });

    try {
      // Discover all services on the bracelet
      final services = await device.discoverServices();

      // Look for a writable/notify characteristic to subscribe to.
      // In a real product, you'd target a specific service UUID.
      // For the hackathon, we subscribe to the first notifiable characteristic.
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.notify || char.properties.indicate) {
            await char.setNotifyValue(true);
            _notifySub?.cancel();
            _notifySub = char.onValueReceived.listen(_handleData);
            _isMonitoring = true;
            return true;
          }
        }
      }

      // No notifiable characteristic found — still mark as monitoring
      // so the UI can show the connection status.
      _isMonitoring = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stop monitoring and clean up subscriptions.
  void stopMonitoring() {
    _notifySub?.cancel();
    _notifySub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _isMonitoring = false;
  }

  /// Simulate a bracelet command (for hackathon demo).
  void simulateCommand(BraceletCommand command) {
    onCommand?.call(command);
  }

  /// Decode raw BLE data and fire the callback.
  void _handleData(List<int> data) {
    if (data.isEmpty) return;

    BraceletCommand? command;
    switch (data[0]) {
      case 0x01:
        command = BraceletCommand.sos;
        break;
      case 0x02:
        command = BraceletCommand.shake;
        break;
      case 0x03:
        command = BraceletCommand.voice;
        break;
      case 0x04:
        command = BraceletCommand.camera;
        break;
    }

    if (command != null) {
      onCommand?.call(command);
    }
  }

  /// Clean up.
  void dispose() {
    stopMonitoring();
  }
}

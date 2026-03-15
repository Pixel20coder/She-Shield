import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bracelet_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  /// Callback set by the parent (HomeScreen) to handle SOS triggers.
  static BraceletCommandCallback? onBraceletCommand;

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothDevice? _connectedDevice;
  StreamSubscription? _scanSub;
  StreamSubscription? _connectionSub;
  final BraceletService _braceletService = BraceletService();

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _braceletService.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on && mounted) {
      _showSnackBar('⚠️ Please turn on Bluetooth');
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    // Request location + Bluetooth permissions (required for BLE scan on Android)
    await [Permission.location, Permission.bluetoothScan, Permission.bluetoothConnect].request();

    setState(() {
      _scanResults = [];
      _isScanning = true;
    });

    try {
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            // Only show devices that broadcast a name
            _scanResults = results
                .where((r) => r.device.platformName.isNotEmpty)
                .toList();
            _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
          });
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      _showSnackBar('⚠️ Scan failed: ${e.toString()}');
    }

    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _showSnackBar('🔗 Connecting to ${device.platformName}…');

    try {
      await device.connect(timeout: const Duration(seconds: 10));

      _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (mounted) {
          if (state == BluetoothConnectionState.disconnected) {
            setState(() => _connectedDevice = null);
            _showPopup('🔴 Disconnected', '${device.platformName} has been disconnected.');
          }
        }
      });

      if (mounted) {
        setState(() => _connectedDevice = device);
        HapticFeedback.heavyImpact();
        _showPopup('✅ Paired Successfully', 'Connected to ${device.platformName}.\nYour bracelet is now active and listening for SOS signals.');

        // Start bracelet monitoring
        _braceletService.onCommand = (cmd) {
          BluetoothScreen.onBraceletCommand?.call(cmd);
        };
        await _braceletService.startMonitoring(device);
        if (mounted) setState(() {});
      }
    } catch (e) {
      _showPopup('❌ Pairing Failed', 'Could not connect to ${device.platformName}.\nMake sure the device is in pairing mode and try again.');
    }
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDevice == null) return;
    final name = _connectedDevice!.platformName;
    try {
      await _connectedDevice!.disconnect();
      _braceletService.stopMonitoring();
      setState(() => _connectedDevice = null);
      _showPopup('🔴 Disconnected', 'Successfully disconnected from $name.');
    } catch (_) {
      _showPopup('⚠️ Error', 'Could not disconnect from $name. Please try again.');
    }
  }

  void _showPopup(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(color: Color(0xFFF0F0F5), fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF8A8A9A), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
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
      appBar: AppBar(
        title: const Text('Bluetooth Pairing'),
        leading: IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: const Icon(Icons.arrow_back, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Connected device card
            if (_connectedDevice != null) _buildConnectedCard(),

            const SizedBox(height: 8),

            // Scan button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.bluetooth_searching, size: 20),
                  label: Text(_isScanning ? 'Scanning…' : 'Scan for Devices'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF42A5F5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Text(
                    'NEARBY DEVICES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5A5A6E),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_scanResults.length} found',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5A5A6E),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Device list (scrollable within the page)
            if (_scanResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bluetooth_disabled,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isScanning
                          ? 'Searching for devices…'
                          : 'Tap "Scan" to find nearby devices',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF5A5A6E),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _scanResults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _buildDeviceCard(_scanResults[i]),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedCard() {
    final monitoring = _braceletService.isMonitoring;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF1A1A2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0x2600E676),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.bluetooth_connected, color: Color(0xFF00E676), size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        monitoring ? 'BRACELET ACTIVE' : 'CONNECTED',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF00E676),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _connectedDevice!.platformName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF0F0F5),
                        ),
                      ),
                      if (monitoring)
                        const Text(
                          'Listening for SOS signals…',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8A8A9A)),
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _disconnectDevice,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Disconnect',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A8A9A),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Demo simulate buttons
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SimulateBtn(
                    label: '🚨 Simulate SOS',
                    color: const Color(0xFFE53935),
                    onTap: () {
                      _braceletService.simulateCommand(BraceletCommand.sos);
                      _showSnackBar('🚨 Simulated SOS from bracelet');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SimulateBtn(
                    label: '📳 Simulate Shake',
                    color: const Color(0xFFFF7043),
                    onTap: () {
                      _braceletService.simulateCommand(BraceletCommand.shake);
                      _showSnackBar('📳 Simulated shake from bracelet');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(ScanResult result) {
    final device = result.device;
    final isConnected = _connectedDevice?.remoteId == device.remoteId;
    final signalStrength = _getSignalIcon(result.rssi);

    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isConnected ? null : () => _connectToDevice(device),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isConnected
                  ? const Color(0xFF00E676).withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              // Bluetooth icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0x2600E676)
                      : const Color(0x1F42A5F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                    color: isConnected
                        ? const Color(0xFF00E676)
                        : const Color(0xFF42A5F5),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.platformName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF0F0F5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConnected ? 'Connected' : 'Tap to pair',
                      style: TextStyle(
                        fontSize: 12,
                        color: isConnected
                            ? const Color(0xFF00E676)
                            : const Color(0xFF8A8A9A),
                      ),
                    ),
                  ],
                ),
              ),
              // Signal strength
              Icon(signalStrength, color: const Color(0xFF5A5A6E), size: 20),
              const SizedBox(width: 4),
              Text(
                '${result.rssi} dBm',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF5A5A6E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getSignalIcon(int rssi) {
    if (rssi >= -60) return Icons.signal_cellular_4_bar;
    if (rssi >= -75) return Icons.signal_cellular_alt;
    if (rssi >= -85) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }
}

class _SimulateBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SimulateBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

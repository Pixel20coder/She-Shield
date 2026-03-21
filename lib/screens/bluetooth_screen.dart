import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bluetooth_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});
  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final FlutterBluetoothSerial _bt = FlutterBluetoothSerial.instance;
  final BluetoothService _service = BluetoothService.instance;

  List<BluetoothDiscoveryResult> _scanResults = [];
  List<BluetoothDevice> _bondedDevices = [];
  bool _isScanning = false;
  StreamSubscription? _discoverySub;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _init();
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await _requestPermissions();
    await _loadBondedDevices();
    if (!_service.isConnected) _startScan();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _loadBondedDevices() async {
    try {
      final bonded = await _bt.getBondedDevices();
      if (mounted) setState(() => _bondedDevices = bonded);
    } catch (_) {}
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    // Check if Bluetooth is enabled
    final isOn = await _bt.isEnabled ?? false;
    if (!isOn) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.bluetooth_disabled,
                    color: Color(0xFFE53935), size: 24),
                SizedBox(width: 10),
                Text('Bluetooth Off',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 18)),
              ],
            ),
            content: const Text(
              'Please enable Bluetooth to connect to your SheShield device.',
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _bt.requestEnable();
                  await Future.delayed(const Duration(seconds: 1));
                  _startScan();
                },
                child: const Text('Enable',
                    style: TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() {
      _scanResults = [];
      _isScanning = true;
    });

    try {
      _discoverySub?.cancel();
      _discoverySub = _bt.startDiscovery().listen(
        (result) {
          if (!mounted) return;
          setState(() {
            final idx = _scanResults.indexWhere(
                (r) => r.device.address == result.device.address);
            if (idx >= 0) {
              _scanResults[idx] = result;
            } else {
              _scanResults.add(result);
            }
          });
        },
        onDone: () {
          if (mounted) setState(() => _isScanning = false);
        },
        onError: (_) {
          if (mounted) setState(() => _isScanning = false);
        },
      );
    } catch (e) {
      _snack('⚠️ Scan failed: $e');
      setState(() => _isScanning = false);
    }
  }

  void _stopScan() {
    _discoverySub?.cancel();
    setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan();
    final name = device.name ?? device.address;
    _snack('🔗 Connecting to $name…');

    try {
      if (device.isBonded != true) {
        final bonded = await FlutterBluetoothSerial.instance
            .bondDeviceAtAddress(device.address);
        if (bonded != true) {
          _popup('❌ Pairing Failed', 'Could not pair with $name.');
          return;
        }
      }

      final ok = await _service.connect(device);
      if (ok && mounted) {
        HapticFeedback.heavyImpact();
        _snack('✅ Connected to $name');
        await _loadBondedDevices();
      } else {
        _popup('❌ Failed', 'Could not connect to $name.');
      }
    } catch (e) {
      _popup('❌ Error', '$e');
    }
  }

  void _disconnect() {
    _service.disconnect();
    _snack('🔴 Disconnected');
  }

  void _popup(String title, String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 18)),
        content:
            Text(msg, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Pairing'),
        leading: IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.08)),
            ),
            child: const Icon(Icons.arrow_back, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Connected card ──
            if (_service.isConnected) _connectedCard(isDark),
            const SizedBox(height: 8),

            // ── Scan button ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? _stopScan : _startScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.bluetooth_searching, size: 20),
                  label:
                      Text(_isScanning ? 'Stop Scanning' : 'Scan for Devices'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF42A5F5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Paired devices ──
            if (_bondedDevices.isNotEmpty) ...[
              _header('PAIRED DEVICES', _bondedDevices.length, isDark),
              const SizedBox(height: 10),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _bondedDevices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    _deviceCard(_bondedDevices[i], null, isDark: isDark, isPaired: true),
              ),
              const SizedBox(height: 16),
            ],

            // ── Discovered devices ──
            _header('NEARBY DEVICES', _scanResults.length, isDark),
            const SizedBox(height: 10),
            if (_scanResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bluetooth_disabled,
                        size: 48,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.15)),
                    const SizedBox(height: 12),
                    Text(
                      _isScanning
                          ? 'Searching…'
                          : 'Tap "Scan" to find devices',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF5A5A6E)
                            : const Color(0xFF8A8A9A),
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
                itemBuilder: (_, i) => _deviceCard(
                    _scanResults[i].device, _scanResults[i].rssi,
                    isDark: isDark),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _header(String title, int count, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFF5A5A6E)
                      : const Color(0xFF8A8A9A),
                  letterSpacing: 0.5,
                )),
            const Spacer(),
            Text('$count found',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF5A5A6E)
                      : const Color(0xFF8A8A9A),
                )),
          ],
        ),
      );

  Widget _connectedCard(bool isDark) {
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
          border: Border.all(
              color: const Color(0xFF00E676).withValues(alpha: 0.3)),
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
                    child: Icon(Icons.bluetooth_connected,
                        color: Color(0xFF00E676), size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BRACELET ACTIVE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF00E676),
                            letterSpacing: 0.5,
                          )),
                      const SizedBox(height: 2),
                      Text(_service.deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF0F0F5),
                          )),
                      const Text(
                        'Connected globally — SOS active even after leaving this screen',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFF8A8A9A)),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _disconnect,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Disconnect',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8A8A9A),
                        )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SimBtn(
                    label: '🚨 Simulate SOS',
                    color: const Color(0xFFE53935),
                    onTap: () {
                      _service.simulateCommand(BraceletCommand.sos);
                      _snack('🚨 Simulated SOS');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SimBtn(
                    label: '📳 Simulate Shake',
                    color: const Color(0xFFFF7043),
                    onTap: () {
                      _service.simulateCommand(BraceletCommand.shake);
                      _snack('📳 Simulated shake');
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

  Widget _deviceCard(BluetoothDevice device, int? rssi,
      {required bool isDark, bool isPaired = false}) {
    final isThis =
        _service.isConnected && _service.deviceAddress == device.address;
    final name = device.name?.isNotEmpty == true
        ? device.name!
        : 'Unknown (${device.address})';
    final isSheShield =
        device.name?.toUpperCase().contains('SHESHIELD') == true;
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isThis ? null : () => _connectToDevice(device),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isThis
                  ? const Color(0xFF00E676).withValues(alpha: 0.3)
                  : isSheShield
                      ? const Color(0xFFE53935).withValues(alpha: 0.3)
                      : isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isThis
                      ? const Color(0x2600E676)
                      : isSheShield
                          ? const Color(0x26E53935)
                          : const Color(0x1F42A5F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    isThis
                        ? Icons.bluetooth_connected
                        : isSheShield
                            ? Icons.watch
                            : Icons.bluetooth,
                    color: isThis
                        ? const Color(0xFF00E676)
                        : isSheShield
                            ? const Color(0xFFE53935)
                            : const Color(0xFF42A5F5),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFFF0F0F5)
                                    : const Color(0xFF1A1A2E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (isSheShield) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('SheShield',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFE53935),
                                )),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isThis
                          ? 'Connected'
                          : isPaired
                              ? 'Paired · Tap to connect'
                              : 'Tap to pair & connect',
                      style: TextStyle(
                        fontSize: 12,
                        color: isThis
                            ? const Color(0xFF00E676)
                            : isDark
                                ? const Color(0xFF8A8A9A)
                                : const Color(0xFF5A5A6E),
                      ),
                    ),
                  ],
                ),
              ),
              if (rssi != null) ...[
                Icon(_sigIcon(rssi),
                    color: isDark
                        ? const Color(0xFF5A5A6E)
                        : const Color(0xFF8A8A9A),
                    size: 20),
                const SizedBox(width: 4),
                Text('$rssi dBm',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF5A5A6E)
                          : const Color(0xFF8A8A9A),
                    )),
              ],
              if (isPaired && rssi == null)
                Icon(Icons.link,
                    color: isDark
                        ? const Color(0xFF5A5A6E)
                        : const Color(0xFF8A8A9A),
                    size: 18),
            ],
          ),
        ),
      ),
    );
  }

  IconData _sigIcon(int r) {
    if (r >= -60) return Icons.signal_cellular_4_bar;
    if (r >= -75) return Icons.signal_cellular_alt;
    if (r >= -85) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }
}

class _SimBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SimBtn(
      {required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ),
      );
}

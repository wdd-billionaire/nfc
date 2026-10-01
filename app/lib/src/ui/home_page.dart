import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../protocol/revg_client.dart';
import '../transport/ble_transport.dart';

/// MVP screen for a ChameleonMini RevG / RevH device (the Chameleon side of the
/// fused PM3+Chameleon hardware): scan → connect → device info → read a card.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  bool _scanning = false;

  BleTransport? _transport;
  RevgClient? _client;
  String? _connectedName;

  String _fw = '?';
  String _cfg = '?';
  String _mem = '?';
  List<String> _lastRead = [];
  final List<String> _log = [];

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _client?.dispose();
    _transport?.disconnect();
    super.dispose();
  }

  void _addLog(String s) => setState(() => _log.insert(0, s));

  Future<bool> _ensurePermissions() async {
    final req = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    final scan = req[Permission.bluetoothScan];
    final connect = req[Permission.bluetoothConnect];
    final loc = req[Permission.location];
    final ok = ((scan?.isGranted ?? false) && (connect?.isGranted ?? false)) ||
        (loc?.isGranted ?? false);
    if (!ok) _addLog('Permissions: scan=$scan connect=$connect location=$loc');
    return ok;
  }

  static bool _isLikely(ScanResult r) {
    if (r.advertisementData.serviceUuids.contains(NusUuids.service)) return true;
    final n = (r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName)
        .toLowerCase();
    return n.contains('chameleon') ||
        n.contains('ultra') ||
        n.contains('pm3') ||
        n.contains('proxmark') ||
        n.contains('mini') ||
        n.contains('revh') ||
        n.contains('revg');
  }

  static String _displayName(ScanResult r) {
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    if (r.advertisementData.advName.isNotEmpty) return r.advertisementData.advName;
    return '(unnamed)';
  }

  Future<void> _startScan() async {
    if (!await _ensurePermissions()) {
      _addLog('Bluetooth permission denied');
      return;
    }
    _addLog('Scan tapped');
    try {
      final state = FlutterBluePlus.adapterStateNow;
      _addLog('Adapter: $state');
      if (state != BluetoothAdapterState.on) {
        _addLog('Bluetooth is off — turn it on');
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          _addLog('turnOn failed: $e');
        }
      }
    } catch (e) {
      _addLog('Adapter check error: $e');
    }

    setState(() {
      _results.clear();
      _scanning = true;
    });

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((rs) {
      final byId = <String, ScanResult>{};
      for (final r in rs) {
        byId[r.device.remoteId.str] = r;
      }
      final list = byId.values.toList()
        ..sort((a, b) {
          final la = _isLikely(a), lb = _isLikely(b);
          if (la != lb) return la ? -1 : 1;
          return b.rssi.compareTo(a.rssi);
        });
      setState(() {
        _results
          ..clear()
          ..addAll(list);
      });
    }, onError: (e) => _addLog('Scan error: $e'));

    _isScanningSub?.cancel();
    _isScanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (e) {
      _addLog('startScan failed: $e');
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    final t = BleTransport(device, onLog: _addLog);
    try {
      _addLog('Connecting to ${_displayName0(device)}...');
      await t.connect();
      final c = RevgClient(t, log: _addLog);
      setState(() {
        _transport = t;
        _client = c;
        _connectedName =
            device.platformName.isEmpty ? device.remoteId.str : device.platformName;
      });
      _addLog('Connected. Reading device info...');
      await _refreshInfo();
    } catch (e) {
      _addLog('Connect failed: $e');
      await t.disconnect();
    }
  }

  String _displayName0(BluetoothDevice d) =>
      d.platformName.isEmpty ? d.remoteId.str : d.platformName;

  Future<void> _refreshInfo() async {
    final c = _client;
    if (c == null) return;
    try {
      final fw = await c.version();
      final cfg = await c.config();
      String mem = '?';
      try {
        mem = await c.memSize();
      } catch (_) {}
      setState(() {
        _fw = fw.isEmpty ? '?' : fw;
        _cfg = cfg.isEmpty ? '?' : cfg;
        _mem = mem.isEmpty ? '?' : mem;
      });
      _addLog('Info: fw=$_fw cfg=$_cfg mem=$_mem');
    } catch (e) {
      _addLog('Read info failed: $e');
    }
  }

  Future<void> _readerMode() async {
    final c = _client;
    if (c == null) return;
    try {
      final r = await c.readerMode();
      _addLog('CONFIG=ISO14443A_READER -> $r');
      await _refreshInfo();
    } catch (e) {
      _addLog('Set reader mode failed: $e');
    }
  }

  Future<void> _readCard() async {
    final c = _client;
    if (c == null) return;
    try {
      // Ensure reader mode, then identify + get UID.
      if (!_cfg.toUpperCase().contains('READER')) {
        await c.readerMode();
        await _refreshInfo();
      }
      final ident = await c.identify();
      final uid = await c.getUid();
      final lines = <String>[
        if (uid.isNotEmpty) 'UID: $uid',
        ...ident.text,
        if (ident.text.isEmpty && uid.isEmpty) '(${ident.status})',
      ];
      setState(() => _lastRead = lines);
      _addLog('Read: ${lines.isEmpty ? ident.status : lines.join(" | ")}');
    } catch (e) {
      _addLog('Read failed: $e');
    }
  }

  Future<void> _rebootPm3() async {
    final c = _client;
    if (c == null) return;
    try {
      _addLog('Sending REBOOTPM3 (switch to Proxmark3 mode)...');
      final r = await c.rebootToPm3();
      _addLog('REBOOTPM3 -> $r');
      _addLog('Device is switching to PM3 mode; it will drop the BLE link. '
          'PM3-mode support is not implemented yet.');
    } catch (e) {
      // The device may reboot before replying — that is expected.
      _addLog('REBOOTPM3 sent (no reply, device likely rebooting): $e');
    }
  }

  Future<void> _probe() async {
    final c = _client;
    if (c == null) return;
    _addLog('=== PROBE ===');
    for (final cmd in ['VERSION?', 'CONFIG?', 'MEMSIZE?', 'RSSI?']) {
      try {
        final r = await c.send(cmd);
        _addLog('$cmd -> $r');
      } catch (e) {
        _addLog('$cmd -> ERR $e');
      }
    }
    _addLog('=== PROBE END ===');
  }

  Future<void> _disconnect() async {
    await _client?.dispose();
    await _transport?.disconnect();
    setState(() {
      _client = null;
      _transport = null;
      _connectedName = null;
      _fw = _cfg = _mem = '?';
      _lastRead = [];
    });
    _addLog('Disconnected');
  }

  @override
  Widget build(BuildContext context) {
    final connected = _client != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(connected ? (_connectedName ?? 'Device') : 'NFC Tool (open)'),
        actions: [
          if (connected)
            IconButton(
                onPressed: _disconnect,
                icon: const Icon(Icons.bluetooth_disabled)),
        ],
      ),
      body: connected ? _buildConnected() : _buildScan(),
      floatingActionButton: connected
          ? FloatingActionButton.extended(
              onPressed: _readCard,
              icon: const Icon(Icons.nfc),
              label: const Text('Read card'))
          : FloatingActionButton.extended(
              onPressed: _scanning ? null : _startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Scanning...' : 'Scan')),
    );
  }

  Widget _buildScan() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              if (_scanning)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                const Icon(Icons.bluetooth, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_scanning
                    ? 'Scanning...  ${_results.length} device(s)'
                    : '${_results.length} device(s) found'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _scanning
                          ? 'Scanning for BLE devices...'
                          : 'Tap Scan to list nearby BLE devices.\n'
                              'All devices are shown — pick yours by signal '
                              'strength or the ★ badge.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    final likely = _isLikely(r);
                    return ListTile(
                      leading: Icon(likely ? Icons.star : Icons.memory,
                          color: likely ? Colors.amber[700] : null),
                      title: Text(_displayName(r)),
                      subtitle:
                          Text('${r.device.remoteId.str}   rssi ${r.rssi} dBm'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _connect(r.device),
                    );
                  },
                ),
        ),
        _logPanel(maxHeight: 160),
      ],
    );
  }

  Widget _buildConnected() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Firmware: $_fw'),
                Text('Config: $_cfg'),
                Text('Memory: $_mem'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  FilledButton.tonal(
                      onPressed: _readerMode,
                      child: const Text('Reader mode')),
                  OutlinedButton(
                      onPressed: _refreshInfo, child: const Text('Refresh')),
                  OutlinedButton(
                      onPressed: _probe, child: const Text('Probe')),
                  OutlinedButton(
                      onPressed: _rebootPm3,
                      child: const Text('Switch to PM3')),
                ]),
              ],
            ),
          ),
        ),
        if (_lastRead.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Last read',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ..._lastRead.map((l) => Text(l,
                      style: const TextStyle(fontFamily: 'monospace'))),
                ],
              ),
            ),
          ),
        Expanded(child: _logPanel()),
      ],
    );
  }

  Widget _logPanel({double maxHeight = double.infinity}) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Row(
              children: [
                const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_log.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _log.clear()),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Text('clear', style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: _log.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text('(empty)',
                        style: TextStyle(fontSize: 12, color: Colors.grey)))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                      child: Text(_log[i],
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

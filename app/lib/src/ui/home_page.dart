import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../protocol/chameleon_client.dart';
import '../protocol/commands.dart';
import '../protocol/models.dart';
import '../transport/ble_transport.dart';

/// Single-screen MVP: scan → connect → read device info → HF-14A read.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = false;

  BleTransport? _transport;
  ChameleonClient? _client;
  String? _connectedName;
  DeviceInfo _info = DeviceInfo();
  final List<String> _log = [];
  List<Hf14aTag> _tags = [];

  @override
  void dispose() {
    _scanSub?.cancel();
    _client?.dispose();
    _transport?.disconnect();
    super.dispose();
  }

  void _addLog(String s) {
    setState(() => _log.insert(0, s));
  }

  Future<bool> _ensurePermissions() async {
    // Android 12+ needs BLUETOOTH_SCAN/CONNECT; older needs location.
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> _startScan() async {
    if (!await _ensurePermissions()) {
      _addLog('Bluetooth permission denied');
      return;
    }
    setState(() {
      _results.clear();
      _scanning = true;
    });
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((rs) {
      setState(() {
        _results
          ..clear()
          ..addAll(rs.where((r) =>
              r.advertisementData.serviceUuids.contains(NusUuids.service) ||
              r.device.platformName.isNotEmpty));
      });
    });
    await FlutterBluePlus.startScan(
      withServices: [NusUuids.service],
      timeout: const Duration(seconds: 8),
    );
    setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    final t = BleTransport(device);
    try {
      _addLog('Connecting to ${device.platformName}...');
      await t.connect();
      final c = ChameleonClient(t);
      setState(() {
        _transport = t;
        _client = c;
        _connectedName = device.platformName.isEmpty
            ? device.remoteId.str
            : device.platformName;
      });
      _addLog('Connected. Reading device info...');
      await _refreshInfo();
    } catch (e) {
      _addLog('Connect failed: $e');
      await t.disconnect();
    }
  }

  Future<void> _refreshInfo() async {
    final c = _client;
    if (c == null) return;
    try {
      final model = await c.getDeviceModel();
      final mode = await c.getDeviceMode();
      final ver = await c.getGitVersion();
      int mv = 0, pct = 0;
      try {
        (mv, pct) = await c.getBattery();
      } catch (_) {}
      setState(() {
        _info = DeviceInfo(
          model: model,
          mode: mode,
          gitVersion: ver,
          batteryMv: mv,
          batteryPercent: pct,
        );
      });
      _addLog('Info: model=$model mode=${_info.modeLabel} fw=$ver batt=$pct%');
    } catch (e) {
      _addLog('Read info failed: $e');
    }
  }

  Future<void> _setReader(bool reader) async {
    final c = _client;
    if (c == null) return;
    try {
      await c.setReaderMode(reader);
      _addLog('Switched to ${reader ? "Reader" : "Emulator"} mode');
      await _refreshInfo();
    } catch (e) {
      _addLog('Mode switch failed: $e');
    }
  }

  Future<void> _readCard() async {
    final c = _client;
    if (c == null) return;
    try {
      if (_info.mode != DeviceMode.reader) {
        await c.setReaderMode(true);
        await _refreshInfo();
      }
      final tags = await c.hf14aScan();
      setState(() => _tags = tags);
      if (tags.isEmpty) {
        _addLog('No card in field');
      } else {
        for (final t in tags) {
          _addLog('Card UID=${t.uidHex} SAK=${t.sakHex} (${t.guessedType})');
        }
      }
    } catch (e) {
      _addLog('Read failed: $e');
    }
  }

  Future<void> _disconnect() async {
    await _client?.dispose();
    await _transport?.disconnect();
    setState(() {
      _client = null;
      _transport = null;
      _connectedName = null;
      _info = DeviceInfo();
      _tags = [];
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
                onPressed: _disconnect, icon: const Icon(Icons.bluetooth_disabled)),
        ],
      ),
      body: connected ? _buildConnected() : _buildScan(),
      floatingActionButton: connected
          ? FloatingActionButton.extended(
              onPressed: _readCard,
              icon: const Icon(Icons.nfc),
              label: const Text('Read HF'))
          : FloatingActionButton.extended(
              onPressed: _scanning ? null : _startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Scanning...' : 'Scan')),
    );
  }

  Widget _buildScan() {
    if (_results.isEmpty) {
      return Center(
        child: Text(_scanning
            ? 'Scanning for BLE devices...'
            : 'Tap Scan to find your device'),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final r = _results[i];
        final name = r.device.platformName.isEmpty
            ? '(unnamed)'
            : r.device.platformName;
        return ListTile(
          leading: const Icon(Icons.memory),
          title: Text(name),
          subtitle: Text('${r.device.remoteId.str}  rssi ${r.rssi}'),
          onTap: () => _connect(r.device),
        );
      },
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
                Text('Firmware: ${_info.gitVersion ?? "?"}   '
                    'Model: ${_info.model ?? "?"}'),
                Text('Mode: ${_info.modeLabel}   '
                    'Battery: ${_info.batteryPercent ?? "?"}%'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton.tonal(
                      onPressed: () => _setReader(true),
                      child: const Text('Reader mode')),
                  FilledButton.tonal(
                      onPressed: () => _setReader(false),
                      child: const Text('Emulator mode')),
                  OutlinedButton(
                      onPressed: _refreshInfo, child: const Text('Refresh')),
                ]),
              ],
            ),
          ),
        ),
        if (_tags.isNotEmpty)
          ..._tags.map((t) => ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text('UID ${t.uidHex}'),
                subtitle: Text(
                    'ATQA ${t.atqaHex}  SAK ${t.sakHex}  ${t.guessedType}'),
              )),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Log', style: TextStyle(fontWeight: FontWeight.bold))),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Text(_log[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }
}

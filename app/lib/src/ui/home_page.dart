import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../protocol/chameleon_client.dart';
import '../protocol/commands.dart';
import '../protocol/frame.dart';
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
  StreamSubscription<bool>? _isScanningSub;
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
    _isScanningSub?.cancel();
    _client?.dispose();
    _transport?.disconnect();
    super.dispose();
  }

  void _addLog(String s) {
    setState(() => _log.insert(0, s));
  }

  Future<bool> _ensurePermissions() async {
    // Android 12+ (incl. 16): BLUETOOTH_SCAN + BLUETOOTH_CONNECT are what matter.
    // With neverForLocation set, location is NOT required for scanning, so we
    // request it best-effort for older Android but never block on it.
    final req = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    final scan = req[Permission.bluetoothScan];
    final connect = req[Permission.bluetoothConnect];
    final loc = req[Permission.location];
    final ok = ((scan?.isGranted ?? false) && (connect?.isGranted ?? false)) ||
        (loc?.isGranted ?? false); // older Android path
    if (!ok) {
      _addLog('Permissions: scan=$scan connect=$connect location=$loc');
    }
    return ok;
  }

  /// Likely one of our target devices (for highlighting only — we never filter
  /// it out, because many devices do not advertise their 128-bit service UUID).
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
        n.contains('mini');
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
    // Make sure the adapter is on (use the synchronous getter; .first can hang).
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
      // Show ALL devices (deduped, strongest signal first). We do NOT filter by
      // advertised service: the device exposes Nordic UART only after connect.
      final byId = <String, ScanResult>{};
      for (final r in rs) {
        byId[r.device.remoteId.str] = r;
      }
      final list = byId.values.toList()
        ..sort((a, b) {
          final la = _isLikely(a), lb = _isLikely(b);
          if (la != lb) return la ? -1 : 1; // likely devices first
          return b.rssi.compareTo(a.rssi); // then strongest signal
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
      _addLog('Scanning... (${_results.length} devices so far)');
    } catch (e) {
      _addLog('startScan failed: $e');
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    final t = BleTransport(device, onLog: _addLog);
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
      _addLog('Connected. Probing protocol...');
      await _probe();
    } catch (e) {
      _addLog('Connect failed: $e');
      await t.disconnect();
    }
  }

  /// Send both a ChameleonUltra binary frame and a few Chameleon-Mini ASCII
  /// commands, so the raw `rx<=` log reveals which protocol the device speaks.
  Future<void> _probe() async {
    final t = _transport;
    if (t == null) return;
    Future<void> send(String label, Uint8List bytes) async {
      _addLog('— probe: $label');
      try {
        await t.write(bytes);
      } catch (e) {
        _addLog('tx err: $e');
      }
      await Future.delayed(const Duration(milliseconds: 900));
    }

    _addLog('=== PROBE START ===');
    await send('Ultra GET_APP_VERSION',
        ChameleonFrame(Cmd.getAppVersion, 0, Uint8List(0)).encode());
    await send('ASCII VERSION?', Uint8List.fromList('VERSION?\r\n'.codeUnits));
    await send('ASCII v', Uint8List.fromList('v\r\n'.codeUnits));
    await send('ASCII VERSION? (LF)', Uint8List.fromList('VERSION?\n'.codeUnits));
    _addLog('=== PROBE END — look at rx<= lines ===');
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
                              'All devices are shown (your device may not advertise '
                              'a name) — pick yours by signal strength or the ★ '
                              'badge, or power-cycle it so it is advertising.',
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

  Widget _logPanel({double maxHeight = 200}) {
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
                  OutlinedButton(
                      onPressed: _probe, child: const Text('Probe')),
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

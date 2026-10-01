import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

/// Nordic UART Service (NUS) — the BLE profile used by ChameleonUltra/
/// Chameleon-class devices. Confirmed against the target hardware.
class NusUuids {
  static final Guid service = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  // RX: central writes to peripheral.
  static final Guid rxWrite = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  // TX: peripheral notifies central.
  static final Guid txNotify = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

/// BLE implementation of [DeviceTransport] over Nordic UART.
///
/// Robust against non-standard characteristic UUIDs: it prefers the NUS write/
/// notify characteristics but falls back to the first writable / notifying
/// characteristic found. All I/O is logged via [onLog] for diagnosis.
class BleTransport implements DeviceTransport {
  final BluetoothDevice device;

  /// Diagnostic sink (service/characteristic dump, raw tx/rx hex).
  void Function(String msg)? onLog;

  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final _incoming = StreamController<Uint8List>.broadcast();
  int _mtu = 23;
  bool _connected = false;

  BleTransport(this.device, {this.onLog});

  void _log(String s) => onLog?.call(s);

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  bool get isConnected => _connected;

  int get _chunkSize => (_mtu - 3).clamp(20, 512);

  Future<void> connect() async {
    _connSub = device.connectionState.listen((s) {
      _connected = s == BluetoothConnectionState.connected;
    });

    await device.connect(timeout: const Duration(seconds: 15));

    try {
      _mtu = await device.requestMtu(247);
      _log('MTU=$_mtu');
    } catch (_) {
      _mtu = 23;
    }

    final services = await device.discoverServices();

    // Dump everything so we can see the real data path.
    BluetoothCharacteristic? nusRx, nusTx, anyWrite, anyNotify;
    for (final s in services) {
      _log('svc ${s.uuid.str}');
      for (final c in s.characteristics) {
        final p = c.properties;
        final flags = [
          if (p.read) 'R',
          if (p.write) 'W',
          if (p.writeWithoutResponse) 'w',
          if (p.notify) 'N',
          if (p.indicate) 'I',
        ].join();
        _log('  chr ${c.uuid.str} [$flags]');
        if (c.uuid == NusUuids.rxWrite) nusRx = c;
        if (c.uuid == NusUuids.txNotify) nusTx = c;
        if (anyWrite == null && (p.write || p.writeWithoutResponse)) anyWrite = c;
        if (anyNotify == null && (p.notify || p.indicate)) anyNotify = c;
      }
    }

    _rx = nusRx ?? anyWrite;
    _tx = nusTx ?? anyNotify;
    if (_rx == null || _tx == null) {
      throw StateError('No writable / notifying characteristic found');
    }
    _log('using rx(write)=${_rx!.uuid.str}  tx(notify)=${_tx!.uuid.str}');

    await _tx!.setNotifyValue(true);
    _txSub = _tx!.onValueReceived.listen((v) {
      if (v.isNotEmpty) {
        _log('rx<= ${_hex(v)}');
        _incoming.add(Uint8List.fromList(v));
      }
    });
    _connected = true;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final rx = _rx;
    if (rx == null) throw StateError('not connected');
    _log('tx=> ${_hex(bytes)}');
    final wwr = rx.properties.writeWithoutResponse && !rx.properties.write
        ? true
        : rx.properties.writeWithoutResponse;
    for (int i = 0; i < bytes.length; i += _chunkSize) {
      final end = (i + _chunkSize < bytes.length) ? i + _chunkSize : bytes.length;
      await rx.write(bytes.sublist(i, end), withoutResponse: wwr);
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _txSub?.cancel();
    await _connSub?.cancel();
    try {
      await device.disconnect();
    } catch (_) {}
    await _incoming.close();
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

/// Nordic UART Service (NUS) — the BLE profile ChameleonUltra-class devices use.
/// Confirmed against the target hardware's advertised service UUID.
class NusUuids {
  static final Guid service = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  // RX: central writes to peripheral.
  static final Guid rxWrite = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  // TX: peripheral notifies central.
  static final Guid txNotify = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
}

/// BLE implementation of [DeviceTransport] over Nordic UART.
class BleTransport implements DeviceTransport {
  final BluetoothDevice device;

  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final _incoming = StreamController<Uint8List>.broadcast();
  int _mtu = 23;
  bool _connected = false;

  BleTransport(this.device);

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  bool get isConnected => _connected;

  /// Payload we may put in a single write (ATT MTU minus 3-byte header).
  int get _chunkSize => (_mtu - 3).clamp(20, 512);

  Future<void> connect() async {
    _connSub = device.connectionState.listen((s) {
      _connected = s == BluetoothConnectionState.connected;
    });

    await device.connect(timeout: const Duration(seconds: 15));

    // Larger MTU => fewer writes for long frames. Android only; iOS ignores.
    try {
      _mtu = await device.requestMtu(247);
    } catch (_) {
      _mtu = 23;
    }

    final services = await device.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid == NusUuids.service,
      orElse: () => throw StateError(
          'Nordic UART service not found — is this the right device?'),
    );
    for (final c in svc.characteristics) {
      if (c.uuid == NusUuids.rxWrite) _rx = c;
      if (c.uuid == NusUuids.txNotify) _tx = c;
    }
    if (_rx == null || _tx == null) {
      throw StateError('NUS RX/TX characteristics missing');
    }

    await _tx!.setNotifyValue(true);
    _txSub = _tx!.onValueReceived.listen((v) {
      if (v.isNotEmpty) _incoming.add(Uint8List.fromList(v));
    });
    _connected = true;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final rx = _rx;
    if (rx == null) throw StateError('not connected');
    // Prefer write-without-response when supported (faster); fall back.
    final wwr = rx.properties.writeWithoutResponse;
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

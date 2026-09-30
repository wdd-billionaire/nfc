import 'dart:typed_data';

/// A raw byte pipe to the device. BLE (Nordic UART) is the first
/// implementation; a USB-serial implementation can satisfy the same interface
/// later so the protocol layer stays transport-agnostic.
abstract class DeviceTransport {
  /// Bytes received from the device (unframed; may be chunked).
  Stream<Uint8List> get incoming;

  /// True while a live connection is held.
  bool get isConnected;

  /// Write raw bytes to the device. Implementations must chunk to the
  /// underlying MTU/packet size themselves.
  Future<void> write(Uint8List bytes);

  Future<void> disconnect();
}

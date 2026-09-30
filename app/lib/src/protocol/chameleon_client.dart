import 'dart:async';
import 'dart:typed_data';

import '../transport/transport.dart';
import 'commands.dart';
import 'frame.dart';
import 'models.dart';

/// Thrown when a command completes with a non-OK status.
class ChameleonStatusException implements Exception {
  final int command;
  final int status;
  ChameleonStatusException(this.command, this.status);
  @override
  String toString() =>
      'command $command failed: ${Status.describe(status)}';
}

/// High-level, transport-agnostic client for the ChameleonUltra protocol.
///
/// It frames outgoing commands, reassembles incoming frames, and matches each
/// response to its request by command id (the device echoes the command in its
/// reply). One in-flight command at a time is assumed, which matches the
/// firmware's request/response model.
class ChameleonClient {
  final DeviceTransport transport;
  final FrameParser _parser = FrameParser();
  StreamSubscription<Uint8List>? _sub;

  final Map<int, Completer<ChameleonFrame>> _pending = {};
  final Duration timeout;

  ChameleonClient(this.transport, {this.timeout = const Duration(seconds: 5)}) {
    _sub = transport.incoming.listen(_onData);
  }

  void _onData(Uint8List chunk) {
    for (final frame in _parser.feed(chunk)) {
      final c = _pending.remove(frame.command);
      c?.complete(frame);
    }
  }

  /// Send a command and await its matching response frame.
  Future<ChameleonFrame> send(int command,
      {Uint8List? data, int status = 0}) async {
    final payload = data ?? Uint8List(0);
    final completer = Completer<ChameleonFrame>();
    // If a previous request for the same command is still pending, fail it.
    _pending[command]?.completeError(
        StateError('superseded by newer request for command $command'));
    _pending[command] = completer;

    await transport.write(ChameleonFrame(command, status, payload).encode());

    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(command);
      throw TimeoutException('no response for command $command', timeout);
    });
  }

  /// Send a command and require an OK status, returning the payload bytes.
  Future<Uint8List> sendOk(int command, {Uint8List? data}) async {
    final resp = await send(command, data: data);
    if (!Status.isOk(resp.status)) {
      throw ChameleonStatusException(command, resp.status);
    }
    return resp.data;
  }

  // -------- convenience wrappers --------

  Future<String> getGitVersion() async {
    final d = await sendOk(Cmd.getAppVersion);
    // App version payload is 2 bytes (major, minor); git version has its own
    // command in newer firmware. Fall back to a numeric string here.
    if (d.length >= 2) return '${d[0]}.${d[1]}';
    return d.isEmpty ? '?' : d[0].toString();
  }

  Future<int> getDeviceModel() async {
    final d = await sendOk(Cmd.getDeviceModel);
    return d.isEmpty ? -1 : d[0];
  }

  Future<int> getDeviceMode() async {
    final d = await sendOk(Cmd.getDeviceMode);
    return d.isEmpty ? -1 : d[0];
  }

  Future<void> setReaderMode(bool reader) async {
    await sendOk(Cmd.changeDeviceMode,
        data: Uint8List.fromList([reader ? DeviceMode.reader : DeviceMode.tag]));
  }

  /// Battery payload: 2 bytes voltage (mV, BE) + 1 byte percentage.
  Future<(int mv, int percent)> getBattery() async {
    final d = await sendOk(Cmd.getBatteryInfo);
    if (d.length >= 3) {
      final mv = (d[0] << 8) | d[1];
      return (mv, d[2]);
    }
    return (0, 0);
  }

  /// Scan for ISO14443-A tags in the RF field (device must be in reader mode).
  ///
  /// Response payload is a concatenation of records:
  ///   uidLen(1) uid(uidLen) atqa(2) sak(1) atsLen(1) ats(atsLen)
  Future<List<Hf14aTag>> hf14aScan() async {
    final resp = await send(Cmd.hf14aScan);
    if (resp.status == Status.hfTagNo) return [];
    if (!Status.isOk(resp.status)) {
      throw ChameleonStatusException(Cmd.hf14aScan, resp.status);
    }
    final data = resp.data;
    final tags = <Hf14aTag>[];
    int off = 0;
    while (off < data.length) {
      final uidLen = data[off];
      off += 1;
      if (off + uidLen + 4 > data.length) break; // uid + atqa(2)+sak(1)+atsLen(1)
      final uid = Uint8List.fromList(data.sublist(off, off + uidLen));
      off += uidLen;
      final atqa = Uint8List.fromList(data.sublist(off, off + 2));
      off += 2;
      final sak = Uint8List.fromList(data.sublist(off, off + 1));
      off += 1;
      final atsLen = data[off];
      off += 1;
      if (off + atsLen > data.length) break;
      final ats = Uint8List.fromList(data.sublist(off, off + atsLen));
      off += atsLen;
      tags.add(Hf14aTag(uid: uid, atqa: atqa, sak: sak, ats: ats));
    }
    return tags;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('client disposed'));
    }
    _pending.clear();
  }
}

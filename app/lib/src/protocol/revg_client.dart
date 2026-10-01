import 'dart:async';
import 'dart:typed_data';

import '../transport/transport.dart';

/// Response to a ChameleonMini RevG ASCII command.
///
/// RevG replies with a status line `CODE:TEXT` (e.g. `100:OK`,
/// `101:OK WITH TEXT`, `110:WAITING FOR XMODEM`, `200:UNKNOWN COMMAND`),
/// optionally followed by payload line(s).
class RevgResponse {
  final int code;
  final String status;
  final List<String> text; // payload lines after the status line
  final List<String> raw; // every line received, for logging

  RevgResponse(this.code, this.status, this.text, this.raw);

  bool get ok => code == 100 || code == 101;
  String get firstText => text.isNotEmpty ? text.first : '';

  @override
  String toString() => '[$code] $status${text.isEmpty ? '' : ' | ${text.join(' / ')}'}';
}

/// ChameleonMini RevG / RevH ASCII command client.
///
/// This is the protocol the target device speaks in Chameleon mode (confirmed
/// from the stock app: CONFIG=, GETUID, IDENTIFY, DUMP_MFU, REBOOTPM3, …).
/// Line-oriented over the BLE Nordic UART transport; line endings may be
/// `\r\n`, `\r`, or `\n`.
class RevgClient {
  final DeviceTransport transport;
  final void Function(String msg)? log;
  final Duration timeout;

  final _lines = StreamController<String>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  String _buf = '';

  RevgClient(this.transport, {this.log, this.timeout = const Duration(seconds: 4)}) {
    _sub = transport.incoming.listen(_onData);
  }

  void _onData(Uint8List data) {
    // Decode leniently; RevG output is ASCII.
    _buf += String.fromCharCodes(data);
    // Split on any CR/LF combination, keep the trailing partial line.
    final parts = _buf.split(RegExp(r'\r\n|\r|\n'));
    _buf = parts.removeLast();
    for (final line in parts) {
      final t = line.trim();
      if (t.isNotEmpty) _lines.add(t);
    }
  }

  /// Send one command and collect the status line plus any payload lines that
  /// arrive before a short quiet gap.
  Future<RevgResponse> send(String cmd) async {
    final lines = <String>[];
    Timer? quiet;
    final done = Completer<void>();
    final sub = _lines.stream.listen((l) {
      lines.add(l);
      quiet?.cancel();
      quiet = Timer(const Duration(milliseconds: 300), () {
        if (!done.isCompleted) done.complete();
      });
    });

    log?.call('tx» $cmd');
    await transport.write(Uint8List.fromList('$cmd\r\n'.codeUnits));

    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      // fall through; we return whatever we have (possibly nothing)
    }
    quiet?.cancel();
    await sub.cancel();

    if (lines.isEmpty) {
      throw TimeoutException('no response to "$cmd"', timeout);
    }
    final m = RegExp(r'^(\d{3}):(.*)$').firstMatch(lines.first);
    final code = m != null ? int.parse(m.group(1)!) : -1;
    final status = m != null ? m.group(2)!.trim() : lines.first;
    return RevgResponse(code, status, lines.skip(1).toList(), lines);
  }

  // ---- convenience wrappers ----

  Future<String> version() async => (await send('VERSION?')).firstText;
  Future<String> config() async => (await send('CONFIG?')).firstText;
  Future<String> memSize() async => (await send('MEMSIZE?')).firstText;
  Future<String> rssi() async => (await send('RSSI?')).firstText;

  Future<RevgResponse> setConfig(String value) => send('CONFIG=$value');

  /// Put the device into ISO14443-A reader mode.
  Future<RevgResponse> readerMode() => setConfig('ISO14443A_READER');

  /// Read the UID of a card in the field (device must be in reader mode).
  Future<String> getUid() async => (await send('GETUID')).firstText;

  /// Identify a card (ATQA / SAK / UID lines).
  Future<RevgResponse> identify() => send('IDENTIFY');

  /// Switch the whole device into Proxmark3 mode (it reboots; BLE name is kept).
  Future<RevgResponse> rebootToPm3() => send('REBOOTPM3');

  Future<void> dispose() async {
    await _sub?.cancel();
    await _lines.close();
  }
}

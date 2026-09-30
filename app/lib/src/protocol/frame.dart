import 'dart:typed_data';

/// ChameleonUltra data-frame codec.
///
/// Frame layout (all multi-byte integers are big-endian):
///
///   byte 0      SOF        = 0x11
///   byte 1      LRC1       = lrc([SOF])            = 0xEF
///   byte 2..3   command    (u16 BE)
///   byte 4..5   status     (u16 BE)
///   byte 6..7   dataLength (u16 BE)
///   byte 8      LRC2       = lrc(bytes[0..8))      head checksum
///   byte 9..    data       (dataLength bytes)
///   byte last   LRC3       = lrc(bytes[0..last))   data checksum
///
/// lrc(x) = (0x100 - (sum(x) & 0xFF)) & 0xFF, i.e. the running sum including
/// the LRC byte is congruent to 0 (mod 256).
///
/// This mirrors `chameleon_com.py` in RfidResearchGroup/ChameleonUltra.
class ChameleonFrame {
  static const int sof = 0x11;
  static const int dataMaxLength = 4096;

  final int command;
  final int status;
  final Uint8List data;

  ChameleonFrame(this.command, this.status, this.data);

  static int lrc(List<int> bytes, [int start = 0, int? end]) {
    end ??= bytes.length;
    int sum = 0;
    for (int i = start; i < end; i++) {
      sum += bytes[i];
    }
    return (0x100 - (sum & 0xFF)) & 0xFF;
  }

  /// Encode a command frame ready to be written to the device.
  Uint8List encode() {
    if (data.length > dataMaxLength) {
      throw ArgumentError('data too long: ${data.length} > $dataMaxLength');
    }
    final out = Uint8List(9 + data.length + 1);
    out[0] = sof;
    out[1] = lrc(out, 0, 1); // 0xEF
    out[2] = (command >> 8) & 0xFF;
    out[3] = command & 0xFF;
    out[4] = (status >> 8) & 0xFF;
    out[5] = status & 0xFF;
    out[6] = (data.length >> 8) & 0xFF;
    out[7] = data.length & 0xFF;
    out[8] = lrc(out, 0, 8); // head LRC covers bytes 0..7
    out.setRange(9, 9 + data.length, data);
    out[9 + data.length] = lrc(out, 0, 9 + data.length); // data LRC
    return out;
  }

  @override
  String toString() =>
      'ChameleonFrame(cmd: $command, status: $status, data: ${_hex(data)})';
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join('');

/// Incremental parser that turns a byte stream (BLE notifications arrive in
/// arbitrary chunks) into complete [ChameleonFrame]s.
class FrameParser {
  final List<int> _buf = [];

  /// Feed received bytes; returns every complete, checksum-valid frame found.
  List<ChameleonFrame> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final frames = <ChameleonFrame>[];

    while (true) {
      // Resync to SOF.
      while (_buf.isNotEmpty && _buf[0] != ChameleonFrame.sof) {
        _buf.removeAt(0);
      }
      if (_buf.length < 9) break; // need full head

      // Validate SOF LRC.
      if (_buf[1] != ChameleonFrame.lrc(_buf, 0, 1)) {
        _buf.removeAt(0);
        continue;
      }
      // Validate head LRC.
      if (_buf[8] != ChameleonFrame.lrc(_buf, 0, 8)) {
        _buf.removeAt(0);
        continue;
      }

      final command = (_buf[2] << 8) | _buf[3];
      final status = (_buf[4] << 8) | _buf[5];
      final dataLen = (_buf[6] << 8) | _buf[7];
      final total = 9 + dataLen + 1;
      if (_buf.length < total) break; // wait for more bytes

      final dataLrc = _buf[9 + dataLen];
      if (dataLrc != ChameleonFrame.lrc(_buf, 0, 9 + dataLen)) {
        // Corrupt data checksum: drop SOF and resync.
        _buf.removeAt(0);
        continue;
      }

      final data = Uint8List.fromList(_buf.sublist(9, 9 + dataLen));
      frames.add(ChameleonFrame(command, status, data));
      _buf.removeRange(0, total);
    }
    return frames;
  }

  void reset() => _buf.clear();
}

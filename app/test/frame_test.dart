import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_tool/src/protocol/frame.dart';

void main() {
  group('LRC', () {
    test('lrc of SOF is 0xEF', () {
      expect(ChameleonFrame.lrc([0x11]), 0xEF);
    });
    test('sum including lrc is 0 mod 256', () {
      final bytes = [0x11, 0xEF, 0x03, 0xE8, 0x00, 0x00, 0x00, 0x00];
      final l = ChameleonFrame.lrc(bytes);
      final total = bytes.fold<int>(0, (a, b) => a + b) + l;
      expect(total & 0xFF, 0);
    });
  });

  group('encode', () {
    test('GET_APP_VERSION (cmd 1000) empty payload', () {
      final f = ChameleonFrame(1000, 0, Uint8List(0)).encode();
      // 0x11 0xEF | 03 E8 (1000) | 00 00 | 00 00 | headLRC | dataLRC
      expect(f.sublist(0, 8), [0x11, 0xEF, 0x03, 0xE8, 0x00, 0x00, 0x00, 0x00]);
      expect(f[8], 0x15); // head lrc
      expect(f[9], 0x00); // data lrc (no data)
      expect(f.length, 10);
    });

    test('roundtrip through parser', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final encoded = ChameleonFrame(2000, 0, data).encode();
      final parser = FrameParser();
      final frames = parser.feed(encoded);
      expect(frames.length, 1);
      expect(frames.first.command, 2000);
      expect(frames.first.status, 0);
      expect(frames.first.data, data);
    });

    test('parser reassembles across chunk boundaries', () {
      final encoded = ChameleonFrame(1002, 0, Uint8List.fromList([1])).encode();
      final parser = FrameParser();
      // Feed byte-by-byte.
      List<ChameleonFrame> out = [];
      for (final b in encoded) {
        out = parser.feed([b]);
      }
      expect(out.length, 1);
      expect(out.first.command, 1002);
      expect(out.first.data, [1]);
    });

    test('parser skips leading garbage then finds frame', () {
      final encoded = ChameleonFrame(1000, 0, Uint8List(0)).encode();
      final parser = FrameParser();
      final frames = parser.feed([0x00, 0xAB, 0xCD, ...encoded]);
      expect(frames.length, 1);
      expect(frames.first.command, 1000);
    });
  });
}

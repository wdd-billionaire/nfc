import 'dart:typed_data';

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

/// A single ISO14443-A tag as returned by HF14A_SCAN.
class Hf14aTag {
  final Uint8List uid;
  final Uint8List atqa;
  final Uint8List sak;
  final Uint8List ats;

  Hf14aTag({
    required this.uid,
    required this.atqa,
    required this.sak,
    required this.ats,
  });

  String get uidHex => _hex(uid);
  String get atqaHex => _hex(atqa);
  String get sakHex => _hex(sak);
  String get atsHex => _hex(ats);

  /// Rough guess of the card family from ATQA/SAK for display only.
  String get guessedType {
    final s = sak.isNotEmpty ? sak[0] : 0;
    if (s == 0x08 || s == 0x88) return 'MIFARE Classic 1K';
    if (s == 0x18) return 'MIFARE Classic 4K';
    if (s == 0x00) return 'MIFARE Ultralight / NTAG';
    if (s & 0x20 != 0) return 'ISO14443-4 (DESFire / smartcard)';
    return 'unknown';
  }

  @override
  String toString() =>
      'Hf14aTag(uid: $uidHex, atqa: $atqaHex, sak: $sakHex, ats: $atsHex)';
}

/// Firmware / hardware identity of the connected device.
class DeviceInfo {
  final String? gitVersion;
  final int? model;
  final int? mode; // DeviceMode.tag / DeviceMode.reader
  final int? batteryPercent;
  final int? batteryMv;
  final String? chipId;

  DeviceInfo({
    this.gitVersion,
    this.model,
    this.mode,
    this.batteryPercent,
    this.batteryMv,
    this.chipId,
  });

  DeviceInfo copyWith({
    String? gitVersion,
    int? model,
    int? mode,
    int? batteryPercent,
    int? batteryMv,
    String? chipId,
  }) =>
      DeviceInfo(
        gitVersion: gitVersion ?? this.gitVersion,
        model: model ?? this.model,
        mode: mode ?? this.mode,
        batteryPercent: batteryPercent ?? this.batteryPercent,
        batteryMv: batteryMv ?? this.batteryMv,
        chipId: chipId ?? this.chipId,
      );

  String get modeLabel => mode == 1 ? 'Reader' : (mode == 0 ? 'Emulator' : '?');
}

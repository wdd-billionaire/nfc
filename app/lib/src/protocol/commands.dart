/// Command and status codes for the ChameleonUltra protocol.
///
/// Values are taken verbatim from `chameleon_enum.py` in
/// RfidResearchGroup/ChameleonUltra. Only the subset used by this app is
/// listed; extend as features are added.
class Cmd {
  // --- device / system ---
  static const int getAppVersion = 1000;
  static const int changeDeviceMode = 1001;
  static const int getDeviceMode = 1002;
  static const int setActiveSlot = 1003;
  static const int setSlotTagType = 1004;
  static const int setSlotEnable = 1006;
  static const int getDeviceChipId = 1011;
  static const int getDeviceAddress = 1012;
  static const int getActiveSlot = 1018;
  static const int getSlotInfo = 1019;
  static const int getBatteryInfo = 1025;
  static const int getDeviceModel = 1033;

  // --- HF 14a / MIFARE Classic ---
  static const int hf14aScan = 2000;
  static const int mf1DetectSupport = 2001;
  static const int mf1DetectPrng = 2002;
  static const int mf1AuthOneKeyBlock = 2007;
  static const int mf1ReadOneBlock = 2008;
  static const int mf1WriteOneBlock = 2009;

  // --- LF / EM410x ---
  static const int em410xSetEmuId = 5000;
  static const int em410xGetEmuId = 5001;
}

/// Status codes returned in the frame `status` field.
class Status {
  static const int hfTagOk = 0x00;
  static const int hfTagNo = 0x01;
  static const int hfErrStat = 0x02;
  static const int hfErrCrc = 0x03;
  static const int hfCollision = 0x04;
  static const int hfErrBcc = 0x05;
  static const int mfErrAuth = 0x06;
  static const int hfErrParity = 0x07;
  static const int hfErrAts = 0x08;
  static const int lfTagOk = 0x40;
  static const int lfTagNoFound = 0x41;
  static const int parErr = 0x60;
  static const int deviceModeError = 0x66;
  static const int invalidCmd = 0x67;
  static const int success = 0x68;
  static const int notImplemented = 0x69;
  static const int flashWriteFail = 0x70;
  static const int flashReadFail = 0x71;
  static const int invalidSlotType = 0x72;

  static bool isOk(int s) => s == success || s == hfTagOk || s == lfTagOk;

  static String describe(int s) {
    switch (s) {
      case hfTagOk:
        return 'HF tag OK';
      case hfTagNo:
        return 'no HF tag found';
      case mfErrAuth:
        return 'MIFARE auth failed';
      case lfTagOk:
        return 'LF tag OK';
      case lfTagNoFound:
        return 'no LF tag found';
      case deviceModeError:
        return 'wrong device mode (switch reader/emulator mode)';
      case invalidCmd:
        return 'invalid command';
      case success:
        return 'success';
      case notImplemented:
        return 'not implemented';
      default:
        return 'status 0x${s.toRadixString(16)}';
    }
  }
}

/// Device operating mode byte for [Cmd.changeDeviceMode].
class DeviceMode {
  static const int tag = 0; // emulator
  static const int reader = 1;
}

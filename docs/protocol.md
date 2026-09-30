# ChameleonUltra protocol reference (as implemented here)

Source of truth: `RfidResearchGroup/ChameleonUltra` (`software/script/`,
`chameleon_com.py`, `chameleon_cmd.py`, `chameleon_enum.py`). This file records
the exact details this client depends on.

## Transport (BLE)

Nordic UART Service:

| Role | UUID |
|------|------|
| Service | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` |
| RX (central → device, write) | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |
| TX (device → central, notify) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |

Notifications arrive chunked; frames must be reassembled from the byte stream.
Request MTU 247 on Android and chunk writes to `mtu - 3`.

## Data frame

All integers big-endian. `lrc(x) = (0x100 - (sum(x) & 0xFF)) & 0xFF`.

```
offset  size  field
0       1     SOF        = 0x11
1       1     LRC1       = lrc([SOF]) = 0xEF
2       2     command    (u16)
4       2     status     (u16)
6       2     dataLength (u16)
8       1     LRC2       = lrc(bytes[0..8))     head checksum
9       N     data
9+N     1     LRC3       = lrc(bytes[0..9+N))   data checksum
```

`dataMaxLength = 4096`.

Worked example — `GET_APP_VERSION` (cmd 1000 = 0x03E8), empty payload:

```
11 EF 03 E8 00 00 00 00 15 00
```

(verified by `app/test/frame_test.dart` and an independent computation)

## Commands used

| Name | Value |
|------|------:|
| GET_APP_VERSION | 1000 |
| CHANGE_DEVICE_MODE | 1001 |
| GET_DEVICE_MODE | 1002 |
| SET_ACTIVE_SLOT | 1003 |
| SET_SLOT_TAG_TYPE | 1004 |
| SET_SLOT_ENABLE | 1006 |
| GET_DEVICE_CHIP_ID | 1011 |
| GET_ACTIVE_SLOT | 1018 |
| GET_SLOT_INFO | 1019 |
| GET_BATTERY_INFO | 1025 |
| GET_DEVICE_MODEL | 1033 |
| HF14A_SCAN | 2000 |
| MF1_DETECT_SUPPORT | 2001 |
| MF1_DETECT_PRNG | 2002 |
| MF1_AUTH_ONE_KEY_BLOCK | 2007 |
| MF1_READ_ONE_BLOCK | 2008 |
| MF1_WRITE_ONE_BLOCK | 2009 |
| EM410X_SET_EMU_ID | 5000 |
| EM410X_GET_EMU_ID | 5001 |

## Status codes

`HF_TAG_OK=0x00`, `HF_TAG_NO=0x01`, `MF_ERR_AUTH=0x06`, `LF_TAG_OK=0x40`,
`LF_TAG_NO_FOUND=0x41`, `DEVICE_MODE_ERROR=0x66`, `INVALID_CMD=0x67`,
`SUCCESS=0x68`, `NOT_IMPLEMENTED=0x69`.

## Selected payloads

- **CHANGE_DEVICE_MODE**: 1 byte — `1` = reader, `0` = tag/emulator.
- **GET_BATTERY_INFO** response: 2 bytes voltage (mV) + 1 byte percentage.
- **HF14A_SCAN** response: repeated records
  `uidLen(1) · uid(uidLen) · atqa(2) · sak(1) · atsLen(1) · ats(atsLen)`.
  Status `HF_TAG_NO` means no tag in field.

## Notes for the PM3 side (future)

In Proxmark3 mode the device carries the **PM3 serial protocol** over the same
BLE UART (or USB CDC). The engine is the GPL Iceman client (`libpm3.so` in the
stock app). Plan is to compile the PM3 client `libpm3` via the Android NDK and
drive it over the shared transport — see `roadmap.md`.

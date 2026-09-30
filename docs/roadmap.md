# Roadmap

## M0 — MVP (done / current)

- [x] APK analysis, protocol confirmation
- [x] ChameleonUltra frame codec + unit tests
- [x] BLE (Nordic UART) transport
- [x] Connect, device info, mode switch
- [x] HF14A scan (read UID/ATQA/SAK)

## M1 — MIFARE Classic (read / crack / write)

- [ ] `MF1_DETECT_SUPPORT` / `MF1_DETECT_PRNG` (nested vs hardnested viability)
- [ ] Key dictionary check via `MF1_AUTH_ONE_KEY_BLOCK`
- [ ] `MF1_READ_ONE_BLOCK` / `MF1_WRITE_ONE_BLOCK` full-dump read & write
- [ ] Dump import/export (mfd/eml/json), key management
- [ ] Detection/nonce collection → key recovery (mfkey32 / nested; hardnested is
      a PM3-side capability, see M4)

## M2 — Emulation & slots

- [ ] Slot list / active slot / enable-disable (`GET_SLOT_INFO`, `*_ACTIVE_SLOT`)
- [ ] Set slot tag type, write emulation data (`MF1_WRITE_EMU_BLOCK_DATA`)
- [ ] EM410x emulate (`EM410X_SET_EMU_ID`)

## M3 — LF (125 kHz)

- [ ] EM410x read, T5577 write (default password dictionary bundled in stock app)
- [ ] HID Prox read/emulate

## M4 — USB-serial transport + PM3 engine

- [ ] `usb-serial-for-android` implementation of `DeviceTransport`
- [ ] Cross-compile the GPL Proxmark3 (Iceman) client as `libpm3` via NDK; JNI bridge
- [ ] Route heavy attacks (hardnested, LF sniff) through the PM3 engine
- [ ] Firmware update: BLE OTA (Nordic DFU / custom `5151…` service) and USB/DFU

## Cross-cutting

- [ ] Robust reconnect / connection-state UI
- [ ] Sound/vibration feedback on read/write (parity with stock app)
- [ ] i18n (zh/en)
- [ ] Desktop build (flutter_blue_plus supports macOS/Windows/Linux BLE)

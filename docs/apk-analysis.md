# ProxMini.apk — static analysis

Source: `https://cdn.pm3sehub.com/ProxMini.apk`
SHA-256: `3c349e56031228a02a363e3806b6b7557cc0c5c3b148ad151760eaac26ecfb81`
Size: ~41 MB · 708 files

Analysis was **static only** (unzip + string inspection of the unpacked
archive). No dynamic execution, no unpacking of the protection layer, no attempt
to defeat licensing.

## What the app is

A **Flutter** Android client (vendor "PM3 SE Hub", `pm3sehub.com`) for an
RFID/NFC device that combines **Proxmark3 (RDV4-class)** and **Chameleon
(Mini/Ultra)** functionality, connectable over **USB or Bluetooth LE**, with
mode switching and BLE OTA firmware update.

### Evidence (native libs, `lib/arm64-v8a/`)

| File | Role |
|------|------|
| `libpm3.so` (~5 MB) | Proxmark3 client engine (GPL Iceman/RRG client compiled as a native lib) |
| `libmfkey32v2.so` | mfkey32 — recover MIFARE Classic keys from captured nonces |
| `libserialport.so` | serial I/O to the device over USB |
| `librecovery.so` | firmware recovery / flashing |
| `libtermux.so` | terminal backend |
| `libflutter.so`, `libapp.so` | Flutter runtime + AOT-compiled Dart app code |
| `assets/libjiagu*.so` | Qihoo 360 **Jiagu** packer (anti-reverse hardening) |

### Bundled assets

- `assets/flutter_assets/assets/firmware/bootrom.elf`, `fullimage.elf` — Proxmark3 firmware
- `assets/flutter_assets/assets/firmware/Chameleon-Mini-Update.bin` — Chameleon firmware
- `client/resources/hardnested_tables/bitflip_*_states.bin.lz4` — hardnested attack tables (MIFARE Classic)
- `client/dictionaries/t55xx_default_pwds.dic` — T5577 default password dictionary

### Transport / protocol (from `libapp.so` strings)

- BLE via **Nordic UART Service**: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
  (secondary custom service `51510001-…` also present, likely DFU/OTA)
- USB serial for the PM3 engine and firmware upgrade
- Explicit PM3 ⇄ Chameleon mode switching, BLE OTA and USB/DFU firmware update

## The "redundant" parts (all backend, off the hardware path)

Network calls to `https://api.pm3sehub.com`:

| Endpoint | Purpose |
|----------|---------|
| `customers/validate-login`, `change-password`, `update-username` | account system |
| `customers/public-key/rsa` | RSA key for the account/activation crypto |
| `activation-codes/activate` | device activation |
| `rebind-requests/submit`, `customers/self-rebind` | device↔account binding (limited `remainingRebind`) |
| `Announcement/Announcement`, `Announcement/Changelog` | in-app pop-ups |

Local state: `activation_info.json`, `saved_credentials.json`.

None of these touch the BLE/USB command path to the hardware. Reads, writes,
cracking and emulation are driven entirely by the ChameleonUltra command
protocol and the PM3 serial protocol — both open.

## Conclusion

The app's hardware capability is built on open projects (Proxmark3/Iceman +
ChameleonUltra), wrapped in a commercial account/activation shell and a Jiagu
packer. A clean client can reproduce the hardware features from the open
protocols alone, without the account/activation/pop-up layer — which is the
approach taken in this repo.

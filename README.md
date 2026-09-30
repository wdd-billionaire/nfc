# nfc — open BLE client for a ChameleonUltra/Proxmark3-class device

An open-source, clean-room mobile client for a custom NFC/RFID device that fuses
**Proxmark3** and **ChameleonUltra** functionality (mode-switchable), controlled
over **USB or Bluetooth LE**.

The goal is a client that keeps **full hardware functionality** (read / crack /
write / emulate, PM3 ⇄ Chameleon switching, OTA) while dropping the parts of the
vendor's stock app that get in the way — account registration, online
activation / device rebinding, and announcement pop-ups. None of those live on
the hardware control path, so removing them does not weaken device integration.

> This is a **re-implementation from published, open protocols**, not a patch or
> unpack of any vendor binary. The device speaks the standard **Nordic UART**
> BLE profile and the **ChameleonUltra** command protocol (both open); the
> Proxmark3 engine is the GPL Iceman client. See `docs/`.

## For contributors & AI agents

Start with **[`CLAUDE.md`](./CLAUDE.md)** (or [`AGENTS.md`](./AGENTS.md)) — it has
the requirements, architecture, build toolchain pins, and conventions. Detailed
status, next steps, and decisions are in [`docs/progress.md`](./docs/progress.md).

Prebuilt test APK (release, arm64, ~7MB, debug-signed, installable):
[`dist/nfc_tool-mvp-arm64.apk`](./dist/nfc_tool-mvp-arm64.apk).

## Status

MVP in progress. Working now (BLE path):

- BLE scan / connect over Nordic UART Service (`6e400001-…`)
- ChameleonUltra frame codec (verified against the reference implementation)
- Read device info: model, firmware, mode, battery
- Switch reader / emulator mode
- HF ISO14443-A scan → UID / ATQA / SAK / ATS

See `docs/roadmap.md` for what comes next (MIFARE Classic read/crack/write,
slot & emulation management, LF/EM410x, USB-serial transport, PM3 engine).

## Layout

```
app/                 Flutter application
  lib/src/protocol/  frame codec, command/status enums, high-level client
  lib/src/transport/ transport abstraction + BLE (Nordic UART) implementation
  lib/src/ui/        MVP UI
  test/              protocol unit tests
docs/                APK analysis, protocol reference, roadmap
```

## Build

Prerequisites: Flutter 3.19+ and a device with BLE. See `app/README.md` for the
one-time platform-scaffolding step and the exact Android/iOS permissions to add.

```bash
cd app
flutter create --platforms=android,ios --project-name nfc_tool .   # first time only
flutter pub get
flutter test          # protocol unit tests
flutter run           # on a real phone (BLE needs hardware)
```

## Legal / scope

For working with hardware and cards you own or are authorized to test
(access-control audits, CTF, research). The Proxmark3 client is GPL; anything
built on it and distributed must comply with the GPL.

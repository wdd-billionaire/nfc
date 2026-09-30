# CLAUDE.md — agent handoff & working guide

Entry point for any AI coding agent (or human) continuing this project. Read
this first, then `docs/`. Keep this file current when you change direction.

## What this project is

An open-source mobile client for a **custom NFC/RFID device that fuses
Proxmark3 (PM3) and ChameleonUltra (CU)** functionality, mode-switchable,
controlled over **Bluetooth LE and USB**. It replaces the vendor's stock app
("ProxMini", from pm3sehub.com) while keeping **full hardware functionality**.

The stock app bundles GPL open-source engines (Proxmark3/Iceman client,
ChameleonUltra protocol, mfkey32, hardnested tables) behind a commercial shell:
account registration, online activation / device rebinding, announcement
pop-ups, and a 360 Jiagu packer. The owner of the hardware wants those removed.
**None of that shell is on the hardware-control path**, so a clean re-implementation
from the open protocols keeps every device feature. See `docs/apk-analysis.md`.

Scope note: this is for use with hardware and cards the user owns or is
authorized to test (access-control audits, CTF, research). The Proxmark3 client
is GPL; anything built on it and distributed must comply with the GPL. Do **not**
unpack, patch, or bypass the vendor binary's protection — the whole approach is a
clean-room rebuild from published protocols, which is why no such step is needed.

## Requirements

Functional (preserve parity with the stock app's hardware features):
- Connect to the device over **BLE** (Nordic UART) and later **USB serial**.
- **Read** cards (HF ISO14443-A now; MIFARE Classic full dump next; LF/EM410x later).
- **Crack** MIFARE Classic keys (dictionary, nested/mfkey32; hardnested via PM3 engine).
- **Write** cards (MIFARE Classic blocks; T5577 LF later).
- **Emulate** (CU slots: set tag type, write emu data, EM410x; card slots管理).
- Switch **PM3 ⇄ Chameleon** mode; firmware **OTA** (BLE DFU / USB).

Non-functional / product:
- **No account, no activation, no device binding, no pop-ups, no packer.**
- Must not weaken device integration vs. the stock app.
- Cross-platform friendly (Flutter); Android is the first target.

## Architecture

```
app/lib/
  main.dart                     app entry
  src/protocol/
    frame.dart                  CU data-frame codec (encode + streaming parser) + LRC
    commands.dart               Cmd (command ids) + Status codes + DeviceMode
    models.dart                 Hf14aTag, DeviceInfo
    chameleon_client.dart       high-level client: send/await by cmd id, parse responses
  src/transport/
    transport.dart              DeviceTransport interface (transport-agnostic)
    ble_transport.dart          Nordic UART (flutter_blue_plus) implementation
  src/ui/
    home_page.dart              MVP screen: scan/connect, device info, mode, read HF
  test/frame_test.dart          protocol unit tests (LRC, encode, parse, resync)
docs/
  apk-analysis.md               static analysis of the stock ProxMini APK
  protocol.md                   exact CU frame format + command/status codes used
  roadmap.md                    milestones M0–M4
  progress.md                   detailed status, decisions, environment learnings
```

Design intent: the protocol layer is transport-agnostic. Adding USB later means
implementing `DeviceTransport` with `usb-serial-for-android`; the client and UI
stay unchanged. The heavy PM3 attacks (hardnested, LF sniff) will come from
compiling the GPL Proxmark3 client as `libpm3` (NDK) behind the same transport —
see roadmap M4.

## Current status (M0 MVP — done)

- CU data-frame codec, verified against the reference implementation + unit tests.
- BLE transport over Nordic UART (`6e400001-b5a3-f393-e0a9-e50e24dcca9e`),
  MTU negotiation, chunked writes, streaming frame reassembly.
- High-level client: device model/firmware/mode/battery, reader/emulator mode
  switch, HF14A scan → UID/ATQA/SAK/ATS.
- MVP single-screen UI.
- Builds to an installable APK (see below). `dist/nfc_tool-mvp-arm64.apk` is a
  prebuilt release/arm64 for quick testing.

**Not yet verified against real hardware.** First job for the next agent after
any change: confirm the connect → device info → reader mode → HF read path on the
physical device, and adjust response parsing if a field comes back malformed
(battery/version payload layout can vary by firmware).

Next milestones: `docs/roadmap.md` (M1 MIFARE Classic read/crack/write is the
priority — it's the core "解卡写卡" ask).

## Building (IMPORTANT — environment-specific)

The toolchain matters. These pins were established the hard way in a headless
cloud container; keep them unless you know your environment differs.

- **Flutter 3.24.x** (built and shipped with 3.24.5). **Newer Flutter (3.35.x,
  3.47.x) failed to build even a vanilla app** in that container with
  `MissingValueException: Cannot query the value of this provider` at Gradle
  task-graph time (reproduced across JDK 17/21, independent of app code). If your
  local Flutter is newer and builds fine, great — but then you must bump the
  pinned plugin versions (below), because those pins assume 3.24.x.
- **JDK 17** for the Android build (JDK 21 also reproduced the newer-Flutter bug;
  17 is the safe LTS).
- **Plugin pins** (in `pubspec.yaml`): `flutter_blue_plus: 1.32.12`,
  `permission_handler: 11.3.1`. These hardcode their Android `compileSdk` instead
  of relying on Flutter injecting `flutter.compileSdkVersion` into plugin
  projects (a mechanism 3.24.x lacks). On newer Flutter you can raise these.
- Android SDK: platform-tools, `platforms;android-34` (+35/36 fine), build-tools.
- If Maven Central returns **HTTP 429** through a proxy, use the Google-hosted
  mirror `https://maven-central.storage-download.googleapis.com/maven2/` (a
  global `~/.gradle/init.gradle` that rewrites `repo.maven.apache.org` URLs to it
  works well). Not needed on a normal network.

Platform folders (`app/android/`, etc.) are **git-ignored and regenerated**:

```bash
cd app
flutter create --platforms=android --project-name nfc_tool --org com.opennfc .
# then re-add BLE permissions to android/app/src/main/AndroidManifest.xml
#   (see app/README.md for the exact <uses-permission> block)
flutter pub get
flutter test                                  # protocol unit tests, no hardware
flutter build apk --release --target-platform android-arm64   # ~7MB, debug-signed
flutter run                                   # on a real phone (BLE needs hardware)
```

`app/README.md` has the exact manifest permissions and iOS notes.

## Conventions

- Keep the protocol layer transport-agnostic; never import Flutter/BLE types into
  `src/protocol/`.
- Command ids, status codes, and frame format come from
  `RfidResearchGroup/ChameleonUltra` — mirror it exactly and cite the source in
  `docs/protocol.md` when adding commands.
- Add a unit test in `test/` for every new codec/parse path.
- Commits: clear messages; do not commit build artifacts (only the one prebuilt
  APK under `dist/` is intentionally force-added for download convenience).

## Pointers

- Protocol details & exact byte layout: `docs/protocol.md`
- What the stock app is / evidence: `docs/apk-analysis.md`
- Milestones & next steps: `docs/roadmap.md`
- Detailed progress log & decisions: `docs/progress.md`

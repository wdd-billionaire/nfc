# Progress log & decisions

Living record of what's done, why, and what to do next. Newest context on top.

## ⚠️ Protocol correction (important)

Real-hardware testing revealed the target device's **Chameleon side speaks the
ChameleonMini RevG/RevH ASCII command protocol, NOT the ChameleonUltra binary
frame protocol** that `src/protocol/frame.dart` + `chameleon_client.dart`
implement. The device's BLE name is `ChameleonRevH`; the stock app uses RevG
commands (`CONFIG=ISO14443A_READER`, `GETUID`, `IDENTIFY`, `DUMP_MFU`,
`DETECTION?`, `LEDRED=`, the full `CONFIG` card-type list, …). That is why every
Ultra command timed out.

- **Chameleon mode = RevG ASCII** → implemented in `src/protocol/revg_client.dart`
  (line-based `CMD\r\n` → `CODE:TEXT` responses). This is what the UI now uses.
- **Switch to PM3 = send the `REBOOTPM3` command.** The device reboots into PM3
  mode and keeps the same BLE name (`ChameleonRevH`); it is one Nordic UART link
  that carries either protocol depending on mode.
- **PM3 mode = Proxmark3 serial protocol** (driven by the GPL Iceman client,
  `libpm3.so` in the stock app) — still to implement (roadmap M4).
- The Ultra code (`frame.dart`, `commands.dart`, `chameleon_client.dart`,
  `test/frame_test.dart`) is kept for reference / a possible future Ultra device,
  but is **not used** by this device.

## Status snapshot

| Milestone | State |
|-----------|-------|
| BLE scan + connect | **working on real hardware** (ChameleonRevH) |
| M0 MVP read (RevG ASCII) | **re-implemented after protocol correction; awaiting hardware retest** |
| M1 MIFARE Classic (read/crack/write) | not started (next priority) |
| M2 Emulation & slots | not started |
| M3 LF (125 kHz) | not started |
| M4 USB transport + PM3 engine + OTA | not started |

Prebuilt test binary: `dist/nfc_tool-mvp-arm64.apk` (release, arm64, ~7MB,
debug-signed, installable). Rebuild it after code changes.

## Immediate next steps (do these first)

1. **Hardware retest with the RevG client.** Connect → device info (VERSION?,
   CONFIG?, MEMSIZE?) should populate → "Reader mode" (CONFIG=ISO14443A_READER)
   → "Read card" (IDENTIFY + GETUID) with a card on the antenna. Read the `tx»`
   / `rx<=` and `CMD -> [code] status` lines in the Log to confirm the exact
   RevG response format, then tighten parsing in `revg_client.dart` /
   `home_page.dart` (UID/ATQA/SAK fields, MF detection, DUMP via XMODEM).
2. **M1 MIFARE Classic over RevG** (the core "解卡/写卡" ask). Likely path:
   `CONFIG=ISO14443A_READER` → `IDENTIFY` → `MF_DETECTION_1K/4K` /
   `DETECTION?` for nonce collection → key recovery → `DUMP`/`DUMP_MFU`
   (XMODEM download) for full read; emulate by setting a card `CONFIG=` and
   `UPLOAD` (XMODEM) of a dump. Implement XMODEM over the transport.
   (The old Ultra-based M1 plan below is kept only if a true Ultra device shows up.)
   - `MF1_DETECT_SUPPORT` (2001), `MF1_DETECT_PRNG` (2002) — check attack viability.
   - Key check via `MF1_AUTH_ONE_KEY_BLOCK` (2007) against a dictionary.
   - Full read via `MF1_READ_ONE_BLOCK` (2008); write via `MF1_WRITE_ONE_BLOCK` (2009).
   - Dump model + import/export (mfd/eml/json), key management UI.
   - Key recovery: mfkey32/nested. hardnested is a PM3-engine capability → M4.

## Decisions & rationale

- **Rebuild, not repack.** The stock app is GPL engines behind a commercial
  account/activation/pop-up shell + Jiagu packer. All hardware features come from
  open protocols (CU over Nordic UART; PM3 serial). Re-implementing from those is
  cleaner, legal, and doesn't touch the protected binary. See `apk-analysis.md`.
- **Flutter + BLE first, then USB.** Matches the stock app's stack; maximizes
  reuse; USB slots in behind the `DeviceTransport` interface later.
- **Protocol = ChameleonUltra (RfidResearchGroup/ChameleonUltra).** The device's
  BLE service is standard Nordic UART and it speaks the open CU protocol. Frame
  format and command/status ids are mirrored exactly in `docs/protocol.md` and
  `src/protocol/`, verified by an independent LRC computation and unit tests.

## Environment / build learnings (the painful part)

Building in the headless cloud container surfaced toolchain issues. Recorded so
the next agent doesn't repeat the dig:

- **Newer Flutter (3.35.x, 3.47.x) could not build even a vanilla app** here:
  `MissingValueException: Cannot query the value of this provider because it has
  no value available` on `:app:compileDebugJavaWithJavac` at Gradle task-graph
  time. Reproduced with AGP 8.11.1/Gradle 8.14.3 and AGP 9.1.0/Gradle 9.3.1, on
  JDK 17 and 21, with a fresh `flutter create` (no project code). Root cause is in
  the Flutter Gradle plugin's `project.files({ packJniLibs })` dependency in that
  environment — not our code.
- **Flutter 3.24.5 builds cleanly** (vanilla and this app) → that's the pinned
  toolchain. If a future environment builds newer Flutter fine, migrating up is
  welcome; then raise the plugin pins.
- **JDK 17** used for the Android build. Do **not** `unset JAVA_TOOL_OPTIONS` in a
  proxied environment — it carries the TLS truststore; without it the Gradle
  wrapper download fails with PKIX errors.
- **Plugin pins** `flutter_blue_plus 1.32.12` / `permission_handler 11.3.1`:
  newer versions expect Flutter to inject `flutter.compileSdkVersion` into plugin
  projects, which 3.24.x doesn't do ("Could not get unknown property 'flutter'").
  The pinned versions hardcode `compileSdk`.
- **Maven Central 429** through the proxy → Google mirror
  `maven-central.storage-download.googleapis.com/maven2/` via a `~/.gradle/init.gradle`
  that rewrites `repo.maven.apache.org` URLs. Only needed under rate-limiting.
- NDK r27/r28 have no `platforms/` dir (normal since r23); the `CXX5101` warning
  about it is benign.

## Verification done

- `flutter test` — 6/6 protocol tests pass (LRC, encode, roundtrip, chunk
  reassembly, garbage resync).
- `flutter build apk` — debug (all ABIs, ~82MB) and release/arm64 (~7MB) both
  build successfully with the pinned toolchain.
- Independent check: `GET_APP_VERSION` encodes to `11 EF 03 E8 00 00 00 00 15 00`,
  matching the reference.

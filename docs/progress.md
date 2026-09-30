# Progress log & decisions

Living record of what's done, why, and what to do next. Newest context on top.

## Status snapshot

| Milestone | State |
|-----------|-------|
| M0 MVP (BLE connect, device info, mode switch, HF14A read) | **code complete, builds, NOT yet hardware-verified** |
| M1 MIFARE Classic (read/crack/write) | not started (next priority) |
| M2 Emulation & slots | not started |
| M3 LF (125 kHz) | not started |
| M4 USB transport + PM3 engine + OTA | not started |

Prebuilt test binary: `dist/nfc_tool-mvp-arm64.apk` (release, arm64, ~7MB,
debug-signed, installable). Rebuild it after code changes.

## Immediate next steps (do these first)

1. **Hardware smoke test.** Install the APK, connect to the real device over BLE,
   confirm: scan finds it → connects → device info populates (model/firmware/
   mode/battery) → "Reader mode" → "Read HF" returns a card's UID/ATQA/SAK.
   If any field is wrong, fix the parsing in `chameleon_client.dart`:
   - `getBattery()` assumes `[voltage_hi, voltage_lo, percent]`; confirm layout.
   - `getGitVersion()`/`getDeviceModel()` return raw bytes; map to real strings
     once the device's actual responses are known.
2. **M1 MIFARE Classic** (the core "解卡/写卡" ask). Implement, in order:
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

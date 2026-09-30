# nfc_tool (Flutter app)

BLE client MVP. The `lib/`, `test/`, `pubspec.yaml` are checked in; the
platform folders (`android/`, `ios/`, …) are generated locally so they are not
committed.

## First-time setup

```bash
cd app
flutter create --platforms=android,ios --project-name nfc_tool .
flutter pub get
```

`flutter create` will not overwrite existing `lib/main.dart` / `pubspec.yaml`.

### Android permissions

Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>` (above
`<application>`):

```xml
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Android 11 and below -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

Set `minSdkVersion 21` (or higher) in `android/app/build.gradle`.

### iOS permissions

Add to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect to your NFC/RFID device over Bluetooth.</string>
```

## Run

```bash
flutter test     # protocol unit tests (no hardware needed)
flutter run      # deploy to a real phone; BLE does not work on emulators
```

## Using it

1. Tap **Scan**, pick your device (advertises the Nordic UART service).
2. On connect it reads model / firmware / mode / battery.
3. Tap **Reader mode**, then the **Read HF** button to scan an ISO14443-A card.

No account, no activation, no pop-ups.

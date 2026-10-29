# Delivery report

## Completed

- Inspected the supplied AILink APKs, recorded sizes and SHA-256 hashes, and
  preserved the originals.
- Decompiled/inspected the Flutter app, 15 DEX files, manifest, resources and
  native libraries. Created `analysis/jadx/` without modifying the APKs.
- Identified the AILink BLE transport (service `FFE0`, characteristics
  `FFE1/FFE2/FFE3`, CCCD `2902`) and the A6/A7 frame formats with checksums from
  `com.pingwang.bluetoothlib`.
- Identified two scale families in the APK: the CID 86 weight-only scale and
  the CID 19/50/82/104 eight-electrode scale, including weight field layout,
  unit codes, completion states and transmitted body-composition subtypes.
- Distinguished transmitted body composition from AILink's local Holtek SDK
  calculation. The replacement only stores transmitted values.
- Implemented the LingYang `F0A0` / CID `0x16` broadcast decoder (TEA, flags,
  weight, impedance, status) after cross-checking `anxkhn/localscale` and a
  live LYE idle frame. Tap **Listen** instead of connecting; GATT is not used.
- Documented AILink cloud endpoints found through static strings and TLS SNI
  inspection of the captures, and excluded all of them from the replacement.
- Built a Flutter/Riverpod app with a platform-independent BLE interface,
  pure-Dart protocol decoders, SQLite storage, all requested screens,
  diagnostics with redacted logs, CSV export and local-only settings.
- Added household profiles (schema v3) with per-profile measurement history,
  optional height/sex/birth year for local estimates, and a shareable PNG
  summary card through the system share sheet.
- Added automatic attachment to a supported broadcast scale on launch/resume,
  continuous foreground listening across weigh-ins, and a live weight/save card
  on the dashboard.
- Added a Bluetooth-off notice with an Android turn-on prompt, hid BLE controls
  until the adapter is usable, and made idle 0.00 kg / intermediate broadcast
  values visible without saving them.
- Added a weight-change indicator (up/down/flat, delta in the display unit,
  previous value and date) to live, details, latest and history views.
- Added Android 12+ BLE permissions only; removed transitive location
  permissions with manifest-merger rules. The release manifest has no
  `INTERNET` permission.
- Added iOS Bluetooth usage descriptions and documented the untested iOS /
  background-BLE limitations.
- Added 103 automated tests and synthetic fixtures, plus docs, AGENTS.md and
  build instructions.
- Built debug and release APKs, installed them on the connected Samsung
  devices (SM-S938B and SM-M346B), and confirmed the app launches without a
  crash.
- Renamed the app to **Scale** (`com.aniruth.scale`), renamed the Dart package
  to `scale`, and replaced the Flutter template icon with a generated scale
  icon (legacy, adaptive and iOS sets).

## Test results

| Check | Result |
|---|---|
| `dart format lib test` | clean |
| `flutter analyze` | No issues found |
| `flutter test` | 103 passed |
| Debug APK | built (`dist/ailink_scale-debug.apk`) |
| Release APK | built (`dist/ailink_scale-release-debugkey.apk`) |
| Release permissions | `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` only (plus AndroidX dynamic receiver permission) |
| Device install | Success |
| App launch | Process started; no FATAL/Flutter error in logcat |

## Known limitations

- **Partial hardware verification.** The user reported that the broadcast
  scale's weight matched the app display. Body-composition estimates and range
  labels have not been compared with AILink, and no independent capture was
  recorded. The protocol remains code-derived for the other families.
- **The nearby scale is a broadcast scale.** `LYE` advertises the AILink `F0A0`
  service with Ling Yang CID 22 manufacturer data. GATT connection attempts
  time out, which is expected for a broadcast-only scale. The replacement now
  listens to the advertisements, decrypts the LingYang TEA payload, and saves
  weight + impedance; no GATT connection is attempted. This still needs a real
  weigh-in comparison with the scale display.
- Body composition for the broadcast scale is **estimated locally** from weight
  + impedance with the open Jinghuawei/Aicare formulas, using the local profile
  (height, sex, birth year). It is labelled estimated, not transmitted. If the
  profile is incomplete, only weight/impedance are stored.
- The phone was locked, so BLE scan, connection, permission dialogs and a live
  measurement could not be exercised. No runtime network capture was possible.
- Encrypted A7/handshake devices are not supported. AILink license keys are
  deliberately not reused.
- The body-composition field mapping is from AILink UI code, not a vendor
  specification; some field units remain hypotheses.
- The app does not calculate body composition for GATT scales. If the scale
  does not transmit it, it is omitted. The LingYang broadcast estimate is the
  only exception.
- Range labels (BMI, body fat, water, muscle, visceral fat, BMR, body age,
  obesity index and so on) are local WHO/ACE/BIA reference bands. They never
  change a stored value and are not medical advice.
- Background BLE is not implemented. The continuous scan runs only in the
  foreground and uses more battery than a one-shot scan. iOS has not been
  built or tested.
- The database is app-private but not encrypted at rest.
- Sharing a measurement image or CSV hands the profile name, weight and body
  composition to whichever app you select in the system share sheet.
- Schema v3 migrates the old single profile into one named "Me". Old app data
  is preserved; if the device data was cleared, create the profile again.
- The APKs are signed with the Flutter debug key; they are test builds, not
  production releases.

## Remaining hardware tests

1. Unlock the phone and grant Nearby devices permission.
2. Scan, identify and connect the physical scale; record its advertised name,
   service UUIDs and GATT properties.
3. Weigh a known object/person; compare decoded weight in kg, lb and st:lb with
   the scale display.
4. Capture a full live → stable → complete sequence and confirm the save/dedup
   behavior.
5. If body composition is displayed, compare every value with AILink for the
   same measurement; otherwise record it as not transmitted.
6. Test disconnect/reconnect, sleep, out-of-range and repeated weigh-ins.
7. Record the result in Settings → Hardware verification and update
   `docs/ble-protocol.md` with redacted/synthetic evidence.

Until these steps pass, the app is a software-tested diagnostic replacement,
not a verified working scale replacement.








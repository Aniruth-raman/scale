# AILink APK analysis

Status: static analysis complete for the shipped artifacts in this workspace.
Hardware verification of any scale protocol is **not** complete.

This document records what was inspected, what is confirmed by code, and what
remains a hypothesis. It intentionally contains no credentials, tokens,
account identifiers or real measurement values.

## 1. Artifacts and hashes

| Artifact | Size (bytes) | SHA-256 |
|---|---:|---|
| `base.apk` | 142,432,166 | `CBF5E5641CD97AD97972F9DB30C70F3201140E2F69012C8A6398D8ED6D93CD32` |
| `split_config.arm64_v8a.apk` | 32,920,983 | `9A9FA088C25079794D2B868E854D51B5267020C2FA345FB6853913A14AE9F77A` |
| `split_config.xxhdpi.apk` | 18,723,661 | `775EBAF25CA9373E1C0C75C484FB9A71CD0E2B3859496FA7704BF2FCE243A691` |

The original APKs were not modified. Android application identity from the
manifest:

- Package: `com.pingwang.elink`
- Version name: `2.10.00`
- Version code: `2100080`
- `minSdkVersion`: 24
- `targetSdkVersion`: 36
- `compileSdkVersion`: 36
- Build metadata: Flutter release app (AOT `libapp.so`), 15 DEX files

## 2. Environment and tools

| Tool | Version / location | Notes |
|---|---|---|
| Flutter | 3.47.8 stable, `%USERPROFILE%\flutter` | Not on `PATH` originally |
| Dart | 3.13.7 | Bundled with Flutter |
| Java | Temurin 25.0.4.1 LTS | `JAVA_HOME` set |
| Android SDK | `%USERPROFILE%\android-sdk` | Platforms 34/35/36/37; build-tools 34/36/37 |
| Gradle | 9.3.1 | Wrapper |
| Android Gradle Plugin | 9.1.0 | From `android/settings.gradle.kts` |
| Apktool | 3.0.3 | Used for the existing `decoded/` tree; not on `PATH` |
| JADX | 1.5.1 | Downloaded to `tools/jadx` for this analysis |
| Python | 3.12.10 | Analysis scripts in `tools/` |
| Node.js | 24.22.1 | Existing PCAP helper scripts |
| Connected device | Samsung SM-S938B, Android 17 / API 37 | Locked during this run |

Missing or unavailable: Xcode/iOS build toolchain (Windows host), a BLE
scanner outside the app, and an unlocked phone for UI/BLE testing.

## 3. APK contents relevant to the replacement

### Flutter UI

The app is a multi-module Flutter application. Strings in `libapp.so` and
`decoded/assets/flutter_assets/` identify feature packages including:

- `ailink_feature_eight_scales_0013`
- `ailink_feature_four_body_fat_scale`
- `ailink_feature_nutrition_scale`
- `ailink_feature_core`

The Dart code is AOT compiled; there is no Dart source in the APK. The
replacement does not reuse any Dart code.

### Native libraries

The arm64 split contains, among others:

- `libflutter.so`, `libapp.so` — Flutter engine and AOT app
- `libAILinkBle-lib.so` — thin/native BLE helper
- `libBodyfat_SDK.so` — Holtek body-fat SDK native library
- `libalgorithm-lib.so`, `libsqlite3.so`, `libBugly_Native.so`,
  `libtnet-3.1.14.so`

The replacement does not load or link these libraries.

### BLE stack in Java/Kotlin

Relevant decompiled packages:

- `com.pingwang.bluetoothlib` — A6/A7 framing, UUID constants, GATT plumbing,
  scan handling, optional handshake/encryption
- `com.elinkthings.modulebleweightscale` — CID 86 weight-only scale
- `cn.net.aicare.modulebodyfatscale` — CID 14/94/118 four-electrode body-fat
  scale; weight is decoded, local body-fat calculation is not reused
- `aicare.net.eightscale` — eight-electrode scale, CID 19/50/82/104
- `com.pingwang.modulebase.utils` — unit conversion helpers

JADX output is in `analysis/jadx/sources/`. The original DEX files remain in
`raw/` and `decoded/`.

## 4. Manifest and permissions in AILink

The original manifest requests a broad capability set, including:

- BLE: `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_SCAN`,
  `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`
- Network: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
  `CHANGE_WIFI_MULTICAST_STATE`
- Location: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- Storage, phone state, notifications, overlay, foreground service
- Android Health Connect write permissions
- Calendar, phone-call and alarm permissions
- Third-party push/analytics components

None of these are inherited by the replacement. The replacement's release
manifest is documented in `docs/privacy.md` and contains only the Android 12+
nearby-device permissions.

## 5. BLE protocol evidence

Full framing, UUIDs, payload layouts and confidence levels are in
`docs/ble-protocol.md`. The key static evidence:

| Claim | Evidence |
|---|---|
| AILink service `FFE0`, write `FFE1`, notify `FFE2`, write/notify `FFE3` | `com/pingwang/bluetoothlib/config/BleConfig.java:21-24` |
| AILink subscribes to `FFE3` and `FFE2`, CCCD enabled | `BleDevice.java:491-492`, `BleDevice.java:520-545` |
| A6 framing `A6 len payload sum 6A` | `AiLinkBleCheckUtil.java:38-50` |
| A7 framing `A7 cidHi cidLo len payload sum 7A` | `AiLinkBleCheckUtil.java:56-78` |
| Checksum sums bytes after start up to the checksum | `AiLinkBleCheckUtil.java:80-156` |
| Weight-only CID = 86 | `WeightScaleDevice.java:5` |
| Weight scale live/stable/complete message types 1/2/10 | `WeightScaleDevice.java:134-219` |
| Eight-scale CIDs 19/50/82/104 | `EightBodyFatBleDeviceData.java:5-8` |
| 24-bit BE weight + decimal/unit nibble | `EightBodyFatBleDeviceData.java:980-1034` |
| Unit codes 0 kg, 1 jin, 4 st:lb, 6 lb | `WeightScaleConfig.java`; `UnitUtil.weightUnitToString`; `UnitUtils.fgToKG` |
| Optional A7 encryption / handshake | `BleDevice.java:267-298`, `AiLinkBleCheckUtil.java:310-360` |

The checksum and field layouts are confirmed **in decompiled code**. They are
not yet confirmed against the physical scale.

### Scan behaviour

AILink starts scans filtered by the AILink broadcast service UUIDs (for
example `FFE0` and `F0A0`) in its feature activities. The replacement scans
unfiltered so a scale that does not advertise a service UUID is not hidden.
No scan filter is invented.

AILink also parses advertisement manufacturer data for CID/VID/PID/MAC
(`BleValueBean.java`). The replacement does not depend on that layout; device
identity comes from the selected BLE device and the A7 CID.

## 6. Body composition: transmitted vs calculated

There are two distinct mechanisms in AILink:

1. **Eight-electrode scale family** — the MCU sends computed body-composition
   metrics in an A7 payload with state `9` and subtype `1..4` (single MCU) or
   `1..9` (dual MCU). The mapping is in
   `EightBodyFatScaleMainActivity.java:1109-1240`. This is transmitted data.
2. **Other body-fat modules** — the app includes `libBodyfat_SDK.so` and calls
   `com.holtek.libHTBodyfat` from `ArithmeticUtils` to calculate metrics from
   weight, impedance and user data. That is a local/proprietary calculation.
   The four-electrode CID 14/94/118 module's type-9 body-fat payload is tied to
   this path; the replacement does not decode those fields.

The replacement stores transmitted metrics where the scale provides them. It
does not link or call the Holtek SDK. For the LingYang broadcast scale it can
additionally estimate body composition from weight + impedance with the open
Jinghuawei/Aicare formulas, using the local profile; those values are marked
estimated, not transmitted. For the weight-only CID 86 family, no
body-composition field was found; the UI therefore omits those fields. For
CID 14/94/118, only weight is decoded.

The user's exact scale model is not known from static analysis. It may be the
CID 86 weight scale or one of the eight-electrode variants. This is the main
hardware blocker.

## 7. Network data flows and what must be excluded

The local captures (`ailink2.pcap`, `ailink4.pcap`, `ailink5.pcap`, not
committed) contain mixed device traffic. TLS SNI extraction found AILink-related
hosts including:

- `ailink.aicare.net.cn`
- `res.aicare.net.cn`
- `app.api.elinkthings.com`

Static strings also reference:

- `http://ailink.aicare.net.cn/`
- `http://ailink.h5.aicare.net.cn`
- `http://ga.app.api.elinkthings.com/`
- `http://fitcloud.hetangsmart.com/public/checkVersion`

The captures also contain unrelated system and third-party traffic (Google,
Microsoft, Facebook, AdGuard, push services, etc.), so host counts are not
attribution to AILink. No tokens, credentials, account data or personal data
are reproduced here.

Excluded from the replacement:

- All AILink/Elink cloud endpoints and APIs
- Account/login, device binding, cloud history and synchronization
- Push, analytics, crash-reporting and advertising SDKs
- Any AILink keys, license tables or encrypted cloud payloads
- AILink's network stack and native libraries

The replacement has no Internet permission in its release manifest, no
networking dependency, and no application-initiated upload.

## 8. Uncertainties

- Which of the three protocol families the physical scale uses.
- Actual GATT properties and whether the scale advertises `FFE0`.
- Whether the scale requires the A6 handshake or A7 AES encryption; the
  replacement does not implement either.
- Exact semantics/units of some body-composition fields (the field mapping is
  from UI code, not from a vendor specification).
- Whether the device reports negative or infant weights in normal mode.
- Whether the scale sends completion before or after body composition.
- Advertisement manufacturer-data layout beyond what `BleValueBean` shows.

## 9. Proposed hardware experiments

1. Install the release APK (`dist/` or `build/app/outputs/flutter-apk/`) on the
   Android phone; grant Nearby devices permission; scan and record the scale's
   advertised name, service UUIDs and RSSI.
2. Connect and dump the GATT tree; confirm `FFE0/FFE1/FFE2/FFE3` and actual
   properties/CCCD.
3. Step on the scale at a known weight; capture raw notifications in
   Diagnostics. Compare the decoded value with the scale display.
4. Repeat in kg, lb and st:lb if the scale can switch units. Record exact
   payloads and unit/decimal nibbles.
5. Measure the live → stable → complete sequence. Confirm which message is the
   completion signal and whether duplicates appear.
6. If body composition is shown, compare each app value with AILink for the
   same measurement. If no state-9 payload appears, record body composition as
   not transmitted for that scale.
7. Test disconnect/reconnect, out-of-range, scale sleep and repeated
   measurements. Confirm no transient notification is saved twice.
8. Record the result under Settings → Hardware verification only after the
   comparison succeeds. Update this document and `docs/ble-protocol.md`.

## 10. Reproduction notes

- Decoded resources/manifest: `decoded/` (Apktool 3.0.3 output).
- JADX sources: `analysis/jadx/sources/` (JADX 1.5.1).
- DEX originals: `raw/base_classes*.dex`.
- Native originals: `raw/split_config.arm64_v8a_*.so`.
- Packet captures and helper scripts: workspace root and `tools/`.
- The replacement app source is under `lib/`; tests are under `test/`.

Static analysis was performed on the user's own APK using local tools only.
No AILink cloud service was contacted as part of this analysis.

The LingYang broadcast frame/decrypt implementation was cross-checked against
the MIT-licensed `anxkhn/localscale` project and its protocol notes
(`docs/architecture.md`). The key constant is a local BLE protocol constant
from Elink's published SDK; the replacement does not bundle the Elink native
library.


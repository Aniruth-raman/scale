# AGENTS.md

Durable instructions for this repository.

## Mission

Maintain a privacy-first Flutter replacement for the AILink Android app
(`com.pingwang.elink`) for a BLE scale. The app must read the scale locally,
store data locally, and never contact AILink or another cloud service.

## Non-negotiable rules

1. **Never fabricate protocol details.** Do not invent UUIDs, characteristic
   properties, packet layouts, scaling factors, units, checksums or init
   sequences. Every decoder field must point to APK evidence or a hardware
   capture.
2. **Separate evidence levels.** Label findings as confirmed in decompiled
   code, hypothesis, or unverified on hardware. A code-derived protocol is not
   a hardware-verified protocol.
3. **Preserve original evidence.** Never modify, delete or overwrite
   `base.apk`, the split APKs, `raw/`, `decoded/`, `analysis/`, pcaps or
   `docs/`. Add new analysis output in a separate directory.
4. **No AILink cloud reuse.** Do not copy AILink cloud endpoints, tokens or
   account credentials, and do not add AILink network integration. The local
   LingYang broadcast TEA constant is implemented for offline interoperability
   and documented in `docs/ble-protocol.md`; do not expand that exception to
   cloud/account crypto or other AILink native SDKs.
5. **Privacy.** No accounts, ads, analytics, telemetry, crash reporting or
   cloud sync. Do not add `INTERNET` to the release manifest. Do not add a
   permission without documenting why and verifying the merged manifest. BLE
   listening stays foreground-only; do not add a background scan or foreground
   service without documenting the battery and privacy trade-off.
6. **Local data.** Measurements stay in the app-private SQLite database.
   CSV export and the shareable measurement image are user-initiated through
   the system share sheet. No automatic backup or upload.
7. **Do not claim hardware success.** Until a real measurement has been
   compared with the physical scale, describe the app as software-tested only.
   The Hardware verification setting is a user attestation, not automatic
   proof.
8. **No personal data in fixtures.** Use synthetic values (e.g. 70.00 kg) and
   redacted device identifiers. Never commit a real measurement, MAC address,
   name or account data.

## Architecture boundaries

- `lib/core/` — units, formatting and shared primitives. No BLE/database imports.
- `lib/domain/` — measurement models, repository interfaces, session rules,
  settings and household profiles. Pure Dart where possible.
- `lib/data/protocol/` — frame parser, LingYang broadcast decoder and TEA.
  Pure Dart; never import Flutter, BLE plugins or SQLite.
- `lib/data/ble/` — platform-independent BLE interface plus the Flutter
  Reactive BLE adapter. No widget imports.
- `lib/data/database/` — SQLite schema, migrations, repositories.
- `lib/features/` — UI and Riverpod controllers. Do not put packet parsing in
  widgets.
- `test/` — unit, database and integration tests. Protocol tests use synthetic
  frames.

Do not collapse these layers for convenience. A future iOS CoreBluetooth
adapter must be implementable behind `BleTransport` without changing the
decoder or database.

## Measurement rules

- Live notifications update the UI but are never auto-saved.
- A completion signal is the only automatic save trigger:
  - CID 86: message type 10, using the preceding stable type 2 reading.
  - CID 14/94/118: message type 10, using the preceding stable type 2 result.
  - Eight-scale: state 15 (CID 19/50), using the most recent state 1 weight.
    CID 82/104 state 15 is a dual-MCU test-complete event, not a measurement.
  - LingYang broadcast (CID 0x16 / F0A0): status 0xFF, using the last stable
    advertisement reading. Never call `connectGatt` for an F0A0-only scale.
- A completion with no recent usable reading (30 s) is ignored.
- Live packets during the 3-second stable hold are ignored; this mirrors
  AILink and prevents a stable value from being overwritten by jitter. A zero
  or sub-5 kg broadcast frame may be displayed so the scale looks responsive,
  but it is never saved or fed into the measurement session.
- A 700 ms grace period after completion lets late body-composition frames
  attach to the same cycle. Body-composition frames with no active reading are
  ignored, never carried into the next measurement.
- Manual saves are explicit and stored with `status = manual`.
- Deduplicate same source/weight (±0.02 kg) within 15 s.
- Store kilograms as the normalized value; keep the original value/unit for
  audit. Convert only at display time.
- Every saved measurement belongs to the active household profile. Save the
  profile id at write time; never move a measurement between profiles later.
  Deduplicate and list measurements per profile.
- Body-composition fields are stored only when the scale transmits them, or
  (for the LingYang broadcast family) when the open Jinghuawei formula can be
  applied to weight + impedance with a complete local profile. Estimated values
  must set `bodyCompositionEstimated = true` and be labelled estimated; never
  mix them with transmitted values.

## Protocol changes

When adding or changing a decoder:

1. Add the evidence reference (file path + line or capture file + packet).
2. Update `docs/ble-protocol.md` confidence table.
3. Add synthetic fixture bytes and tests for valid, invalid and boundary cases.
4. Keep unknown/unsupported fields as unknown; do not guess.
5. Run `flutter analyze` and `flutter test`.
6. Update `docs/build-and-test.md` if the result or limitation changes.

## Commands

```powershell
$env:ANDROID_HOME="$env:USERPROFILE\android-sdk"
& "$env:USERPROFILE\flutter\bin\dart.bat" format lib test
& "$env:USERPROFILE\flutter\bin\flutter.bat" analyze
& "$env:USERPROFILE\flutter\bin\flutter.bat" test
& "$env:USERPROFILE\flutter\bin\flutter.bat" build apk --debug
& "$env:USERPROFILE\flutter\bin\flutter.bat" build apk --release
```

After a dependency or manifest change, verify:

```powershell
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

The release manifest must contain only `BLUETOOTH_SCAN` and
`BLUETOOTH_CONNECT` (plus AndroidX's dynamic-receiver permission). Debug builds
contain `INTERNET` for Flutter tooling; never use them for privacy claims.

## Dependency policy

- Prefer the standard library or an existing dependency.
- Review the license. `flutter_blue_plus` is not used because its license
  requires a commercial license for for-profit use; `flutter_reactive_ble`
  (BSD-3-Clause) is the selected adapter.
- Adding a dependency requires checking its merged Android manifest and any
  transitive permissions.
- Do not add a package that performs networking, analytics or cloud storage.

## Documentation

Keep these current:

- `docs/apk-analysis.md` — artifact hashes, environment, APK findings.
- `docs/ble-protocol.md` — UUIDs, frames, fields, confidence, unknowns.
- `docs/privacy.md` — data, permissions, verification, limits.
- `docs/build-and-test.md` — actual commands and results.
- `README.md` — short overview and status.

No credentials, tokens, account identifiers or real measurement data in docs.

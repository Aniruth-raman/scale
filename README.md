# Scale

A privacy-first Flutter replacement for the AILink Android app
(`com.pingwang.elink`) for a BLE weighing scale. It reads measurements from the
scale, stores them in a local SQLite database and never sends them to AILink or
another cloud service. Application id: `com.aniruth.scale`.

**Status: software-tested; weight confirmed by the user, body composition not
yet compared with AILink.** The AILink-compatible protocol was derived from the
supplied APK. The user reported that the displayed weight matched the physical
scale. Body-composition estimates, range labels and the remaining protocol
families still need hardware comparison; record any test in Settings → Hardware
verification.

## What is implemented

- BLE scan, connect, GATT inspection, notification logging and disconnect
- AILink A6/A7 frame parsing with checksum validation and split-frame reassembly
- Weight-only decoder (CID 86), four-electrode weight decoder (CID 14/94/118)
  and eight-electrode decoder (CID 19/50/82/104)
- LingYang `F0A0` / CID `0x16` broadcast decoder (weight + impedance, no GATT
  connection), using the published local protocol constant
- Explicit live vs stable vs completion handling; transient readings are not saved
- Optional body-composition fields only when transmitted by the scale
- Household profiles: each family member has their own name, optional height,
  sex and birth year, and their own measurement history
- Weight comparison against the previous saved reading (arrow, delta in the
  display unit, previous value and date) on live, details and history views
- Local SQLite storage with versioned schema, deletion and deduplication
- kg / lb / st:lb display; storage always in kg
- Dashboard, connect, live measurement, details, history, trends, profiles,
  settings and diagnostics screens
- CSV export and a shareable measurement image through the system share sheet
  (user-initiated)
- No Internet permission in the release manifest; no analytics or cloud code

## Screens

| Screen | Purpose |
|---|---|
| Dashboard | live weight, save button, connection status, latest saved measurement, privacy note |
| Connect scale | unfiltered scan, device selection, permission/GATT errors |
| Live measurement | live weight, stability, body composition, manual save |
| Measurement details | stored values, range labels and share-as-image |
| History | active profile's search, details, delete |
| Trends | weight and available body-composition metrics for the active profile |
| Profiles | add, edit, switch and delete household members |
| Settings | units, profiles, privacy, CSV export, delete-all, hardware verification note |
| Diagnostics | GATT tree, redacted packet log, A6 version probe |

## Listening and saving

- If Bluetooth is off, the dashboard hides the connect/live controls and shows
  a **Turn on Bluetooth** button that opens Android's own prompt, then re-arms
  the scan automatically. Nothing is enabled silently.
- On launch (and when the app returns to the foreground) the app starts a scan
  and **attaches to the first supported broadcast scale automatically**. You do
  not need to pick `LYE` each time or press Listen.
- The scan stays on while the app is open, so the next weigh-in appears without
  stopping and starting anything. After a save the weight stays on screen and
  the Save button disables until the scale starts a new weigh-in.
- The live view follows the scale's changing values, including an idle
  `0.00 kg`. Only readings from 5 kg to 250 kg are saveable; a zero or
  under-range frame is shown but never stored.
- The live weight, saved measurement and history rows show whether the reading
  went **up or down** against the previous saved reading, with the delta in the
  selected unit and the previous value/date.
- The dashboard shows the live weight, the active profile, key body-composition
  values and a Save button. Tap the card for the full report.
- Tap the link-off icon on the Live screen to stop listening deliberately.
  Scanning is foreground-only; there is no background service.

## Profiles and sharing

- The top bar switches the active household profile. New readings are saved to
  that profile; history, latest measurement and trends are filtered to it.
- A profile holds a name and optional height, sex and birth year. Only the
  optional details feed the local body-composition estimate.
- Deleting a profile deletes its measurements. The last profile cannot be
  deleted, and "delete all measurements" applies to the active profile.
- On a measurement, tap the share icon to preview a PNG summary card with the
  weight, body-composition values, range labels and profile name, then send it
  through the system share sheet. The app performs no upload itself; the app
  you pick receives the image.

## Run

Requires Flutter 3.47+ and Android SDK 37 (for the BLE plugin). Android 12+
(API 31+) is supported.

```powershell
$env:ANDROID_HOME="$env:USERPROFILE\android-sdk"
flutter pub get
flutter run -d <device-id>
```

Build:

```powershell
flutter build apk --debug
flutter build apk --release
```

Release builds are signed with a private key kept outside the repository.
`android/key.properties` points at it (template: `android/key.properties.example`)
and `docs/build-and-test.md` §11 covers the setup. Without that file the release
build fails instead of quietly signing with the debug key.

Builds are not committed. The release artifacts from the verified run are in
the local `dist/` directory, signed with the Flutter debug key and for testing
only; they still carry the old `dev.ailinkreplacement.ailink_scale` id (see
`docs/build-and-test.md` §10).

## Test

```powershell
flutter analyze
flutter test
```

103 tests cover framing, decoders, units, session/completion rules,
deduplication, SQLite persistence and migrations, profile separation, CSV
escaping, body-composition estimates and range labels, auto-listen, permission
denial and UI smoke tests. All use synthetic data.

## Repository

The project is `lib/`, `test/`, `android/`, `ios/`, `docs/`, the root config
files and the two asset generators in `tools/`. The APK and split APKs, `raw/`,
`decoded/`, `analysis/`, the pcaps, `dist/` and the local capture scripts are
reverse-engineering evidence; they stay on this machine and are excluded by
`.gitignore`. `python tools/make_icon.py` regenerates the launcher icons,
`tools/make_fixtures.py` the synthetic protocol fixtures.

## Documentation

- [`docs/apk-analysis.md`](docs/apk-analysis.md) — APK hashes, environment,
  decompiled findings, network flows, unknowns
- [`docs/ble-protocol.md`](docs/ble-protocol.md) — UUIDs, frame formats,
  payload fields, body-composition mapping, confidence levels, hardware tests
- [`docs/privacy.md`](docs/privacy.md) — data flows, permissions, verification,
  dependency licenses
- [`docs/build-and-test.md`](docs/build-and-test.md) — commands and actual
  results, APK hashes, limitations
- [`AGENTS.md`](AGENTS.md) — repository rules for future work

## Known limitations

- The nearby scale is `LYE`, a Ling Yang `F0A0` **broadcast** scale. It does
  not accept a GATT connection. The app listens to its advertisements,
  decrypts the LingYang TEA payload, and captures weight + impedance, then
  estimates body composition from the local profile. A real weigh-in still
  needs to be compared with the display. `BLE797P` is a different device
  (service `F3C9`).
- The physical scale's protocol family, GATT properties and encryption
  requirements are not confirmed.
- Handshake/AES-encrypted A7 devices are not supported; AILink license keys are
  deliberately not reused.
- The app does not calculate body composition for GATT scales. If the scale
  does not transmit it, the section shows only the available fields. The
  LingYang broadcast scale is the only family that gets a local estimate.
- Metric ranges (BMI, body fat, water, muscle, visceral fat, BMR and so on) are
  labels calculated locally from WHO/ACE/BIA reference bands. They do not change
  the stored values and are not a diagnosis.
- Sharing a CSV or image hands that data to the app you select in the system
  share sheet. That app's privacy rules apply from then on.
- Background BLE is not implemented. The continuous scan only runs while the
  app is open, so it uses more battery than a one-shot scan. iOS has not been
  built or tested.
- The database is app-private but not encrypted at rest.
- The app was renamed from `dev.ailinkreplacement.ailink_scale` to
  `com.aniruth.scale`; Android treats that as a different app. Nothing is
  migrated from the old package, so export anything you need before uninstalling
  it.

## Privacy

No account, no analytics, no telemetry, no cloud sync, and no `INTERNET`
permission in the release APK. The debug APK contains `INTERNET` for Flutter
tooling. See `docs/privacy.md` for the exact verification and its limits.





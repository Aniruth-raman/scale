import 'dart:async';
import 'dart:typed_data';

import 'package:scale/app/app.dart';
import 'package:scale/app/providers.dart';
import 'package:scale/data/ble/ble_permissions.dart';
import 'package:scale/data/ble/ble_transport.dart';
import 'package:scale/data/database/settings_repository.dart';
import 'package:scale/domain/measurement.dart';
import 'package:scale/domain/measurement_repository.dart';
import 'package:scale/domain/profile.dart';
import 'package:scale/features/connection/ble_controller.dart';
import 'package:scale/features/profiles/profiles_screen.dart';
import 'package:scale/features/shared/cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBleTransport implements BleTransport {
  final adapter = StreamController<BleAdapterState>.broadcast();

  @override
  Stream<BleAdapterState> get adapterState => adapter.stream;

  @override
  Stream<DiscoveredScale> scan() => const Stream.empty();

  @override
  Stream<BleConnectionEvent> connect(String deviceId) => const Stream.empty();

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<List<BleServiceInfo>> discoverServices(String deviceId) async => [];

  @override
  Future<Uint8List> read({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async => Uint8List(0);

  @override
  Future<void> write({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    required bool withResponse,
  }) async {}

  @override
  Stream<Uint8List> subscribe({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) => const Stream.empty();
}

class _FakeSystemActions implements BleSystemActions {
  bool requested = false;

  @override
  Future<void> requestEnableBluetooth() async => requested = true;
}

class _FakePermissions implements BlePermissionRequester {
  @override
  Future<bool> request() async => true;
}

class _FakeMeasurementRepository implements MeasurementRepository {
  @override
  Future<List<Measurement>> getAll({String? profileId}) async => [];

  @override
  Future<Measurement?> latest({String? profileId}) async => null;

  @override
  Future<SaveOutcome> save(
    Measurement measurement, {
    Duration duplicateWindow = const Duration(seconds: 15),
  }) async => SaveOutcome.inserted;

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteAll({String? profileId}) async {}
}

class _FakeProfiles implements ProfileRepository {
  _FakeProfiles()
    : all = [
        Profile(
          id: 'p1',
          name: 'Me',
          heightCm: 175,
          sex: 'male',
          birthYear: 1990,
          createdAt: DateTime.utc(2026),
        ),
      ];

  final List<Profile> all;
  String? _active = 'p1';

  @override
  Future<List<Profile>> getAll() async => all;

  @override
  Future<Profile> ensureActive() async => all.first;

  @override
  Future<void> save(Profile profile) async {
    all.removeWhere((p) => p.id == profile.id);
    all.add(profile);
  }

  @override
  Future<void> delete(String id) async => all.removeWhere((p) => p.id == id);

  @override
  Future<String?> activeId() async => _active;

  @override
  Future<void> setActive(String id) async => _active = id;
}

class _MemorySettingsStore implements SettingsStoreLike {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  testWidgets('dashboard and history render without a scale', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleTransportProvider.overrideWithValue(_FakeBleTransport()),
          blePermissionProvider.overrideWithValue(_FakePermissions()),
          measurementRepositoryProvider.overrideWithValue(
            _FakeMeasurementRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            SettingsRepository(_MemorySettingsStore()),
          ),
          profileRepositoryProvider.overrideWithValue(_FakeProfiles()),
          latestMeasurementProvider.overrideWith((ref) async => null),
          measurementsProvider.overrideWith((ref) async => <Measurement>[]),
        ],
        child: const ScaleApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('No measurements saved yet.'), findsOneWidget);

    await tester.tap(find.text('History').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('No measurements yet'), findsOneWidget);
  });

  testWidgets('Bluetooth off hides connect actions and offers turn-on', (
    tester,
  ) async {
    final transport = _FakeBleTransport();
    final actions = _FakeSystemActions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleTransportProvider.overrideWithValue(transport),
          blePermissionProvider.overrideWithValue(_FakePermissions()),
          bleSystemActionsProvider.overrideWithValue(actions),
          measurementRepositoryProvider.overrideWithValue(
            _FakeMeasurementRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            SettingsRepository(_MemorySettingsStore()),
          ),
          profileRepositoryProvider.overrideWithValue(_FakeProfiles()),
          latestMeasurementProvider.overrideWith((ref) async => null),
          measurementsProvider.overrideWith((ref) async => <Measurement>[]),
        ],
        child: const ScaleApp(),
      ),
    );
    await tester.pump();
    transport.adapter.add(BleAdapterState.poweredOff);
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.text('Connect scale'), findsNothing);
    expect(find.text('Live measurement'), findsNothing);

    await tester.tap(find.text('Turn on Bluetooth'));
    await tester.pump();
    expect(actions.requested, isTrue);
  });

  testWidgets('profile switcher opens the household menu', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(_FakeProfiles()),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfileSwitcher())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Me'), findsOneWidget);
    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    expect(find.text('Manage profiles'), findsOneWidget);
  });

  testWidgets('body composition renders range labels', (tester) async {
    final store = _MemorySettingsStore()
      ..values.addAll({
        'profile_height_cm': '175',
        'profile_sex': 'male',
        'profile_birth_year': '1990',
      });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            SettingsRepository(store),
          ),
          profileRepositoryProvider.overrideWithValue(_FakeProfiles()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BodyCompositionList(
                weightKg: 70,
                values: const {
                  'bmi': 22.9,
                  'bodyFatPercent': 20,
                  'musclePercent': 45,
                  'bodyWaterPercent': 55,
                  'boneMassKg': 3,
                  'proteinPercent': 16,
                  'visceralFat': 7,
                  'bmrKcal': 1600,
                  'bodyAgeYears': 29,
                  'subcutaneousFatPercent': 18,
                },
                estimated: true,
                impedanceOhm: 500,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Estimated from weight'), findsOneWidget);
    expect(find.text('Obesity rating'), findsOneWidget);
    expect(find.text('In range'), findsOneWidget);
    expect(find.text('Standard'), findsWidgets);
    expect(find.text('22.9'), findsOneWidget);
  });

  test('device identifiers are redacted', () {
    expect(redactDeviceId('AA:BB:CC:DD:EE:FF'), '••:••:••:••:••:FF');
    expect(redactDeviceId('12345'), '12345');
  });

  test('MAC bytes are redacted from diagnostic hex', () {
    final redacted = redactHex([
      0xAA,
      0xBB,
      0xCC,
      0xDD,
      0xEE,
      0xFF,
      0x01,
    ], 'AA:BB:CC:DD:EE:FF');
    expect(redacted, isNot(contains('aa')));
    expect(redacted, contains('01'));
  });
}

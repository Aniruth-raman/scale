import 'dart:async';
import 'dart:typed_data';

import 'package:scale/app/providers.dart';
import 'package:scale/data/ble/ble_permissions.dart';
import 'package:scale/data/ble/ble_transport.dart';
import 'package:scale/data/protocol/ailink_frame.dart';
import 'package:scale/data/protocol/lingyang_broadcast.dart';
import 'package:scale/domain/measurement.dart';
import 'package:scale/domain/measurement_repository.dart';
import 'package:scale/domain/profile.dart';
import 'package:scale/features/connection/ble_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../protocol/lingyang_fixture.dart';

class _FakeTransport implements BleTransport {
  final adapter = StreamController<BleAdapterState>.broadcast();
  final scans = StreamController<DiscoveredScale>.broadcast();
  final connections = StreamController<BleConnectionEvent>.broadcast();
  final notifications = <String, StreamController<Uint8List>>{};
  final writes = <List<int>>[];

  @override
  Stream<BleAdapterState> get adapterState => adapter.stream;

  @override
  Stream<DiscoveredScale> scan() => scans.stream;

  @override
  Stream<BleConnectionEvent> connect(String deviceId) => connections.stream;

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<List<BleServiceInfo>> discoverServices(String deviceId) async => [
    const BleServiceInfo(
      uuid: ailinkServiceUuid,
      characteristics: [
        BleCharacteristicInfo(
          uuid: ailinkNotifyUuid,
          isReadable: false,
          isWritableWithResponse: false,
          isWritableWithoutResponse: false,
          isNotifiable: true,
          isIndicatable: false,
        ),
      ],
    ),
  ];

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
  }) async {
    writes.add(value);
  }

  @override
  Stream<Uint8List> subscribe({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    return notifications
        .putIfAbsent(characteristicUuid, StreamController<Uint8List>.broadcast)
        .stream;
  }
}

class _FakePermissions implements BlePermissionRequester {
  _FakePermissions(this.granted);

  final bool granted;

  @override
  Future<bool> request() async => granted;
}

class _FakeRepository implements MeasurementRepository {
  final saved = <Measurement>[];

  @override
  Future<List<Measurement>> getAll({String? profileId}) async => saved;

  @override
  Future<Measurement?> latest({String? profileId}) async =>
      saved.isEmpty ? null : saved.last;

  @override
  Future<SaveOutcome> save(
    Measurement measurement, {
    Duration duplicateWindow = const Duration(seconds: 15),
  }) async {
    saved.add(measurement);
    return SaveOutcome.inserted;
  }

  @override
  Future<void> delete(String id) async => saved.removeWhere((m) => m.id == id);

  @override
  Future<void> deleteAll({String? profileId}) async => saved.clear();
}

class _FakeProfiles implements ProfileRepository {
  _FakeProfiles(this.profile);

  final Profile profile;

  @override
  Future<List<Profile>> getAll() async => [profile];

  @override
  Future<Profile> ensureActive() async => profile;

  @override
  Future<void> save(Profile value) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<String?> activeId() async => profile.id;

  @override
  Future<void> setActive(String id) async {}
}

final _profile = Profile(
  id: 'profile-1',
  name: 'Me',
  heightCm: 175,
  sex: 'male',
  birthYear: 1990,
  createdAt: DateTime.utc(2026),
);

void main() {
  test('permission denial produces a clear error and no scan', () async {
    final transport = _FakeTransport();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(false)),
        measurementRepositoryProvider.overrideWithValue(_FakeRepository()),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);

    await container.read(bleProvider.notifier).startScan();
    final state = container.read(bleProvider);
    expect(state.scanning, isFalse);
    expect(state.error, contains('permission'));
  });

  test('adapter powered off is visible', () async {
    final transport = _FakeTransport();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(_FakeRepository()),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    container.read(bleProvider);
    transport.adapter.add(BleAdapterState.poweredOff);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(bleProvider).adapter, BleAdapterState.poweredOff);
  });

  test('stable notification plus completion saves one measurement', () async {
    final transport = _FakeTransport();
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(repository),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(bleProvider.notifier);

    await notifier.connect(
      DiscoveredScale(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Synthetic scale',
        rssi: -50,
        serviceUuids: [ailinkServiceUuid],
        manufacturerData: Uint8List(0),
      ),
    );
    transport.connections.add(
      const BleConnectionEvent(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        phase: BleConnectionPhase.connected,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final notification = transport.notifications[ailinkNotifyUuid]!;
    notification.add(buildA7Frame(86, [0x02, 0x00, 0x1B, 0x58, 0x20]));
    notification.add(buildA7Frame(86, [0x0A]));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.weightKg, 70.0);
    expect(repository.saved.single.status, MeasurementStatus.complete);
    expect(container.read(bleProvider).lastCompleted, isNotNull);

    transport.connections.add(
      const BleConnectionEvent(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        phase: BleConnectionPhase.disconnected,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(bleProvider).phase, BleConnectionPhase.disconnected);
    expect(container.read(bleProvider).services, isEmpty);

    await notifier.connect(
      DiscoveredScale(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Synthetic scale',
        rssi: -50,
        serviceUuids: [ailinkServiceUuid],
        manufacturerData: Uint8List(0),
      ),
    );
    transport.connections.add(
      const BleConnectionEvent(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        phase: BleConnectionPhase.connected,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(bleProvider).phase, BleConnectionPhase.connected);
    expect(container.read(bleProvider).services, isNotEmpty);
  });

  test('completion grace attaches a late body-composition frame', () async {
    final transport = _FakeTransport();
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(repository),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
        bleCompletionGraceProvider.overrideWithValue(
          const Duration(milliseconds: 30),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(bleProvider.notifier);
    await notifier.connect(
      DiscoveredScale(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Synthetic scale',
        rssi: -50,
        serviceUuids: [ailinkServiceUuid],
        manufacturerData: Uint8List(0),
      ),
    );
    transport.connections.add(
      const BleConnectionEvent(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        phase: BleConnectionPhase.connected,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final notification = transport.notifications[ailinkNotifyUuid]!;
    notification.add(buildA7Frame(50, [0x01, 0x01, 0x00, 0x1B, 0x58, 0x20]));
    notification.add(buildA7Frame(50, [0x0F]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    notification.add(
      buildA7Frame(50, [
        0x09,
        0x01,
        0x00,
        0xE1,
        0x00,
        0xC8,
        0x01,
        0x90,
        0x00,
        0x0C,
        0x00,
        0x0D,
      ]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.bodyComposition['bmi'], 22.5);
  });

  test('broadcast scale listens, decodes and saves without GATT', () async {
    final transport = _FakeTransport();
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(repository),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(bleProvider.notifier);
    await notifier.startScan();

    final live = DiscoveredScale(
      id: 'AA:BB:CC:DD:EE:FF',
      name: 'LYE',
      rssi: -50,
      serviceUuids: const ['0000f0a0-0000-1000-8000-00805f9b34fb'],
      manufacturerData: buildLingYangFrame(
        status: 0,
        flags: 0x05,
        rawWeight: 7000,
        adc: 500,
        algorithm: 1,
      ),
    );
    transport.scans.add(live);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await notifier.connect(live);
    expect(container.read(bleProvider).isListening, isTrue);
    transport.scans.add(live);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(bleProvider);
    expect(state.liveReading, isNotNull);
    expect(state.liveReading!.kilograms, 70.0);
    expect(state.liveReading!.impedanceOhm, 500);
    expect(
      state.liveReading!.sourceProtocol,
      LingYangBroadcastDecoder.sourceProtocol,
    );

    final done = DiscoveredScale(
      id: 'AA:BB:CC:DD:EE:FF',
      name: 'LYE',
      rssi: -50,
      serviceUuids: const ['0000f0a0-0000-1000-8000-00805f9b34fb'],
      manufacturerData: buildLingYangFrame(
        status: 0xFF,
        flags: 0x05,
        rawWeight: 7000,
        adc: 500,
        algorithm: 1,
      ),
    );
    transport.scans.add(done);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.saved, isEmpty);
    expect(container.read(bleProvider).statusMessage, contains('Save'));
    await notifier.saveCurrentReading();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.weightKg, 70.0);
    expect(repository.saved.single.impedanceOhm, 500);
    expect(repository.saved.single.algorithmId, 1);
    expect(repository.saved.single.status, MeasurementStatus.complete);
    expect(repository.saved.single.profileId, _profile.id);
    expect(repository.saved.single.bodyCompositionEstimated, isTrue);
    expect(
      repository.saved.single.bodyComposition.keys,
      containsAll(['bodyFatPercent', 'bodyWaterPercent', 'musclePercent']),
    );
    expect(container.read(bleProvider).savedCurrent, isTrue);
    expect(container.read(bleProvider).liveReading, isNotNull);

    await notifier.disconnect();
    expect(container.read(bleProvider).phase, BleConnectionPhase.disconnected);
  });

  test('autoListen attaches without selection and keeps listening', () async {
    final transport = _FakeTransport();
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(repository),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(bleProvider.notifier);

    await notifier.autoListen();
    expect(container.read(bleProvider).scanning, isTrue);

    DiscoveredScale frame(int status) => DiscoveredScale(
      id: 'AA:BB:CC:DD:EE:FF',
      name: 'LYE',
      rssi: -50,
      serviceUuids: const ['0000f0a0-0000-1000-8000-00805f9b34fb'],
      manufacturerData: buildLingYangFrame(
        status: status,
        flags: 0x05,
        rawWeight: 7000,
        adc: 500,
        algorithm: 1,
      ),
    );

    transport.scans.add(frame(0));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(bleProvider).isListening, isTrue);
    expect(container.read(bleProvider).connectedDevice?.name, 'LYE');

    transport.scans.add(frame(0xFF));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await notifier.saveCurrentReading();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.saved, hasLength(1));
    expect(container.read(bleProvider).savedCurrent, isTrue);

    await notifier.saveCurrentReading();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.saved, hasLength(1));
    expect(
      container.read(bleProvider).statusMessage,
      contains('already saved'),
    );

    // The next weigh-in re-enables saving without a reconnect.
    transport.scans.add(frame(0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(bleProvider).savedCurrent, isFalse);
    expect(container.read(bleProvider).isListening, isTrue);

    // Backgrounding pauses the scan; resume re-arms it without a new pick.
    await notifier.pauseScan();
    expect(container.read(bleProvider).scanning, isFalse);
    await notifier.autoListen();
    expect(container.read(bleProvider).scanning, isTrue);
    expect(container.read(bleProvider).isListening, isTrue);

    // An explicit stop is respected by a later resume.
    await notifier.disconnect();
    expect(container.read(bleProvider).scanning, isFalse);
    await notifier.autoListen();
    expect(container.read(bleProvider).scanning, isFalse);
  });

  test('zero-weight broadcast is shown live but is not saveable', () async {
    final transport = _FakeTransport();
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(repository),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(bleProvider.notifier);
    await notifier.autoListen();

    transport.scans.add(
      DiscoveredScale(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'LYE',
        rssi: -50,
        serviceUuids: const ['0000f0a0-0000-1000-8000-00805f9b34fb'],
        manufacturerData: buildLingYangFrame(
          status: 0,
          flags: 0x04,
          rawWeight: 0,
          adc: 0,
          algorithm: 1,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final state = container.read(bleProvider);
    expect(state.liveReading, isNotNull);
    expect(state.liveReading!.kilograms, 0.0);
    expect(state.statusMessage, contains('zero'));

    await notifier.saveCurrentReading();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.saved, isEmpty);
  });

  test('live view follows changing weights before completion', () async {
    final transport = _FakeTransport();
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(repository),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(bleProvider.notifier);
    await notifier.autoListen();

    DiscoveredScale frame(bool stable, int rawWeight, int status) {
      return DiscoveredScale(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'LYE',
        rssi: -50,
        serviceUuids: const ['0000f0a0-0000-1000-8000-00805f9b34fb'],
        manufacturerData: buildLingYangFrame(
          status: status,
          flags: stable ? 0x05 : 0x04,
          rawWeight: rawWeight,
          adc: 500,
          algorithm: 1,
        ),
      );
    }

    transport.scans.add(frame(true, 6000, 0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(bleProvider).liveReading!.kilograms, 60.0);

    transport.scans.add(frame(false, 7000, 0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(bleProvider).liveReading!.kilograms, 70.0);
  });

  test(
    'Bluetooth off shows a friendly state and re-arms when enabled',
    () async {
      final transport = _FakeTransport();
      final container = ProviderContainer(
        overrides: [
          bleTransportProvider.overrideWithValue(transport),
          blePermissionProvider.overrideWithValue(_FakePermissions(true)),
          measurementRepositoryProvider.overrideWithValue(_FakeRepository()),
          profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
          bleCompletionGraceProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(bleProvider.notifier);

      transport.adapter.add(BleAdapterState.poweredOff);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(bleProvider).bluetoothAvailable, isFalse);

      await notifier.autoListen();
      var state = container.read(bleProvider);
      expect(state.scanning, isFalse);
      expect(state.error, isNull);
      expect(state.statusMessage.toLowerCase(), contains('bluetooth'));

      transport.adapter.add(BleAdapterState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      state = container.read(bleProvider);
      expect(state.bluetoothAvailable, isTrue);
      expect(state.scanning, isTrue);
    },
  );

  test('live-only notification is not saved', () async {
    final transport = _FakeTransport();
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        blePermissionProvider.overrideWithValue(_FakePermissions(true)),
        measurementRepositoryProvider.overrideWithValue(repository),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(_profile)),
        bleCompletionGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(bleProvider.notifier);

    await notifier.connect(
      DiscoveredScale(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Synthetic scale',
        rssi: -50,
        serviceUuids: [ailinkServiceUuid],
        manufacturerData: Uint8List(0),
      ),
    );
    transport.connections.add(
      const BleConnectionEvent(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        phase: BleConnectionPhase.connected,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    transport.notifications[ailinkNotifyUuid]!.add(
      buildA7Frame(86, [0x01, 0x00, 0x1B, 0x58, 0x20]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.saved, isEmpty);
    expect(container.read(bleProvider).liveReading, isNotNull);
  });
}

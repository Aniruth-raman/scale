import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_transport.dart';

/// Thin adapter over Flutter Reactive BLE (BSD-3-Clause).
///
/// The adapter intentionally exposes no plugin types outside this file.
class ReactiveBleTransport implements BleTransport {
  ReactiveBleTransport({FlutterReactiveBle? ble})
    : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  final Map<String, _ConnectionHandle> _connections = {};

  @override
  Stream<BleAdapterState> get adapterState => _ble.statusStream.map(_mapStatus);

  @override
  Stream<DiscoveredScale> scan() {
    return _ble
        .scanForDevices(
          withServices: const [],
          // The app keeps the scan running so a broadcast scale can send every
          // weigh-in without a manual restart. Balanced mode is a compromise
          // between receiving those frames and battery use.
          scanMode: ScanMode.balanced,
          // On Android 12+ BLUETOOTH_SCAN has neverForLocation. Legacy
          // Android still needs location services; the status stream reports it.
          requireLocationServicesEnabled: false,
        )
        .map(
          (device) => DiscoveredScale(
            id: device.id,
            name: device.name,
            rssi: device.rssi,
            serviceUuids: device.serviceUuids.map((u) => u.toString()).toList(),
            manufacturerData: device.manufacturerData,
          ),
        );
  }

  @override
  Stream<BleConnectionEvent> connect(String deviceId) {
    final existing = _connections.remove(deviceId);
    existing?.cancel();

    final controller = StreamController<BleConnectionEvent>.broadcast();
    final subscription = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen(
          (update) {
            controller.add(
              BleConnectionEvent(
                deviceId: deviceId,
                phase: _mapConnection(update.connectionState),
                error: update.failure?.message,
              ),
            );
            if (update.connectionState == DeviceConnectionState.disconnected) {
              controller.close();
              _connections.remove(deviceId);
            }
          },
          onError: (Object error) {
            controller.add(
              BleConnectionEvent(
                deviceId: deviceId,
                phase: BleConnectionPhase.disconnected,
                error: error.toString(),
              ),
            );
            controller.close();
            _connections.remove(deviceId);
          },
        );

    _connections[deviceId] = _ConnectionHandle(controller, subscription);
    return controller.stream;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final handle = _connections.remove(deviceId);
    await handle?.cancel();
  }

  @override
  Future<List<BleServiceInfo>> discoverServices(String deviceId) async {
    await _ble.discoverAllServices(deviceId);
    final services = await _ble.getDiscoveredServices(deviceId);
    return services
        .map(
          (service) => BleServiceInfo(
            uuid: service.id.toString(),
            characteristics: service.characteristics
                .map(
                  (c) => BleCharacteristicInfo(
                    uuid: c.id.toString(),
                    isReadable: c.isReadable,
                    isWritableWithResponse: c.isWritableWithResponse,
                    isWritableWithoutResponse: c.isWritableWithoutResponse,
                    isNotifiable: c.isNotifiable,
                    isIndicatable: c.isIndicatable,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Uint8List> read({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final value = await _ble.readCharacteristic(
      QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
      ),
    );
    return Uint8List.fromList(value);
  }

  @override
  Future<void> write({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    required bool withResponse,
  }) async {
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
    );
    if (withResponse) {
      await _ble.writeCharacteristicWithResponse(characteristic, value: value);
    } else {
      await _ble.writeCharacteristicWithoutResponse(
        characteristic,
        value: value,
      );
    }
  }

  @override
  Stream<Uint8List> subscribe({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    return _ble
        .subscribeToCharacteristic(
          QualifiedCharacteristic(
            deviceId: deviceId,
            serviceId: Uuid.parse(serviceUuid),
            characteristicId: Uuid.parse(characteristicUuid),
          ),
        )
        .map(Uint8List.fromList);
  }

  BleAdapterState _mapStatus(BleStatus status) {
    switch (status) {
      case BleStatus.unknown:
        return BleAdapterState.unknown;
      case BleStatus.unsupported:
        return BleAdapterState.unsupported;
      case BleStatus.unauthorized:
        return BleAdapterState.unauthorized;
      case BleStatus.poweredOff:
        return BleAdapterState.poweredOff;
      case BleStatus.locationServicesDisabled:
        return BleAdapterState.locationServicesDisabled;
      case BleStatus.ready:
        return BleAdapterState.ready;
    }
  }

  BleConnectionPhase _mapConnection(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connecting:
        return BleConnectionPhase.connecting;
      case DeviceConnectionState.connected:
        return BleConnectionPhase.connected;
      case DeviceConnectionState.disconnecting:
        return BleConnectionPhase.disconnecting;
      case DeviceConnectionState.disconnected:
        return BleConnectionPhase.disconnected;
    }
  }
}

class _ConnectionHandle {
  _ConnectionHandle(this.controller, this.subscription);

  final StreamController<BleConnectionEvent> controller;
  final StreamSubscription<ConnectionStateUpdate> subscription;

  Future<void> cancel() async {
    await subscription.cancel();
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

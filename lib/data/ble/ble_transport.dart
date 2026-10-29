import 'dart:typed_data';

enum BleAdapterState {
  unknown,
  unsupported,
  unauthorized,
  poweredOff,
  locationServicesDisabled,
  ready,
}

enum BleConnectionPhase {
  disconnected,
  connecting,
  connected,
  disconnecting,

  /// Broadcast scale selected: the app keeps scanning advertisements and does
  /// not open a GATT connection.
  listening,
}

class DiscoveredScale {
  const DiscoveredScale({
    required this.id,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
    required this.manufacturerData,
  });

  final String id;
  final String name;
  final int rssi;
  final List<String> serviceUuids;
  final Uint8List manufacturerData;

  String get displayName => name.isEmpty ? 'Unnamed BLE device' : name;
}

class BleConnectionEvent {
  const BleConnectionEvent({
    required this.deviceId,
    required this.phase,
    this.error,
  });

  final String deviceId;
  final BleConnectionPhase phase;
  final String? error;
}

class BleCharacteristicInfo {
  const BleCharacteristicInfo({
    required this.uuid,
    required this.isReadable,
    required this.isWritableWithResponse,
    required this.isWritableWithoutResponse,
    required this.isNotifiable,
    required this.isIndicatable,
  });

  final String uuid;
  final bool isReadable;
  final bool isWritableWithResponse;
  final bool isWritableWithoutResponse;
  final bool isNotifiable;
  final bool isIndicatable;

  String get properties {
    final values = <String>[
      if (isReadable) 'read',
      if (isWritableWithResponse) 'write',
      if (isWritableWithoutResponse) 'write-no-response',
      if (isNotifiable) 'notify',
      if (isIndicatable) 'indicate',
    ];
    return values.isEmpty ? 'none' : values.join(', ');
  }
}

class BleServiceInfo {
  const BleServiceInfo({required this.uuid, required this.characteristics});

  final String uuid;
  final List<BleCharacteristicInfo> characteristics;
}

class BleNotification {
  const BleNotification({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.data,
  });

  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;
  final Uint8List data;
}

/// Platform-independent BLE boundary.
///
/// A future iOS implementation can be a CoreBluetooth adapter behind this
/// interface; the protocol decoder and storage layers never import a plugin.
abstract class BleTransport {
  Stream<BleAdapterState> get adapterState;
  Stream<DiscoveredScale> scan();
  Stream<BleConnectionEvent> connect(String deviceId);
  Future<void> disconnect(String deviceId);
  Future<List<BleServiceInfo>> discoverServices(String deviceId);
  Future<Uint8List> read({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  });
  Future<void> write({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    required bool withResponse,
  });
  Stream<Uint8List> subscribe({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/units.dart';
import '../../data/ble/ble_transport.dart';
import '../../data/protocol/ailink_frame.dart';
import '../../data/protocol/ailink_scale_decoder.dart';
import '../../data/protocol/lingyang_broadcast.dart';
import '../../data/protocol/scale_event.dart';
import '../../domain/jinghuawei_algorithm.dart';
import '../../domain/measurement.dart';
import '../../domain/measurement_repository.dart';
import '../../domain/measurement_session.dart';

const String protocolConfidenceNote =
    'AILink candidate protocol. Format decoded from the APK; not yet verified on this physical scale.';

@immutable
class PacketLogEntry {
  const PacketLogEntry({
    required this.at,
    required this.direction,
    required this.text,
    this.characteristic,
    this.note,
  });

  final DateTime at;
  final String direction; // rx, tx, info, error
  final String? characteristic;
  final String text;
  final String? note;
}

@immutable
class BleState {
  const BleState({
    this.adapter = BleAdapterState.unknown,
    this.scanning = false,
    this.devices = const [],
    this.phase = BleConnectionPhase.disconnected,
    this.connectedDevice,
    this.services = const [],
    this.liveReading,
    this.bodyComposition = const {},
    this.lastCompleted,
    this.packetLog = const [],
    this.error,
    this.statusMessage = 'Not connected',
    this.detectedProtocol,
    this.subscribedCharacteristics = 0,
    this.savedCurrent = false,
  });

  final BleAdapterState adapter;
  final bool scanning;
  final List<DiscoveredScale> devices;
  final BleConnectionPhase phase;
  final DiscoveredScale? connectedDevice;
  final List<BleServiceInfo> services;
  final WeightReading? liveReading;
  final Map<String, double> bodyComposition;
  final Measurement? lastCompleted;
  final List<PacketLogEntry> packetLog;
  final String? error;
  final String statusMessage;
  final String? detectedProtocol;
  final int subscribedCharacteristics;

  /// True when the current broadcast burst has already been saved. It resets
  /// when the scale starts a new weigh-in.
  final bool savedCurrent;

  bool get isConnected =>
      phase == BleConnectionPhase.connected ||
      phase == BleConnectionPhase.listening;
  bool get isListening => phase == BleConnectionPhase.listening;
  bool get canScan => adapter == BleAdapterState.ready;

  /// True while the adapter is usable or still being queried. Only a definite
  /// off/unauthorized/unsupported state hides the connection UI.
  bool get bluetoothAvailable =>
      adapter == BleAdapterState.ready || adapter == BleAdapterState.unknown;

  BleState copyWith({
    BleAdapterState? adapter,
    bool? scanning,
    List<DiscoveredScale>? devices,
    BleConnectionPhase? phase,
    DiscoveredScale? connectedDevice,
    bool clearConnectedDevice = false,
    List<BleServiceInfo>? services,
    WeightReading? liveReading,
    bool clearLiveReading = false,
    Map<String, double>? bodyComposition,
    Measurement? lastCompleted,
    bool clearLastCompleted = false,
    List<PacketLogEntry>? packetLog,
    String? error,
    bool clearError = false,
    String? statusMessage,
    String? detectedProtocol,
    bool clearDetectedProtocol = false,
    int? subscribedCharacteristics,
    bool? savedCurrent,
  }) {
    return BleState(
      adapter: adapter ?? this.adapter,
      scanning: scanning ?? this.scanning,
      devices: devices ?? this.devices,
      phase: phase ?? this.phase,
      connectedDevice: clearConnectedDevice
          ? null
          : connectedDevice ?? this.connectedDevice,
      services: services ?? this.services,
      liveReading: clearLiveReading ? null : liveReading ?? this.liveReading,
      bodyComposition: bodyComposition ?? this.bodyComposition,
      lastCompleted: clearLastCompleted
          ? null
          : lastCompleted ?? this.lastCompleted,
      packetLog: packetLog ?? this.packetLog,
      error: clearError ? null : error ?? this.error,
      statusMessage: statusMessage ?? this.statusMessage,
      detectedProtocol: clearDetectedProtocol
          ? null
          : detectedProtocol ?? this.detectedProtocol,
      subscribedCharacteristics:
          subscribedCharacteristics ?? this.subscribedCharacteristics,
      savedCurrent: savedCurrent ?? this.savedCurrent,
    );
  }
}

class BleController extends Notifier<BleState> {
  BleTransport? _transport;
  StreamSubscription<BleAdapterState>? _adapterSub;
  StreamSubscription<DiscoveredScale>? _scanSub;
  StreamSubscription<BleConnectionEvent>? _connectionSub;
  final List<StreamSubscription<Uint8List>> _notifySubs = [];
  final AilinkFrameAssembler _assembler = AilinkFrameAssembler();
  static const AilinkScaleDecoder _decoder = AilinkScaleDecoder();
  static const LingYangBroadcastDecoder _broadcastDecoder =
      LingYangBroadcastDecoder();
  MeasurementSession? _session;
  String? _broadcastDeviceId;
  bool _broadcastDone = false;
  bool _savedCurrent = false;
  Timer? _scanTimer;
  bool _disposed = false;
  bool _completionPending = false;
  String? _connectedId;
  String? _connectedName;
  final Map<String, DiscoveredScale> _deviceMap = {};

  /// True while the app is waiting to auto-attach to a nearby broadcast scale.
  bool _autoListen = false;

  /// Set when the user explicitly stops or disconnects, so a resume does not
  /// re-arm the scan against their choice.
  bool _userStopped = false;

  @override
  BleState build() {
    _transport = ref.watch(bleTransportProvider);
    _adapterSub = _transport!.adapterState.listen((status) {
      if (_disposed) return;
      state = state.copyWith(
        adapter: status,
        statusMessage: _adapterMessage(status),
      );
      if (status == BleAdapterState.poweredOff ||
          status == BleAdapterState.unauthorized) {
        if (!_userStopped) {
          // Re-arm automatically once the user turns Bluetooth back on.
          _autoListen = true;
        }
        _scanTimer?.cancel();
        _scanTimer = null;
        unawaited(_scanSub?.cancel());
        _scanSub = null;
        if (state.isConnected) {
          _resetConnectionState(_adapterMessage(status));
        } else {
          state = state.copyWith(scanning: false, devices: const []);
        }
      } else if (status == BleAdapterState.ready &&
          _autoListen &&
          !state.scanning &&
          !state.isConnected) {
        unawaited(startScan());
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _scanTimer?.cancel();
      _adapterSub?.cancel();
      _scanSub?.cancel();
      _connectionSub?.cancel();
      for (final sub in _notifySubs) {
        sub.cancel();
      }
      _notifySubs.clear();
      _transport?.disconnect(_connectedId ?? '');
    });
    return const BleState();
  }

  /// Re-arms the scan on launch/resume and attaches to the first supported
  /// broadcast scale without asking the user to pick it. An explicit stop wins
  /// until the user connects again.
  Future<void> autoListen() async {
    if (_disposed || _userStopped) return;
    if (state.isConnected) {
      // Resume can outlive the platform scan stream. Re-arm it quietly for a
      // broadcast scale; a GATT connection needs no scan.
      if (state.isListening && _scanSub == null) await startScan();
      return;
    }
    _autoListen = true;
    if (state.scanning) {
      // Keep an already-running manual scan alive until the scale is found.
      _scanTimer?.cancel();
      _scanTimer = null;
      return;
    }
    await startScan();
  }

  Future<void> startScan() async {
    if (_disposed) return;
    if (state.adapter == BleAdapterState.poweredOff) {
      _autoListen = true;
      state = state.copyWith(
        scanning: false,
        error: null,
        clearError: true,
        statusMessage: 'Bluetooth is off. Turn it on to find the scale.',
      );
      return;
    }
    final allowed = await ref.read(blePermissionProvider).request();
    if (_disposed) return;
    if (!allowed) {
      _autoListen = false;
      state = state.copyWith(
        error:
            'Bluetooth permission was denied. Grant Nearby devices '
            '(Android 12+) or Location (older Android) permission in system settings.',
        statusMessage: 'Permission denied',
      );
      return;
    }

    await stopScan();
    _deviceMap.clear();
    state = state.copyWith(
      scanning: true,
      devices: const [],
      error: null,
      clearError: true,
      statusMessage: state.isListening
          ? state.statusMessage
          : _autoListen
          ? 'Looking for your scale. Step on it to begin.'
          : 'Scanning for BLE devices…',
    );

    _scanSub = _transport!.scan().listen(
      (device) {
        if (_disposed) return;
        _deviceMap[device.id] = device;
        if (kDebugMode) {
          debugPrint(
            'AILINK_SCAN name="${device.name}" id=${redactDeviceId(device.id)} '
            'rssi=${device.rssi} services=${device.serviceUuids.join("|")} '
            'mfg=${redactHex(device.manufacturerData, device.id)}',
          );
        }
        final devices = _deviceMap.values.toList()
          ..sort((a, b) {
            final aAilink = _isAilinkService(a.serviceUuids);
            final bAilink = _isAilinkService(b.serviceUuids);
            if (aAilink != bAilink) return aAilink ? -1 : 1;
            return b.rssi.compareTo(a.rssi);
          });
        state = state.copyWith(devices: devices);
        if (_autoListen &&
            _broadcastDeviceId == null &&
            _isBroadcastDevice(device)) {
          _autoListen = false;
          unawaited(
            _startBroadcastListening(device)
                .then((_) => _handleBroadcastAdvertisement(device)),
          );
          return;
        }
        _handleBroadcastAdvertisement(device);
      },
      onError: (Object error) {
        if (_disposed) return;
        final ready = state.adapter == BleAdapterState.ready;
        state = state.copyWith(
          scanning: false,
          error: ready ? 'Scan failed: $error' : null,
          clearError: !ready,
          statusMessage: ready
              ? 'Scan failed'
              : 'Could not start the scan. Check that Bluetooth is on.',
        );
      },
    );
    _scanTimer?.cancel();
    // A broadcast scale only sends data while the scan is active, so an
    // auto-listen scan runs until the user stops it. Manual scans time out.
    if (!_autoListen) {
      _scanTimer = Timer(const Duration(seconds: 15), () {
        if (_broadcastDeviceId == null) {
          stopScan();
        }
      });
    }
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    if (!_disposed) {
      state = state.copyWith(
        scanning: false,
        statusMessage: state.isConnected ? state.statusMessage : 'Scan stopped',
      );
    }
  }

  /// Stops the foreground scan when the app is backgrounded. Auto-listen
  /// re-arms it on resume; an explicit user stop is left alone.
  Future<void> pauseScan() async {
    if (_userStopped) return;
    if (state.scanning) await stopScan();
  }

  Future<void> connect(DiscoveredScale device) async {
    if (_disposed) return;
    _userStopped = false;
    _autoListen = false;
    if (_isBroadcastDevice(device)) {
      await _startBroadcastListening(device);
      return;
    }
    await stopScan();
    await _closeConnection();
    _broadcastDeviceId = null;
    _connectedId = device.id;
    _connectedName = device.displayName;
    _completionPending = false;
    _assembler.reset();
    _session = MeasurementSession(sourceProtocol: 'ailink.auto');
    state = state.copyWith(
      phase: BleConnectionPhase.connecting,
      connectedDevice: device,
      services: const [],
      clearLiveReading: true,
      clearLastCompleted: true,
      bodyComposition: const {},
      error: null,
      clearError: true,
      detectedProtocol: null,
      clearDetectedProtocol: true,
      subscribedCharacteristics: 0,
      statusMessage: 'Connecting to ${device.displayName}…',
    );

    _connectionSub = _transport!
        .connect(device.id)
        .listen(
          _onConnectionEvent,
          onError: (Object error) {
            if (_disposed) return;
            _addLog('error', null, 'connection error', note: error.toString());
            _resetConnectionState('Connection failed: $error');
          },
        );
  }

  Future<void> _startBroadcastListening(DiscoveredScale device) async {
    if (_scanSub == null) {
      await startScan();
    }
    if (_disposed) return;
    // Body-composition estimates need the active household profile. Wait for
    // it to load so the first weigh-in frame is not decoded without one.
    try {
      await ref.read(profilesProvider.future);
    } catch (_) {
      // A missing profile is fine; weight and impedance still work.
    }
    if (_disposed) return;
    await _closeConnection();
    _broadcastDeviceId = device.id;
    _broadcastDone = false;
    _savedCurrent = false;
    _connectedId = device.id;
    _connectedName = device.displayName;
    _completionPending = false;
    _assembler.reset();
    _session = MeasurementSession(
      sourceProtocol: LingYangBroadcastDecoder.sourceProtocol,
      // AILink ignores jitter for 3 s after a stable value. The scale's own
      // 0xFF status still ends the cycle; live values before that are shown
      // immediately even when the session keeps the stable one for saving.
      stableHold: const Duration(seconds: 3),
    );
    _scanTimer?.cancel();
    state = state.copyWith(
      phase: BleConnectionPhase.listening,
      connectedDevice: device,
      services: const [],
      clearLiveReading: true,
      clearLastCompleted: true,
      bodyComposition: const {},
      error: null,
      clearError: true,
      detectedProtocol: LingYangBroadcastDecoder.sourceProtocol,
      subscribedCharacteristics: 0,
      savedCurrent: false,
      statusMessage:
          'Listening for ${device.displayName} broadcast. Step on the scale.',
    );
    _addLog('info', null, 'broadcast listening started');
  }

  void _handleBroadcastAdvertisement(DiscoveredScale device) {
    if (_disposed || _broadcastDeviceId != device.id) return;
    final reading = _broadcastDecoder.decode(
      device.manufacturerData,
      name: device.name,
    );
    if (reading == null) return;

    _addLog(
      'rx',
      'F0A0 broadcast',
      redactHex(reading.rawFrame, device.id),
      note: 'LingYang CID ${reading.cid} status ${reading.status}',
    );

    final frame = AilinkFrame(
      type: AilinkFrameType.a7,
      cid: reading.cid,
      payload: reading.rawFrame,
      raw: reading.rawFrame,
    );
    final composition = reading.weightValid
        ? _estimateBroadcastBodyComposition(reading)
        : null;
    if (reading.weightValid) {
      final weightReading = WeightReading(
        value: reading.value,
        unit: reading.unit,
        decimals: reading.decimals,
        stable: reading.stable,
        receivedAt: DateTime.now(),
        sourceProtocol: LingYangBroadcastDecoder.sourceProtocol,
        impedanceOhm: reading.impedanceOhm,
        algorithmId: reading.algorithmId,
        bodyCompositionEstimated: composition != null,
      );
      _handleEvent(ScaleReadingEvent(weightReading), frame);
      if (composition != null) {
        final map = composition.toMap();
        _session?.onBodyComposition(ScaleBodyCompositionEvent(map));
        state = state.copyWith(
          bodyComposition: map,
          liveReading: state.liveReading?.copyWith(
            bodyComposition: map,
            bodyCompositionEstimated: true,
          ),
        );
      }
    } else if (reading.status != 0xFF) {
      // Show an idle/zero or sub-5 kg reading so the scale visibly responds,
      // but never feed it into the measurement session. Do not erase a real
      // reading that has not been saved yet.
      final current = state.liveReading;
      if (current == null || current.kilograms <= 0.05) {
        state = state.copyWith(
          liveReading: WeightReading(
            value: reading.value,
            unit: reading.unit,
            decimals: reading.decimals,
            stable: reading.stable,
            receivedAt: DateTime.now(),
            sourceProtocol: LingYangBroadcastDecoder.sourceProtocol,
            algorithmId: reading.algorithmId,
          ),
          bodyComposition: const {},
          detectedProtocol: LingYangBroadcastDecoder.sourceProtocol,
          error: null,
          clearError: true,
        );
      }
    }

    _broadcastDone = reading.status == 0xFF;
    if (reading.weightValid && reading.status != 0xFF) {
      // A real new weigh-in (or another impedance frame with a weight)
      // re-enables saving. An idle zero frame does not.
      _savedCurrent = false;
    }

    if (_disposed) return;
    state = state.copyWith(
      detectedProtocol: LingYangBroadcastDecoder.sourceProtocol,
      savedCurrent: _savedCurrent,
      statusMessage: !reading.weightValid && reading.status != 0xFF
          ? reading.kilograms <= 0.05
                ? 'Scale at zero. Step on to measure.'
                : 'Weight below 5 kg is shown but not saved.'
          : switch (reading.status) {
              0x00 =>
                reading.stable
                    ? 'Stable weight received. Waiting for completion…'
                    : 'Live weight received.',
              0x01 => 'Measuring impedance. Stay still and barefoot.',
              0x02 => 'Impedance measurement complete.',
              0x03 => 'Impedance failed; weight is still usable.',
              0xFF =>
                _savedCurrent
                    ? 'Saved. Still listening for the next weigh-in.'
                    : 'Measurement complete. Tap Save current reading.',
              _ => 'Broadcast reading received.',
            },
    );
  }

  BodyCompositionEstimate? _estimateBroadcastBodyComposition(
    BroadcastReading reading,
  ) {
    if (!reading.weightValid || reading.impedanceOhm == null) return null;
    final profile = ref.read(activeProfileProvider);
    if (profile == null ||
        profile.heightCm == null ||
        profile.birthYear == null) {
      return null;
    }
    final sex = switch (profile.sex) {
      'male' => EstimationSex.male,
      'female' => EstimationSex.female,
      _ => null,
    };
    if (sex == null) return null;
    return estimateBodyComposition(
      weightKg: reading.kilograms,
      impedanceOhm: reading.impedanceOhm!,
      sex: sex,
      age: profile.age!,
      heightCm: profile.heightCm!,
    );
  }

  bool _isBroadcastDevice(DiscoveredScale device) {
    if (_hasServiceUuid(
      device.serviceUuids,
      '0000f0a0-0000-1000-8000-00805f9b34fb',
      'f0a0',
    )) {
      return true;
    }
    final name = device.name.toLowerCase();
    return name.startsWith('lye') || name.contains('lingyang');
  }

  Future<void> disconnect() async {
    _userStopped = true;
    _autoListen = false;
    if (_broadcastDeviceId != null) {
      await stopScan();
    }
    await _closeConnection();
    _resetConnectionState('Disconnected');
  }

  void clearLog() {
    if (_disposed) return;
    state = state.copyWith(packetLog: const []);
  }

  Future<void> saveCurrentReading() async {
    if (state.savedCurrent) {
      state = state.copyWith(
        statusMessage: 'This reading is already saved. Step on again.',
      );
      return;
    }
    final session = _session;
    if (session == null || !session.hasReading) {
      state = state.copyWith(
        error: 'No live reading to save. Step on the scale first.',
        statusMessage: 'Nothing to save',
      );
      return;
    }
    Measurement? measurement;
    if (_broadcastDeviceId != null && _broadcastDone) {
      // The broadcast burst ended with 0xFF. Save it as a completed reading,
      // not as a transient live value.
      measurement = session.complete(
        requiresStable: false,
        deviceLabel: _connectedName,
      );
    }
    measurement ??= session.manualSave(deviceLabel: _connectedName);
    if (measurement == null) {
      state = state.copyWith(
        error: 'The current reading is not usable (zero or invalid).',
        statusMessage: 'Nothing to save',
      );
      return;
    }
    _broadcastDone = false;
    await _persist(measurement);
  }

  /// Sends the documented A6 "get version" request as a harmless identity
  /// probe. No handshake or encryption is attempted.
  Future<void> probeVersion() async {
    final service = _findService(ailinkServiceUuid);
    if (service == null) {
      state = state.copyWith(
        error: 'Service FFE0 was not discovered; cannot send the probe.',
      );
      return;
    }
    final characteristic = _findCharacteristic(service, const [
      ailinkWriteUuid,
      ailinkWriteNotifyUuid,
    ], writable: true);
    if (characteristic == null) {
      state = state.copyWith(error: 'No writable AILink characteristic found.');
      return;
    }
    final frame = buildA6Frame(const [0x0E]);
    await _write(
      service.uuid,
      characteristic,
      frame,
      withResponse:
          characteristic.isWritableWithResponse &&
          !characteristic.isWritableWithoutResponse,
    );
  }

  Future<void> _write(
    String serviceUuid,
    BleCharacteristicInfo characteristic,
    List<int> value, {
    required bool withResponse,
  }) async {
    final id = _connectedId;
    if (id == null) return;
    _addLog('tx', characteristic.uuid, _hex(value));
    try {
      await _transport!.write(
        deviceId: id,
        serviceUuid: serviceUuid,
        characteristicUuid: characteristic.uuid,
        value: value,
        withResponse: withResponse,
      );
      _addLog('info', characteristic.uuid, 'write accepted');
    } catch (error) {
      _addLog('error', characteristic.uuid, 'write failed', note: '$error');
      state = state.copyWith(error: 'Write failed: $error');
    }
  }

  Future<void> _onConnectionEvent(BleConnectionEvent event) async {
    if (_disposed) return;
    if (kDebugMode) {
      debugPrint(
        'AILINK_CONN id=${redactDeviceId(event.deviceId)} '
        'phase=${event.phase.name} error=${event.error ?? ""}',
      );
    }
    _addLog('info', null, 'connection ${event.phase.name}', note: event.error);
    switch (event.phase) {
      case BleConnectionPhase.connecting:
        state = state.copyWith(
          phase: BleConnectionPhase.connecting,
          statusMessage: 'Connecting…',
        );
      case BleConnectionPhase.connected:
        state = state.copyWith(
          phase: BleConnectionPhase.connected,
          statusMessage: 'Connected. Discovering GATT…',
        );
        await _onConnected();
      case BleConnectionPhase.disconnecting:
        state = state.copyWith(
          phase: BleConnectionPhase.disconnecting,
          statusMessage: 'Disconnecting…',
        );
      case BleConnectionPhase.disconnected:
        _resetConnectionState(
          event.error == null ? 'Disconnected' : 'Disconnected: ${event.error}',
        );
      case BleConnectionPhase.listening:
        break;
    }
  }

  Future<void> _onConnected() async {
    final id = _connectedId;
    if (id == null) return;
    try {
      final services = await _transport!.discoverServices(id);
      if (_disposed) return;
      state = state.copyWith(
        services: services,
        statusMessage: 'Connected. Subscribing to notifications…',
      );
      _addLog('info', null, 'GATT discovered: ${services.length} services');

      var count = 0;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (!characteristic.isNotifiable && !characteristic.isIndicatable) {
            continue;
          }
          count++;
          final sub = _transport!
              .subscribe(
                deviceId: id,
                serviceUuid: service.uuid,
                characteristicUuid: characteristic.uuid,
              )
              .listen(
                (data) => _onNotification(
                  BleNotification(
                    deviceId: id,
                    serviceUuid: service.uuid,
                    characteristicUuid: characteristic.uuid,
                    data: data,
                  ),
                ),
                onError: (Object error) {
                  _addLog(
                    'error',
                    characteristic.uuid,
                    'notification stream error',
                    note: '$error',
                  );
                },
              );
          _notifySubs.add(sub);
        }
      }
      if (_disposed) return;
      state = state.copyWith(
        subscribedCharacteristics: count,
        statusMessage: count == 0
            ? 'Connected, but no notifiable characteristics were found.'
            : 'Connected. Step on the scale to send a measurement.',
      );
      _addLog('info', null, 'Subscribed to $count characteristic(s)');
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        error: 'Service discovery failed: $error',
        statusMessage: 'GATT discovery failed',
      );
    }
  }

  void _onNotification(BleNotification notification) {
    if (_disposed) return;
    _addLog(
      'rx',
      notification.characteristicUuid,
      redactHex(notification.data, _connectedId),
    );

    final outcome = _assembler.add(notification.data);
    for (final error in outcome.errors) {
      _addLog('error', notification.characteristicUuid, error.message);
    }
    for (final frame in outcome.frames) {
      final result = _decoder.decode(frame);
      for (final event in result.events) {
        _handleEvent(event, frame);
      }
    }
  }

  void _handleEvent(ScaleEvent event, AilinkFrame frame) {
    if (_disposed) return;
    switch (event) {
      case ScaleReadingEvent():
        if (_completionPending) {
          _addLog(
            'info',
            notificationFor(frame),
            'reading ignored during completion grace',
          );
          break;
        }
        _session?.onReading(event);
        final body = _session?.bodyComposition ?? const <String, double>{};
        state = state.copyWith(
          liveReading: event.reading.copyWith(bodyComposition: body),
          bodyComposition: body,
          detectedProtocol: event.reading.sourceProtocol,
          statusMessage: event.reading.stable
              ? 'Stable weight received. Waiting for completion…'
              : 'Live weight received.',
          error: null,
          clearError: true,
        );
        _addLog(
          'info',
          notificationFor(frame),
          'weight ${event.reading.value.toStringAsFixed(event.reading.decimals)} '
              '${event.reading.unit.label}${event.reading.stable ? ' (stable)' : ''}',
        );
      case ScaleBodyCompositionEvent():
        final session = _session;
        if (session == null || !session.hasReading) {
          _addLog(
            'info',
            notificationFor(frame),
            'body composition ignored: no active reading',
          );
          break;
        }
        session.onBodyComposition(event);
        final body = session.bodyComposition;
        final live = state.liveReading?.copyWith(bodyComposition: body);
        state = state.copyWith(
          bodyComposition: body,
          liveReading: live,
          statusMessage: 'Body composition received from the scale.',
        );
        _addLog(
          'info',
          notificationFor(frame),
          'body composition: ${event.metrics.keys.join(', ')}',
        );
      case ScaleCompletionEvent():
        unawaited(_onCompletion(event.requiresStable, frame));
      case ScaleErrorEvent():
        state = state.copyWith(
          error: event.message,
          statusMessage: event.message,
        );
        _addLog('error', notificationFor(frame), event.message);
      case ScaleInfoEvent():
        _addLog('info', notificationFor(frame), event.message);
    }
  }

  Future<void> _onCompletion(bool requiresStable, AilinkFrame frame) async {
    _completionPending = true;
    try {
      final grace = ref.read(bleCompletionGraceProvider);
      if (grace > Duration.zero) {
        await Future<void>.delayed(grace);
      }
      if (_disposed) return;
      final measurement = _session?.complete(
        requiresStable: requiresStable,
        deviceLabel: _connectedName,
      );
      if (measurement == null) {
        state = state.copyWith(
          statusMessage: 'Completion signal without a recent usable weight; nothing saved.',
        );
        _addLog(
          'info',
          notificationFor(frame),
          'completion ignored: no recent usable reading',
        );
        return;
      }
      await _persist(measurement);
    } finally {
      _completionPending = false;
    }
  }

  Future<void> _persist(Measurement measurement) async {
    // Attach the active household profile at save time, so switching profiles
    // while listening sends the reading to the selected member.
    var saved = measurement;
    if (saved.profileId == null) {
      final active = ref.read(activeProfileProvider);
      final profile =
          active ?? (await ref.read(profilesProvider.future)).active;
      saved = saved.copyWith(profileId: profile.id);
    }
    final outcome = await ref.read(measurementRepositoryProvider).save(saved);
    if (_disposed) return;
    final broadcast = _broadcastDeviceId != null;
    if (broadcast) {
      _savedCurrent = true;
    }
    final profileName = ref.read(activeProfileProvider)?.name;
    if (outcome == SaveOutcome.inserted) {
      ref.invalidate(measurementsProvider);
      ref.invalidate(latestMeasurementProvider);
      state = state.copyWith(
        lastCompleted: saved,
        clearLiveReading: !broadcast,
        savedCurrent: broadcast,
        statusMessage: broadcast
            ? 'Saved${profileName == null ? '' : ' for $profileName'}. '
                  'Still listening; step on again for the next reading.'
            : 'Measurement saved locally.',
        error: null,
        clearError: true,
      );
      _addLog('info', null, 'saved measurement ${saved.id}');
    } else {
      state = state.copyWith(
        lastCompleted: state.lastCompleted ?? saved,
        clearLiveReading: !broadcast,
        savedCurrent: broadcast,
        statusMessage: broadcast
            ? 'This reading was already saved. Still listening.'
            : 'Duplicate notification ignored.',
      );
      _addLog('info', null, 'duplicate measurement ignored');
    }
  }

  void _resetConnectionState(String message) {
    if (_disposed) return;
    _session?.reset();
    _session = null;
    _broadcastDeviceId = null;
    _broadcastDone = false;
    _savedCurrent = false;
    _completionPending = false;
    _assembler.reset();
    _connectedId = null;
    _connectedName = null;
    state = state.copyWith(
      phase: BleConnectionPhase.disconnected,
      clearConnectedDevice: true,
      services: const [],
      clearLiveReading: true,
      bodyComposition: const {},
      clearDetectedProtocol: true,
      subscribedCharacteristics: 0,
      savedCurrent: false,
      statusMessage: message,
    );
  }

  Future<void> _closeConnection() async {
    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();
    await _connectionSub?.cancel();
    _connectionSub = null;
    final id = _connectedId;
    if (id != null) {
      await _transport?.disconnect(id);
    }
  }

  void _addLog(
    String direction,
    String? characteristic,
    String text, {
    String? note,
  }) {
    if (_disposed) return;
    final entry = PacketLogEntry(
      at: DateTime.now(),
      direction: direction,
      characteristic: characteristic,
      text: text,
      note: note,
    );
    final log = [entry, ...state.packetLog];
    state = state.copyWith(packetLog: log.take(200).toList(growable: false));
  }

  BleServiceInfo? _findService(String uuid) {
    for (final service in state.services) {
      if (service.uuid.toLowerCase() == uuid) return service;
    }
    return null;
  }

  BleCharacteristicInfo? _findCharacteristic(
    BleServiceInfo service,
    List<String> uuids, {
    bool writable = false,
  }) {
    for (final characteristic in service.characteristics) {
      if (uuids.contains(characteristic.uuid.toLowerCase()) &&
          (!writable ||
              characteristic.isWritableWithResponse ||
              characteristic.isWritableWithoutResponse)) {
        return characteristic;
      }
    }
    return null;
  }

  String _adapterMessage(BleAdapterState status) {
    switch (status) {
      case BleAdapterState.unknown:
        return 'Bluetooth status unknown';
      case BleAdapterState.unsupported:
        return 'Bluetooth LE is not supported on this device';
      case BleAdapterState.unauthorized:
        return 'Bluetooth permission not granted';
      case BleAdapterState.poweredOff:
        return 'Bluetooth is turned off';
      case BleAdapterState.locationServicesDisabled:
        return 'Location services are off (required for BLE scan on older Android)';
      case BleAdapterState.ready:
        return state.isConnected ? state.statusMessage : 'Bluetooth ready';
    }
  }

  String notificationFor(AilinkFrame frame) {
    if (frame.type == AilinkFrameType.a7) return 'A7 CID ${frame.cid}';
    return 'A6';
  }
}

const String ailinkServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const String ailinkWriteUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
const String ailinkNotifyUuid = '0000ffe2-0000-1000-8000-00805f9b34fb';
const String ailinkWriteNotifyUuid = '0000ffe3-0000-1000-8000-00805f9b34fb';

final bleProvider = NotifierProvider<BleController, BleState>(
  BleController.new,
);

bool _isAilinkService(List<String> serviceUuids) {
  return _hasServiceUuid(serviceUuids, ailinkServiceUuid, 'ffe0') ||
      _hasServiceUuid(
        serviceUuids,
        '0000f0a0-0000-1000-8000-00805f9b34fb',
        'f0a0',
      );
}

bool _hasServiceUuid(
  List<String> serviceUuids,
  String fullUuid,
  String shortUuid,
) {
  for (final uuid in serviceUuids) {
    final value = uuid.toLowerCase();
    if (value == fullUuid || value == shortUuid) return true;
  }
  return false;
}

String redactDeviceId(String? id) {
  if (id == null || id.isEmpty) return 'unknown device';
  final compact = id.replaceAll(':', '');
  if (compact.length == 12 && RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(compact)) {
    return '••:••:••:••:••:${compact.substring(10).toUpperCase()}';
  }
  if (id.length <= 8) return id;
  return '…${id.substring(id.length - 6)}';
}

String redactHex(List<int> data, String? deviceId) {
  var hex = _hex(data);
  final compact = (deviceId ?? '').replaceAll(':', '').toLowerCase();
  if (compact.length == 12 && RegExp(r'^[0-9a-f]{12}$').hasMatch(compact)) {
    final pairs = <String>[];
    for (var i = 0; i < 12; i += 2) {
      pairs.add(compact.substring(i, i + 2));
    }
    final forward = pairs.join(' ');
    final reverse = pairs.reversed.join(' ');
    hex = hex.replaceAll(forward, '•• •• •• •• •• ••');
    hex = hex.replaceAll(reverse, '•• •• •• •• •• ••');
    hex = hex.replaceAll(compact, '••••••••••••');
    hex = hex.replaceAll(pairs.reversed.join(''), '••••••••••••');
  }
  return hex;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

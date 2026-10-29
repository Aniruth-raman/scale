import 'package:uuid/uuid.dart';

import '../core/units.dart';
import '../domain/measurement.dart';
import '../data/protocol/scale_event.dart';

/// Turns protocol events into at most one completed measurement per cycle.
///
/// Live notifications are never written by themselves. A measurement is only
/// returned after an explicit completion event (or a deliberate manual save).
class MeasurementSession {
  MeasurementSession({
    required this.sourceProtocol,
    this.completionTimeout = const Duration(seconds: 30),
    this.stableHold = const Duration(seconds: 3),
  });

  final String sourceProtocol;
  final Duration completionTimeout;
  final Duration stableHold;

  WeightReading? _latest;
  WeightReading? _stable;
  DateTime? _lastReadingAt;
  final Map<String, double> _bodyComposition = {};

  WeightReading? get latest => _latest;
  bool get hasReading => _latest != null;
  Map<String, double> get bodyComposition => Map.unmodifiable(_bodyComposition);

  /// AILink ignores live packets during a short stable hold
  /// (`WeightScaleDevice.mStableStatus`). Broadcast bursts are longer because
  /// impedance frames arrive between the stable weight and completion, so the
  /// controller can pass a longer hold for them.
  void onReading(ScaleReadingEvent event) {
    final reading = event.reading.copyWith(
      bodyComposition: Map.of(_bodyComposition),
    );
    final stable = _stable;
    if (!reading.stable && stable != null) {
      final elapsed = reading.receivedAt.difference(stable.receivedAt);
      if (elapsed <= stableHold) {
        return;
      }
      _stable = null;
    }
    _latest = reading;
    _lastReadingAt = reading.receivedAt;
    if (reading.stable) {
      _stable = reading;
    }
  }

  void onBodyComposition(ScaleBodyCompositionEvent event) {
    // Ignore metrics that arrive after completion; they belong to no active
    // cycle and must not leak into the next measurement.
    if (_latest == null) return;
    _bodyComposition.addAll(event.metrics);
    final current = _latest;
    if (current != null) {
      _latest = current.copyWith(bodyComposition: Map.of(_bodyComposition));
    }
    if (_stable != null) {
      _stable = _stable!.copyWith(bodyComposition: Map.of(_bodyComposition));
    }
  }

  /// Completes the current cycle if there is an acceptable reading.
  ///
  /// [requiresStable] is true for the CID 86 weight scale, which emits an
  /// explicit live/stable pair. The eight-electrode family emits one weight
  /// stream and a separate finish state, so its last reading is used.
  Measurement? complete({
    required bool requiresStable,
    required String? deviceLabel,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final reading = requiresStable ? _stable : _latest;
    if (reading == null) return null;
    if (_lastReadingAt == null) return null;
    if (at.difference(_lastReadingAt!).abs() > completionTimeout) return null;
    if (!reading.kilograms.isFinite || reading.kilograms <= 0) return null;

    final measurement = _toMeasurement(
      reading,
      at: at,
      status: MeasurementStatus.complete,
      deviceLabel: deviceLabel,
    );
    _clearReading();
    return measurement;
  }

  /// A user-initiated capture of the current live value.
  Measurement? manualSave({required String? deviceLabel, DateTime? now}) {
    final reading = _latest;
    if (reading == null) return null;
    if (!reading.kilograms.isFinite || reading.kilograms <= 0) return null;
    final measurement = _toMeasurement(
      reading,
      at: now ?? DateTime.now(),
      status: MeasurementStatus.manual,
      deviceLabel: deviceLabel,
    );
    _clearReading();
    return measurement;
  }

  void reset() {
    _latest = null;
    _stable = null;
    _lastReadingAt = null;
    _bodyComposition.clear();
  }

  Measurement _toMeasurement(
    WeightReading reading, {
    required DateTime at,
    required MeasurementStatus status,
    required String? deviceLabel,
  }) {
    return Measurement(
      id: newMeasurementId(),
      measuredAt: at.toUtc(),
      weightKg: reading.kilograms,
      originalValue: reading.value,
      originalUnit: reading.unit,
      decimals: reading.decimals,
      status: status,
      stability: status == MeasurementStatus.manual
          ? MeasurementStability.manual
          : reading.stable
          ? MeasurementStability.stable
          : MeasurementStability.completionOnly,
      sourceProtocol: reading.sourceProtocol,
      sourceDeviceLabel: deviceLabel,
      bodyComposition: Map.of(_bodyComposition),
      impedanceOhm: reading.impedanceOhm,
      algorithmId: reading.algorithmId,
      bodyCompositionEstimated: reading.bodyCompositionEstimated,
      note: reading.isInfant ? 'Infant mode reading' : null,
    );
  }

  void _clearReading() {
    _latest = null;
    _stable = null;
    _lastReadingAt = null;
    _bodyComposition.clear();
  }
}

const Uuid _uuid = Uuid();

/// Local-only unique ID. It never leaves the device.
String newMeasurementId() => _uuid.v4();

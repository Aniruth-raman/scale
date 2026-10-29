import '../core/units.dart';
import '../domain/measurement.dart';

/// Repository boundary used by the UI and BLE layers.
abstract class MeasurementRepository {
  Future<List<Measurement>> getAll({String? profileId});
  Future<Measurement?> latest({String? profileId});
  Future<SaveOutcome> save(
    Measurement measurement, {
    Duration duplicateWindow = const Duration(seconds: 15),
  });
  Future<void> delete(String id);
  Future<void> deleteAll({String? profileId});
}

enum SaveOutcome { inserted, duplicate }

/// A pure CSV exporter so it can be tested without files or plugins.
class MeasurementCsv {
  static String build(List<Measurement> measurements) {
    final buffer = StringBuffer();
    buffer.writeln(
      'id,profile_id,measured_at_utc,weight_kg,original_value,original_unit,decimals,status,stability,source_protocol,source_device,body_composition_json,body_composition_estimated,impedance_ohm,algorithm_id,note',
    );
    for (final m in measurements) {
      buffer.writeln(
        [
          _escape(m.id),
          _escape(m.profileId ?? ''),
          m.measuredAt.toUtc().toIso8601String(),
          m.weightKg.toStringAsFixed(6),
          m.originalValue.toStringAsFixed(6),
          m.originalUnit.name,
          m.decimals.toString(),
          m.status.name,
          m.stability.name,
          _escape(m.sourceProtocol),
          _escape(m.sourceDeviceLabel ?? ''),
          _escape(_json(m.bodyComposition)),
          m.bodyCompositionEstimated ? '1' : '0',
          m.impedanceOhm?.toString() ?? '',
          m.algorithmId?.toString() ?? '',
          _escape(m.note ?? ''),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  static String _json(Map<String, double> values) {
    if (values.isEmpty) return '{}';
    final entries = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '{${entries.map((e) => '"${e.key}":${e.value}').join(',')}}';
  }

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

/// Storage-facing validation of a measurement, shared by UI and tests.
bool isValidMeasurement(Measurement m) {
  if (!m.weightKg.isFinite || m.weightKg <= 0) return false;
  if (!m.originalValue.isFinite || m.originalValue < 0) return false;
  if (m.originalUnit == WeightUnit.unknown) return false;
  if (m.decimals < 0 || m.decimals > 3) return false;
  if (m.measuredAt.isAfter(
    DateTime.now().toUtc().add(const Duration(minutes: 1)),
  )) {
    return false;
  }
  return true;
}

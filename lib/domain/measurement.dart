import 'package:meta/meta.dart';

import '../core/units.dart';

/// A body-composition metric that was actually reported by the device.
///
/// The keys come from the dual-MCU branch of the decompiled eight-electrode
/// decoder. They are never synthesized locally.
@immutable
class BodyMetric {
  const BodyMetric({
    required this.key,
    required this.label,
    required this.unit,
    this.decimals = 1,
  });

  final String key;
  final String label;
  final String unit;
  final int decimals;

  String format(double? value) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
  }
}

const List<BodyMetric> bodyMetrics = [
  BodyMetric(key: 'bmi', label: 'BMI', unit: ''),
  BodyMetric(key: 'bodyFatPercent', label: 'Body fat', unit: '%'),
  BodyMetric(key: 'bodyWaterPercent', label: 'Body water', unit: '%'),
  BodyMetric(key: 'musclePercent', label: 'Muscle', unit: '%'),
  BodyMetric(key: 'boneMassKg', label: 'Bone mass', unit: 'kg'),
  BodyMetric(key: 'proteinPercent', label: 'Protein', unit: '%'),
  BodyMetric(key: 'visceralFat', label: 'Visceral fat', unit: ''),
  BodyMetric(key: 'bmrKcal', label: 'BMR', unit: 'kcal', decimals: 0),
  BodyMetric(
    key: 'bodyAgeYears',
    label: 'Body age',
    unit: 'years',
    decimals: 0,
  ),
  BodyMetric(key: 'bodyScore', label: 'Body score', unit: '', decimals: 0),
  BodyMetric(key: 'fatMassKg', label: 'Fat mass', unit: 'kg'),
  BodyMetric(key: 'leanMassKg', label: 'Lean mass', unit: 'kg'),
  BodyMetric(key: 'muscleMassKg', label: 'Muscle mass', unit: 'kg'),
  BodyMetric(key: 'muscleControlKg', label: 'Muscle control', unit: 'kg'),
  BodyMetric(key: 'skeletalMuscleKg', label: 'Skeletal muscle', unit: 'kg'),
  BodyMetric(key: 'waterKg', label: 'Water mass', unit: 'kg'),
  BodyMetric(key: 'proteinMassKg', label: 'Protein mass', unit: 'kg'),
  BodyMetric(key: 'weightWithoutKg', label: 'Weight without fat', unit: 'kg'),
  BodyMetric(key: 'standardWeightKg', label: 'Standard weight', unit: 'kg'),
  BodyMetric(key: 'weightControlKg', label: 'Weight control', unit: 'kg'),
  BodyMetric(
    key: 'obesityIndex',
    label: 'Obesity index',
    unit: '%',
    decimals: 0,
  ),
  BodyMetric(key: 'bodyFatKgCon', label: 'Body-fat control', unit: 'kg'),
  BodyMetric(
    key: 'subcutaneousFatPercent',
    label: 'Subcutaneous fat',
    unit: '%',
  ),
  BodyMetric(key: 'whr', label: 'Waist-hip ratio', unit: ''),
  BodyMetric(key: 'fatMassLeftArmKg', label: 'Fat mass, left arm', unit: 'kg'),
  BodyMetric(
    key: 'fatMassRightArmKg',
    label: 'Fat mass, right arm',
    unit: 'kg',
  ),
  BodyMetric(key: 'fatMassBodyKg', label: 'Fat mass, trunk', unit: 'kg'),
  BodyMetric(key: 'fatMassLeftLegKg', label: 'Fat mass, left leg', unit: 'kg'),
  BodyMetric(
    key: 'fatMassRightLegKg',
    label: 'Fat mass, right leg',
    unit: 'kg',
  ),
  BodyMetric(key: 'muscleMassLeftArmKg', label: 'Muscle, left arm', unit: 'kg'),
  BodyMetric(
    key: 'muscleMassRightArmKg',
    label: 'Muscle, right arm',
    unit: 'kg',
  ),
  BodyMetric(key: 'muscleMassBodyKg', label: 'Muscle, trunk', unit: 'kg'),
  BodyMetric(key: 'muscleMassLeftLegKg', label: 'Muscle, left leg', unit: 'kg'),
  BodyMetric(
    key: 'muscleMassRightLegKg',
    label: 'Muscle, right leg',
    unit: 'kg',
  ),
  BodyMetric(key: 'fatMassBodyPercent', label: 'Fat, trunk', unit: '%'),
  BodyMetric(key: 'fatMassLeftLegPercent', label: 'Fat, left leg', unit: '%'),
  BodyMetric(key: 'fatMassRightLegPercent', label: 'Fat, right leg', unit: '%'),
  BodyMetric(key: 'fatMassLeftArmPercent', label: 'Fat, left arm', unit: '%'),
  BodyMetric(key: 'fatMassRightArmPercent', label: 'Fat, right arm', unit: '%'),
  BodyMetric(key: 'muscleMassBodyPercent', label: 'Muscle, trunk', unit: '%'),
  BodyMetric(
    key: 'muscleMassLeftLegPercent',
    label: 'Muscle, left leg',
    unit: '%',
  ),
  BodyMetric(
    key: 'muscleMassRightLegPercent',
    label: 'Muscle, right leg',
    unit: '%',
  ),
  BodyMetric(
    key: 'muscleMassLeftArmPercent',
    label: 'Muscle, left arm',
    unit: '%',
  ),
  BodyMetric(
    key: 'muscleMassRightArmPercent',
    label: 'Muscle, right arm',
    unit: '%',
  ),
];

BodyMetric? bodyMetricFor(String key) {
  for (final metric in bodyMetrics) {
    if (metric.key == key) return metric;
  }
  return null;
}

enum MeasurementStatus {
  /// The scale emitted an explicit completion signal.
  complete,

  /// The user deliberately saved a live reading.
  manual,
}

/// How the saved reading was stabilised.
///
/// The weight-only family reports an explicit stable packet. The
/// eight-electrode family reports only a completion state, so its stability is
/// recorded as `completionOnly` rather than guessed.
enum MeasurementStability { stable, completionOnly, manual }

@immutable
class Measurement {
  const Measurement({
    required this.id,
    required this.measuredAt,
    required this.weightKg,
    required this.originalValue,
    required this.originalUnit,
    required this.decimals,
    required this.status,
    required this.sourceProtocol,
    this.profileId,
    this.stability = MeasurementStability.completionOnly,
    this.sourceDeviceLabel,
    this.bodyComposition = const {},
    this.impedanceOhm,
    this.algorithmId,
    this.bodyCompositionEstimated = false,
    this.note,
  });

  final String id;
  final DateTime measuredAt;
  final double weightKg;
  final double originalValue;
  final WeightUnit originalUnit;
  final int decimals;
  final MeasurementStatus status;
  final String? profileId;
  final MeasurementStability stability;
  final String sourceProtocol;
  final String? sourceDeviceLabel;
  final Map<String, double> bodyComposition;
  final int? impedanceOhm;
  final int? algorithmId;

  /// True when the body-composition map was calculated locally from weight +
  /// impedance, not transmitted by the scale.
  final bool bodyCompositionEstimated;
  final String? note;

  Measurement copyWith({
    DateTime? measuredAt,
    double? weightKg,
    double? originalValue,
    WeightUnit? originalUnit,
    int? decimals,
    MeasurementStatus? status,
    String? profileId,
    MeasurementStability? stability,
    String? sourceProtocol,
    String? sourceDeviceLabel,
    Map<String, double>? bodyComposition,
    int? impedanceOhm,
    int? algorithmId,
    bool? bodyCompositionEstimated,
    String? note,
  }) {
    return Measurement(
      id: id,
      measuredAt: measuredAt ?? this.measuredAt,
      weightKg: weightKg ?? this.weightKg,
      originalValue: originalValue ?? this.originalValue,
      originalUnit: originalUnit ?? this.originalUnit,
      decimals: decimals ?? this.decimals,
      status: status ?? this.status,
      profileId: profileId ?? this.profileId,
      stability: stability ?? this.stability,
      sourceProtocol: sourceProtocol ?? this.sourceProtocol,
      sourceDeviceLabel: sourceDeviceLabel ?? this.sourceDeviceLabel,
      bodyComposition: bodyComposition ?? this.bodyComposition,
      impedanceOhm: impedanceOhm ?? this.impedanceOhm,
      algorithmId: algorithmId ?? this.algorithmId,
      bodyCompositionEstimated:
          bodyCompositionEstimated ?? this.bodyCompositionEstimated,
      note: note ?? this.note,
    );
  }
}

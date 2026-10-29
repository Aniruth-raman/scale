import 'package:scale/core/units.dart';
import 'package:scale/domain/metric_report.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, double> _estimate({double fat = 20}) => {
  'bmi': 22.9,
  'bodyFatPercent': fat,
  'subcutaneousFatPercent': 17.9,
  'visceralFat': 7,
  'musclePercent': 45,
  'bmrKcal': 1600,
  'boneMassKg': 3,
  'bodyWaterPercent': 55,
  'bodyAgeYears': 29,
  'proteinPercent': 16,
};

void main() {
  test('full profile reports about twenty labelled metrics', () {
    final report = buildMetricReport(
      weightKg: 70,
      values: _estimate(),
      unit: DisplayUnit.kg,
      sex: 'male',
      age: 30,
      heightCm: 175,
      impedanceOhm: 500,
    );

    expect(report.profileComplete, isTrue);
    expect(report.metrics.length, greaterThanOrEqualTo(20));
    final keys = report.metrics.map((m) => m.key).toList();
    expect(keys.toSet(), hasLength(keys.length), reason: 'no duplicates');
    expect(
      keys,
      containsAll([
        'weight',
        'bmi',
        'standardWeightKg',
        'weightControlKg',
        'obesityIndex',
        'obesityRating',
        'bodyFatPercent',
        'fatMassKg',
        'leanMassKg',
        'musclePercent',
        'muscleMassKg',
        'bodyWaterPercent',
        'waterKg',
        'boneMassKg',
        'proteinPercent',
        'proteinMassKg',
        'visceralFat',
        'subcutaneousFatPercent',
        'bmrKcal',
        'bodyAgeYears',
        'bodyType',
        'impedanceOhm',
      ]),
    );
    for (final metric in report.metrics) {
      expect(metric.value, isNotEmpty, reason: metric.key);
    }
  });

  test('fat and lean mass add up to the measured weight', () {
    final report = buildMetricReport(
      weightKg: 80,
      values: _estimate(fat: 25),
      unit: DisplayUnit.kg,
      sex: 'male',
      age: 30,
      heightCm: 180,
    );
    final byKey = {for (final m in report.metrics) m.key: m};
    expect(byKey['fatMassKg']!.value, '20.0 kg');
    expect(byKey['leanMassKg']!.value, '60.0 kg');
  });

  test('missing sex still reports values but flags the missing bands', () {
    final report = buildMetricReport(
      weightKg: 70,
      values: _estimate(),
      unit: DisplayUnit.kg,
    );
    expect(report.profileComplete, isFalse);
    final byKey = {for (final m in report.metrics) m.key: m};
    expect(byKey['bodyFatPercent']!.status!.label, 'Set sex in profile');
    expect(byKey.containsKey('bodyType'), isFalse);
    expect(byKey['bmi']!.status!.tone, MetricTone.good);
  });

  test('BMI bands follow the WHO Asian cutoffs', () {
    MetricTone toneAt(double bmi) {
      final report = buildMetricReport(
        weightKg: 70,
        values: {'bmi': bmi},
        unit: DisplayUnit.kg,
        sex: 'male',
        age: 30,
        heightCm: 175,
      );
      return report.metrics.firstWhere((m) => m.key == 'bmi').status!.tone;
    }

    expect(toneAt(18.4), MetricTone.warn);
    expect(toneAt(18.5), MetricTone.good);
    expect(toneAt(23), MetricTone.warn);
    expect(toneAt(25), MetricTone.bad);
    expect(toneAt(30), MetricTone.bad);
  });

  test('out-of-range body fat is marked bad', () {
    final report = buildMetricReport(
      weightKg: 70,
      values: {'bodyFatPercent': 30},
      unit: DisplayUnit.kg,
      sex: 'male',
      age: 30,
      heightCm: 175,
    );
    expect(
      report.metrics.firstWhere((m) => m.key == 'bodyFatPercent').status!.tone,
      MetricTone.bad,
    );
  });
}

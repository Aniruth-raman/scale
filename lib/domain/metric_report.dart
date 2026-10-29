import '../core/units.dart';
import 'measurement.dart';

/// Label-only colouring for a metric. Never changes a stored value.
enum MetricTone { good, warn, bad, neutral }

class MetricStatus {
  const MetricStatus(this.label, this.tone, [this.range]);

  final String label;
  final MetricTone tone;
  final String? range;
}

class MetricDisplay {
  const MetricDisplay({
    required this.key,
    required this.label,
    required this.value,
    this.status,
    this.detail,
  });

  final String key;
  final String label;
  final String value;
  final MetricStatus? status;
  final String? detail;
}

class MetricReport {
  const MetricReport({required this.metrics, required this.profileComplete});

  final List<MetricDisplay> metrics;
  final bool profileComplete;

  bool get isEmpty => metrics.isEmpty;
}

/// Builds display-ready body-composition metrics with range labels.
///
/// Bands are labels only. Sources: WHO Asian BMI cutoffs, ACE/ACSM body-fat
/// bands, typical BIA water/muscle bands, and Mifflin-St Jeor for BMR.
/// Ported from the MIT-licensed `anxkhn/localscale` ReferenceRanges.kt.
MetricReport buildMetricReport({
  required double weightKg,
  required Map<String, double> values,
  required DisplayUnit unit,
  String? sex,
  int? age,
  int? heightCm,
  int? impedanceOhm,
}) {
  final male = sex == 'male';
  final female = sex == 'female';
  final knownSex = male || female;
  final profileComplete = knownSex && age != null && heightCm != null;
  final data = Map<String, double>.from(values);

  final heightM = heightCm == null ? null : heightCm / 100.0;
  final ideal = heightM == null ? null : 22.0 * heightM * heightM;
  final predictedBmr = profileComplete
      ? (10 * weightKg + 6.25 * heightCm - 5 * age + (male ? 5 : -161)).round()
      : null;

  if (ideal != null && ideal > 0 && weightKg > 0) {
    data.putIfAbsent('standardWeightKg', () => ideal);
    data.putIfAbsent('weightControlKg', () => weightKg - ideal);
    data.putIfAbsent('obesityIndex', () => weightKg / ideal * 100);
  }
  double? share(String percentKey) {
    final percent = data[percentKey];
    if (percent == null || weightKg <= 0) {
      return null;
    }
    return weightKg * percent / 100;
  }

  final fatMass = share('bodyFatPercent');
  if (fatMass != null) {
    data['fatMassKg'] = fatMass;
    data['leanMassKg'] = weightKg - fatMass;
  }
  final muscleMass = share('musclePercent');
  if (muscleMass != null) {
    data['muscleMassKg'] = muscleMass;
  }
  final waterMass = share('bodyWaterPercent');
  if (waterMass != null) {
    data['waterKg'] = waterMass;
  }
  final proteinMass = share('proteinPercent');
  if (proteinMass != null) {
    data['proteinMassKg'] = proteinMass;
  }

  final bmi = data['bmi'];
  final bmiStatus = bmi == null ? null : _bmiStatus(bmi);
  final fat = data['bodyFatPercent'];
  final fatStatus = fat == null
      ? null
      : _bodyFatStatus(fat, male: male, female: female);
  final muscle = data['musclePercent'];
  final muscleStatus = muscle == null
      ? null
      : _muscleStatus(muscle, male: male, female: female);
  final water = data['bodyWaterPercent'];
  final waterStatus = water == null
      ? null
      : _waterStatus(water, male: male, female: female);
  final bone = data['boneMassKg'];
  final boneStatus = bone == null ? null : _boneStatus(bone, weightKg);
  final protein = data['proteinPercent'];
  final proteinStatus = protein == null ? null : _proteinStatus(protein);
  final visceral = data['visceralFat'];
  final visceralStatus = visceral == null
      ? null
      : _visceralStatus(visceral.round());
  final subcutaneous = data['subcutaneousFatPercent'];
  final subcutaneousStatus = subcutaneous == null
      ? null
      : _subcutaneousStatus(subcutaneous, male: male, female: female);
  final bmr = data['bmrKcal'];
  final bmrStatus = bmr == null ? null : _bmrStatus(bmr.round(), predictedBmr);
  final bodyAge = data['bodyAgeYears'];
  final bodyAgeStatus = bodyAge == null || age == null
      ? null
      : _bodyAgeStatus(bodyAge.round(), age);
  final obesity = data['obesityIndex'];
  final obesityStatus = obesity == null ? null : _obesityStatus(obesity);

  final metrics = <MetricDisplay>[];

  void add(String key, {MetricStatus? status, String? value, String? detail}) {
    final metric = bodyMetricFor(key);
    final raw = data[key];
    if (metric == null || raw == null) return;
    metrics.add(
      MetricDisplay(
        key: key,
        label: metric.label,
        value: value ?? metric.format(raw),
        status: status,
        detail: detail ?? status?.range,
      ),
    );
  }

  metrics.add(
    MetricDisplay(
      key: 'weight',
      label: 'Body weight',
      value: formatWeight(weightKg, unit, decimals: 1),
      status: _weightStatus(weightKg, ideal),
      detail: ideal == null
          ? null
          : 'Ideal ${formatWeight(ideal, unit, decimals: 1)}',
    ),
  );
  add('bmi', status: bmiStatus);
  add(
    'standardWeightKg',
    status: const MetricStatus('BMI 22 target', MetricTone.neutral),
  );
  add(
    'weightControlKg',
    status: _weightControlStatus(weightKg, ideal),
    value: data['weightControlKg'] == null
        ? null
        : _signedWeight(data['weightControlKg']!, unit),
  );
  add('obesityIndex', status: obesityStatus);
  if (bmiStatus != null) {
    metrics.add(
      MetricDisplay(
        key: 'obesityRating',
        label: 'Obesity rating',
        value: bmiStatus.label,
        status: bmiStatus,
        detail: bmiStatus.range,
      ),
    );
  }
  add('bodyFatPercent', status: fatStatus);
  add('fatMassKg', status: fatStatus);
  add(
    'leanMassKg',
    status: const MetricStatus('Informational', MetricTone.neutral),
  );
  add('musclePercent', status: muscleStatus);
  add('muscleMassKg', status: muscleStatus);
  add('bodyWaterPercent', status: waterStatus);
  add('waterKg', status: waterStatus);
  add('boneMassKg', status: boneStatus);
  add('proteinPercent', status: proteinStatus);
  add('proteinMassKg', status: proteinStatus);
  add('visceralFat', status: visceralStatus);
  add('subcutaneousFatPercent', status: subcutaneousStatus);
  add('bmrKcal', status: bmrStatus);
  add('bodyAgeYears', status: bodyAgeStatus);
  if (fat != null && muscle != null && knownSex) {
    final type = _bodyType(fat, muscle, male: male);
    metrics.add(
      MetricDisplay(
        key: 'bodyType',
        label: 'Body type',
        value: type.label,
        status: type,
      ),
    );
  }
  // Keep any additional metric a connected scale transmitted but the report
  // does not know how to band.
  for (final metric in bodyMetrics) {
    final raw = data[metric.key];
    if (raw == null || metrics.any((m) => m.key == metric.key)) {
      continue;
    }
    metrics.add(
      MetricDisplay(
        key: metric.key,
        label: metric.label,
        value: metric.format(raw),
      ),
    );
  }
  if (impedanceOhm != null) {
    metrics.add(
      MetricDisplay(
        key: 'impedanceOhm',
        label: 'Impedance',
        value: '$impedanceOhm Ω',
        status: const MetricStatus('Raw from scale', MetricTone.neutral),
        detail: 'Used for the estimate',
      ),
    );
  }

  return MetricReport(metrics: metrics, profileComplete: profileComplete);
}

String _range(double low, double high) => '${_num(low)}–${_num(high)}';

String _num(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

String _signedWeight(double kg, DisplayUnit unit) {
  final shown = formatWeight(kg, unit, decimals: 1);
  return kg >= 0 ? '+$shown' : shown;
}

MetricStatus _bmiStatus(double v) {
  if (v < 18.5) {
    return const MetricStatus(
      'Underweight',
      MetricTone.warn,
      'WHO Asian < 18.5',
    );
  }
  if (v < 23) {
    return const MetricStatus(
      'Standard',
      MetricTone.good,
      'WHO Asian 18.5–22.9',
    );
  }
  if (v < 25) {
    return const MetricStatus(
      'Overweight',
      MetricTone.warn,
      'WHO Asian 23–24.9',
    );
  }
  if (v < 30) {
    return const MetricStatus('Obese I', MetricTone.bad, 'WHO Asian 25–29.9');
  }
  return const MetricStatus('Obese II+', MetricTone.bad, 'WHO Asian 30+');
}

MetricStatus _weightStatus(double weight, double? ideal) {
  if (ideal == null || ideal <= 0) {
    return const MetricStatus('Add height', MetricTone.neutral);
  }
  final ratio = weight / ideal;
  if (ratio < 0.9) {
    return const MetricStatus('Below target', MetricTone.warn);
  }
  if (ratio <= 1.1) {
    return const MetricStatus('Near target', MetricTone.good);
  }
  if (ratio <= 1.2) {
    return const MetricStatus('Above target', MetricTone.warn);
  }
  return const MetricStatus('Well above target', MetricTone.bad);
}

MetricStatus _bodyFatStatus(
  double v, {
  required bool male,
  required bool female,
}) {
  if (!male && !female) {
    return const MetricStatus('Set sex in profile', MetricTone.neutral);
  }
  if (male) {
    if (v < 6) {
      return const MetricStatus('Essential', MetricTone.warn, 'ACE men < 6%');
    }
    if (v < 14) {
      return const MetricStatus('Athletic', MetricTone.good, 'ACE 6–13%');
    }
    if (v < 18) {
      return const MetricStatus('Fitness', MetricTone.good, 'ACE 14–17%');
    }
    if (v < 25) {
      return const MetricStatus('Average', MetricTone.neutral, 'ACE 18–24%');
    }
    return const MetricStatus('High', MetricTone.bad, 'ACE 25%+');
  }
  if (v < 14) {
    return const MetricStatus('Essential', MetricTone.warn, 'ACE women < 14%');
  }
  if (v < 21) {
    return const MetricStatus('Athletic', MetricTone.good, 'ACE 14–20%');
  }
  if (v < 25) {
    return const MetricStatus('Fitness', MetricTone.good, 'ACE 21–24%');
  }
  if (v < 32) {
    return const MetricStatus('Average', MetricTone.neutral, 'ACE 25–31%');
  }
  return const MetricStatus('High', MetricTone.bad, 'ACE 32%+');
}

MetricStatus _waterStatus(
  double v, {
  required bool male,
  required bool female,
}) {
  if (!male && !female) {
    return const MetricStatus('Set sex in profile', MetricTone.neutral);
  }
  final low = male ? 50.0 : 45.0;
  final high = male ? 65.0 : 60.0;
  if (v < low) {
    return MetricStatus(
      'Low',
      MetricTone.warn,
      'Typical ${_range(low, high)}%',
    );
  }
  if (v <= high) {
    return MetricStatus(
      'Standard',
      MetricTone.good,
      'Typical ${_range(low, high)}%',
    );
  }
  return const MetricStatus('Above typical', MetricTone.warn);
}

MetricStatus _muscleStatus(
  double v, {
  required bool male,
  required bool female,
}) {
  if (!male && !female) {
    return const MetricStatus('Set sex in profile', MetricTone.neutral);
  }
  final low = male ? 40.0 : 30.0;
  final high = male ? 54.0 : 47.0;
  if (v < low) {
    return MetricStatus(
      'Low',
      MetricTone.warn,
      'Typical ${_range(low, high)}%',
    );
  }
  if (v <= high) {
    return MetricStatus(
      'Standard',
      MetricTone.good,
      'Typical ${_range(low, high)}%',
    );
  }
  return MetricStatus(
    'Above typical',
    MetricTone.good,
    'Typical ${_range(low, high)}%',
  );
}

MetricStatus _visceralStatus(int v) {
  if (v <= 9) {
    return const MetricStatus('Standard', MetricTone.good, 'BIA index 1–9');
  }
  if (v <= 14) {
    return const MetricStatus('High', MetricTone.warn, 'BIA index 10–14');
  }
  return const MetricStatus('Very high', MetricTone.bad, 'BIA index 15+');
}

MetricStatus _subcutaneousStatus(
  double v, {
  required bool male,
  required bool female,
}) {
  if (!male && !female) {
    return const MetricStatus('Set sex in profile', MetricTone.neutral);
  }
  final high = male ? 20.0 : 25.0;
  if (v < 10) {
    return const MetricStatus('Low', MetricTone.warn, 'Typical 10%+');
  }
  if (v <= high) {
    return MetricStatus(
      'Standard',
      MetricTone.good,
      'Typical ${_range(10, high)}%',
    );
  }
  return MetricStatus(
    'A little high',
    MetricTone.warn,
    'Above ${_range(10, high)}%',
  );
}

MetricStatus _boneStatus(double kg, double weight) {
  final percent = weight > 0 ? kg / weight * 100 : 0.0;
  if (percent < 3) {
    return const MetricStatus(
      'Low',
      MetricTone.warn,
      'Typical 3–5.5% of weight',
    );
  }
  if (percent <= 5.5) {
    return const MetricStatus(
      'Standard',
      MetricTone.good,
      'Typical 3–5.5% of weight',
    );
  }
  return const MetricStatus(
    'Above typical',
    MetricTone.neutral,
    'Typical 3–5.5% of weight',
  );
}

MetricStatus _proteinStatus(double v) {
  if (v < 14) {
    return const MetricStatus('Low', MetricTone.warn, 'Typical 14–18%');
  }
  if (v <= 18) {
    return const MetricStatus('Standard', MetricTone.good, 'Typical 14–18%');
  }
  return const MetricStatus(
    'Above typical',
    MetricTone.neutral,
    'Typical 14–18%',
  );
}

MetricStatus _bmrStatus(int measured, int? predicted) {
  if (predicted == null || predicted <= 0) {
    return const MetricStatus('Add profile', MetricTone.neutral);
  }
  final ratio = measured / predicted;
  if (ratio < 0.9) {
    return MetricStatus(
      'Below predicted',
      MetricTone.warn,
      'Mifflin-St Jeor $predicted kcal',
    );
  }
  if (ratio <= 1.1) {
    return MetricStatus(
      'Near predicted',
      MetricTone.good,
      'Mifflin-St Jeor $predicted kcal',
    );
  }
  return MetricStatus(
    'Above predicted',
    MetricTone.neutral,
    'Mifflin-St Jeor $predicted kcal',
  );
}

MetricStatus _bodyAgeStatus(int bodyAge, int age) {
  final delta = bodyAge - age;
  if (delta <= -3) {
    return MetricStatus('Younger', MetricTone.good, 'Chronological $age');
  }
  if (delta >= 3) {
    return MetricStatus('Older', MetricTone.warn, 'Chronological $age');
  }
  return MetricStatus('Similar', MetricTone.good, 'Chronological $age');
}

MetricStatus _obesityStatus(double index) {
  if (index < 90) {
    return const MetricStatus('Low', MetricTone.warn, 'Ideal 90–110%');
  }
  if (index <= 110) {
    return const MetricStatus('Standard', MetricTone.good, 'Ideal 90–110%');
  }
  if (index <= 120) {
    return const MetricStatus('High', MetricTone.warn, 'Ideal 90–110%');
  }
  return const MetricStatus('High', MetricTone.bad, 'Ideal 90–110%');
}

MetricStatus _weightControlStatus(double weight, double? ideal) {
  if (ideal == null) {
    return const MetricStatus('Add height', MetricTone.neutral);
  }
  final delta = weight - ideal;
  if (delta.abs() <= 2) {
    return const MetricStatus('Near target', MetricTone.good);
  }
  return MetricStatus(
    delta > 0 ? 'Above target' : 'Below target',
    MetricTone.warn,
    'Ideal ${ideal.toStringAsFixed(1)} kg',
  );
}

MetricStatus _bodyType(double fat, double muscle, {required bool male}) {
  final fatHigh = male ? 25.0 : 32.0;
  final muscleLow = male ? 40.0 : 30.0;
  if (fat >= fatHigh && muscle < muscleLow) {
    return const MetricStatus('Hidden obese', MetricTone.bad);
  }
  if (fat >= fatHigh) {
    return const MetricStatus('Overweight', MetricTone.bad);
  }
  if (muscle >= muscleLow + 6) {
    return const MetricStatus('Muscular', MetricTone.good);
  }
  if (fat < (male ? 14.0 : 21.0) && muscle >= muscleLow) {
    return const MetricStatus('Lean', MetricTone.good);
  }
  return const MetricStatus('Average', MetricTone.neutral);
}

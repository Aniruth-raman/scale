import 'dart:math' as math;

/// Open Jinghuawei/Aicare body-composition formulas (algorithm id 1).
///
/// Ported from the MIT-licensed `anxkhn/localscale`
/// (`domain/JinghuaweiAlgorithm.kt`), itself a port of Elink's published iOS
/// `AlgorithmSDK.m`. These values are estimates from weight + impedance, not
/// data transmitted by the scale.
enum EstimationSex { male, female }

class BodyCompositionEstimate {
  const BodyCompositionEstimate({
    required this.bmi,
    required this.bodyFatPercent,
    required this.subcutaneousFatPercent,
    required this.visceralFat,
    required this.musclePercent,
    required this.bmrKcal,
    required this.boneMassKg,
    required this.bodyWaterPercent,
    required this.bodyAgeYears,
    required this.proteinPercent,
  });

  final double bmi;
  final double bodyFatPercent;
  final double subcutaneousFatPercent;
  final int visceralFat;
  final double musclePercent;
  final int bmrKcal;
  final double boneMassKg;
  final double bodyWaterPercent;
  final int bodyAgeYears;
  final double proteinPercent;

  Map<String, double> toMap() => {
    'bmi': bmi,
    'bodyFatPercent': bodyFatPercent,
    'subcutaneousFatPercent': subcutaneousFatPercent,
    'visceralFat': visceralFat.toDouble(),
    'musclePercent': musclePercent,
    'bmrKcal': bmrKcal.toDouble(),
    'boneMassKg': boneMassKg,
    'bodyWaterPercent': bodyWaterPercent,
    'bodyAgeYears': bodyAgeYears.toDouble(),
    'proteinPercent': proteinPercent,
  };
}

BodyCompositionEstimate? estimateBodyComposition({
  required double weightKg,
  required int impedanceOhm,
  required EstimationSex sex,
  required int age,
  required int heightCm,
}) {
  if (weightKg <= 0 || weightKg > 220) return null;
  if (age < 0 || age > 120) return null;
  if (heightCm < 1 || heightCm > 269) return null;
  if (impedanceOhm < 1 || impedanceOhm > 1000) return null;

  final heightM = heightCm / 100.0;
  final bmi = _oneDecimalUp(weightKg / (heightM * heightM));
  final bone = _boneMass(sex, heightM, age, impedanceOhm, weightKg);
  final muscle = _musclePercent(sex, weightKg, heightM, age, impedanceOhm);
  final water = _waterPercent(sex, bmi, impedanceOhm, age);
  final fat = _bodyFatPercent(sex, bmi, impedanceOhm, age);
  final sub = _subcutaneous(sex, age, fat);
  final protein = _proteinPercent(fat, water, bone, weightKg, age, sex);
  final visceral = _visceralFat(sex, weightKg, heightM, age, impedanceOhm);
  final bmr = _bmrKcal(sex, weightKg, heightM, age, impedanceOhm);
  final bodyAge = _bodyAge(age, bmi, sex);

  return BodyCompositionEstimate(
    bmi: bmi,
    bodyFatPercent: _oneDecimalUp(fat),
    subcutaneousFatPercent: _oneDecimal(sub),
    visceralFat: visceral,
    musclePercent: _oneDecimal(muscle),
    bmrKcal: bmr,
    boneMassKg: _oneDecimal(bone),
    bodyWaterPercent: _oneDecimal(water),
    bodyAgeYears: bodyAge,
    proteinPercent: _oneDecimal(protein),
  );
}

double _boneMass(
  EstimationSex sex,
  double heightM,
  int age,
  int adc,
  double weight,
) {
  if (age < 10) return 1.0;
  var bm = switch (sex) {
    EstimationSex.male when age < 15 =>
      0.015 * weight + (2 - 0.00055 * adc) * heightM + 0.035 * age - 1.79,
    EstimationSex.male => 0.015 * weight + (2 - 0.00055 * adc) * heightM - 1.15,
    _ =>
      0.000022 * adc * weight +
          (4.99 - 0.00284 * adc) * heightM +
          0.0012 * adc -
          4.45,
  };
  bm = bm.clamp(weight * 0.02, weight * 0.15);
  if (bm < 1.0) bm = 1.0;
  return bm;
}

double _musclePercent(
  EstimationSex sex,
  double weight,
  double heightM,
  int age,
  int adc,
) {
  if (age < 10) return 5.0;
  final rom = switch (sex) {
    EstimationSex.male when age < 16 =>
      (0.0001262 * adc + 0.2196) * weight +
          (49.64 - 0.031 * adc) * heightM +
          0.018 * adc +
          0.52 * age -
          46.5,
    EstimationSex.male =>
      (0.0001262 * adc + 0.2196) * weight +
          (49.64 - 0.031 * adc) * heightM +
          0.018 * adc -
          36.12,
    _ when age < 16 =>
      (0.0001555 * adc + 0.0448) * weight +
          (55.76 - 0.032 * adc) * heightM +
          0.0225 * adc -
          44.41,
    _ =>
      (0.0001555 * adc + 0.0448) * weight +
          (55.76 - 0.032 * adc) * heightM +
          0.026 * adc -
          45.51,
  };
  return rom.clamp(15.0, 75.0);
}

double _waterPercent(EstimationSex sex, double bmi, int adc, int age) {
  if (age < 5) return 60.0;
  final moi = sex == EstimationSex.male
      ? 1000000 / (bmi * (2.688 * adc - 78.28)) -
            10058.0 / adc -
            0.05 * age +
            47.1
      : 1000000 / (bmi * (2.467 * adc - 75.37)) -
            14215.0 / adc -
            0.034 * age +
            43.2;
  return moi.clamp(20.0, 70.0);
}

double _bodyFatPercent(EstimationSex sex, double bmi, int adc, int age) {
  if (age < 10) return 5.0;
  final bfr = switch (sex) {
    EstimationSex.male when age < 15 =>
      -1000000 / (bmi * (1.966 * adc - 58.46)) +
          13176.0 / adc -
          1.8 * age +
          67.04,
    EstimationSex.male =>
      -1000000 / (bmi * (1.966 * adc - 58.46)) +
          13176.0 / adc +
          0.067 * age +
          36.79,
    _ when age < 15 =>
      -1000000 / (bmi * (1.803 * adc - 45.22)) +
          18911.0 / adc -
          0.485 * age +
          49.1,
    _ =>
      -1000000 / (bmi * (1.803 * adc - 45.22)) +
          18911.0 / adc +
          0.046 * age +
          41.5,
  };
  return bfr.clamp(5.0, 50.0);
}

double _subcutaneous(EstimationSex sex, int age, double bfr) {
  if (age < 5) return 10.0;
  final sfr = sex == EstimationSex.male ? 0.898 * bfr : 0.876 * bfr + 1.66;
  return math.max(sfr, 10.0);
}

double _proteinPercent(
  double bfr,
  double water,
  double bone,
  double weight,
  int age,
  EstimationSex sex,
) {
  if (age < 5) return 10.0;
  final factor = sex == EstimationSex.male ? 0.8 : 0.75;
  return (factor * (100 - bfr - water - bone / weight)).clamp(10.0, 50.0);
}

int _visceralFat(
  EstimationSex sex,
  double weight,
  double heightM,
  int age,
  int adc,
) {
  if (age < 5) return 1;
  final uvi = sex == EstimationSex.male
      ? 0.224 * weight - 25.58 * heightM + 0.151 * age + 0.005 * adc + 29.0
      : 0.183 * weight - 15.34 * heightM + 0.063 * age + 0.005 * adc + 14.2;
  return uvi.round().clamp(1, 20);
}

int _bmrKcal(
  EstimationSex sex,
  double weight,
  double heightM,
  int age,
  int adc,
) {
  if (age < 5) return 0;
  final bmr = sex == EstimationSex.male
      ? (9.937 + 0.0015 * adc) * weight +
            (1350 - 0.88 * adc) * heightM +
            3088.0 / age +
            0.748 * adc -
            1263
      : (0.00307 * adc + 7.194) * weight +
            (1459 - 0.989 * adc) * heightM +
            3105.0 / age +
            0.923 * adc -
            1386;
  return bmr.round();
}

int _bodyAge(int age, double bmi, EstimationSex sex) {
  if (age < 18) return age;
  final (ref, lowK, highK) = sex == EstimationSex.male
      ? (22.0, 0.04, 0.02)
      : (21.2, 0.04, 0.02);
  final k = bmi < ref ? lowK : highK;
  final predicted = age * (1 + k * (bmi - ref));
  return predicted.clamp(age - 10.0, age + 10.0).round();
}

double _oneDecimal(double value) => (value * 10).floor() / 10;
double _oneDecimalUp(double value) => (value * 10).round() / 10;

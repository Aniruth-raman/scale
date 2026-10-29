import 'package:scale/domain/jinghuawei_algorithm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('male estimate is within the published ranges', () {
    final result = estimateBodyComposition(
      weightKg: 70,
      impedanceOhm: 500,
      sex: EstimationSex.male,
      age: 30,
      heightCm: 175,
    );
    expect(result, isNotNull);
    expect(result!.bmi, closeTo(22.9, 0.1));
    expect(result.bodyFatPercent, inInclusiveRange(5, 50));
    expect(result.bodyWaterPercent, inInclusiveRange(20, 70));
    expect(result.musclePercent, inInclusiveRange(15, 75));
    expect(result.boneMassKg, greaterThan(0));
    expect(result.proteinPercent, inInclusiveRange(10, 50));
    expect(result.visceralFat, inInclusiveRange(1, 20));
    expect(result.bmrKcal, greaterThan(0));
    expect(result.bodyAgeYears, greaterThan(0));
    expect(
      result.toMap().keys,
      containsAll([
        'bmi',
        'bodyFatPercent',
        'bodyWaterPercent',
        'musclePercent',
        'boneMassKg',
        'proteinPercent',
        'visceralFat',
        'bmrKcal',
        'bodyAgeYears',
        'subcutaneousFatPercent',
      ]),
    );
  });

  test('missing or invalid impedance produces no estimate', () {
    expect(
      estimateBodyComposition(
        weightKg: 70,
        impedanceOhm: 0,
        sex: EstimationSex.female,
        age: 30,
        heightCm: 165,
      ),
      isNull,
    );
  });

  test('female estimate differs from male at the same inputs', () {
    final male = estimateBodyComposition(
      weightKg: 70,
      impedanceOhm: 500,
      sex: EstimationSex.male,
      age: 30,
      heightCm: 175,
    )!;
    final female = estimateBodyComposition(
      weightKg: 70,
      impedanceOhm: 500,
      sex: EstimationSex.female,
      age: 30,
      heightCm: 175,
    )!;
    expect(female.bodyFatPercent, isNot(equals(male.bodyFatPercent)));
  });
}

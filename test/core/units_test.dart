import 'package:scale/core/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unit conversion', () {
    test('kg round-trips', () {
      expect(toKilograms(70, WeightUnit.kg), 70);
      expect(formatWeight(70, DisplayUnit.kg), '70.00 kg');
    });

    test('pounds use the exact international definition', () {
      expect(toKilograms(1, WeightUnit.pound), closeTo(0.45359237, 1e-12));
      expect(fromKilograms(0.45359237, DisplayUnit.lb), closeTo(1, 1e-12));
      expect(formatWeight(70, DisplayUnit.lb), '154.32 lb');
    });

    test('stone/pounds display splits pounds without losing value', () {
      expect(formatWeight(70, DisplayUnit.stonePound), '11 st 0.3 lb');
      expect(toKilograms(154.3, WeightUnit.stonePound), closeTo(69.99, 0.01));
    });

    test('jin is half a kilogram in the decompiled app', () {
      expect(toKilograms(140, WeightUnit.jin), 70);
    });

    test('unknown unit cannot be converted', () {
      expect(() => toKilograms(1, WeightUnit.unknown), throwsArgumentError);
    });

    test('AILink unit codes are not guessed', () {
      expect(WeightUnit.fromAilinkCode(0), WeightUnit.kg);
      expect(WeightUnit.fromAilinkCode(1), WeightUnit.jin);
      expect(WeightUnit.fromAilinkCode(4), WeightUnit.stonePound);
      expect(WeightUnit.fromAilinkCode(6), WeightUnit.pound);
      expect(WeightUnit.fromAilinkCode(2), isNull);
      expect(WeightUnit.fromAilinkCode(3), isNull);
      expect(WeightUnit.fromAilinkCode(5), isNull);
    });
  });
}

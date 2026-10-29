import 'package:scale/domain/weight_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 1);

  WeightComparison compare(double current, double previous) => WeightComparison(
    currentKg: current,
    previousKg: previous,
    previousAt: at,
  );

  test('increase, decrease and tiny change resolve to a trend', () {
    expect(compare(71.0, 70.0).trend, WeightTrend.up);
    expect(compare(69.5, 70.0).trend, WeightTrend.down);
    expect(compare(70.004, 70.0).trend, WeightTrend.flat);
    expect(compare(70.0, 70.0).trend, WeightTrend.flat);
  });

  test('delta is current minus previous in kilograms', () {
    expect(compare(70.25, 70.0).deltaKg, closeTo(0.25, 1e-9));
    expect(compare(69.75, 70.0).deltaKg, closeTo(-0.25, 1e-9));
  });
}

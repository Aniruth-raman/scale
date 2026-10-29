/// Direction of a weight change against the last saved reading.
enum WeightTrend { up, down, flat }

class WeightComparison {
  const WeightComparison({
    required this.currentKg,
    required this.previousKg,
    required this.previousAt,
  });

  final double currentKg;
  final double previousKg;
  final DateTime previousAt;

  double get deltaKg => currentKg - previousKg;

  /// Changes of 5 g or less are treated as flat; this is below the scale's
  /// normal jitter and avoids flickering arrows.
  WeightTrend get trend {
    if (deltaKg.abs() < 0.005) return WeightTrend.flat;
    return deltaKg > 0 ? WeightTrend.up : WeightTrend.down;
  }
}

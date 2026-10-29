import 'package:scale/core/units.dart';
import 'package:scale/domain/weight_comparison.dart';
import 'package:scale/features/shared/weight_change.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    WeightComparison? comparison, {
    DisplayUnit unit = DisplayUnit.kg,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeightChangeText(comparison: comparison, unit: unit),
        ),
      ),
    );
  }

  testWidgets('shows an increase against the last saved reading', (
    tester,
  ) async {
    await pump(
      tester,
      WeightComparison(
        currentKg: 70.45,
        previousKg: 70.0,
        previousAt: DateTime.utc(2026, 10, 1),
      ),
    );
    expect(find.text('+0.45 kg'), findsOneWidget);
    expect(find.text('since last saved'), findsOneWidget);
    expect(find.textContaining('Previous 70.00 kg'), findsOneWidget);
  });

  testWidgets('shows a decrease in the display unit', (tester) async {
    await pump(
      tester,
      WeightComparison(
        currentKg: 69.5,
        previousKg: 70.0,
        previousAt: DateTime.utc(2026, 10, 1),
      ),
      unit: DisplayUnit.lb,
    );
    expect(find.text('-1.10 lb'), findsOneWidget);
  });

  testWidgets('shows a flat change and the first-reading case', (tester) async {
    await pump(
      tester,
      WeightComparison(
        currentKg: 70.0,
        previousKg: 70.0,
        previousAt: DateTime.utc(2026, 10, 1),
      ),
    );
    expect(find.text('0.00 kg'), findsOneWidget);
    expect(find.text('since last saved'), findsOneWidget);

    await pump(tester, null);
    expect(find.text('First saved reading for this profile'), findsOneWidget);
  });
}

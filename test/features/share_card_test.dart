import 'package:scale/core/units.dart';
import 'package:scale/domain/metric_report.dart';
import 'package:scale/features/measurement/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('share card renders the profile, weight and metric tiles', (
    tester,
  ) async {
    final report = buildMetricReport(
      weightKg: 70,
      values: const {
        'bmi': 22.9,
        'bodyFatPercent': 20,
        'musclePercent': 45,
        'bodyWaterPercent': 55,
        'boneMassKg': 3,
        'proteinPercent': 16,
        'visceralFat': 7,
        'bmrKcal': 1600,
        'bodyAgeYears': 29,
        'subcutaneousFatPercent': 18,
      },
      unit: DisplayUnit.kg,
      sex: 'male',
      age: 30,
      heightCm: 175,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShareCard(
              width: 360,
              profileName: 'Alex',
              weightText: '70.00 kg',
              dateText: '2026-01-02 03:04',
              deviceLabel: 'Synthetic scale',
              estimated: true,
              metrics: report.metrics,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('70.00 kg'), findsOneWidget);
    expect(find.text('Body fat'), findsOneWidget);
    expect(find.text('Standard'), findsWidgets);
    expect(find.textContaining('Generated on this device'), findsOneWidget);
  });
}

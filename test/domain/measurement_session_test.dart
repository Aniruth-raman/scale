import 'package:scale/core/units.dart';
import 'package:scale/data/protocol/scale_event.dart';
import 'package:scale/domain/measurement.dart';
import 'package:scale/domain/measurement_session.dart';
import 'package:flutter_test/flutter_test.dart';

WeightReading reading({
  double value = 70,
  WeightUnit unit = WeightUnit.kg,
  bool stable = false,
  DateTime? at,
}) {
  return WeightReading(
    value: value,
    unit: unit,
    decimals: 2,
    stable: stable,
    receivedAt: at ?? DateTime.utc(2026, 1, 2, 3, 4, 5),
    sourceProtocol: 'test',
  );
}

void main() {
  group('MeasurementSession', () {
    test('live-only reading is never saved automatically', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      session.onReading(ScaleReadingEvent(reading()));
      final result = session.complete(
        requiresStable: true,
        deviceLabel: 'Synthetic scale',
        now: DateTime.utc(2026, 1, 2, 3, 4, 6),
      );
      expect(result, isNull);
    });

    test(
      'stable reading plus completion creates one completed measurement',
      () {
        final session = MeasurementSession(sourceProtocol: 'test');
        final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
        session.onReading(ScaleReadingEvent(reading(stable: true, at: at)));
        final result = session.complete(
          requiresStable: true,
          deviceLabel: 'Synthetic scale',
          now: at.add(const Duration(seconds: 3)),
        );
        expect(result, isNotNull);
        expect(result!.weightKg, 70);
        expect(result.status, MeasurementStatus.complete);
        expect(result.id, isNotEmpty);
      },
    );

    test('eight-scale completion uses the latest reading', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      session.onReading(ScaleReadingEvent(reading(at: at)));
      final result = session.complete(
        requiresStable: false,
        deviceLabel: null,
        now: at.add(const Duration(seconds: 2)),
      );
      expect(result, isNotNull);
      expect(result!.weightKg, 70);
    });

    test('stale reading is rejected at completion', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      session.onReading(ScaleReadingEvent(reading(at: at)));
      final result = session.complete(
        requiresStable: false,
        deviceLabel: null,
        now: at.add(const Duration(minutes: 2)),
      );
      expect(result, isNull);
    });

    test('zero or invalid weight is rejected', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      session.onReading(ScaleReadingEvent(reading(value: 0, stable: true)));
      expect(session.complete(requiresStable: true, deviceLabel: null), isNull);
    });

    test('manual save labels the measurement as manual', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      session.onReading(ScaleReadingEvent(reading()));
      final result = session.manualSave(deviceLabel: 'Synthetic scale');
      expect(result, isNotNull);
      expect(result!.status, MeasurementStatus.manual);
    });

    test('body composition is attached to the current reading', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      session.onReading(ScaleReadingEvent(reading(stable: true, at: at)));
      session.onBodyComposition(
        const ScaleBodyCompositionEvent({'bodyFatPercent': 20.0, 'bmi': 22.5}),
      );
      final result = session.complete(
        requiresStable: true,
        deviceLabel: null,
        now: at.add(const Duration(seconds: 1)),
      );
      expect(result!.bodyComposition, {'bodyFatPercent': 20.0, 'bmi': 22.5});
    });

    test('live readings during the stable hold are ignored', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      session.onReading(ScaleReadingEvent(reading(stable: true, at: at)));
      session.onReading(
        ScaleReadingEvent(
          reading(value: 71, at: at.add(const Duration(seconds: 1))),
        ),
      );
      final result = session.complete(
        requiresStable: true,
        deviceLabel: null,
        now: at.add(const Duration(seconds: 2)),
      );
      expect(result, isNotNull);
      expect(result!.weightKg, 70);
    });

    test('broadcast stable hold survives impedance frames', () {
      final session = MeasurementSession(
        sourceProtocol: 'test',
        stableHold: const Duration(seconds: 30),
      );
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      session.onReading(ScaleReadingEvent(reading(stable: true, at: at)));
      session.onReading(
        ScaleReadingEvent(
          reading(value: 70, at: at.add(const Duration(seconds: 5))),
        ),
      );
      final result = session.complete(
        requiresStable: true,
        deviceLabel: null,
        now: at.add(const Duration(seconds: 8)),
      );
      expect(result, isNotNull);
      expect(result!.weightKg, 70);
    });

    test('a live reading after the hold starts a new cycle', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      session.onReading(ScaleReadingEvent(reading(stable: true, at: at)));
      session.onReading(
        ScaleReadingEvent(
          reading(value: 71, at: at.add(const Duration(seconds: 5))),
        ),
      );
      expect(
        session.complete(
          requiresStable: true,
          deviceLabel: null,
          now: at.add(const Duration(seconds: 6)),
        ),
        isNull,
      );
      session.onReading(
        ScaleReadingEvent(
          reading(
            value: 71,
            stable: true,
            at: at.add(const Duration(seconds: 7)),
          ),
        ),
      );
      final result = session.complete(
        requiresStable: true,
        deviceLabel: null,
        now: at.add(const Duration(seconds: 8)),
      );
      expect(result!.weightKg, 71);
    });

    test(
      'body composition after completion does not contaminate next cycle',
      () {
        final session = MeasurementSession(sourceProtocol: 'test');
        final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
        session.onReading(ScaleReadingEvent(reading(stable: true, at: at)));
        final first = session.complete(
          requiresStable: true,
          deviceLabel: null,
          now: at.add(const Duration(seconds: 1)),
        );
        expect(first, isNotNull);
        session.onBodyComposition(
          const ScaleBodyCompositionEvent({'bodyFatPercent': 99}),
        );
        expect(session.bodyComposition, isEmpty);

        session.onReading(
          ScaleReadingEvent(
            reading(stable: true, at: at.add(const Duration(minutes: 1))),
          ),
        );
        final second = session.manualSave(deviceLabel: null);
        expect(second!.bodyComposition, isEmpty);
      },
    );

    test('session is cleared after saving', () {
      final session = MeasurementSession(sourceProtocol: 'test');
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      session.onReading(ScaleReadingEvent(reading(stable: true, at: at)));
      expect(
        session.complete(
          requiresStable: true,
          deviceLabel: null,
          now: at.add(const Duration(seconds: 1)),
        ),
        isNotNull,
      );
      expect(session.hasReading, isFalse);
      expect(
        session.complete(
          requiresStable: true,
          deviceLabel: null,
          now: at.add(const Duration(seconds: 2)),
        ),
        isNull,
      );
    });

    test('IDs are unique', () {
      expect(newMeasurementId(), isNot(newMeasurementId()));
    });
  });
}

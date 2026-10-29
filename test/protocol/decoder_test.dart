import 'dart:typed_data';

import 'package:scale/core/units.dart';
import 'package:scale/data/protocol/ailink_frame.dart';
import 'package:scale/data/protocol/ailink_scale_decoder.dart';
import 'package:scale/data/protocol/scale_event.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  const decoder = AilinkScaleDecoder();
  final at = DateTime.utc(2026, 1, 2, 3, 4, 5);

  group('weight-only scale CID 86', () {
    test('live and stable weight', () {
      final live = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x01, 0x00, 0x1B, 0x58, 0x20]),
          raw: Uint8List.fromList([]),
        ),
        receivedAt: at,
      );
      final reading = (live.events.single as ScaleReadingEvent).reading;
      expect(reading.value, 70.0);
      expect(reading.unit, WeightUnit.kg);
      expect(reading.decimals, 2);
      expect(reading.stable, isFalse);
      expect(reading.kilograms, 70.0);

      final stable = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x02, 0x00, 0x1B, 0x58, 0x20]),
          raw: Uint8List.fromList([]),
        ),
        receivedAt: at,
      );
      expect(
        (stable.events.single as ScaleReadingEvent).reading.stable,
        isTrue,
      );
    });

    test('jin and pound units convert to kilograms', () {
      final jin = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x02, 0x00, 0x05, 0x78, 0x11]),
          raw: Uint8List.fromList([]),
        ),
      );
      final jinReading = (jin.events.single as ScaleReadingEvent).reading;
      expect(jinReading.unit, WeightUnit.jin);
      expect(jinReading.value, 140.0);
      expect(jinReading.kilograms, closeTo(70.0, 1e-9));

      final lb = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x02, 0x00, 0x06, 0x07, 0x16]),
          raw: Uint8List.fromList([]),
        ),
      );
      final lbReading = (lb.events.single as ScaleReadingEvent).reading;
      expect(lbReading.unit, WeightUnit.pound);
      expect(lbReading.kilograms, closeTo(69.99, 0.01));
    });

    test('BMI, unit result and error message types are parsed', () {
      final bmi = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x09, 0x00, 0x00, 0xE1]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(
        (bmi.events.single as ScaleBodyCompositionEvent).metrics['bmi'],
        22.5,
      );

      final unit = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x82, 0x00]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(unit.events.single, isA<ScaleInfoEvent>());

      final error = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0xFF, 0x05]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(error.events.single, isA<ScaleErrorEvent>());
    });

    test('completion requires a stable reading', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x0A]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(
        (result.events.single as ScaleCompletionEvent).requiresStable,
        isTrue,
      );
    });

    test('unknown unit code is an error, not a guessed unit', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x02, 0x00, 0x1B, 0x58, 0x02]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(result.events.single, isA<ScaleErrorEvent>());
    });

    test('unsupported decimal count is an error', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x02, 0x00, 0x1B, 0x58, 0x42]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(result.events.single, isA<ScaleErrorEvent>());
    });

    test('short weight payload is rejected', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 86,
          payload: Uint8List.fromList([0x02, 0x00]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(result.events.single, isA<ScaleErrorEvent>());
    });
  });

  group('four-electrode body-fat scale (CID 14/94/118)', () {
    for (final cid in [14, 94, 118]) {
      test('CID $cid weight result and completion', () {
        final result = decoder.decode(
          AilinkFrame(
            type: AilinkFrameType.a7,
            cid: cid,
            payload: Uint8List.fromList([0x02, 0x00, 0x1B, 0x58, 0x20]),
            raw: Uint8List.fromList([]),
          ),
        );
        final reading = (result.events.single as ScaleReadingEvent).reading;
        expect(reading.value, 70.0);
        expect(reading.stable, isTrue);
        expect(reading.sourceProtocol, AilinkScaleDecoder.bodyFatScaleProtocol);

        final complete = decoder.decode(
          AilinkFrame(
            type: AilinkFrameType.a7,
            cid: cid,
            payload: Uint8List.fromList([0x0A]),
            raw: Uint8List.fromList([]),
          ),
        );
        expect(
          (complete.events.single as ScaleCompletionEvent).requiresStable,
          isTrue,
        );
      });
    }

    test('local body-fat payload is not decoded as transmitted metrics', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 14,
          payload: Uint8List.fromList([0x09, 0x01, 0x02]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(result.events.single, isA<ScaleInfoEvent>());
    });
  });

  group('eight-electrode scale', () {
    test('weight uses the one-byte state prefix', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 50,
          payload: Uint8List.fromList([0x01, 0x01, 0x00, 0x1B, 0x58, 0x20]),
          raw: Uint8List.fromList([]),
        ),
      );
      final reading = (result.events.single as ScaleReadingEvent).reading;
      expect(reading.value, 70.0);
      expect(reading.stable, isFalse);
      expect(reading.sourceProtocol, AilinkScaleDecoder.eightScaleProtocol);
    });

    test('dual-MCU state 15 is not a measurement completion', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 104,
          payload: Uint8List.fromList([0x0F]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(result.events.single, isA<ScaleInfoEvent>());
    });

    test('completion does not require a stable flag', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 50,
          payload: Uint8List.fromList([0x0F]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(
        (result.events.single as ScaleCompletionEvent).requiresStable,
        isFalse,
      );
    });

    test('status, heart-rate, temperature and error states are parsed', () {
      for (final payload in const [
        [0x02, 0x01],
        [0x03, 0x02, 0x48],
        [0x04, 0x01, 0x00, 0x00],
      ]) {
        final result = decoder.decode(
          AilinkFrame(
            type: AilinkFrameType.a7,
            cid: 50,
            payload: Uint8List.fromList(payload),
            raw: Uint8List.fromList([]),
          ),
        );
        expect(result.events.single, isA<ScaleInfoEvent>());
      }

      final failure = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 50,
          payload: Uint8List.fromList([0x02, 0x02]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(failure.events.single, isA<ScaleErrorEvent>());

      final error = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 50,
          payload: Uint8List.fromList([0xFF]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(error.events.single, isA<ScaleErrorEvent>());
    });

    test('body composition subtype 1 maps confirmed fields', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 50,
          payload: Uint8List.fromList([
            0x09,
            0x01,
            0x00,
            0xE1,
            0x00,
            0xC8,
            0x01,
            0x90,
            0x00,
            0x0C,
            0x00,
            0x0D,
          ]),
          raw: Uint8List.fromList([]),
        ),
      );
      final metrics =
          (result.events.single as ScaleBodyCompositionEvent).metrics;
      expect(metrics['bmi'], 22.5);
      expect(metrics['bodyFatPercent'], 20.0);
      expect(metrics['musclePercent'], 40.0);
      expect(metrics['fatMassLeftArmKg'], 1.2);
      expect(metrics['fatMassRightArmKg'], 1.3);
    });

    test('dual-MCU body composition subtype 5 maps only used fields', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 104,
          payload: Uint8List.fromList([
            0x09,
            0x05,
            0x00,
            0x64,
            0x01,
            0x2C,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x78,
            0x01,
            0x90,
            0x02,
            0x58,
          ]),
          raw: Uint8List.fromList([]),
        ),
      );
      final metrics =
          (result.events.single as ScaleBodyCompositionEvent).metrics;
      expect(metrics, {
        'fatMassKg': 10.0,
        'waterKg': 30.0,
        'proteinMassKg': 12.0,
        'muscleMassKg': 40.0,
        'weightWithoutKg': 60.0,
      });
    });

    test('subtype 5 on single-MCU CID 50 is not claimed', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 50,
          payload: Uint8List.fromList([0x09, 0x05, 0x00, 0x64]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(result.events.single, isA<ScaleInfoEvent>());
    });

    test('truncated body composition is an error', () {
      final result = decoder.decode(
        AilinkFrame(
          type: AilinkFrameType.a7,
          cid: 50,
          payload: Uint8List.fromList([0x09, 0x01, 0x00]),
          raw: Uint8List.fromList([]),
        ),
      );
      expect(result.events.single, isA<ScaleErrorEvent>());
    });
  });

  test('unknown CID is reported for diagnostics', () {
    final result = decoder.decode(
      AilinkFrame(
        type: AilinkFrameType.a7,
        cid: 0x7F,
        payload: Uint8List.fromList([0x01]),
        raw: Uint8List.fromList([]),
      ),
    );
    expect(result.events.single, isA<ScaleInfoEvent>());
  });

  test('fixture expectations match decoder output', () {
    final fixture = loadFixture();
    for (final entry
        in (fixture['frames'] as List).cast<Map<String, dynamic>>()) {
      final expected = entry['expected'] as Map<String, dynamic>;
      final frameResult = AilinkFrameAssembler().add(
        hex(entry['frame_hex'] as String),
      );
      if (entry['name'] == 'corrupt_checksum') {
        expect(frameResult.frames, isEmpty);
        continue;
      }
      final frame = frameResult.frames.single;
      final decoded = decoder.decode(frame, receivedAt: at);
      final event = decoded.events.single;
      switch (expected['type']) {
        case 'reading':
          final reading = (event as ScaleReadingEvent).reading;
          expect(
            reading.value,
            pet(expected['value']),
            reason: entry['name'] as String,
          );
          expect(
            reading.unit.label,
            expected['unit'],
            reason: entry['name'] as String,
          );
          expect(
            reading.decimals,
            expected['decimals'],
            reason: entry['name'] as String,
          );
          expect(
            reading.stable,
            expected['stable'],
            reason: entry['name'] as String,
          );
        case 'completion':
          expect(
            event,
            isA<ScaleCompletionEvent>(),
            reason: entry['name'] as String,
          );
        case 'body':
          final metrics = (event as ScaleBodyCompositionEvent).metrics;
          final expectedMetrics = (expected['metrics'] as Map)
              .cast<String, num>();
          for (final item in expectedMetrics.entries) {
            expect(
              metrics[item.key],
              closeTo(item.value.toDouble(), 1e-9),
              reason: '${entry['name']} ${item.key}',
            );
          }
        case 'info':
          expect(event, isA<ScaleInfoEvent>(), reason: entry['name'] as String);
        case 'error':
          expect(
            event,
            isA<ScaleErrorEvent>(),
            reason: entry['name'] as String,
          );
      }
    }
  });
}

double pet(Object? value) => (value as num).toDouble();

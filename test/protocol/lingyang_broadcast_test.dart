import 'dart:typed_data';

import 'package:scale/data/protocol/lingyang_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lingyang_fixture.dart';

void main() {
  const decoder = LingYangBroadcastDecoder();

  test('known idle frame decrypts to a valid LingYang plaintext', () {
    final cipher = Uint8List.fromList([
      0x0c,
      0x24,
      0x59,
      0x16,
      0x63,
      0x8b,
      0xe9,
      0xc3,
      0xff,
      0xff,
    ]);
    final plain = decryptLingYang(cipher);
    expect(plain, [0x81, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x11, 0xff, 0xff]);
  });

  test('decodes a synthetic stable 70.00 kg frame', () {
    final frame = buildLingYangFrame(
      status: 0,
      flags: 0x05, // stable, 2 decimals, kg
      rawWeight: 7000,
      adc: 500,
      algorithm: 1,
    );
    final reading = decoder.decode(frame);
    expect(reading, isNotNull);
    expect(reading!.stable, isTrue);
    expect(reading.value, 70.0);
    expect(reading.unit.name, 'kg');
    expect(reading.decimals, 2);
    expect(reading.impedanceOhm, 500);
    expect(reading.algorithmId, 1);
    expect(reading.kilograms, 70.0);
  });

  test('decodes a completion frame', () {
    final frame = buildLingYangFrame(
      status: 0xFF,
      flags: 0x05,
      rawWeight: 7000,
      adc: 500,
      algorithm: 1,
    );
    final reading = decoder.decode(frame);
    expect(reading, isNotNull);
    expect(reading!.status, 0xFF);
  });

  test('a completion frame may have an unusable weight field', () {
    final frame = buildLingYangFrame(
      status: 0xFF,
      flags: 0x05,
      rawWeight: 100,
      adc: 0xFFFF,
      algorithm: 1,
    );
    final reading = decoder.decode(frame);
    expect(reading, isNotNull);
    expect(reading!.status, 0xFF);
    expect(reading.weightValid, isFalse);
  });

  test('rejects a bad checksum', () {
    final frame = buildLingYangFrame(
      status: 0,
      flags: 0x05,
      rawWeight: 7000,
      adc: 500,
      algorithm: 1,
    );
    frame[9] = (frame[9] + 1) & 0xFF;
    expect(decoder.decode(frame), isNull);
  });

  test('rejects an invalid status', () {
    final frame = buildLingYangFrame(
      status: 0x24,
      flags: 0x05,
      rawWeight: 7000,
      adc: 500,
      algorithm: 1,
    );
    expect(decoder.decode(frame), isNull);
  });

  test('a zero-weight frame is readable but not saveable', () {
    final frame = buildLingYangFrame(
      status: 0,
      flags: 0x05,
      rawWeight: 0,
      adc: 0,
      algorithm: 1,
    );
    final reading = decoder.decode(frame);
    expect(reading, isNotNull);
    expect(reading!.weightValid, isFalse);
    expect(reading.kilograms, 0.0);
  });

  test('an under-range weight is readable but not saveable', () {
    final frame = buildLingYangFrame(
      status: 0,
      flags: 0x05,
      rawWeight: 100,
      adc: 500,
      algorithm: 1,
    );
    final reading = decoder.decode(frame);
    expect(reading, isNotNull);
    expect(reading!.weightValid, isFalse);
    expect(reading.kilograms, 1.0);
  });

  test('rejects a weight above the supported range', () {
    final frame = buildLingYangFrame(
      status: 0,
      flags: 0x05,
      rawWeight: 30000,
      adc: 500,
      algorithm: 1,
    );
    expect(decoder.decode(frame), isNull);
  });

  test('rejects an unsupported unit code', () {
    final frame = buildLingYangFrame(
      status: 0,
      flags: 0x15, // unit 2 is not one of the confirmed AILink unit codes
      rawWeight: 7000,
      adc: 500,
      algorithm: 1,
    );
    expect(decoder.decode(frame), isNull);
  });

  test('decodes jin units to kilograms', () {
    final frame = buildLingYangFrame(
      status: 0,
      flags: 0x0D, // unit 1 (jin), 2 decimals
      rawWeight: 14000,
      adc: 500,
      algorithm: 1,
    );
    final reading = decoder.decode(frame);
    expect(reading, isNotNull);
    expect(reading!.unit.name, 'jin');
    expect(reading.kilograms, closeTo(70.0, 1e-9));
  });
}

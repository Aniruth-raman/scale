import 'package:scale/data/protocol/ailink_frame.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  group('AilinkFrameAssembler', () {
    test('parses a complete A7 frame with checksum', () {
      final frameBytes = buildA7Frame(86, [0x02, 0x00, 0x1B, 0x58, 0x02]);
      final outcome = AilinkFrameAssembler().add(frameBytes);
      expect(outcome.errors, isEmpty);
      expect(outcome.frames, hasLength(1));
      final frame = outcome.frames.single;
      expect(frame.type, AilinkFrameType.a7);
      expect(frame.cid, 86);
      expect(frame.payload, [0x02, 0x00, 0x1B, 0x58, 0x02]);
    });

    test('parses a complete A6 frame', () {
      final frameBytes = buildA6Frame([0x0E]);
      final outcome = AilinkFrameAssembler().add(frameBytes);
      expect(outcome.errors, isEmpty);
      expect(outcome.frames.single.type, AilinkFrameType.a6);
      expect(outcome.frames.single.payload, [0x0E]);
    });

    test('reassembles a frame split across notifications', () {
      final assembler = AilinkFrameAssembler();
      final frameBytes = buildA7Frame(50, [0x01, 0x01, 0x00, 0x1B, 0x58, 0x02]);
      final first = assembler.add(frameBytes.sublist(0, 3));
      expect(first.frames, isEmpty);
      final second = assembler.add(frameBytes.sublist(3));
      expect(second.errors, isEmpty);
      expect(second.frames.single.cid, 50);
    });

    test('parses two concatenated frames', () {
      final assembler = AilinkFrameAssembler();
      final a = buildA7Frame(86, [0x02, 0x00, 0x1B, 0x58, 0x02]);
      final b = buildA7Frame(86, [0x0A]);
      final outcome = assembler.add([...a, ...b]);
      expect(outcome.frames, hasLength(2));
      expect(outcome.frames.last.payload, [0x0A]);
    });

    test('rejects a corrupt checksum', () {
      final bytes = buildA7Frame(86, [0x02, 0x00, 0x1B, 0x58, 0x02]);
      bytes[bytes.length - 2] = (bytes[bytes.length - 2] + 1) & 0xFF;
      final outcome = AilinkFrameAssembler().add(bytes);
      expect(outcome.frames, isEmpty);
      expect(outcome.errors, isNotEmpty);
    });

    test('ignores leading garbage and reports it', () {
      final frameBytes = buildA7Frame(86, [0x02, 0x00, 0x1B, 0x58, 0x02]);
      final outcome = AilinkFrameAssembler().add([0x00, 0xFF, ...frameBytes]);
      expect(outcome.frames, hasLength(1));
      expect(outcome.errors.first.message, contains('before frame'));
    });

    test('unknown start byte is reported', () {
      final outcome = AilinkFrameAssembler().add([0x00, 0x01, 0x02]);
      expect(outcome.frames, isEmpty);
      expect(outcome.errors, isNotEmpty);
    });
  });

  test('fixture frame bytes round-trip through the assembler', () {
    final fixture = loadFixture();
    final frames = (fixture['frames'] as List).cast<Map<String, dynamic>>();
    for (final entry in frames) {
      if (entry['kind'] == 'a6') {
        final outcome = AilinkFrameAssembler().add(
          hex(entry['frame_hex'] as String),
        );
        expect(
          outcome.frames.single.type,
          AilinkFrameType.a6,
          reason: entry['name'] as String,
        );
      } else {
        final outcome = AilinkFrameAssembler().add(
          hex(entry['frame_hex'] as String),
        );
        if (entry['name'] == 'corrupt_checksum') {
          expect(outcome.errors, isNotEmpty);
        } else {
          expect(outcome.frames, hasLength(1), reason: entry['name'] as String);
          expect(
            outcome.frames.single.cid,
            entry['cid'],
            reason: entry['name'] as String,
          );
        }
      }
    }
  });
}

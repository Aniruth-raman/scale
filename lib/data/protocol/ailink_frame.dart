import 'dart:typed_data';

import 'package:meta/meta.dart';

/// AILink application frames observed in `com.pingwang.bluetoothlib`.
///
/// ```text
/// A6:  A6 <len> <payload...> <sum> 6A
/// A7:  A7 <cidHi> <cidLo> <len> <payload...> <sum> 7A
/// ```
///
/// `sum` is the low byte of the sum of every byte after the start byte and
/// before the checksum (length and CID included). These rules are implemented
/// from `AiLinkBleCheckUtil.sendBleDataFormat`, `sendMcuDataFormat`,
/// `returnBleDataFormat`, `returnMcuDataFormat` and `checkReturnDataFormat`.
enum AilinkFrameType { a6, a7 }

@immutable
class AilinkFrame {
  const AilinkFrame({
    required this.type,
    required this.payload,
    required this.raw,
    this.cid,
  });

  final AilinkFrameType type;

  /// CID for A7 frames; null for A6 frames.
  final int? cid;
  final Uint8List payload;
  final Uint8List raw;
}

@immutable
class AilinkParseError {
  const AilinkParseError(this.message, this.raw);

  final String message;
  final Uint8List raw;
}

@immutable
class AilinkParseOutcome {
  const AilinkParseOutcome({this.frames = const [], this.errors = const []});

  final List<AilinkFrame> frames;
  final List<AilinkParseError> errors;
}

/// Reassembles frames that arrive split across BLE notifications.
///
/// AILink's own parser treats each notification as one frame. Weight scales
/// negotiate a larger MTU, but a diagnostic client should still tolerate a
/// split frame instead of dropping it.
class AilinkFrameAssembler {
  final List<int> _buffer = [];

  static const int _maxBuffer = 1024;

  AilinkParseOutcome add(List<int> data) {
    _buffer.addAll(data);
    final frames = <AilinkFrame>[];
    final errors = <AilinkParseError>[];

    if (_buffer.length > _maxBuffer) {
      errors.add(
        AilinkParseError('frame buffer overflow', Uint8List.fromList(_buffer)),
      );
      _buffer.clear();
      return AilinkParseOutcome(frames: frames, errors: errors);
    }

    while (_buffer.isNotEmpty) {
      final start = _firstStartIndex();
      if (start < 0) {
        errors.add(
          AilinkParseError('no A6/A7 start byte', Uint8List.fromList(_buffer)),
        );
        _buffer.clear();
        break;
      }
      if (start > 0) {
        errors.add(
          AilinkParseError(
            'discarded bytes before frame',
            Uint8List.fromList(_buffer.sublist(0, start)),
          ),
        );
        _buffer.removeRange(0, start);
      }
      if (_buffer.isEmpty) break;

      final startByte = _buffer[0];
      if (startByte == 0xA7 && _buffer.length < 4) break;
      if (startByte == 0xA6 && _buffer.length < 2) break;
      final total = _frameLength(startByte);
      if (total == null) {
        errors.add(
          AilinkParseError(
            'unrecognised frame header',
            Uint8List.fromList(_buffer),
          ),
        );
        _buffer.clear();
        break;
      }
      if (_buffer.length < total) break;

      final raw = Uint8List.fromList(_buffer.sublist(0, total));
      final frame = _parseRaw(raw, startByte);
      if (frame == null) {
        errors.add(AilinkParseError('checksum or terminator mismatch', raw));
        _buffer.removeRange(0, 1);
      } else {
        frames.add(frame);
        _buffer.removeRange(0, total);
      }
    }

    return AilinkParseOutcome(frames: frames, errors: errors);
  }

  void reset() => _buffer.clear();

  int _firstStartIndex() {
    for (var i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == 0xA6 || _buffer[i] == 0xA7) return i;
    }
    return -1;
  }

  int? _frameLength(int startByte) {
    if (startByte == 0xA6) {
      if (_buffer.length < 2) return null;
      return _buffer[1] + 4;
    }
    if (startByte == 0xA7) {
      if (_buffer.length < 4) return null;
      return _buffer[3] + 6;
    }
    return null;
  }

  AilinkFrame? _parseRaw(Uint8List raw, int startByte) {
    final isA6 = startByte == 0xA6;
    final payloadLength = isA6 ? raw[1] : raw[3];
    final expectedTotal = isA6 ? payloadLength + 4 : payloadLength + 6;
    if (raw.length != expectedTotal) return null;
    if (raw[raw.length - 1] != (isA6 ? 0x6A : 0x7A)) return null;

    var sum = 0;
    for (var i = 1; i < raw.length - 2; i++) {
      sum = (sum + raw[i]) & 0xFF;
    }
    if (sum != raw[raw.length - 2]) return null;

    final payloadStart = isA6 ? 2 : 4;
    final payload = Uint8List.fromList(
      raw.sublist(payloadStart, payloadStart + payloadLength),
    );
    return AilinkFrame(
      type: isA6 ? AilinkFrameType.a6 : AilinkFrameType.a7,
      cid: isA6 ? null : (raw[1] << 8) | raw[2],
      payload: payload,
      raw: raw,
    );
  }
}

/// Builds a frame for diagnostics/tests. Not used to drive measurements.
Uint8List buildA6Frame(List<int> payload) {
  final raw = Uint8List(payload.length + 4);
  raw[0] = 0xA6;
  raw[1] = payload.length;
  raw.setRange(2, 2 + payload.length, payload);
  raw[raw.length - 2] = _sum(raw, 1, raw.length - 2);
  raw[raw.length - 1] = 0x6A;
  return raw;
}

Uint8List buildA7Frame(int cid, List<int> payload) {
  final raw = Uint8List(payload.length + 6);
  raw[0] = 0xA7;
  raw[1] = (cid >> 8) & 0xFF;
  raw[2] = cid & 0xFF;
  raw[3] = payload.length;
  raw.setRange(4, 4 + payload.length, payload);
  raw[raw.length - 2] = _sum(raw, 1, raw.length - 2);
  raw[raw.length - 1] = 0x7A;
  return raw;
}

int _sum(List<int> bytes, int start, int endExclusive) {
  var sum = 0;
  for (var i = start; i < endExclusive; i++) {
    sum = (sum + bytes[i]) & 0xFF;
  }
  return sum;
}

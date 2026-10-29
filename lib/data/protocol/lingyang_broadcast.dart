import 'dart:typed_data';

import '../../core/units.dart';

/// LingYang broadcast scale protocol, ported from the publicly documented
/// frame layout in `anxkhn/localscale` (MIT) and the published Elink SDK.
///
/// The 20-byte advertisement is:
///   [0] CID (0x16), [1] VID, [2] PID, [3..8] MAC,
///   [9] checksum of bytes 10..19, [10..19] 10-byte payload.
///
/// Only the first 8 payload bytes are TEA ciphertext. The last two are the
/// temperature field and are left untouched. The TEA variant uses the key
/// words below and the initial sum 0xC6EF3720, decrementing by 0x9E3779B9.
///
/// Key provenance: Elink's published `libAILinkBle-lib.so`
/// (`decryptLingYang`), also used by `anxkhn/localscale`. This is a local BLE
/// protocol constant; no cloud endpoint or account credential is involved.
const List<int> _lingYangKey = [0x31783163, 0x306c6531, 0x41493031, 0x4c32796b];

const int _delta = 0x9E3779B9;

Uint8List decryptLingYang(Uint8List ciphertext) {
  if (ciphertext.length < 8) {
    throw ArgumentError('LingYang payload must be at least 8 bytes');
  }
  final output = Uint8List.fromList(ciphertext);
  var v0 = _readLe32(output, 0);
  var v1 = _readLe32(output, 4);
  var sum = 0xC6EF3720;

  for (var i = 0; i < 32; i++) {
    v1 =
        (v1 -
            ((((v0 << 4) + _lingYangKey[0]) ^
                    (v0 + sum) ^
                    ((v0 >> 5) + _lingYangKey[1])) &
                0xFFFFFFFF)) &
        0xFFFFFFFF;
    v0 =
        (v0 -
            ((((v1 << 4) + _lingYangKey[2]) ^
                    (v1 + sum) ^
                    ((v1 >> 5) + _lingYangKey[3])) &
                0xFFFFFFFF)) &
        0xFFFFFFFF;
    sum = (sum - _delta) & 0xFFFFFFFF;
  }

  _writeLe32(output, 0, v0);
  _writeLe32(output, 4, v1);
  return output;
}

int _readLe32(Uint8List data, int offset) =>
    (data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24)) &
    0xFFFFFFFF;

void _writeLe32(Uint8List data, int offset, int value) {
  data[offset] = value & 0xFF;
  data[offset + 1] = (value >> 8) & 0xFF;
  data[offset + 2] = (value >> 16) & 0xFF;
  data[offset + 3] = (value >> 24) & 0xFF;
}

class BroadcastReading {
  const BroadcastReading({
    required this.cid,
    required this.status,
    required this.stable,
    required this.value,
    required this.unit,
    required this.decimals,
    required this.algorithmId,
    required this.rawFrame,
    required this.weightValid,
    this.impedanceOhm,
  });

  final int cid;
  final int status;
  final bool stable;
  final double value;
  final WeightUnit unit;
  final int decimals;
  final int algorithmId;
  final int? impedanceOhm;
  final Uint8List rawFrame;

  /// False only for a completion frame whose weight field is not usable. The
  /// controller still uses it to complete the preceding stable reading.
  final bool weightValid;

  double get kilograms => toKilograms(value, unit);
}

/// Decodes a LingYang CID 0x16 advertisement.
class LingYangBroadcastDecoder {
  const LingYangBroadcastDecoder();

  static const String sourceProtocol = 'ailink.lingyang.broadcast.cid16';
  static const Set<int> validStatuses = {0x00, 0x01, 0x02, 0x03, 0xFF};

  BroadcastReading? decode(Uint8List manufacturerData, {String name = ''}) {
    if (manufacturerData.length < 20) return null;
    for (var offset = 0; offset + 20 <= manufacturerData.length; offset++) {
      final frame = Uint8List.fromList(
        manufacturerData.sublist(offset, offset + 20),
      );
      if (frame[0] != 0x16) continue;
      if (frame[9] != _checksum(frame, 10, 20)) continue;

      final ciphertext = Uint8List.fromList(frame.sublist(10, 20));
      final plain = decryptLingYang(ciphertext);
      final status = plain[1];
      if (!validStatuses.contains(status)) continue;

      final flags = plain[2];
      final unitCode = (flags >> 3) & 0x07;
      final decimals = (flags >> 1) & 0x03;
      final stable = (flags & 0x01) == 0x01;
      final negative = (plain[3] & 0x80) != 0;
      final rawWeight = ((plain[3] & 0x7F) << 8) | plain[4];
      final signedWeight = negative ? -rawWeight : rawWeight;
      final value = signedWeight / _pow10(decimals);

      final unit = WeightUnit.fromAilinkCode(unitCode);
      final kilograms = unit == null ? null : toKilograms(value, unit);
      final inRange =
          kilograms != null &&
          kilograms.isFinite &&
          kilograms >= 0 &&
          kilograms <= 250;
      // A zero or sub-5 kg frame is still shown live so the scale feels
      // responsive, but it is never treated as a saveable measurement.
      final weightValid = inRange && kilograms >= 5.0;
      if (!inRange) {
        if (status != 0xFF) continue;
        // A completion frame may carry an empty/neutral weight field. It does
        // not need a unit; it only closes the preceding stable reading.
        return BroadcastReading(
          cid: frame[0],
          status: status,
          stable: stable,
          value: 0,
          unit: WeightUnit.kg,
          decimals: decimals,
          algorithmId: plain[7],
          impedanceOhm: null,
          rawFrame: frame,
          weightValid: false,
        );
      }

      final adcRaw = (plain[5] << 8) | plain[6];
      final adc = adcRaw == 0 || adcRaw == 0xFFFF ? null : adcRaw;
      if (adc != null && (adc < 1 || adc > 1000)) {
        if (status != 0xFF) continue;
      }
      final usableAdc = adc != null && adc >= 1 && adc <= 1000 ? adc : null;

      return BroadcastReading(
        cid: frame[0],
        status: status,
        stable: stable,
        value: value,
        unit: unit!,
        decimals: decimals,
        algorithmId: plain[7],
        impedanceOhm: usableAdc,
        rawFrame: frame,
        weightValid: weightValid,
      );
    }
    return null;
  }

  int _checksum(Uint8List data, int start, int endExclusive) {
    var sum = 0;
    for (var i = start; i < endExclusive; i++) {
      sum = (sum + data[i]) & 0xFF;
    }
    return sum;
  }

  double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}

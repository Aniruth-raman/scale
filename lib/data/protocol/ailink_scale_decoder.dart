import 'dart:typed_data';

import '../../core/units.dart';
import 'ailink_frame.dart';
import 'scale_event.dart';

/// Decodes the two scale families whose protocols are present in AILink.
///
/// * CID 86: weight-only scale (`WeightScaleDevice`).
/// * CID 19/50/82/104: eight-electrode scale (`EightBodyFatBleDeviceData`).
///
/// Every field mapping is taken from decompiled code; see docs/ble-protocol.md.
class AilinkScaleDecoder {
  const AilinkScaleDecoder();

  static const String weightScaleProtocol = 'ailink.weight_scale.cid86';
  static const String eightScaleProtocol = 'ailink.eight_scale.cid50';
  static const String bodyFatScaleProtocol =
      'ailink.body_fat_scale.cid14_94_118';

  DecodeResult decode(AilinkFrame frame, {DateTime? receivedAt}) {
    if (frame.type == AilinkFrameType.a6) {
      return DecodeResult(
        events: [
          ScaleInfoEvent('A6 frame, ${frame.payload.length} payload bytes'),
        ],
      );
    }

    final cid = frame.cid;
    if (cid == null) {
      return const DecodeResult(
        events: [ScaleErrorEvent('A7 frame without CID')],
      );
    }
    switch (cid) {
      case 0x56: // 86, weight-only scale
        return _decodeWeightScale(frame, receivedAt ?? DateTime.now());
      case 0x0E: // 14, four-electrode body-fat scale
      case 0x5E: // 94, AIFit BLE body-fat scale
      case 0x76: // 118, HMI body-fat scale
        return _decodeBodyFatScale(frame, receivedAt ?? DateTime.now());
      case 0x13: // 19, eight-scale app side
      case 0x32: // 50, eight-scale MCU
      case 0x52: // 82, eight-scale dual
      case 0x68: // 104, eight-scale dual MCU
        return _decodeEightScale(frame, receivedAt ?? DateTime.now());
      default:
        return DecodeResult(
          events: [
            ScaleInfoEvent(
              'A7 CID $cid, ${frame.payload.length} payload bytes',
            ),
          ],
          rawSummary: 'CID $cid',
        );
    }
  }

  DecodeResult _decodeWeightScale(AilinkFrame frame, DateTime receivedAt) {
    final payload = frame.payload;
    if (payload.isEmpty) {
      return const DecodeResult(
        events: [ScaleErrorEvent('empty CID 86 payload')],
      );
    }
    final type = payload[0];
    switch (type) {
      case 1:
        return _weight(
          payload,
          stable: false,
          protocol: weightScaleProtocol,
          receivedAt: receivedAt,
        );
      case 2:
        return _weight(
          payload,
          stable: true,
          protocol: weightScaleProtocol,
          receivedAt: receivedAt,
        );
      case 5:
        return _weight(
          payload,
          stable: false,
          protocol: weightScaleProtocol,
          receivedAt: receivedAt,
          infant: true,
        );
      case 9:
        if (payload.length < 4) {
          return const DecodeResult(
            events: [ScaleErrorEvent('short CID 86 BMI payload')],
          );
        }
        final raw = ((payload[2] & 0xFF) << 8) | (payload[3] & 0xFF);
        return DecodeResult(
          events: [
            ScaleBodyCompositionEvent({'bmi': raw / 10.0}),
          ],
        );
      case 10:
        return const DecodeResult(
          events: [ScaleCompletionEvent(requiresStable: true)],
        );
      case 130:
        return DecodeResult(
          events: [
            ScaleInfoEvent(
              'unit result: ${payload.length > 1 ? payload[1] : 'missing'}',
            ),
          ],
        );
      case 255:
        return DecodeResult(
          events: [
            ScaleErrorEvent(
              'scale error code ${payload.length > 1 ? payload[1] : 'unknown'}',
            ),
          ],
        );
      default:
        return DecodeResult(
          events: [ScaleInfoEvent('CID 86 message type $type')],
          rawSummary: _hex(payload),
        );
    }
  }

  /// Four-electrode body-fat modules share the CID 86 weight layout.
  ///
  /// Evidence: `BodyFatBleUtils.onNotifyData` types 1 (testing), 2 (result),
  /// 18 (infant), 10 (finish) and `BodyFatDataUtil.getWeightInt/Point/Unit`.
  /// Type 9 carries body-fat fields calculated with AILink's local algorithm;
  /// those fields are deliberately not decoded or fabricated here.
  DecodeResult _decodeBodyFatScale(AilinkFrame frame, DateTime receivedAt) {
    final payload = frame.payload;
    if (payload.isEmpty) {
      return const DecodeResult(
        events: [ScaleErrorEvent('empty body-fat scale payload')],
      );
    }
    final type = payload[0];
    switch (type) {
      case 1:
        return _weight(
          payload,
          stable: false,
          protocol: bodyFatScaleProtocol,
          receivedAt: receivedAt,
        );
      case 2:
        return _weight(
          payload,
          stable: true,
          protocol: bodyFatScaleProtocol,
          receivedAt: receivedAt,
        );
      case 18:
        return _weight(
          payload,
          stable: false,
          protocol: bodyFatScaleProtocol,
          receivedAt: receivedAt,
          infant: true,
        );
      case 10:
        return const DecodeResult(
          events: [ScaleCompletionEvent(requiresStable: true)],
        );
      case 9:
        return const DecodeResult(
          events: [
            ScaleInfoEvent(
              'body-fat payload uses AILink local calculation; not decoded',
            ),
          ],
        );
      case 130:
        return DecodeResult(
          events: [
            ScaleInfoEvent(
              'unit result: ${payload.length > 1 ? payload[1] : 'missing'}',
            ),
          ],
        );
      case 255:
        return const DecodeResult(
          events: [ScaleErrorEvent('body-fat scale error')],
        );
      default:
        return DecodeResult(
          events: [ScaleInfoEvent('body-fat scale message type $type')],
          rawSummary: _hex(payload),
        );
    }
  }

  DecodeResult _decodeEightScale(AilinkFrame frame, DateTime receivedAt) {
    final payload = frame.payload;
    if (payload.isEmpty) {
      return const DecodeResult(
        events: [ScaleErrorEvent('empty eight-scale payload')],
      );
    }
    final state = payload[0];
    switch (state) {
      case 1:
        return _weight(
          payload,
          stable: false,
          protocol: eightScaleProtocol,
          receivedAt: receivedAt,
          payloadOffset: 2,
        );
      case 2:
        if (payload.length < 2) {
          return const DecodeResult(
            events: [ScaleErrorEvent('short eight-scale state payload')],
          );
        }
        final substate = payload[1];
        if (substate == 2 && (frame.cid == 19 || frame.cid == 50)) {
          return const DecodeResult(
            events: [ScaleErrorEvent('body-composition analysis failed')],
          );
        }
        return DecodeResult(
          events: [ScaleInfoEvent('eight-scale state 2/$substate')],
        );
      case 15:
        if (frame.cid == 19 || frame.cid == 50) {
          return const DecodeResult(
            events: [ScaleCompletionEvent(requiresStable: false)],
          );
        }
        return const DecodeResult(
          events: [
            ScaleInfoEvent(
              'dual-MCU test complete; not a measurement completion',
            ),
          ],
        );
      case 255:
        return const DecodeResult(
          events: [ScaleErrorEvent('scale reported a measurement error')],
        );
      case 9:
        if (frame.cid != 50 && frame.cid != 104) {
          return const DecodeResult(
            events: [
              ScaleInfoEvent(
                'body-composition state is only defined for MCU CIDs 50/104',
              ),
            ],
          );
        }
        return _bodyCompositionPayload(frame);
      case 3:
        return const DecodeResult(
          events: [
            ScaleInfoEvent(
              'heart-rate payload (not stored as body composition)',
            ),
          ],
        );
      case 4:
        return const DecodeResult(
          events: [ScaleInfoEvent('temperature payload (not stored)')],
        );
      default:
        return DecodeResult(
          events: [ScaleInfoEvent('eight-scale state $state')],
          rawSummary: _hex(payload),
        );
    }
  }

  DecodeResult _weight(
    Uint8List payload, {
    required bool stable,
    required String protocol,
    required DateTime receivedAt,
    int payloadOffset = 1,
    bool infant = false,
  }) {
    if (payload.length < payloadOffset + 4) {
      return DecodeResult(
        events: [
          ScaleErrorEvent('short weight payload (${payload.length} bytes)'),
        ],
      );
    }
    final raw =
        ((payload[payloadOffset] & 0xFF) << 16) |
        ((payload[payloadOffset + 1] & 0xFF) << 8) |
        (payload[payloadOffset + 2] & 0xFF);
    final decimalUnit = payload[payloadOffset + 3];
    final decimals = (decimalUnit & 0xF0) >> 4;
    final unitCode = decimalUnit & 0x0F;
    final unit = WeightUnit.fromAilinkCode(unitCode);

    if (decimals > 3) {
      return DecodeResult(
        events: [
          ScaleErrorEvent('unsupported decimal count $decimals (raw $raw)'),
        ],
      );
    }
    if (unit == null) {
      return DecodeResult(
        events: [
          ScaleErrorEvent('unknown weight unit code $unitCode (raw $raw)'),
        ],
      );
    }

    final value = raw / _powerOfTen(decimals);
    return DecodeResult(
      events: [
        ScaleReadingEvent(
          WeightReading(
            value: value,
            unit: unit,
            decimals: decimals,
            stable: stable,
            receivedAt: receivedAt,
            sourceProtocol: protocol,
            isInfant: infant,
          ),
        ),
      ],
    );
  }

  DecodeResult _bodyCompositionPayload(AilinkFrame frame) {
    final payload = frame.payload;
    if (payload.length < 2) {
      return const DecodeResult(
        events: [ScaleErrorEvent('short body-composition payload')],
      );
    }
    final cid = frame.cid!;
    final subtype = payload[1];
    final maxSubtype = cid == 0x68 ? 9 : 4;
    if (subtype < 1 || subtype > maxSubtype) {
      return DecodeResult(
        events: [
          ScaleInfoEvent(
            'body-composition subtype $subtype not defined for CID $cid',
          ),
        ],
      );
    }

    final metrics = _metricsForSubtype(subtype, payload);
    if (metrics == null) {
      return DecodeResult(
        events: [
          ScaleErrorEvent('truncated body-composition subtype $subtype'),
        ],
      );
    }
    return DecodeResult(events: [ScaleBodyCompositionEvent(metrics)]);
  }

  /// Maps subtype fields exactly as `EightBodyFatScaleMainActivity` does.
  /// Unused fields are intentionally omitted rather than guessed.
  Map<String, double>? _metricsForSubtype(int subtype, Uint8List p) {
    int? u16(int index) {
      if (index + 1 >= p.length) return null;
      final value = ((p[index] & 0xFF) << 8) | (p[index + 1] & 0xFF);
      return value == 0xFFFF ? 0 : value;
    }

    double? d(int index) {
      final value = u16(index);
      return value == null ? null : value / 10.0;
    }

    final metrics = <String, double>{};
    switch (subtype) {
      case 1:
        final bmi = d(2);
        final bodyFat = d(4);
        final muscle = d(6);
        final leftArm = d(8);
        final rightArm = d(10);
        if ([bmi, bodyFat, muscle, leftArm, rightArm].contains(null)) {
          return null;
        }
        metrics['bmi'] = bmi!;
        metrics['bodyFatPercent'] = bodyFat!;
        metrics['musclePercent'] = muscle!;
        metrics['fatMassLeftArmKg'] = leftArm!;
        metrics['fatMassRightArmKg'] = rightArm!;
        return metrics;
      case 2:
        final trunk = d(2);
        final leftLeg = d(4);
        final rightLeg = d(6);
        final leftArm = d(8);
        final rightArm = d(10);
        if ([trunk, leftLeg, rightLeg, leftArm, rightArm].contains(null)) {
          return null;
        }
        metrics['fatMassBodyKg'] = trunk!;
        metrics['fatMassLeftLegKg'] = leftLeg!;
        metrics['fatMassRightLegKg'] = rightLeg!;
        metrics['muscleMassLeftArmKg'] = leftArm!;
        metrics['muscleMassRightArmKg'] = rightArm!;
        return metrics;
      case 3:
        final trunk = d(2);
        final leftLeg = d(4);
        final rightLeg = d(6);
        final water = d(8);
        final bone = d(10);
        if ([trunk, leftLeg, rightLeg, water, bone].contains(null)) return null;
        metrics['muscleMassBodyKg'] = trunk!;
        metrics['muscleMassLeftLegKg'] = leftLeg!;
        metrics['muscleMassRightLegKg'] = rightLeg!;
        metrics['bodyWaterPercent'] = water!;
        metrics['boneMassKg'] = bone!;
        return metrics;
      case 4:
        final bmr = u16(2);
        final protein = d(4);
        final visceral = u16(6);
        final subcutaneous = d(8);
        final bodyAge = p.length > 11 ? (p[11] == 0xFF ? 0 : p[11]) : null;
        if ([bmr, protein, visceral, subcutaneous, bodyAge].contains(null)) {
          return null;
        }
        metrics['bmrKcal'] = bmr!.toDouble();
        metrics['proteinPercent'] = protein!;
        metrics['visceralFat'] = visceral!.toDouble();
        metrics['subcutaneousFatPercent'] = subcutaneous!;
        metrics['bodyAgeYears'] = bodyAge!.toDouble();
        return metrics;
      case 5:
        final fatMass = d(2);
        final water = d(4);
        final proteinMass = d(10);
        final muscleMass = d(12);
        final withoutFat = d(14);
        if ([
          fatMass,
          water,
          proteinMass,
          muscleMass,
          withoutFat,
        ].contains(null)) {
          return null;
        }
        metrics['fatMassKg'] = fatMass!;
        metrics['waterKg'] = water!;
        metrics['proteinMassKg'] = proteinMass!;
        metrics['muscleMassKg'] = muscleMass!;
        metrics['weightWithoutKg'] = withoutFat!;
        return metrics;
      case 6:
        final skeletal = d(2);
        final score = u16(4);
        final bmi = d(6);
        final standard = d(8);
        final muscleControl = d(10);
        final whr = d(12);
        if ([
          skeletal,
          score,
          bmi,
          standard,
          muscleControl,
          whr,
        ].contains(null)) {
          return null;
        }
        metrics['skeletalMuscleKg'] = skeletal!;
        metrics['bodyScore'] = score!.toDouble();
        metrics['bmi'] = bmi!;
        metrics['standardWeightKg'] = standard!;
        metrics['muscleControlKg'] = muscleControl!;
        metrics['whr'] = whr!;
        return metrics;
      case 7:
        final control = d(4);
        final bodyFatControl = d(6);
        final leftArm = d(8);
        final rightArm = d(10);
        if ([control, bodyFatControl, leftArm, rightArm].contains(null)) {
          return null;
        }
        metrics['weightControlKg'] = control!;
        metrics['bodyFatKgCon'] = bodyFatControl!;
        metrics['fatMassLeftArmPercent'] = leftArm!;
        metrics['fatMassRightArmPercent'] = rightArm!;
        return metrics;
      case 8:
        final trunk = d(2);
        final leftLeg = d(4);
        final rightLeg = d(6);
        final leftArm = d(8);
        final rightArm = d(10);
        if ([trunk, leftLeg, rightLeg, leftArm, rightArm].contains(null)) {
          return null;
        }
        metrics['fatMassBodyPercent'] = trunk!;
        metrics['fatMassLeftLegPercent'] = leftLeg!;
        metrics['fatMassRightLegPercent'] = rightLeg!;
        metrics['muscleMassLeftArmPercent'] = leftArm!;
        metrics['muscleMassRightArmPercent'] = rightArm!;
        return metrics;
      case 9:
        final trunk = d(2);
        final leftLeg = d(4);
        final rightLeg = d(6);
        if ([trunk, leftLeg, rightLeg].contains(null)) return null;
        metrics['muscleMassBodyPercent'] = trunk!;
        metrics['muscleMassLeftLegPercent'] = leftLeg!;
        metrics['muscleMassRightLegPercent'] = rightLeg!;
        return metrics;
    }
    return null;
  }

  double _powerOfTen(int decimals) {
    var result = 1.0;
    for (var i = 0; i < decimals; i++) {
      result *= 10;
    }
    return result;
  }

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

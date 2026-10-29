import 'dart:typed_data';

/// Test-only LingYang frame builder. The production app only decrypts.
Uint8List buildLingYangFrame({
  required int status,
  required int flags,
  required int rawWeight,
  required int adc,
  required int algorithm,
  int sequence = 1,
}) {
  const key = [0x31783163, 0x306c6531, 0x41493031, 0x4c32796b];
  final plain = Uint8List(10)
    ..[0] = sequence
    ..[1] = status
    ..[2] = flags
    ..[3] = (rawWeight >> 8) & 0xFF
    ..[4] = rawWeight & 0xFF
    ..[5] = (adc >> 8) & 0xFF
    ..[6] = adc & 0xFF
    ..[7] = algorithm
    ..[8] = 0xFF
    ..[9] = 0xFF;

  var v0 =
      (plain[0] | plain[1] << 8 | plain[2] << 16 | plain[3] << 24) & 0xFFFFFFFF;
  var v1 =
      (plain[4] | plain[5] << 8 | plain[6] << 16 | plain[7] << 24) & 0xFFFFFFFF;
  var sum = 0;
  for (var i = 0; i < 32; i++) {
    sum = (sum + 0x9E3779B9) & 0xFFFFFFFF;
    v0 =
        (v0 +
            ((((v1 << 4) + key[2]) ^ (v1 + sum) ^ ((v1 >> 5) + key[3])) &
                0xFFFFFFFF)) &
        0xFFFFFFFF;
    v1 =
        (v1 +
            ((((v0 << 4) + key[0]) ^ (v0 + sum) ^ ((v0 >> 5) + key[1])) &
                0xFFFFFFFF)) &
        0xFFFFFFFF;
  }
  plain[0] = v0 & 0xFF;
  plain[1] = (v0 >> 8) & 0xFF;
  plain[2] = (v0 >> 16) & 0xFF;
  plain[3] = (v0 >> 24) & 0xFF;
  plain[4] = v1 & 0xFF;
  plain[5] = (v1 >> 8) & 0xFF;
  plain[6] = (v1 >> 16) & 0xFF;
  plain[7] = (v1 >> 24) & 0xFF;
  plain[8] = 0xFF;
  plain[9] = 0xFF;

  var checksum = 0;
  for (final byte in plain) {
    checksum = (checksum + byte) & 0xFF;
  }
  final frame = Uint8List(20)
    ..[0] = 0x16
    ..[1] = 0x15
    ..[2] = 0x02
    ..[9] = checksum;
  frame.setRange(10, 20, plain);
  return frame;
}

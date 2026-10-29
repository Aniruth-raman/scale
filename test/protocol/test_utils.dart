import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

List<int> hex(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .map((part) => int.parse(part, radix: 16))
    .toList();

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

Map<String, dynamic> loadFixture() {
  final raw = File('test/fixtures/synthetic_frames.json').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

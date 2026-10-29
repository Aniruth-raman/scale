import '../core/units.dart';

const String _unitKey = 'display_unit';
const String _verificationNoteKey = 'hardware_verification_note';
const String _verificationAtKey = 'hardware_verification_at';

class AppSettings {
  const AppSettings({
    this.displayUnit = DisplayUnit.kg,
    this.hardwareVerificationNote,
    this.hardwareVerifiedAt,
  });

  final DisplayUnit displayUnit;
  final String? hardwareVerificationNote;
  final DateTime? hardwareVerifiedAt;

  bool get hasHardwareVerification => hardwareVerifiedAt != null;

  AppSettings copyWith({
    DisplayUnit? displayUnit,
    String? hardwareVerificationNote,
    DateTime? hardwareVerifiedAt,
  }) {
    return AppSettings(
      displayUnit: displayUnit ?? this.displayUnit,
      hardwareVerificationNote:
          hardwareVerificationNote ?? this.hardwareVerificationNote,
      hardwareVerifiedAt: hardwareVerifiedAt ?? this.hardwareVerifiedAt,
    );
  }

  Map<String, String> toKeys() {
    final map = <String, String>{_unitKey: displayUnit.name};
    if (hardwareVerificationNote != null) {
      map[_verificationNoteKey] = hardwareVerificationNote!;
    }
    if (hardwareVerifiedAt != null) {
      map[_verificationAtKey] = hardwareVerifiedAt!.toUtc().toIso8601String();
    }
    return map;
  }

  static AppSettings fromValues(Map<String, String?> values) {
    final unitName = values[_unitKey];
    final unit = DisplayUnit.values
        .where((u) => u.name == unitName)
        .firstOrNull;
    return AppSettings(
      displayUnit: unit ?? DisplayUnit.kg,
      hardwareVerificationNote: values[_verificationNoteKey],
      hardwareVerifiedAt: DateTime.tryParse(values[_verificationAtKey] ?? '')
          ?.toLocal(),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}

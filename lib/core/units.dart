import 'package:meta/meta.dart';

/// Units that the reverse-engineered AILink protocols actually report.
///
/// Unit codes are taken from `WeightScaleConfig` and `UnitUtil` in the
/// decompiled application (see docs/ble-protocol.md). Codes that were not
/// observed are deliberately not guessed.
enum WeightUnit {
  kg('kg'),
  jin('jin'),
  pound('lb'),
  stonePound('st:lb'),
  unknown('unknown');

  const WeightUnit(this.label);

  final String label;

  static WeightUnit? fromAilinkCode(int code) {
    switch (code) {
      case 0:
        return WeightUnit.kg;
      case 1:
        return WeightUnit.jin;
      case 4:
        return WeightUnit.stonePound;
      case 6:
        return WeightUnit.pound;
      default:
        return null;
    }
  }
}

/// Display units supported by the app. Storage is always kilograms.
enum DisplayUnit {
  kg('kg'),
  lb('lb'),
  stonePound('st:lb');

  const DisplayUnit(this.label);

  final String label;
}

const double _kgPerPound = 0.45359237;
const double _kgPerJin = 0.5;

/// Converts a device-reported value to kilograms without intermediate rounding.
double toKilograms(double value, WeightUnit unit) {
  switch (unit) {
    case WeightUnit.kg:
      return value;
    case WeightUnit.jin:
      return value * _kgPerJin;
    case WeightUnit.pound:
    case WeightUnit.stonePound:
      return value * _kgPerPound;
    case WeightUnit.unknown:
      throw ArgumentError.value(unit, 'unit', 'Cannot convert an unknown unit');
  }
}

/// Converts kilograms to a display unit. Keep values in kg until this point.
double fromKilograms(double kilograms, DisplayUnit unit) {
  switch (unit) {
    case DisplayUnit.kg:
      return kilograms;
    case DisplayUnit.lb:
      return kilograms / _kgPerPound;
    case DisplayUnit.stonePound:
      return kilograms / _kgPerPound;
  }
}

/// Formats a stored kilogram value in the requested display unit.
///
/// For `st:lb`, the value is rendered as `st st lb lb`; the pounds part uses
/// one decimal so small changes remain visible.
String formatWeight(double kilograms, DisplayUnit unit, {int decimals = 2}) {
  switch (unit) {
    case DisplayUnit.kg:
      return '${kilograms.toStringAsFixed(decimals)} kg';
    case DisplayUnit.lb:
      return '${(kilograms / _kgPerPound).toStringAsFixed(decimals)} lb';
    case DisplayUnit.stonePound:
      final totalPounds = kilograms / _kgPerPound;
      final stones = totalPounds ~/ 14;
      final pounds = totalPounds - stones * 14;
      return '$stones st ${pounds.toStringAsFixed(1)} lb';
  }
}

/// Produces the numeric value in [unit] without a suffix.
double displayValue(double kilograms, DisplayUnit unit) =>
    fromKilograms(kilograms, unit);

@immutable
class WeightReading {
  const WeightReading({
    required this.value,
    required this.unit,
    required this.decimals,
    required this.stable,
    required this.receivedAt,
    required this.sourceProtocol,
    this.isInfant = false,
    this.isManual = false,
    this.bodyComposition = const {},
    this.impedanceOhm,
    this.algorithmId,
    this.bodyCompositionEstimated = false,
  });

  final double value;
  final WeightUnit unit;
  final int decimals;
  final bool stable;
  final DateTime receivedAt;
  final String sourceProtocol;
  final bool isInfant;
  final bool isManual;
  final Map<String, double> bodyComposition;

  /// Optional raw fields reported by broadcast scales. They are not body
  /// composition; impedance is the scale's raw ADC value.
  final int? impedanceOhm;
  final int? algorithmId;
  final bool bodyCompositionEstimated;

  double get kilograms => toKilograms(value, unit);

  WeightReading copyWith({
    double? value,
    WeightUnit? unit,
    int? decimals,
    bool? stable,
    DateTime? receivedAt,
    String? sourceProtocol,
    bool? isInfant,
    bool? isManual,
    Map<String, double>? bodyComposition,
    int? impedanceOhm,
    int? algorithmId,
    bool? bodyCompositionEstimated,
  }) {
    return WeightReading(
      value: value ?? this.value,
      unit: unit ?? this.unit,
      decimals: decimals ?? this.decimals,
      stable: stable ?? this.stable,
      receivedAt: receivedAt ?? this.receivedAt,
      sourceProtocol: sourceProtocol ?? this.sourceProtocol,
      isInfant: isInfant ?? this.isInfant,
      isManual: isManual ?? this.isManual,
      bodyComposition: bodyComposition ?? this.bodyComposition,
      impedanceOhm: impedanceOhm ?? this.impedanceOhm,
      algorithmId: algorithmId ?? this.algorithmId,
      bodyCompositionEstimated:
          bodyCompositionEstimated ?? this.bodyCompositionEstimated,
    );
  }
}

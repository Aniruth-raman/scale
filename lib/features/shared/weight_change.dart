import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/units.dart';
import '../../domain/weight_comparison.dart';

/// Shows a weight difference against a saved reading, with an arrow and the
/// previous value/date. Direction is informational, not a health judgement.
class WeightChangeText extends StatelessWidget {
  const WeightChangeText({
    super.key,
    required this.comparison,
    required this.unit,
    this.baselineLabel = 'since last saved',
    this.center = false,
    this.showPrevious = true,
  });

  final WeightComparison? comparison;
  final DisplayUnit unit;
  final String baselineLabel;
  final bool center;
  final bool showPrevious;

  static const Color _up = Color(0xFFB26A00);
  static const Color _down = Color(0xFF0E7C66);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = comparison;
    final align = center ? TextAlign.center : null;
    if (value == null) {
      return Text(
        'First saved reading for this profile',
        textAlign: align,
        style: theme.textTheme.bodySmall,
      );
    }

    final (icon, color, sign) = switch (value.trend) {
      WeightTrend.up => (Icons.arrow_upward, _up, '+'),
      WeightTrend.down => (Icons.arrow_downward, _down, '-'),
      WeightTrend.flat => (Icons.remove, theme.colorScheme.outline, ''),
    };
    final delta = formatWeight(value.deltaKg.abs(), unit, decimals: 2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              '$sign$delta',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(baselineLabel, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (showPrevious)
          Text(
            'Previous ${formatWeight(value.previousKg, unit)} · '
            '${formatDate(value.previousAt)}',
            textAlign: align,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

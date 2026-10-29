import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../domain/measurement.dart';

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  String _metricKey = 'weight';

  @override
  Widget build(BuildContext context) {
    final measurements = ref.watch(measurementsProvider);
    final displayUnit = ref.watch(displayUnitProvider);
    final theme = Theme.of(context);

    return measurements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Could not read history: $error')),
      data: (all) {
        final available = _availableMetrics(all);
        final effectiveKey = available.any((m) => m.key == _metricKey)
            ? _metricKey
            : 'weight';
        final points = _pointsFor(all, effectiveKey, displayUnit);
        final metric = available.firstWhere((m) => m.key == effectiveKey);
        final unitLabel = effectiveKey == 'weight'
            ? displayUnit.label
            : metric.unit;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Text(
                    'Trends appear after the first saved measurement.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: effectiveKey,
                decoration: const InputDecoration(
                  labelText: 'Metric',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final item in available)
                    DropdownMenuItem(value: item.key, child: Text(item.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _metricKey = value);
                },
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            metric.label,
                            style: theme.textTheme.titleMedium,
                          ),
                          const Spacer(),
                          if (unitLabel.isNotEmpty)
                            Text(unitLabel, style: theme.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 240,
                        width: double.infinity,
                        child: points.isEmpty
                            ? const Center(
                                child: Text('No values for this metric.'),
                              )
                            : CustomPaint(
                                painter: _TrendPainter(
                                  points: points,
                                  lineColor: theme.colorScheme.primary,
                                  gridColor: theme.colorScheme.outlineVariant,
                                  labelColor:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                                child: const SizedBox.expand(),
                              ),
                      ),
                      const SizedBox(height: 8),
                      if (points.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(formatShortDate(points.first.$1)),
                            Text(formatShortDate(points.last.$1)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (points.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Stat(
                          label: 'Latest',
                          value: _fmt(points.last.$2, unitLabel),
                        ),
                        _Stat(
                          label: 'Minimum',
                          value: _fmt(_min(points), unitLabel),
                        ),
                        _Stat(
                          label: 'Maximum',
                          value: _fmt(_max(points), unitLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                effectiveKey == 'weight'
                    ? 'Weight is stored in kilograms and converted once for display. '
                          'This chart shows the active profile.'
                    : 'Only stored values for the active profile are charted. '
                          'Missing values are not interpolated.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }

  List<({String key, String label, String unit})> _availableMetrics(
    List<Measurement> all,
  ) {
    final result = <({String key, String label, String unit})>[
      (key: 'weight', label: 'Weight', unit: ''),
    ];
    for (final metric in bodyMetrics) {
      if (all.any((m) => m.bodyComposition.containsKey(metric.key))) {
        result.add((key: metric.key, label: metric.label, unit: metric.unit));
      }
    }
    return result;
  }

  List<(DateTime, double)> _pointsFor(
    List<Measurement> all,
    String key,
    DisplayUnit displayUnit,
  ) {
    final sorted = [...all]
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    final points = <(DateTime, double)>[];
    for (final m in sorted) {
      if (key == 'weight') {
        points.add((m.measuredAt, displayValue(m.weightKg, displayUnit)));
      } else {
        final value = m.bodyComposition[key];
        if (value != null) points.add((m.measuredAt, value));
      }
    }
    return points;
  }

  double _min(List<(DateTime, double)> points) =>
      points.map((p) => p.$2).reduce((a, b) => a < b ? a : b);

  double _max(List<(DateTime, double)> points) =>
      points.map((p) => p.$2).reduce((a, b) => a > b ? a : b);

  String _fmt(double value, String unit) =>
      '${value.toStringAsFixed(unit == 'kcal' || unit == 'years' ? 0 : 1)}'
      '${unit.isEmpty ? '' : ' $unit'}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<(DateTime, double)> points;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0;
    const right = 8.0;
    const top = 10.0;
    const bottom = 18.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final values = points.map((p) => p.$2).toList();
    var minValue = values.reduce((a, b) => a < b ? a : b);
    var maxValue = values.reduce((a, b) => a > b ? a : b);
    if ((maxValue - minValue).abs() < 0.01) {
      minValue -= 0.5;
      maxValue += 0.5;
    }
    final padding = (maxValue - minValue) * 0.12;
    minValue -= padding;
    maxValue += padding;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = maxValue - (maxValue - minValue) * i / 3;
      _label(canvas, value.toStringAsFixed(1), Offset(0, y - 6), 10);
    }

    final offsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * i / (points.length - 1);
      final ratio = (points[i].$2 - minValue) / (maxValue - minValue);
      final y = chart.bottom - chart.height * ratio;
      offsets.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final point in offsets.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
    }
    final dotPaint = Paint()..color = lineColor;
    for (final point in offsets) {
      canvas.drawCircle(point, 3.2, dotPaint);
    }
  }

  void _label(Canvas canvas, String text, Offset offset, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: labelColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 42);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}

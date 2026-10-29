import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../data/ble/ble_transport.dart';
import '../../domain/measurement.dart';
import '../../domain/metric_report.dart';
import '../../domain/profile.dart';
import '../../domain/weight_comparison.dart';
import '../../features/connection/ble_controller.dart';
import '../../features/connection/connect_screen.dart';
import '../../features/measurement/live_measurement_screen.dart';
import '../../features/measurement/measurement_details_screen.dart';
import 'weight_change.dart';

class ConnectionCard extends ConsumerWidget {
  const ConnectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);
    final theme = Theme.of(context);
    final connected = ble.connectedDevice;
    final color = ble.isConnected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connected?.displayName ?? 'No scale connected',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StatusChip(
                  label: ble.isListening
                      ? 'Listening'
                      : ble.isConnected
                      ? 'Connected'
                      : ble.phase == BleConnectionPhase.connecting
                      ? 'Connecting'
                      : 'Offline',
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(ble.statusMessage, style: theme.textTheme.bodyMedium),
            if (ble.error != null) ...[
              const SizedBox(height: 8),
              Text(
                ble.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ConnectScreen()),
                  ),
                  icon: const Icon(Icons.search),
                  label: Text(
                    ble.isConnected ? 'Change scale' : 'Connect scale',
                  ),
                ),
                if (ble.isConnected)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiveMeasurementScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.monitor_weight_outlined),
                    label: const Text('Live measurement'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LiveReadingCard extends ConsumerWidget {
  const LiveReadingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);
    final unit = ref.watch(displayUnitProvider);
    final theme = Theme.of(context);
    final reading = ble.liveReading;
    final completed = ble.lastCompleted;
    if (!ble.isConnected && reading == null && completed == null) {
      return const SizedBox.shrink();
    }

    final kilograms = reading?.kilograms ?? completed?.weightKg;
    final body = reading?.bodyComposition.isNotEmpty == true
        ? reading!.bodyComposition
        : completed?.bodyComposition ?? const <String, double>{};
    final profile = ref.watch(activeProfileProvider);
    final latestSaved = ref.watch(latestMeasurementProvider).value;
    final comparison = kilograms == null || latestSaved == null
        ? null
        : WeightComparison(
            currentKg: kilograms,
            previousKg: latestSaved.weightKg,
            previousAt: latestSaved.measuredAt,
          );
    final stats = <String>[
      for (final key in const [
        'bmi',
        'bodyFatPercent',
        'musclePercent',
        'bodyWaterPercent',
      ])
        if (body[key] != null)
          '${bodyMetricFor(key)!.label} ${bodyMetricFor(key)!.format(body[key])}',
    ];

    void open(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => open(const LiveMeasurementScreen()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ble.isListening
                        ? Icons.sensors
                        : Icons.monitor_weight_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ble.statusMessage,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ble.isListening)
                    _StatusChip(
                      label: 'Listening',
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                kilograms == null
                    ? 'Waiting for a weigh-in'
                    : formatWeight(kilograms, unit),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: kilograms == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                profile == null
                    ? 'No profile selected'
                    : 'Profile: ${profile.name}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              WeightChangeText(comparison: comparison, unit: unit),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final stat in stats)
                      Text(stat, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: reading == null || ble.savedCurrent
                        ? null
                        : () => ref
                              .read(bleProvider.notifier)
                              .saveCurrentReading(),
                    icon: Icon(
                      ble.savedCurrent ? Icons.check : Icons.save_outlined,
                    ),
                    label: Text(
                      ble.savedCurrent ? 'Saved' : 'Save current reading',
                    ),
                  ),
                  if (completed != null)
                    OutlinedButton.icon(
                      onPressed: () => open(
                        MeasurementDetailsScreen(measurement: completed),
                      ),
                      icon: const Icon(Icons.insights_outlined),
                      label: const Text('Details'),
                    ),
                ],
              ),
              if (ble.isListening && reading != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Listening stays on after saving. Step on the scale again '
                  'for the next reading.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LatestMeasurementCard extends ConsumerWidget {
  const LatestMeasurementCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(bleProvider).liveReading;
    if (live != null) return const SizedBox.shrink();
    final latest = ref.watch(latestMeasurementProvider);
    final all = ref.watch(measurementsProvider).value ?? const <Measurement>[];
    final unit = ref.watch(displayUnitProvider);
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: latest.value == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      MeasurementDetailsScreen(measurement: latest.value!),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: latest.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Could not read local history: $error'),
            data: (measurement) {
              if (measurement == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest measurement',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No measurements saved yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect the scale and step on it. Readings stay on this device.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                );
              }
              final index = all.indexWhere((m) => m.id == measurement.id);
              final previous = index >= 0 && index + 1 < all.length
                  ? all[index + 1]
                  : null;
              final comparison = previous == null
                  ? null
                  : WeightComparison(
                      currentKg: measurement.weightKg,
                      previousKg: previous.weightKg,
                      previousAt: previous.measuredAt,
                    );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Latest measurement',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    formatWeight(measurement.weightKg, unit),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (previous != null) ...[
                    const SizedBox(height: 4),
                    WeightChangeText(
                      comparison: comparison,
                      unit: unit,
                      baselineLabel: 'vs previous saved',
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${formatDateTime(measurement.measuredAt)} • '
                    '${measurement.status == MeasurementStatus.complete ? 'Scale completion' : 'Manually saved'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (measurement.bodyComposition.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      measurement.bodyCompositionEstimated
                          ? 'Body composition estimated locally: '
                                '${measurement.bodyComposition.length} value(s).'
                          : 'Body composition reported by the scale: '
                                '${measurement.bodyComposition.length} value(s).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class PrivacyBanner extends StatelessWidget {
  const PrivacyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Local-only by design: no account, no analytics, no cloud sync, '
                'and no Internet permission in the release build.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BodyCompositionList extends ConsumerWidget {
  const BodyCompositionList({
    super.key,
    required this.weightKg,
    required this.values,
    this.estimated = false,
    this.impedanceOhm,
    this.profile,
  });

  final double weightKg;
  final Map<String, double> values;
  final bool estimated;
  final int? impedanceOhm;

  /// Profile used for the reference bands. Falls back to the active profile.
  final Profile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = this.profile ?? ref.watch(activeProfileProvider);
    final report = buildMetricReport(
      weightKg: weightKg,
      values: values,
      unit: ref.watch(displayUnitProvider),
      sex: profile?.sex,
      age: profile?.age,
      heightCm: profile?.heightCm,
      impedanceOhm: impedanceOhm,
    );

    if (report.isEmpty) {
      return Text(
        'No body-composition values for this measurement. Add height, sex and '
        'birth year to the profile to estimate them from weight and impedance.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          estimated
              ? 'Estimated from weight + impedance using the open Jinghuawei '
                    'formula. Not transmitted by the scale. Ranges are labels '
                    'only, not a diagnosis.'
              : 'Reported by the scale. Ranges are labels only, not a diagnosis.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        _ToneLegend(),
        const SizedBox(height: 10),
        for (final metric in report.metrics)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MetricRow(metric: metric),
          ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metric});

  final MetricDisplay metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = metric.status?.tone ?? MetricTone.neutral;
    final color = _toneColor(theme, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (metric.detail != null)
                  Text(
                    metric.detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                metric.value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (metric.status != null) ...[
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    metric.status!.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ToneLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const entries = [
      ('In range', MetricTone.good),
      ('Watch', MetricTone.warn),
      ('Out of range', MetricTone.bad),
      ('Info', MetricTone.neutral),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final (label, tone) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _toneColor(theme, tone),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}

Color _toneColor(ThemeData theme, MetricTone tone) {
  return switch (tone) {
    MetricTone.good => const Color(0xFF0E7C66),
    MetricTone.warn => const Color(0xFFB26A00),
    MetricTone.bad => theme.colorScheme.error,
    MetricTone.neutral => theme.colorScheme.outline,
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../domain/measurement.dart';
import '../../domain/weight_comparison.dart';
import '../shared/cards.dart';
import '../shared/weight_change.dart';
import 'share_card.dart';

class MeasurementDetailsScreen extends ConsumerWidget {
  const MeasurementDetailsScreen({super.key, required this.measurement});

  final Measurement measurement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(displayUnitProvider);
    final theme = Theme.of(context);
    final profiles = ref.watch(profilesProvider).value?.all ?? const [];
    final matches = profiles.where((p) => p.id == measurement.profileId);
    final profile = matches.isEmpty
        ? ref.watch(activeProfileProvider)
        : matches.first;
    final all = ref.watch(measurementsProvider).value ?? const <Measurement>[];
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Measurement details'),
        actions: [
          IconButton(
            tooltip: 'Share as image',
            onPressed: () => showSharePreview(context, measurement),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Delete measurement',
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    formatWeight(measurement.weightKg, unit),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    measurement.status == MeasurementStatus.complete
                        ? 'Completed by the scale'
                        : 'Manually saved from a live reading',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  WeightChangeText(
                    comparison: comparison,
                    unit: unit,
                    baselineLabel: 'vs previous saved',
                    center: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _row('Measured at', formatDateTime(measurement.measuredAt)),
                _row('Profile', profile?.name ?? 'Unknown'),
                _row(
                  'Stored value',
                  '${measurement.weightKg.toStringAsFixed(4)} kg',
                ),
                _row(
                  'Device value',
                  '${measurement.originalValue.toStringAsFixed(measurement.decimals)} '
                      '${measurement.originalUnit.label}',
                ),
                _row('Source protocol', measurement.sourceProtocol),
                _row(
                  'Source device',
                  measurement.sourceDeviceLabel ?? 'Not recorded',
                ),
                _row('Status', measurement.status.name),
                _row('Stability', measurement.stability.name),
                if (measurement.impedanceOhm != null)
                  _row('Impedance', '${measurement.impedanceOhm} Ω'),
                if (measurement.algorithmId != null)
                  _row('Algorithm ID', '${measurement.algorithmId}'),
                if (measurement.note != null) _row('Note', measurement.note!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Body composition', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  BodyCompositionList(
                    weightKg: measurement.weightKg,
                    values: measurement.bodyComposition,
                    estimated: measurement.bodyCompositionEstimated,
                    impedanceOhm: measurement.impedanceOhm,
                    profile: profile,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Range labels are calculated locally from your profile and the '
            'stored values; they never change the measurement.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete measurement?'),
        content: const Text('This removes the record from the local database.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(measurementRepositoryProvider).delete(measurement.id);
    ref.invalidate(measurementsProvider);
    ref.invalidate(latestMeasurementProvider);
    if (context.mounted) Navigator.of(context).pop();
  }
}

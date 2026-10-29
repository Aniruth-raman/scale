import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../domain/measurement.dart';
import '../../domain/weight_comparison.dart';
import '../measurement/measurement_details_screen.dart';
import '../shared/weight_change.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final measurements = ref.watch(measurementsProvider);
    final unit = ref.watch(displayUnitProvider);
    return measurements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not read local history: $error'),
        ),
      ),
      data: (all) {
        final query = _search.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? all
            : all
                  .where((m) {
                    final haystack = [
                      formatDateTime(m.measuredAt),
                      m.weightKg.toStringAsFixed(2),
                      formatWeight(m.weightKg, unit),
                      m.status.name,
                      m.sourceProtocol,
                      m.sourceDeviceLabel ?? '',
                    ].join(' ').toLowerCase();
                    return haystack.contains(query);
                  })
                  .toList(growable: false);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search date, weight or status',
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} measurement(s)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () {
                      ref.invalidate(measurementsProvider);
                      ref.invalidate(latestMeasurementProvider);
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          all.isEmpty
                              ? 'No measurements yet. Connect the scale and step on it.'
                              : 'No measurements match this search.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(measurementsProvider);
                        ref.invalidate(latestMeasurementProvider);
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final m = filtered[index];
                          final previous = index + 1 < filtered.length
                              ? filtered[index + 1]
                              : null;
                          return _HistoryTile(
                            measurement: m,
                            previous: previous,
                            unit: unit,
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.measurement,
    required this.unit,
    this.previous,
  });

  final Measurement measurement;
  final Measurement? previous;
  final DisplayUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyFat = measurement.bodyComposition['bodyFatPercent'];
    final older = previous;
    return Card(
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MeasurementDetailsScreen(measurement: measurement),
          ),
        ),
        title: Text(
          formatWeight(measurement.weightKg, unit),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatDateTime(measurement.measuredAt)} • '
              '${measurement.status.name}'
              '${bodyFat == null ? '' : ' • body fat ${bodyFat.toStringAsFixed(1)}%'}',
            ),
            if (older != null)
              WeightChangeText(
                comparison: WeightComparison(
                  currentKg: measurement.weightKg,
                  previousKg: older.weightKg,
                  previousAt: older.measuredAt,
                ),
                unit: unit,
                showPrevious: false,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

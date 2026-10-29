import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../domain/measurement.dart';
import '../../domain/weight_comparison.dart';
import '../connection/ble_controller.dart';
import '../connection/connect_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../shared/bluetooth_off_card.dart';
import '../shared/cards.dart';
import '../shared/weight_change.dart';

class LiveMeasurementScreen extends ConsumerWidget {
  const LiveMeasurementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);
    final unit = ref.watch(displayUnitProvider);
    final theme = Theme.of(context);
    final reading = ble.liveReading;
    final completed = ble.lastCompleted;
    final kilograms = reading?.kilograms ?? completed?.weightKg;
    final body = reading?.bodyComposition.isNotEmpty == true
        ? reading!.bodyComposition
        : completed?.bodyComposition ?? const <String, double>{};
    final estimated =
        reading?.bodyCompositionEstimated ??
        completed?.bodyCompositionEstimated ??
        false;

    final (statusText, statusColor) = _status(ble, reading, completed);
    final profile = ref.watch(activeProfileProvider);
    final latestSaved = ref.watch(latestMeasurementProvider).value;
    final comparison = reading == null || latestSaved == null
        ? null
        : WeightComparison(
            currentKg: reading.kilograms,
            previousKg: latestSaved.weightKg,
            previousAt: latestSaved.measuredAt,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live measurement'),
        actions: [
          if (ble.isListening)
            IconButton(
              tooltip: 'Stop listening',
              onPressed: () => ref.read(bleProvider.notifier).disconnect(),
              icon: const Icon(Icons.link_off),
            ),
          IconButton(
            tooltip: 'Diagnostics',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
            icon: const Icon(Icons.bluetooth_searching),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const BluetoothOffCard(),
          if (!ble.bluetoothAvailable) const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(statusColor.$1, color: statusColor.$2, size: 18),
                      const SizedBox(width: 6),
                      Text(statusText, style: theme.textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    kilograms == null ? '—' : formatWeight(kilograms, unit),
                    key: const Key('live-weight'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ble.savedCurrent
                        ? 'Saved. Still listening for the next weigh-in.'
                        : reading?.stable == true
                        ? 'Stable'
                        : reading != null
                        ? 'Live — not saved until completion or manual save'
                        : completed != null
                        ? 'Completed measurement'
                        : 'Step on the scale',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  WeightChangeText(
                    comparison: comparison,
                    unit: unit,
                    center: true,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    profile == null
                        ? 'No profile selected'
                        : 'Saving to ${profile.name}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
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
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ConnectScreen(),
                          ),
                        ),
                        icon: Icon(
                          ble.isConnected ? Icons.swap_horiz : Icons.search,
                        ),
                        label: Text(
                          ble.isConnected ? 'Change scale' : 'Connect scale',
                        ),
                      ),
                    ],
                  ),
                  if (completed != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Saved ${formatDateTime(completed.measuredAt)} • '
                      '${completed.status == MeasurementStatus.complete ? 'scale completion' : 'manual'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (ble.error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Attention'),
                subtitle: Text(ble.error!),
              ),
            ),
          ],
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
                    weightKg: kilograms ?? 0,
                    values: body,
                    estimated: estimated,
                    impedanceOhm:
                        reading?.impedanceOhm ?? completed?.impedanceOhm,
                  ),
                  if (ble.isListening && body.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Add height, sex and birth year to the active profile to '
                      'estimate body composition from weight and impedance.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(protocolConfidenceNote),
            ),
          ),
        ],
      ),
    );
  }

  (String, (IconData, Color)) _status(
    BleState ble,
    WeightReading? reading,
    Measurement? completed,
  ) {
    if (ble.error != null) {
      return ('Error', (Icons.error_outline, const Color(0xFFB3261E)));
    }
    if (!ble.isConnected) {
      return ('Not connected', (Icons.bluetooth_disabled, Colors.grey));
    }
    if (ble.isListening) {
      return ('Listening', (Icons.sensors, const Color(0xFF0E7C66)));
    }
    if (reading?.stable == true) {
      return ('Stable', (Icons.check_circle, const Color(0xFF0E7C66)));
    }
    if (reading != null) {
      return ('Live', (Icons.timeline, const Color(0xFFB26A00)));
    }
    if (completed != null) {
      return ('Saved', (Icons.check_circle, const Color(0xFF0E7C66)));
    }
    return ('Connected, waiting', (Icons.hourglass_empty, Colors.blueGrey));
  }
}

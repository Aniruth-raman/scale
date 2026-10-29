import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../connection/ble_controller.dart';
import '../shared/bluetooth_off_card.dart';
import '../shared/cards.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final bluetoothAvailable = ref.watch(bleProvider).bluetoothAvailable;
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(latestMeasurementProvider);
        ref.invalidate(measurementsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PrivacyBanner(),
          const BluetoothOffCard(),
          if (bluetoothAvailable) ...[
            const SizedBox(height: 12),
            const ConnectionCard(),
            const SizedBox(height: 12),
            const LiveReadingCard(),
          ],
          const SizedBox(height: 12),
          const LatestMeasurementCard(),
          const SizedBox(height: 12),
          settings.when(
            loading: () => const SizedBox.shrink(),
            error: (error, _) => Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Could not read settings'),
                subtitle: Text('$error'),
              ),
            ),
            data: (value) {
              if (value.hasHardwareVerification) {
                return Card(
                  color: theme.colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: const Text('Hardware test recorded'),
                    subtitle: Text(
                      '${formatDateTime(value.hardwareVerifiedAt!)}'
                      '${value.hardwareVerificationNote == null ? '' : ' — ${value.hardwareVerificationNote}'}',
                    ),
                  ),
                );
              }
              return Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Software-tested build'),
                  subtitle: const Text(
                    'The AILink-compatible decoder has not been verified against '
                    'this physical scale. Use Diagnostics during the first hardware test.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

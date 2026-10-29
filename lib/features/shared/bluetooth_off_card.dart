import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/ble/ble_transport.dart';
import '../connection/ble_controller.dart';

/// Explains why Bluetooth cannot be used and offers the system prompt when the
/// adapter is simply switched off. Renders nothing while Bluetooth is usable.
class BluetoothOffCard extends ConsumerWidget {
  const BluetoothOffCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ref.watch(bleProvider).adapter;
    if (adapter == BleAdapterState.ready ||
        adapter == BleAdapterState.unknown) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final (title, message, canEnable) = switch (adapter) {
      BleAdapterState.poweredOff => (
        'Bluetooth is off',
        'Turn on Bluetooth to find your scale and see live weight.',
        true,
      ),
      BleAdapterState.unauthorized => (
        'Bluetooth permission needed',
        'Allow Nearby devices for this app in system settings.',
        false,
      ),
      BleAdapterState.unsupported => (
        'Bluetooth LE is not supported',
        'This phone cannot receive the scale broadcast.',
        false,
      ),
      BleAdapterState.locationServicesDisabled => (
        'Location services are off',
        'Turn on location services to scan for the scale on this Android '
            'version.',
        false,
      ),
      _ => (
        'Bluetooth unavailable',
        'Check the Bluetooth adapter and try again.',
        false,
      ),
    };

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(message, style: theme.textTheme.bodyMedium),
            if (canEnable) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(bleSystemActionsProvider).requestEnableBluetooth(),
                icon: const Icon(Icons.bluetooth),
                label: const Text('Turn on Bluetooth'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

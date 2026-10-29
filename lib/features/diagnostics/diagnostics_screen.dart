import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../connection/ble_controller.dart';
import '../connection/connect_screen.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleProvider);
    final theme = Theme.of(context);
    final recent = ble.packetLog.take(60).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy redacted log',
            onPressed: () {
              final text = ble.packetLog
                  .map(
                    (e) =>
                        '${formatTime(e.at)} ${e.direction.toUpperCase()} '
                        '${e.characteristic ?? '-'} ${e.text}${e.note == null ? '' : ' (${e.note})'}',
                  )
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Redacted log copied.')),
              );
            },
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Clear log',
            onPressed: () => ref.read(bleProvider.notifier).clearLog(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Transport', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _kv('Adapter', ble.adapter.name),
                  _kv('Phase', ble.phase.name),
                  _kv('Device', redactDeviceId(ble.connectedDevice?.id)),
                  _kv('Name', ble.connectedDevice?.displayName ?? '—'),
                  _kv(
                    'Subscribed characteristics',
                    '${ble.subscribedCharacteristics}',
                  ),
                  _kv(
                    'Detected protocol',
                    ble.detectedProtocol ?? 'not detected',
                  ),
                  const SizedBox(height: 8),
                  Text(ble.statusMessage, style: theme.textTheme.bodySmall),
                  if (ble.error != null) ...[
                    const SizedBox(height: 6),
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
                      if (!ble.isConnected)
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ConnectScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.search),
                          label: const Text('Scan and connect'),
                        ),
                      if (ble.isConnected) ...[
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(bleProvider.notifier).probeVersion(),
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('Send A6 version probe'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(bleProvider.notifier).disconnect(),
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect'),
                        ),
                      ],
                    ],
                  ),
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
          const SizedBox(height: 12),
          Text('GATT structure', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          if (ble.services.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_tree_outlined),
                title: Text('No services discovered'),
                subtitle: Text('Connect to a scale to inspect its GATT tree.'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final service in ble.services)
                    ExpansionTile(
                      title: Text(
                        service.uuid,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${service.characteristics.length} characteristic(s)',
                      ),
                      children: [
                        for (final characteristic in service.characteristics)
                          ListTile(
                            dense: true,
                            title: Text(
                              characteristic.uuid,
                              style: const TextStyle(fontSize: 12),
                            ),
                            subtitle: Text(characteristic.properties),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text('Packet log', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '${ble.packetLog.length} entries',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Payloads are shown as received. Device identifiers are redacted. '
            'The log is in memory only and is never uploaded.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.receipt_long_outlined),
                title: Text('No packets yet'),
                subtitle: Text(
                  'Step on the connected scale to generate notifications.',
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final entry in recent)
                    ListTile(
                      dense: true,
                      leading: _directionIcon(entry.direction, theme),
                      title: Text(
                        '${formatTime(entry.at)}  ${entry.characteristic ?? entry.direction.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        entry.text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      trailing: entry.note == null
                          ? null
                          : Tooltip(
                              message: entry.note!,
                              child: const Icon(Icons.info_outline, size: 16),
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _directionIcon(String direction, ThemeData theme) {
    switch (direction) {
      case 'rx':
        return const Icon(Icons.download, size: 18, color: Colors.blue);
      case 'tx':
        return const Icon(Icons.upload, size: 18, color: Colors.orange);
      case 'error':
        return Icon(
          Icons.error_outline,
          size: 18,
          color: theme.colorScheme.error,
        );
      default:
        return const Icon(Icons.info_outline, size: 18, color: Colors.grey);
    }
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 190, child: Text(key)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

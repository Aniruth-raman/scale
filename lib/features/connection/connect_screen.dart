import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ble/ble_transport.dart';
import '../shared/bluetooth_off_card.dart';
import 'ble_controller.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(bleProvider).bluetoothAvailable) {
        ref.read(bleProvider.notifier).startScan();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleProvider);
    final theme = Theme.of(context);
    final devices = ble.devices;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect scale'),
        actions: [
          IconButton(
            tooltip: 'Scan again',
            onPressed: ble.scanning
                ? null
                : () => ref.read(bleProvider.notifier).startScan(),
            icon: const Icon(Icons.refresh),
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
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bluetooth', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(_adapterText(ble.adapter)),
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
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: ble.scanning || !ble.bluetoothAvailable
                            ? null
                            : () => ref.read(bleProvider.notifier).startScan(),
                        icon: ble.scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(ble.scanning ? 'Scanning…' : 'Scan'),
                      ),
                      const SizedBox(width: 10),
                      if (ble.scanning)
                        Text(
                          '${devices.length} found',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (ble.isConnected) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(
                  '${ble.isListening ? 'Listening to' : 'Connected to'} '
                  '${ble.connectedDevice?.displayName ?? 'scale'}',
                ),
                subtitle: Text(ble.statusMessage),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text('Nearby devices', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'All advertising BLE devices are listed. The "AILink FFE0/F0A0" badge '
            'means the device advertises a service used by the documented protocol; '
            'it is not proof that the protocol is compatible. F0A0-only devices '
            'can be broadcast scales: they may not accept a GATT connection. '
            'Tap Listen to capture their advertisements without connecting.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    size: 42,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ble.scanning ? 'Looking for devices…' : 'No devices found',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Wake the scale and keep it nearby. On older Android versions, '
                    'location services must be enabled for a BLE scan.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            for (final device in devices) ...[
              _DeviceTile(
                device: device,
                connecting:
                    ble.phase == BleConnectionPhase.connecting &&
                    ble.connectedDevice?.id == device.id,
                connected:
                    ble.isConnected && ble.connectedDevice?.id == device.id,
                onConnect: () => ref.read(bleProvider.notifier).connect(device),
                onDetails: () => _showDeviceDetails(context, device),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.connecting,
    required this.connected,
    required this.onConnect,
    required this.onDetails,
  });

  final DiscoveredScale device;
  final bool connecting;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ailinkLabel = _ailinkServiceLabel(device.serviceUuids);
    final broadcast = _isBroadcastDevice(device);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            ailinkLabel != null
                ? Icons.monitor_weight_outlined
                : Icons.bluetooth,
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(device.displayName)),
            if (ailinkLabel != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(ailinkLabel, style: theme.textTheme.labelSmall),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${redactDeviceId(device.id)} • RSSI ${device.rssi} dBm',
          style: theme.textTheme.bodySmall,
        ),
        trailing: connected
            ? const Icon(Icons.check)
            : connecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                onPressed: onConnect,
                child: Text(broadcast ? 'Listen' : 'Connect'),
              ),
        onTap: onDetails,
      ),
    );
  }
}

bool _isAilinkService(List<String> serviceUuids) =>
    _ailinkServiceLabel(serviceUuids) != null;

bool _isBroadcastDevice(DiscoveredScale device) {
  final name = device.name.toLowerCase();
  return _isBroadcastOnly(device.serviceUuids) ||
      name.startsWith('lye') ||
      name.contains('lingyang');
}

bool _isBroadcastOnly(List<String> serviceUuids) {
  final hasF0a0 = serviceUuids.any((u) {
    final value = u.toLowerCase();
    return value == '0000f0a0-0000-1000-8000-00805f9b34fb' || value == 'f0a0';
  });
  final hasFfe0 = serviceUuids.any((u) {
    final value = u.toLowerCase();
    return value == '0000ffe0-0000-1000-8000-00805f9b34fb' || value == 'ffe0';
  });
  return hasF0a0 && !hasFfe0;
}

String? _ailinkServiceLabel(List<String> serviceUuids) {
  for (final uuid in serviceUuids) {
    final value = uuid.toLowerCase();
    if (value == '0000ffe0-0000-1000-8000-00805f9b34fb' || value == 'ffe0') {
      return 'AILink FFE0';
    }
  }
  for (final uuid in serviceUuids) {
    final value = uuid.toLowerCase();
    if (value == '0000f0a0-0000-1000-8000-00805f9b34fb' || value == 'f0a0') {
      return 'AILink F0A0';
    }
  }
  return null;
}

void _showDeviceDetails(BuildContext context, DiscoveredScale device) {
  final theme = Theme.of(context);
  final services = device.serviceUuids;
  final manufacturer = device.manufacturerData.isEmpty
      ? 'None advertised'
      : redactHex(device.manufacturerData, device.id);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.displayName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${redactDeviceId(device.id)} • RSSI ${device.rssi} dBm',
              style: theme.textTheme.bodySmall,
            ),
            if (_isAilinkService(services)) ...[
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.monitor_weight_outlined, size: 18),
                label: const Text('Advertises AILink FFE0/F0A0'),
              ),
            ],
            const SizedBox(height: 16),
            Text('Advertised services', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (services.isEmpty)
              const Text('None advertised')
            else
              for (final service in services)
                SelectableText(
                  service,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
            const SizedBox(height: 16),
            Text(
              'Manufacturer data (redacted)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              manufacturer,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(
              'FFE0/F0A0 is the documented AILink service. It is a hint, not '
              'proof that this device uses the scale protocol. After connecting, '
              'the Diagnostics screen shows the real GATT tree.',
              style: theme.textTheme.bodySmall,
            ),
            if (_isBroadcastOnly(services)) ...[
              const SizedBox(height: 8),
              Text(
                'This device advertises F0A0 only. AILink broadcast scales '
                '(for example the LingYang CID 0x16 family) send measurements in '
                'advertisements and may not accept a GATT connection. Use Listen '
                'to decode the broadcast without connecting.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

String _adapterText(BleAdapterState state) {
  switch (state) {
    case BleAdapterState.unknown:
      return 'Bluetooth status is not available yet.';
    case BleAdapterState.unsupported:
      return 'This device does not support Bluetooth LE.';
    case BleAdapterState.unauthorized:
      return 'Bluetooth permission is not granted. Use Scan to request it.';
    case BleAdapterState.poweredOff:
      return 'Bluetooth is off. Turn it on in system settings.';
    case BleAdapterState.locationServicesDisabled:
      return 'Location services are off. They are required for BLE scanning on older Android.';
    case BleAdapterState.ready:
      return 'Bluetooth is ready.';
  }
}

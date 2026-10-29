import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../domain/measurement_repository.dart';
import '../profiles/profiles_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final profiles = ref.watch(profilesProvider).value;
    final theme = Theme.of(context);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Could not load settings: $error')),
      data: (settings) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Display', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Weight unit'),
                    const SizedBox(height: 8),
                    SegmentedButton<DisplayUnit>(
                      segments: const [
                        ButtonSegment(value: DisplayUnit.kg, label: Text('kg')),
                        ButtonSegment(value: DisplayUnit.lb, label: Text('lb')),
                        ButtonSegment(
                          value: DisplayUnit.stonePound,
                          label: Text('st:lb'),
                        ),
                      ],
                      selected: {settings.displayUnit},
                      onSelectionChanged: (selection) {
                        ref
                            .read(settingsProvider.notifier)
                            .setDisplayUnit(selection.first);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Values are stored in kilograms. Conversion happens once at display time.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Household profiles', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('Profiles'),
                subtitle: Text(
                  profiles == null
                      ? 'Loading profiles'
                      : '${profiles.all.length} profile(s) · '
                            'active: ${profiles.active.name}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfilesScreen()),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Local data', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('Export measurements as CSV'),
                    subtitle: const Text(
                      'All profiles. Opens the system share sheet; the app performs no upload.',
                    ),
                    onTap: _exportCsv,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete all measurements for '
                      '${profiles?.active.name ?? 'the active profile'}',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: const Text('Cannot be undone.'),
                    onTap: _deleteAll,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Hardware verification', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(
                  settings.hasHardwareVerification
                      ? Icons.verified_outlined
                      : Icons.science_outlined,
                ),
                title: Text(
                  settings.hasHardwareVerification
                      ? 'Recorded ${formatDateTime(settings.hardwareVerifiedAt!)}'
                      : 'Not verified on this scale',
                ),
                subtitle: Text(
                  settings.hardwareVerificationNote ?? 'Software tests do not prove scale compatibility. Record a real measurement test after checking the decoded weight against the scale display.',
                ),
                trailing: TextButton(
                  onPressed: _recordVerification,
                  child: Text(
                    settings.hasHardwareVerification ? 'Update' : 'Record',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Privacy', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PrivacyRow(
                      icon: Icons.person_off_outlined,
                      text: 'No account, login, advertising, analytics or telemetry.',
                    ),
                    const _PrivacyRow(
                      icon: Icons.cloud_off_outlined,
                      text: 'No cloud sync or application-initiated upload.',
                    ),
                    const _PrivacyRow(
                      icon: Icons.wifi_off_outlined,
                      text: 'No Internet permission is requested in the release manifest.',
                    ),
                    const _PrivacyRow(
                      icon: Icons.storage_outlined,
                      text: 'Measurements and settings stay in the local SQLite database.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'See docs/privacy.md for the verification notes and limitations.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Scale • local build',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportCsv() async {
    final measurements = await ref.read(measurementRepositoryProvider).getAll();
    if (measurements.isEmpty) {
      _message('No measurements to export.');
      return;
    }
    final csv = MeasurementCsv.build(measurements);
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'scale_measurements.csv'));
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Scale measurements',
      ),
    );
  }

  Future<void> _deleteAll() async {
    final profile = ref.read(activeProfileProvider);
    if (profile == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete all measurements for ${profile.name}?'),
        content: const Text(
          'Only this profile\'s measurements are removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(measurementRepositoryProvider)
        .deleteAll(profileId: profile.id);
    ref.invalidate(measurementsProvider);
    ref.invalidate(latestMeasurementProvider);
    _message('All measurements deleted.');
  }

  Future<void> _recordVerification() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record hardware test'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Only record this after comparing the weight shown by this app '
              'with the scale display and saving a real measurement.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Test note (scale model, result)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (note == null || note.isEmpty) return;
    await ref.read(settingsProvider.notifier).recordHardwareVerification(note);
    _message('Hardware test recorded locally.');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

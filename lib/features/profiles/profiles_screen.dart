import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/profile.dart';

const String _manageProfiles = '__manage_profiles__';

class ProfileSwitcher extends ConsumerWidget {
  const ProfileSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profilesProvider).value;
    if (state == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Switch profile',
      onSelected: (value) {
        if (value == _manageProfiles) {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ProfilesScreen()));
        } else {
          ref.read(profilesProvider.notifier).setActive(value);
        }
      },
      itemBuilder: (context) => [
        for (final profile in state.all)
          CheckedPopupMenuItem(
            value: profile.id,
            checked: profile.id == state.active.id,
            child: Text(profile.name),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _manageProfiles,
          child: Text('Manage profiles'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                _initial(state.active.name),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                state.active.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(profilesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Household profiles')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load profiles: $error')),
        data: (state) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Each profile keeps its own measurements on this device. New '
              'readings are saved to the selected profile.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final profile in state.all)
              Card(
                child: ListTile(
                  onTap: () =>
                      ref.read(profilesProvider.notifier).setActive(profile.id),
                  leading: CircleAvatar(child: Text(_initial(profile.name))),
                  title: Row(
                    children: [
                      Flexible(child: Text(profile.name)),
                      if (profile.id == state.active.id) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, size: 18),
                      ],
                    ],
                  ),
                  subtitle: Text(_details(profile)),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Profile actions',
                    onSelected: (value) {
                      if (value == 'edit') {
                        _edit(context, ref, profile);
                      } else {
                        _delete(context, ref, state, profile);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add profile'),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Profile? profile,
  ) async {
    final result = await showDialog<Profile>(
      context: context,
      builder: (_) => _ProfileDialog(initial: profile),
    );
    if (result == null) return;
    await ref.read(profilesProvider.notifier).save(result);
    if (profile == null) {
      await ref.read(profilesProvider.notifier).setActive(result.id);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ProfilesState state,
    Profile profile,
  ) async {
    if (state.all.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one profile.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: const Text(
          'The profile and every measurement saved to it are removed from this '
          'device. This cannot be undone.',
        ),
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
    await ref.read(profilesProvider.notifier).delete(profile.id);
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({this.initial});

  final Profile? initial;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _height;
  late final TextEditingController _birthYear;
  String? _sex;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _height = TextEditingController(text: initial?.heightCm?.toString() ?? '');
    _birthYear = TextEditingController(
      text: initial?.birthYear?.toString() ?? '',
    );
    _sex = initial?.sex;
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New profile' : 'Edit profile'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _height,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Height (cm, optional)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    _optionalNumber(value, min: 50, max: 269, label: 'Height'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sex,
                decoration: const InputDecoration(
                  labelText: 'Sex (optional)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Other / prefer not to say'),
                  ),
                ],
                onChanged: (value) => setState(() => _sex = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _birthYear,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Birth year (optional)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _optionalNumber(
                  value,
                  min: 1900,
                  max: DateTime.now().year,
                  label: 'Birth year',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Height, sex and birth year are used only for local '
                'body-composition estimates.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final initial = widget.initial;
    final height = int.tryParse(_height.text.trim());
    final birthYear = int.tryParse(_birthYear.text.trim());
    Navigator.of(context).pop(
      Profile(
        id: initial?.id ?? newProfileId(),
        name: _name.text.trim(),
        heightCm: height,
        sex: _sex,
        birthYear: birthYear,
        createdAt: initial?.createdAt ?? DateTime.now().toUtc(),
      ),
    );
  }

  String? _optionalNumber(
    String? value, {
    required int min,
    required int max,
    required String label,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null) return '$label must be a number';
    if (parsed < min || parsed > max) return '$label must be $min–$max';
    return null;
  }
}

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}

String _details(Profile profile) {
  final parts = <String>[
    if (profile.heightCm != null) '${profile.heightCm} cm',
    if (profile.sex != null) profile.sex!,
    if (profile.birthYear != null) 'born ${profile.birthYear}',
  ];
  return parts.isEmpty ? 'No profile details' : parts.join(' · ');
}

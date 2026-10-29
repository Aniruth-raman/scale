import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/units.dart';
import '../data/ble/ble_permissions.dart';
import '../data/ble/ble_transport.dart';
import '../data/ble/reactive_ble_transport.dart';
import '../data/database/app_database.dart';
import '../data/database/settings_repository.dart';
import '../domain/app_settings.dart';
import '../domain/measurement.dart';
import '../domain/measurement_repository.dart';
import '../domain/profile.dart';

/// Overridden in main() with the opened database, and in tests with an
/// in-memory database.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('appDatabaseProvider must be overridden at startup');
});

final measurementRepositoryProvider = Provider<MeasurementRepository>((ref) {
  return SqliteMeasurementRepository(ref.watch(appDatabaseProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    SqliteSettingsStoreAdapter(SettingsStore(ref.watch(appDatabaseProvider))),
  );
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SqliteProfileRepository(ref.watch(appDatabaseProvider));
});

final bleTransportProvider = Provider<BleTransport>((ref) {
  return ReactiveBleTransport();
});

final blePermissionProvider = Provider<BlePermissionRequester>((ref) {
  return const MethodChannelBlePermissionRequester();
});

final bleSystemActionsProvider = Provider<BleSystemActions>((ref) {
  return const MethodChannelBleSystemActions();
});

/// Short grace period after a completion signal so late body-composition
/// frames in the same measurement cycle can still be attached.
final bleCompletionGraceProvider = Provider<Duration>((ref) {
  return const Duration(milliseconds: 700);
});

final measurementsProvider = FutureProvider<List<Measurement>>((ref) async {
  final profile = ref.watch(activeProfileProvider);
  if (profile == null) return const [];
  return ref.watch(measurementRepositoryProvider).getAll(profileId: profile.id);
});

final latestMeasurementProvider = FutureProvider<Measurement?>((ref) async {
  final profile = ref.watch(activeProfileProvider);
  if (profile == null) return null;
  return ref.watch(measurementRepositoryProvider).latest(profileId: profile.id);
});

class ProfilesState {
  const ProfilesState({required this.all, required this.active});

  final List<Profile> all;
  final Profile active;
}

class ProfilesController extends AsyncNotifier<ProfilesState> {
  @override
  Future<ProfilesState> build() async {
    final repository = ref.watch(profileRepositoryProvider);
    final active = await repository.ensureActive();
    return ProfilesState(all: await repository.getAll(), active: active);
  }

  Future<void> setActive(String id) async {
    await ref.read(profileRepositoryProvider).setActive(id);
    ref.invalidateSelf();
  }

  Future<void> save(Profile profile) async {
    await ref.read(profileRepositoryProvider).save(profile);
    ref.invalidateSelf();
  }

  /// The last profile cannot be removed; the repository also deletes that
  /// profile's measurements.
  Future<void> delete(String id) async {
    await ref.read(profileRepositoryProvider).delete(id);
    ref.invalidateSelf();
    ref.invalidate(measurementsProvider);
    ref.invalidate(latestMeasurementProvider);
  }
}

final profilesProvider =
    AsyncNotifierProvider<ProfilesController, ProfilesState>(
      ProfilesController.new,
    );

/// Active household profile, or null while profiles load.
final activeProfileProvider = Provider<Profile?>((ref) {
  return ref.watch(profilesProvider).value?.active;
});

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).load();
  }

  Future<void> save(AppSettings settings) async {
    state = AsyncData(settings);
    await ref.read(settingsRepositoryProvider).save(settings);
  }

  Future<void> setDisplayUnit(DisplayUnit unit) async {
    final current = state.value ?? const AppSettings();
    await save(current.copyWith(displayUnit: unit));
  }

  Future<void> recordHardwareVerification(String note) async {
    final current = state.value ?? const AppSettings();
    await save(
      current.copyWith(
        hardwareVerificationNote: note,
        hardwareVerifiedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final displayUnitProvider = Provider<DisplayUnit>((ref) {
  return ref.watch(settingsProvider).value?.displayUnit ?? DisplayUnit.kg;
});

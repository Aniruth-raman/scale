import '../../domain/app_settings.dart';
import 'app_database.dart';

class SettingsRepository {
  SettingsRepository(this._store);

  final SettingsStoreLike _store;

  Future<AppSettings> load() async {
    final values = <String, String?>{};
    for (final key in const [
      'display_unit',
      'hardware_verification_note',
      'hardware_verification_at',
    ]) {
      values[key] = await _store.read(key);
    }
    return AppSettings.fromValues(values);
  }

  Future<void> save(AppSettings settings) async {
    final keys = settings.toKeys();
    for (final entry in keys.entries) {
      await _store.write(entry.key, entry.value);
    }
    // Clear optional fields that were removed.
    for (final key in const [
      'hardware_verification_note',
      'hardware_verification_at',
    ]) {
      if (!keys.containsKey(key)) {
        await _store.delete(key);
      }
    }
  }
}

/// Small interface so settings logic can be tested without SQLite.
abstract class SettingsStoreLike {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SqliteSettingsStoreAdapter implements SettingsStoreLike {
  SqliteSettingsStoreAdapter(this._store);

  final SettingsStore _store;

  @override
  Future<String?> read(String key) => _store.get(key);

  @override
  Future<void> write(String key, String value) => _store.set(key, value);

  @override
  Future<void> delete(String key) => _store.remove(key);
}

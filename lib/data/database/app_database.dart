import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/units.dart';
import '../../domain/measurement.dart';
import '../../domain/measurement_repository.dart';
import '../../domain/profile.dart';

/// Versioned local SQLite database. No cloud, no synchronization.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 3;
  static const String fileName = 'scale.db';

  static Future<AppDatabase> open({String? path}) async {
    final directory = await getDatabasesPath();
    final database = await openDatabase(
      path ?? p.join(directory, fileName),
      version: schemaVersion,
      onCreate: _createSchema,
      onUpgrade: _upgrade,
    );
    return AppDatabase._(database);
  }

  /// Test/desktop hook. Pass `databaseFactoryFfi` from sqflite_common_ffi.
  static Future<AppDatabase> openWithFactory(
    DatabaseFactory factory, {
    String path = inMemoryDatabasePath,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _createSchema,
        onUpgrade: _upgrade,
      ),
    );
    return AppDatabase._(database);
  }

  Future<void> close() => db.close();

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE measurements(
        id TEXT PRIMARY KEY,
        profile_id TEXT,
        measured_at INTEGER NOT NULL,
        weight_kg REAL NOT NULL,
        original_value REAL NOT NULL,
        original_unit TEXT NOT NULL,
        decimals INTEGER NOT NULL,
        status TEXT NOT NULL,
        stability TEXT NOT NULL DEFAULT 'completionOnly',
        source_protocol TEXT NOT NULL,
        source_device TEXT,
        body_composition TEXT NOT NULL DEFAULT '{}',
        impedance_ohm INTEGER,
        algorithm_id INTEGER,
        body_composition_estimated INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_measurements_measured_at ON measurements(measured_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_measurements_profile ON measurements(profile_id, measured_at DESC)',
    );
    await db.execute('''
      CREATE TABLE profiles(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        height_cm INTEGER,
        sex TEXT,
        birth_year INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Version 1 shipped without stability, impedance, algorithm id and the
    // estimated-body-composition flag. Add only the columns that are missing
    // so upgrades are safe for any earlier 1.x install.
    if (oldVersion == 1) {
      final columns = await db.rawQuery('PRAGMA table_info(measurements)');
      final names = columns.map((row) => row['name'] as String).toSet();
      if (!names.contains('stability')) {
        await db.execute(
          "ALTER TABLE measurements ADD COLUMN stability TEXT NOT NULL DEFAULT 'completionOnly'",
        );
      }
      if (!names.contains('impedance_ohm')) {
        await db.execute(
          'ALTER TABLE measurements ADD COLUMN impedance_ohm INTEGER',
        );
      }
      if (!names.contains('algorithm_id')) {
        await db.execute(
          'ALTER TABLE measurements ADD COLUMN algorithm_id INTEGER',
        );
      }
      if (!names.contains('body_composition_estimated')) {
        await db.execute(
          'ALTER TABLE measurements ADD COLUMN body_composition_estimated INTEGER NOT NULL DEFAULT 0',
        );
      }
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profiles(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          height_cm INTEGER,
          sex TEXT,
          birth_year INTEGER,
          created_at INTEGER NOT NULL
        )
      ''');
      final columns = await db.rawQuery('PRAGMA table_info(measurements)');
      final names = columns.map((row) => row['name'] as String).toSet();
      if (!names.contains('profile_id')) {
        await db.execute('ALTER TABLE measurements ADD COLUMN profile_id TEXT');
      }

      final existing = await db.query('profiles', limit: 1);
      String profileId;
      if (existing.isEmpty) {
        // Move the old single-profile settings into a named household profile.
        final settingsRows = await db.query('settings');
        final settings = {
          for (final row in settingsRows)
            row['key'] as String: row['value'] as String,
        };
        profileId = 'default-profile';
        await db.insert('profiles', {
          'id': profileId,
          'name': 'Me',
          'height_cm': int.tryParse(settings['profile_height_cm'] ?? ''),
          'sex': settings['profile_sex'],
          'birth_year': int.tryParse(settings['profile_birth_year'] ?? ''),
          'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        });
        for (final key in const [
          'profile_height_cm',
          'profile_sex',
          'profile_birth_year',
        ]) {
          await db.delete('settings', where: 'key = ?', whereArgs: [key]);
        }
      } else {
        profileId = existing.first['id'] as String;
      }

      await db.update('measurements', {
        'profile_id': profileId,
      }, where: 'profile_id IS NULL');
      final active = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['active_profile_id'],
        limit: 1,
      );
      if (active.isEmpty) {
        await db.insert('settings', {
          'key': 'active_profile_id',
          'value': profileId,
        });
      }
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_measurements_profile '
        'ON measurements(profile_id, measured_at DESC)',
      );
    }
  }
}

class SqliteMeasurementRepository implements MeasurementRepository {
  SqliteMeasurementRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  @override
  Future<List<Measurement>> getAll({String? profileId}) async {
    final rows = await _db.query(
      'measurements',
      where: profileId == null ? null : 'profile_id = ?',
      whereArgs: profileId == null ? null : [profileId],
      orderBy: 'measured_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<Measurement?> latest({String? profileId}) async {
    final rows = await _db.query(
      'measurements',
      where: profileId == null ? null : 'profile_id = ?',
      whereArgs: profileId == null ? null : [profileId],
      orderBy: 'measured_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<Measurement?> byId(String id) async {
    final rows = await _db.query(
      'measurements',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Inserts a measurement unless it is a repeat of the most recent row for the
  /// same profile.
  ///
  /// A repeated stable notification and the following "measurement complete"
  /// notification therefore produce one row. A manual row is upgraded when a
  /// genuine completion arrives for the same reading.
  @override
  Future<SaveOutcome> save(
    Measurement measurement, {
    Duration duplicateWindow = const Duration(seconds: 15),
  }) async {
    if (!isValidMeasurement(measurement)) {
      throw ArgumentError('Refusing to store an invalid measurement');
    }
    final previous = await latest(profileId: measurement.profileId);
    if (previous != null &&
        previous.sourceProtocol == measurement.sourceProtocol &&
        (previous.measuredAt.difference(measurement.measuredAt).abs() <=
            duplicateWindow) &&
        (previous.weightKg - measurement.weightKg).abs() < 0.02) {
      final shouldUpgrade =
          previous.status == MeasurementStatus.manual &&
          measurement.status == MeasurementStatus.complete;
      if (shouldUpgrade) {
        await _db.update(
          'measurements',
          {
            'status': measurement.status.name,
            'body_composition': jsonEncode(measurement.bodyComposition),
            'source_device':
                measurement.sourceDeviceLabel ?? previous.sourceDeviceLabel,
          },
          where: 'id = ?',
          whereArgs: [previous.id],
        );
      }
      return SaveOutcome.duplicate;
    }

    await _db.insert(
      'measurements',
      _toRow(measurement),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return SaveOutcome.inserted;
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete('measurements', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteAll({String? profileId}) async {
    await _db.delete(
      'measurements',
      where: profileId == null ? null : 'profile_id = ?',
      whereArgs: profileId == null ? null : [profileId],
    );
  }

  Map<String, Object?> _toRow(Measurement m) => {
    'id': m.id,
    'profile_id': m.profileId,
    'measured_at': m.measuredAt.toUtc().millisecondsSinceEpoch,
    'weight_kg': m.weightKg,
    'original_value': m.originalValue,
    'original_unit': m.originalUnit.name,
    'decimals': m.decimals,
    'status': m.status.name,
    'stability': m.stability.name,
    'source_protocol': m.sourceProtocol,
    'source_device': m.sourceDeviceLabel,
    'body_composition': jsonEncode(m.bodyComposition),
    'impedance_ohm': m.impedanceOhm,
    'algorithm_id': m.algorithmId,
    'body_composition_estimated': m.bodyCompositionEstimated ? 1 : 0,
    'note': m.note,
    'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
  };

  Measurement _fromRow(Map<String, Object?> row) {
    final rawBody = row['body_composition'] as String? ?? '{}';
    var body = <String, double>{};
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is num && value.isFinite) {
            body[entry.key.toString()] = value.toDouble();
          }
        }
      }
    } on FormatException {
      body = {};
    }

    return Measurement(
      id: row['id'] as String,
      measuredAt: DateTime.fromMillisecondsSinceEpoch(
        row['measured_at'] as int,
        isUtc: true,
      ),
      weightKg: (row['weight_kg'] as num).toDouble(),
      originalValue: (row['original_value'] as num).toDouble(),
      originalUnit: _unitFromName(row['original_unit'] as String? ?? ''),
      decimals: row['decimals'] as int,
      status: _statusFromName(row['status'] as String? ?? ''),
      profileId: row['profile_id'] as String?,
      stability: _stabilityFromName(row['stability'] as String? ?? ''),
      sourceProtocol: row['source_protocol'] as String,
      sourceDeviceLabel: row['source_device'] as String?,
      bodyComposition: body,
      impedanceOhm: row['impedance_ohm'] as int?,
      algorithmId: row['algorithm_id'] as int?,
      bodyCompositionEstimated:
          (row['body_composition_estimated'] as int? ?? 0) == 1,
      note: row['note'] as String?,
    );
  }
}

WeightUnit _unitFromName(String name) {
  for (final unit in WeightUnit.values) {
    if (unit.name == name) return unit;
  }
  return WeightUnit.unknown;
}

MeasurementStatus _statusFromName(String name) {
  return name == MeasurementStatus.manual.name
      ? MeasurementStatus.manual
      : MeasurementStatus.complete;
}

MeasurementStability _stabilityFromName(String name) {
  for (final value in MeasurementStability.values) {
    if (value.name == name) return value;
  }
  return MeasurementStability.completionOnly;
}

class SettingsStore {
  SettingsStore(this._database);

  final AppDatabase _database;

  Future<String?> get(String key) async {
    final rows = await _database.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await _database.db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String key) async {
    await _database.db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}

const String activeProfileKey = 'active_profile_id';

class SqliteProfileRepository implements ProfileRepository {
  SqliteProfileRepository(this._database)
    : _settings = SettingsStore(_database);

  final AppDatabase _database;
  final SettingsStore _settings;

  Database get _db => _database.db;

  @override
  Future<List<Profile>> getAll() async {
    final rows = await _db.query('profiles', orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<Profile> ensureActive() async {
    final all = await getAll();
    if (all.isEmpty) {
      final profile = Profile(
        id: newProfileId(),
        name: 'Me',
        createdAt: DateTime.now().toUtc(),
      );
      await save(profile);
      await setActive(profile.id);
      return profile;
    }
    final id = await activeId();
    final active = all.where((p) => p.id == id).firstOrNull ?? all.first;
    if (active.id != id) {
      await setActive(active.id);
    }
    return active;
  }

  @override
  Future<void> save(Profile profile) async {
    await _db.insert('profiles', {
      'id': profile.id,
      'name': profile.name,
      'height_cm': profile.heightCm,
      'sex': profile.sex,
      'birth_year': profile.birthYear,
      'created_at': profile.createdAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'measurements',
        where: 'profile_id = ?',
        whereArgs: [id],
      );
      await txn.delete('profiles', where: 'id = ?', whereArgs: [id]);
    });
    if (await activeId() == id) {
      await _settings.remove(activeProfileKey);
    }
  }

  @override
  Future<String?> activeId() => _settings.get(activeProfileKey);

  @override
  Future<void> setActive(String id) => _settings.set(activeProfileKey, id);

  Profile _fromRow(Map<String, Object?> row) {
    return Profile(
      id: row['id'] as String,
      name: row['name'] as String,
      heightCm: row['height_cm'] as int?,
      sex: row['sex'] as String?,
      birthYear: row['birth_year'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}

import 'dart:io';

import 'package:scale/core/units.dart';
import 'package:scale/data/database/app_database.dart';
import 'package:scale/data/database/settings_repository.dart';
import 'package:scale/domain/app_settings.dart';
import 'package:scale/domain/measurement.dart';
import 'package:scale/domain/measurement_repository.dart';
import 'package:scale/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Measurement measurement({
  String id = 'm1',
  DateTime? at,
  double kg = 70,
  MeasurementStatus status = MeasurementStatus.complete,
  Map<String, double> body = const {},
  String? device = 'Synthetic scale',
}) {
  return Measurement(
    id: id,
    measuredAt: at ?? DateTime.utc(2026, 1, 2, 3, 4, 5),
    weightKg: kg,
    originalValue: kg,
    originalUnit: WeightUnit.kg,
    decimals: 2,
    status: status,
    sourceProtocol: 'test.protocol',
    sourceDeviceLabel: device,
    bodyComposition: body,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late SqliteMeasurementRepository repository;

  setUp(() async {
    database = await AppDatabase.openWithFactory(databaseFactoryFfi);
    repository = SqliteMeasurementRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('schema version and required columns exist', () async {
    final version = await database.db.getVersion();
    expect(version, AppDatabase.schemaVersion);
    final columns = await database.db.rawQuery(
      'PRAGMA table_info(measurements)',
    );
    final names = columns.map((row) => row['name'] as String).toSet();
    expect(
      names,
      containsAll({
        'id',
        'measured_at',
        'weight_kg',
        'original_value',
        'original_unit',
        'decimals',
        'status',
        'stability',
        'source_protocol',
        'source_device',
        'body_composition',
        'impedance_ohm',
        'algorithm_id',
        'body_composition_estimated',
        'note',
        'created_at',
        'profile_id',
      }),
    );
    final profileColumns = await database.db.rawQuery(
      'PRAGMA table_info(profiles)',
    );
    expect(
      profileColumns.map((row) => row['name']).toSet(),
      containsAll({
        'id',
        'name',
        'height_cm',
        'sex',
        'birth_year',
        'created_at',
      }),
    );
  });

  test('version 1 database upgrades to the current schema', () async {
    final path =
        '${Directory.systemTemp.path}/scale_migration_${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE measurements(
              id TEXT PRIMARY KEY,
              measured_at INTEGER NOT NULL,
              weight_kg REAL NOT NULL,
              original_value REAL NOT NULL,
              original_unit TEXT NOT NULL,
              decimals INTEGER NOT NULL,
              status TEXT NOT NULL,
              source_protocol TEXT NOT NULL,
              source_device TEXT,
              body_composition TEXT NOT NULL DEFAULT '{}',
              note TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE settings(
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await old.insert('measurements', {
      'id': 'legacy',
      'measured_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      'weight_kg': 70.0,
      'original_value': 70.0,
      'original_unit': 'kg',
      'decimals': 2,
      'status': 'complete',
      'source_protocol': 'test.protocol',
      'body_composition': '{}',
      'created_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    });
    await old.insert('settings', {'key': 'profile_height_cm', 'value': '175'});
    await old.insert('settings', {'key': 'profile_sex', 'value': 'male'});
    await old.insert('settings', {
      'key': 'profile_birth_year',
      'value': '1990',
    });
    await old.close();

    final upgraded = await AppDatabase.openWithFactory(
      databaseFactoryFfi,
      path: path,
    );
    addTearDown(upgraded.close);
    final columns = await upgraded.db.rawQuery(
      'PRAGMA table_info(measurements)',
    );
    final names = columns.map((row) => row['name'] as String).toSet();
    expect(
      names,
      containsAll({
        'stability',
        'impedance_ohm',
        'algorithm_id',
        'body_composition_estimated',
        'profile_id',
      }),
    );
    expect(await upgraded.db.getVersion(), AppDatabase.schemaVersion);

    final profiles = await upgraded.db.query('profiles');
    expect(profiles, hasLength(1));
    expect(profiles.single['name'], 'Me');
    expect(profiles.single['height_cm'], 175);
    expect(profiles.single['sex'], 'male');
    expect(profiles.single['birth_year'], 1990);
    final profileId = profiles.single['id'] as String;
    final legacy = await upgraded.db.query('measurements');
    expect(legacy.single['profile_id'], profileId);
    final active = await upgraded.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['active_profile_id'],
    );
    expect(active.single['value'], profileId);
    await databaseFactoryFfi.deleteDatabase(path);
  });

  test('profiles keep measurements separate', () async {
    final profiles = SqliteProfileRepository(database);
    final me = await profiles.ensureActive();
    expect(me.name, 'Me');
    expect(await profiles.activeId(), me.id);

    final alex = Profile(id: 'p2', name: 'Alex', createdAt: DateTime.utc(2026));
    await profiles.save(alex);
    await repository.save(
      measurement(id: 'a', kg: 70).copyWith(profileId: me.id),
    );
    await repository.save(
      measurement(id: 'b', kg: 60).copyWith(profileId: alex.id),
    );

    expect((await repository.getAll(profileId: me.id)).map((m) => m.id), ['a']);
    expect((await repository.getAll(profileId: alex.id)).map((m) => m.id), [
      'b',
    ]);
    expect((await repository.latest(profileId: me.id))!.weightKg, 70);
    expect((await repository.latest(profileId: alex.id))!.weightKg, 60);

    await profiles.setActive(alex.id);
    expect((await profiles.ensureActive()).id, alex.id);

    await profiles.delete(alex.id);
    expect(await repository.getAll(profileId: alex.id), isEmpty);
    expect((await repository.getAll()).map((m) => m.id), ['a']);
    expect((await profiles.getAll()).map((p) => p.id), [me.id]);
  });

  test('version 2 database gains profiles and keeps its measurements', () async {
    final path =
        '${Directory.systemTemp.path}/scale_v2_${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE measurements(
              id TEXT PRIMARY KEY,
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
          await db.execute('''
            CREATE TABLE settings(
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await old.insert('measurements', {
      'id': 'v2-row',
      'measured_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      'weight_kg': 70.0,
      'original_value': 70.0,
      'original_unit': 'kg',
      'decimals': 2,
      'status': 'complete',
      'source_protocol': 'test.protocol',
      'body_composition': '{}',
      'created_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    });
    await old.insert('settings', {'key': 'profile_height_cm', 'value': '165'});
    await old.insert('settings', {'key': 'profile_sex', 'value': 'female'});
    await old.insert('settings', {
      'key': 'profile_birth_year',
      'value': '1985',
    });
    await old.insert('settings', {'key': 'display_unit', 'value': 'lb'});
    await old.close();

    final upgraded = await AppDatabase.openWithFactory(
      databaseFactoryFfi,
      path: path,
    );
    addTearDown(upgraded.close);
    expect(await upgraded.db.getVersion(), 3);
    final profiles = await upgraded.db.query('profiles');
    expect(profiles, hasLength(1));
    expect(profiles.single['id'], 'default-profile');
    expect(profiles.single['height_cm'], 165);
    expect(profiles.single['sex'], 'female');
    expect(profiles.single['birth_year'], 1985);
    expect(
      await upgraded.db.query(
        'measurements',
        where: 'id = ?',
        whereArgs: ['v2-row'],
      ),
      hasLength(1),
    );
    final rows = await upgraded.db.query('measurements');
    expect(rows.single['profile_id'], 'default-profile');
    final legacyKeys = await upgraded.db.query(
      'settings',
      where: 'key LIKE ?',
      whereArgs: ['profile_%'],
    );
    expect(legacyKeys, isEmpty);
    final unit = await upgraded.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['display_unit'],
    );
    expect(unit.single['value'], 'lb');
    await databaseFactoryFfi.deleteDatabase(path);
  });

  test('insert, read, latest, delete and deleteAll', () async {
    expect(await repository.getAll(), isEmpty);
    final first = measurement(id: 'a', at: DateTime.utc(2026, 1, 1));
    final second = measurement(id: 'b', at: DateTime.utc(2026, 1, 2), kg: 71);
    expect(await repository.save(first), SaveOutcome.inserted);
    expect(await repository.save(second), SaveOutcome.inserted);

    final all = await repository.getAll();
    expect(all.map((m) => m.id), ['b', 'a']);
    expect((await repository.latest())!.id, 'b');
    expect((await repository.byId('a'))!.weightKg, 70);

    await repository.delete('a');
    expect((await repository.getAll()).map((m) => m.id), ['b']);
    await repository.deleteAll();
    expect(await repository.getAll(), isEmpty);
  });

  test('duplicate stable/completion notifications create one row', () async {
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final stable = measurement(id: 'stable', at: at);
    final complete = measurement(
      id: 'complete',
      at: at.add(const Duration(seconds: 3)),
    );
    expect(await repository.save(stable), SaveOutcome.inserted);
    expect(await repository.save(complete), SaveOutcome.duplicate);
    expect(await repository.getAll(), hasLength(1));
  });

  test('different weight or a later measurement is inserted', () async {
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
    expect(
      await repository.save(measurement(id: 'a', at: at)),
      SaveOutcome.inserted,
    );
    expect(
      await repository.save(
        measurement(id: 'b', at: at.add(const Duration(seconds: 2)), kg: 71),
      ),
      SaveOutcome.inserted,
    );
    expect(
      await repository.save(
        measurement(id: 'c', at: at.add(const Duration(minutes: 1))),
      ),
      SaveOutcome.inserted,
    );
    expect(await repository.getAll(), hasLength(3));
  });

  test('manual row is upgraded by a genuine completion', () async {
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
    await repository.save(
      measurement(id: 'manual', at: at, status: MeasurementStatus.manual),
    );
    final outcome = await repository.save(
      measurement(
        id: 'complete',
        at: at.add(const Duration(seconds: 2)),
        status: MeasurementStatus.complete,
        body: {'bodyFatPercent': 20},
      ),
    );
    expect(outcome, SaveOutcome.duplicate);
    final row = (await repository.latest())!;
    expect(row.status, MeasurementStatus.complete);
    expect(row.bodyComposition['bodyFatPercent'], 20);
  });

  test('broadcast impedance and algorithm id persist', () async {
    await repository.save(
      measurement(id: 'broadcast').copyWith(impedanceOhm: 500, algorithmId: 1),
    );
    final row = (await repository.latest())!;
    expect(row.impedanceOhm, 500);
    expect(row.algorithmId, 1);
  });

  test('stability is persisted', () async {
    await repository.save(
      measurement(id: 'stable')
          .copyWith(stability: MeasurementStability.stable),
    );
    expect((await repository.latest())!.stability, MeasurementStability.stable);
  });

  test('body composition survives the database round trip', () async {
    await repository.save(
      measurement(id: 'body', body: {'bmi': 22.5, 'bodyFatPercent': 20.0}),
    );
    final row = (await repository.latest())!;
    expect(row.bodyComposition, {'bmi': 22.5, 'bodyFatPercent': 20.0});
  });

  test('CSV export escapes commas and quotes', () {
    final csv = MeasurementCsv.build([
      measurement(
        id: 'a',
        device: 'Scale, "A"',
        body: {'bodyFatPercent': 20.0},
      ).copyWith(profileId: 'profile-1'),
    ]);
    expect(csv, contains('"Scale, ""A"""'));
    expect(csv, contains('bodyFatPercent'));
    expect(csv.split('\n').first, contains('profile_id'));
    expect(csv, contains('profile-1'));
  });

  test('settings round trip', () async {
    final store = SettingsRepository(
      SqliteSettingsStoreAdapter(SettingsStore(database)),
    );
    expect((await store.load()).displayUnit, DisplayUnit.kg);

    await store.save(
      const AppSettings(
        displayUnit: DisplayUnit.lb,
        hardwareVerificationNote: 'synthetic test',
      ),
    );
    final loaded = await store.load();
    expect(loaded.displayUnit, DisplayUnit.lb);
    expect(loaded.hardwareVerificationNote, 'synthetic test');

    await store.save(const AppSettings(displayUnit: DisplayUnit.kg));
    final cleared = await store.load();
    expect(cleared.hardwareVerificationNote, isNull);
  });
}

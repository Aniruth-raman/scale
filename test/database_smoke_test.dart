import 'package:scale/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('in-memory database opens', () async {
    final db = await AppDatabase.openWithFactory(databaseFactoryFfi);
    expect(db.db.isOpen, isTrue);
    await db.close();
  });
}

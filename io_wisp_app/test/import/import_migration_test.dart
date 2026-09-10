import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:io_wisp_app/data/database/app_database.dart';

void main() {
  late Directory temp;
  late String path;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wisp-schema2-');
    path = '${temp.path}/test.sqlite';
  });
  tearDown(() => temp.delete(recursive: true));
  Database phase1() {
    final db = sqlite3.open(path);
    db.execute(File('test/fixtures/phase1_schema.sql').readAsStringSync());
    db.execute(
      "INSERT INTO projects VALUES ('synthetic-id','Original','original','Client','A','Estimator','2026-01-01T00:00:00Z','2026-01-02T00:00:00Z','active','Original','synthetic-root','Original',NULL)",
    );
    db.execute(
      "INSERT INTO app_settings VALUES ('active_project_id','synthetic-id'),('project_root','synthetic-root')",
    );
    return db;
  }

  test('real Phase 1 schema migration preserves all columns and settings through repeated opens', () {
    final old = phase1();
    final rows = old
        .select('SELECT * FROM projects')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final settings = old
        .select('SELECT * FROM app_settings')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    old.close();
    for (var i = 0; i < 3; i++) {
      final db = AppDatabase.open(path);
      expect(db.userVersion, 7);
      expect(db.database.select('SELECT * FROM projects'), rows);
      expect(db.database.select('SELECT * FROM app_settings'), settings);
      expect(
        db.database
            .select('SELECT version FROM schema_migrations ORDER BY version')
            .map((r) => r['version']),
        [1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        db.database.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      db.close();
    }
    final backups = temp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.pre-v2-'))
        .toList();
    expect(backups, hasLength(1));
    final snapshot = sqlite3.open(backups.single.path, mode: OpenMode.readOnly);
    expect(snapshot.select('PRAGMA user_version').single['user_version'], 1);
    expect(snapshot.select('SELECT * FROM projects'), rows);
    expect(snapshot.select('SELECT * FROM app_settings'), settings);
    snapshot.close();
  });
  test('migration failure is atomic and closes connection; Phase 1 data remains usable', () {
    final old = phase1();
    // Force failure AFTER migration 2 creates its table, at CREATE INDEX.
    old.execute('CREATE INDEX import_legacy_id_idx ON projects(revision)');
    final before = old
        .select('SELECT * FROM projects')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    old.close();
    expect(() => AppDatabase.open(path), throwsA(isA<SqliteException>()));
    final restored = sqlite3.open(path);
    expect(restored.select('PRAGMA user_version').single['user_version'], 1);
    expect(restored.select('SELECT * FROM projects'), before);
    expect(
      restored.select(
        "SELECT name FROM sqlite_master WHERE name='import_provenance'",
      ),
      isEmpty,
    );
    expect(restored.select('SELECT * FROM schema_migrations'), hasLength(1));
    restored.execute('DROP INDEX import_legacy_id_idx');
    restored.close();
    final retry = AppDatabase.open(path);
    expect(retry.userVersion, 7);
    retry.close();
  });
  test('newer database is refused without modifying schema', () {
    final db = phase1();
    db.execute('PRAGMA user_version = 99');
    db.close();
    expect(() => AppDatabase.open(path), throwsStateError);
    final unchanged = sqlite3.open(path);
    expect(unchanged.select('PRAGMA user_version').single['user_version'], 99);
    expect(unchanged.select('SELECT * FROM projects'), hasLength(1));
    unchanged.close();
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:io_wisp_app/data/database/app_database.dart';

void main() {
  late Directory temp;
  late String path;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('wisp-f3-schema-');
    path = '${temp.path}/app.sqlite';
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void phase2() {
    final db = sqlite3.open(path);
    db.execute(File('test/fixtures/phase1_schema.sql').readAsStringSync());
    db.execute(
      '''CREATE TABLE import_provenance (
      project_id TEXT PRIMARY KEY NOT NULL REFERENCES projects(id),
      imported_from_legacy INTEGER NOT NULL DEFAULT 1 CHECK(imported_from_legacy = 1),
      imported_at TEXT NOT NULL, legacy_format TEXT NOT NULL,
      source_fingerprint TEXT NOT NULL UNIQUE CHECK(length(source_fingerprint) = 64),
      legacy_id TEXT, source_filename TEXT NOT NULL, source_byte_count INTEGER NOT NULL,
      original_name_normalized TEXT NOT NULL, importer_version TEXT NOT NULL, accepted_warnings TEXT NOT NULL)''',
    );
    db.execute(
      'CREATE INDEX import_legacy_id_idx ON import_provenance(legacy_id)',
    );
    db.execute(
      "INSERT INTO schema_migrations VALUES(2,'2026-09-03T00:00:00Z')",
    );
    db.execute('PRAGMA user_version=2');
    db.execute(
      "INSERT INTO projects VALUES('id','Original','original','Client','A','Estimator','2026-01-01T00:00:00Z','2026-01-02T00:00:00Z','active','Folder','root','Folder',NULL)",
    );
    db.execute("INSERT INTO app_settings VALUES('active_project_id','id')");
    db.execute(
      "INSERT INTO import_provenance VALUES('id',1,'2026-09-03T00:00:00Z','V0.0.5',?,'legacy','source.json',3,'original','legacy-json/1','[]')",
      ['a' * 64],
    );
    db.close();
  }

  test(
    'schema 2 upgrade preserves populated records and snapshot; repeated opens',
    () {
      phase2();
      final before = sqlite3.open(path);
      final projects = before
          .select('SELECT * FROM projects')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final provenance = before
          .select('SELECT * FROM import_provenance')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      before.close();
      for (var i = 0; i < 2; i++) {
        final db = AppDatabase.open(path);
        expect(db.userVersion, 7);
        expect(db.database.select('SELECT * FROM projects'), projects);
        expect(
          db.database.select('SELECT * FROM import_provenance'),
          provenance,
        );
        expect(db.database.select('SELECT * FROM managed_files'), isEmpty);
        expect(db.database.select('PRAGMA foreign_key_check'), isEmpty);
        db.close();
      }
      final backups = temp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.pre-v3-'))
          .toList();
      expect(backups, hasLength(1));
      final backup = sqlite3.open(backups.single.path, mode: OpenMode.readOnly);
      expect(backup.select('PRAGMA user_version').single['user_version'], 2);
      expect(backup.select('SELECT * FROM import_provenance'), provenance);
      backup.close();
    },
  );
  test('schema 3 DDL failure rolls back ledger and keeps schema 2 intact', () {
    phase2();
    final old = sqlite3.open(path);
    old.execute('CREATE INDEX managed_name_idx ON projects(name)');
    old.close();
    expect(() => AppDatabase.open(path), throwsA(isA<SqliteException>()));
    final after = sqlite3.open(path);
    expect(after.select('PRAGMA user_version').single['user_version'], 2);
    expect(
      after.select("SELECT * FROM sqlite_master WHERE name='managed_files'"),
      isEmpty,
    );
    expect(after.select('SELECT * FROM import_provenance'), hasLength(1));
    after.close();
  });
}

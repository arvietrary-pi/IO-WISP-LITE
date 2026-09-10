import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:io_wisp_app/data/database/app_database.dart';

import 'scope_test_support.dart';

void main() {
  late Directory temp;
  late String path;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('wisp-f4-schema-');
    path = '${temp.path}/app.sqlite';
  });
  tearDown(() => temp.deleteSync(recursive: true));
  Map<String, List<Map<String, Object?>>> populate() {
    final db = sqlite3.open(path);
    db.execute(File('test/fixtures/phase3_schema.sql').readAsStringSync());
    db.execute(
      "INSERT INTO projects VALUES('id','Original','original','Client','A','Estimator','2026-01-01T00:00:00Z','2026-01-02T00:00:00Z','active','Folder','root','Folder',NULL)",
    );
    db.execute(
      "INSERT INTO app_settings VALUES('active_project_id','id'),('project_root','root')",
    );
    db.execute(
      "INSERT INTO import_provenance VALUES('id',1,'2026-09-03T00:00:00Z','V0.0.5',?,'legacy','source.json',3,'original','legacy-json/1','[]')",
      ['a' * 64],
    );
    db.execute(
      "INSERT INTO managed_files VALUES('file','id','source.pdf','source.pdf','sources/file--source.pdf',?,8,'2026-09-04T00:00:00Z','ready',NULL)",
      ['b' * 64],
    );
    final before = {
      for (final table in [
        'projects',
        'app_settings',
        'import_provenance',
        'managed_files',
      ])
        table: db
            .select('SELECT * FROM $table')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    };
    db.close();
    return before;
  }

  test('populated verified schema 3 upgrades through 7, consistent backup and idempotent reopen', () {
    final before = populate();
    for (var i = 0; i < 3; i++) {
      final db = AppDatabase.open(path);
      expect(db.userVersion, 7);
      for (final table in before.keys) {
        expect(db.database.select('SELECT * FROM $table'), before[table]);
      }
      expect(db.database.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        db.database.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      expect(
        db.database
            .select('SELECT version FROM schema_migrations')
            .map((r) => r['version']),
        [1, 2, 3, 4, 5, 6, 7],
      );
      db.close();
    }
    final backups = temp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.pre-v4-'))
        .toList();
    expect(backups, hasLength(1));
    final snapshot = sqlite3.open(backups.single.path, mode: OpenMode.readOnly);
    expect(snapshot.select('PRAGMA user_version').single['user_version'], 3);
    for (final table in before.keys) {
      expect(snapshot.select('SELECT * FROM $table'), before[table]);
    }
    snapshot.close();
  });
  test('failed migration 4 rolls back all DDL and retains original schema and rows', () {
    final before = populate();
    final old = sqlite3.open(path);
    old.execute('CREATE TABLE scope_current (sentinel TEXT)');
    old.close();
    expect(() => AppDatabase.open(path), throwsA(isA<SqliteException>()));
    final after = sqlite3.open(path);
    expect(after.select('PRAGMA user_version').single['user_version'], 3);
    expect(
      after.select(
        "SELECT * FROM sqlite_master WHERE name IN ('scope_revisions','scope_results','scope_seal')",
      ),
      isEmpty,
    );
    expect(after.select('SELECT * FROM schema_migrations'), hasLength(3));
    for (final table in before.keys) {
      expect(after.select('SELECT * FROM $table'), before[table]);
    }
    after.execute('DROP TABLE scope_current');
    after.close();
    final retry = AppDatabase.open(path);
    expect(retry.userVersion, 7);
    retry.close();
  });
  test('database constraints reject incomplete or cross-project current relationships', () {
    final c = ScopeTestContext();
    addTearDown(c.close);
    final r = c.service.apply(
      c.a.id,
      referenceBrief,
      true,
      expectedCurrent: null,
    );
    expect(
      () => c.db.database.execute('INSERT INTO scope_current VALUES(?,?)', [
        c.b.id,
        r.id,
      ]),
      throwsA(isA<SqliteException>()),
    );
    c.db.database.execute(
      "INSERT INTO scope_revisions(id,project_id,revision_order,raw,strict,applied_at,action,interpreter_version) VALUES('incomplete',?,2,'',1,'2026-09-04T00:00:00Z','apply','scope/1')",
      [c.a.id],
    );
    expect(
      () => c.db.database.execute(
        "UPDATE scope_revisions SET complete=1 WHERE id='incomplete'",
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => c.db.database.execute(
        "UPDATE scope_current SET revision_id='incomplete' WHERE project_id=?",
        [c.a.id],
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => c.db.database.execute(
        "INSERT INTO scope_results VALUES('missing','concrete','included','Reason','[]',NULL,NULL,'included')",
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(c.repository.current(c.a.id)!.id, r.id);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/pdf/sqlite_pdf_repository.dart';
import 'package:io_wisp_app/domain/pdf_document.dart';

import '../files/file_test_support.dart';

void main() {
  test('schema4 backup, preservation, migration5 and reopen integrity', () {
    final dir = Directory.systemTemp.createTempSync('wisp-p5-migrate-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.sqlite';
    final old = sqlite3.open(path);
    old.execute(File('test/fixtures/phase4_schema.sql').readAsStringSync());
    old.execute(
      "INSERT INTO projects VALUES('p','Original','original','Client','R','Estimator','2026-01-01','2026-01-01','active','P','root','P',NULL)",
    );
    old.execute("INSERT INTO app_settings VALUES('active_project_id','p')");
    final before = old
        .select('SELECT * FROM projects')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    old.close();
    for (var i = 0; i < 2; i++) {
      final db = AppDatabase.open(path);
      expect(db.userVersion, 7);
      expect(db.database.select('SELECT * FROM projects'), before);
      expect(db.database.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        db.database.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      db.close();
    }
    final backup = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.pre-v5-'))
        .single;
    final b = sqlite3.open(backup.path, mode: OpenMode.readOnly);
    expect(b.select('PRAGMA user_version').single.values.single, 4);
    expect(b.select('SELECT * FROM projects'), before);
    expect(
      b.select("SELECT * FROM sqlite_master WHERE name='pdf_documents'"),
      isEmpty,
    );
    b.close();
  });
  test('migration5 DDL failure rolls back version and complete schema', () {
    final dir = Directory.systemTemp.createTempSync('wisp-p5-rollback-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.sqlite';
    final old = sqlite3.open(path);
    old.execute(File('test/fixtures/phase4_schema.sql').readAsStringSync());
    old.execute('CREATE TABLE pdf_pages(sentinel TEXT)');
    old.close();
    expect(() => AppDatabase.open(path), throwsA(isA<SqliteException>()));
    final check = sqlite3.open(path);
    expect(check.select('PRAGMA user_version').single.values.single, 4);
    expect(
      check.select("SELECT * FROM sqlite_master WHERE name='pdf_documents'"),
      isEmpty,
    );
    expect(check.select('SELECT * FROM schema_migrations'), hasLength(4));
    check.execute('DROP TABLE pdf_pages');
    check.close();
    final retry = AppDatabase.open(path);
    expect(retry.userVersion, 7);
    retry.close();
  });
  test('future schema is rejected without migrating', () {
    final dir = Directory.systemTemp.createTempSync('wisp-p5-future-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.sqlite';
    final old = sqlite3.open(path);
    old.execute('PRAGMA user_version=8');
    old.close();
    expect(() => AppDatabase.open(path), throwsStateError);
  });
  for (final boundary in ['header', 'page', 'seal']) {
    test('index $boundary write failure rolls back without partial rows', () async {
      final c = FileTestContext();
      addTearDown(c.close);
      final f = (await c.service.importFile(
        c.a.id,
        c.source('%PDF-1.4').path,
      )).file!;
      final target = boundary == 'header'
          ? 'INSERT ON pdf_documents'
          : boundary == 'page'
          ? 'INSERT ON pdf_pages'
          : 'UPDATE ON pdf_documents';
      c.db.database.execute(
        "CREATE TRIGGER fail BEFORE $target BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      expect(
        () =>
            SqlitePdfRepository(c.db)
                .save(f, [const PhysicalPage(1, 10, 20, 0)], 'test'),
        throwsA(isA<SqliteException>()),
      );
      expect(c.db.database.select('SELECT * FROM pdf_documents'), isEmpty);
      expect(c.db.database.select('SELECT * FROM pdf_pages'), isEmpty);
    });
  }
  test('complete index is immutable, exact 1..N, isolated and prior state retained', () async {
    final c = FileTestContext();
    addTearDown(c.close);
    final f = (await c.service.importFile(
      c.a.id,
      c.source('%PDF-1.4').path,
    )).file!;
    final repo = SqlitePdfRepository(c.db);
    const pages = [PhysicalPage(1, 10, 20, 0), PhysicalPage(2, 20, 10, 90)];
    final index = repo.save(f, pages, 'test');
    expect(repo.find(c.b.id, f.id), isNull);
    for (final invalid in [
      <PhysicalPage>[],
      [const PhysicalPage(2, 10, 20, 0)],
      [const PhysicalPage(1, double.infinity, 20, 0)],
    ]) {
      expect(() => repo.save(f, invalid, 'test'), throwsA(isA<PdfFailure>()));
    }
    expect(
      () => repo.save(f, [const PhysicalPage(1, 10, 20, 0)], 'test'),
      throwsA(isA<PdfFailure>()),
    );
    expect(repo.find(c.a.id, f.id)!.id, index.id);
    for (final sql in [
      "DELETE FROM pdf_pages WHERE document_id='${index.id}'",
      "UPDATE pdf_documents SET page_count=3 WHERE id='${index.id}'",
      "INSERT INTO pdf_pages VALUES('${c.b.id}','${index.id}',3,10,20,0)",
    ]) {
      expect(() => c.db.database.execute(sql), throwsA(isA<SqliteException>()));
    }
    expect(c.db.database.select('PRAGMA foreign_key_check'), isEmpty);
    expect(
      c.db.database.select('PRAGMA integrity_check').single.values.single,
      'ok',
    );
  });
  test(
    'database linkage and seal reject cross project and missing physical page',
    () async {
      final c = FileTestContext();
      addTearDown(c.close);
      final f = (await c.service.importFile(
        c.a.id,
        c.source('%PDF-1.4').path,
      )).file!;
      void header(String project) => c.db.database.execute(
        "INSERT INTO pdf_documents(id,project_id,managed_file_id,fingerprint,page_count,index_version,indexed_at,complete) VALUES('d',?,?,?,2,'test','now',0)",
        [project, f.id, f.fingerprint.sha256],
      );
      expect(() => header(c.b.id), throwsA(isA<SqliteException>()));
      c.db.database.execute('BEGIN');
      header(c.a.id);
      c.db.database.execute('INSERT INTO pdf_pages VALUES(?,?,?,?,?,?)', [
        c.a.id,
        'd',
        1,
        10,
        20,
        0,
      ]);
      expect(
        () => c.db.database.execute(
          "UPDATE pdf_documents SET complete=1 WHERE id='d'",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => c.db.database.execute(
          'INSERT INTO pdf_pages VALUES(?,?,?,?,?,?)',
          [c.b.id, 'd', 2, 10, 20, 0],
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => c.db.database.execute('COMMIT'),
        throwsA(isA<SqliteException>()),
      );
      c.db.database.execute('ROLLBACK');
    },
  );
}

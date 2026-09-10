import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/register/sqlite_register_repository.dart';
import 'package:io_wisp_app/domain/document_register.dart';
import 'package:io_wisp_app/domain/sheet_detector.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../files/file_test_support.dart';
import 'document_register_test.dart' show detected;

void main() {
  void removePhase7(AppDatabase database) {
    for (final table in [
      'time_entries',
      'roadmap_snapshots',
      'roadmap_items',
      'estimate_content_revisions',
      'estimate_contents',
      'checklist_snapshots',
      'checklist_items',
    ]) {
      database.database.execute('DROP TABLE $table');
    }
    database.database.execute('DELETE FROM schema_migrations WHERE version=7');
  }

  test('schema 5 upgrade retains a unique pre-v6 VACUUM snapshot', () async {
    final temp = await Directory.systemTemp.createTemp('io-wisp-v6-migration-');
    addTearDown(() => temp.delete(recursive: true));
    final path = p.join(temp.path, 'io_wisp.sqlite');
    final seed = AppDatabase.open(path);
    removePhase7(seed);
    seed.database.execute('DROP TABLE document_register_entries');
    seed.database.execute('DROP TABLE document_registers');
    seed.database.execute('DELETE FROM schema_migrations WHERE version=6');
    seed.database.execute('PRAGMA user_version=5');
    seed.close();

    final upgraded = AppDatabase.open(path);
    expect(upgraded.userVersion, 7);
    expect(
      upgraded.database.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='document_register_entries'",
      ),
      hasLength(1),
    );
    upgraded.close();
    final snapshots = temp
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).contains('.pre-v6-'))
        .toList();
    expect(snapshots, hasLength(1));
    final snapshot = sqlite.sqlite3.open(snapshots.single.path);
    expect(snapshot.select('PRAGMA user_version').single['user_version'], 5);
    snapshot.close();
  });

  test('schema 6 DDL failure rolls back and a clean retry succeeds', () async {
    final temp = await Directory.systemTemp.createTemp('io-wisp-v6-rollback-');
    addTearDown(() => temp.delete(recursive: true));
    final path = p.join(temp.path, 'io_wisp.sqlite');
    final seed = AppDatabase.open(path);
    removePhase7(seed);
    seed.database.execute('DROP TABLE document_register_entries');
    seed.database.execute('DROP TABLE document_registers');
    seed.database.execute('DELETE FROM schema_migrations WHERE version=6');
    seed.database.execute('PRAGMA user_version=5');
    seed.close();
    final blocker = sqlite.sqlite3.open(path);
    blocker.execute('CREATE TABLE document_registers(sentinel TEXT)');
    blocker.close();

    expect(
      () => AppDatabase.open(path),
      throwsA(isA<sqlite.SqliteException>()),
    );
    final after = sqlite.sqlite3.open(path);
    expect(after.select('PRAGMA user_version').single['user_version'], 5);
    expect(
      after.select('SELECT version FROM schema_migrations WHERE version=6'),
      isEmpty,
    );
    expect(
      after.select(
        "SELECT name FROM sqlite_master WHERE name='document_register_entries'",
      ),
      isEmpty,
    );
    after.execute('DROP TABLE document_registers');
    after.close();

    final retry = AppDatabase.open(path);
    expect(retry.userVersion, 7);
    expect(retry.database.select('PRAGMA foreign_key_check'), isEmpty);
    retry.close();
  });

  test(
    're-analysis refreshes only detected fields and preserves estimator work',
    () async {
      final context = FileTestContext();
      addTearDown(context.close);
      final imported = await context.service.importFile(
        context.a.id,
        p.normalize(File('test/fixtures/pdf/one.pdf').absolute.path),
      );
      final file = imported.file!;
      final repository = SqliteRegisterRepository(context.db);
      repository.saveDetection(
        projectId: context.a.id,
        managedFileId: file.id,
        sourceFilename: file.name,
        fingerprint: file.fingerprint.sha256,
        detectorVersion: SheetDetector.version,
        entries: [detected(page: 1)],
      );
      repository.updateOverrides(
        context.a.id,
        file.id,
        1,
        const RegisterEntryOverrides(
          sheetNumber: '',
          title: 'Manual title',
          discipline: 'Structural',
          revision: 'M1',
          scale: 'NTS',
          drawingDate: '2026-09-05',
          notes: 'Sacred estimator note.',
          documentState: DocumentState.superseded,
        ),
      );
      repository.setReviewState(
        context.a.id,
        file.id,
        1,
        RegisterReviewState.signedOff,
        signedOffBy: 'Engr. Estimator',
        signedOffAt: DateTime.utc(2026, 9, 5),
      );

      repository.saveDetection(
        projectId: context.a.id,
        managedFileId: file.id,
        sourceFilename: file.name,
        fingerprint: file.fingerprint.sha256,
        detectorVersion: '${SheetDetector.version}-rerun',
        entries: [detected(page: 1, sheet: 'A99.99', revision: 'D')],
      );
      final entry = repository.find(context.a.id, file.id)!.entries.single;
      expect(entry.detected.sheetNumber, 'A99.99');
      expect(entry.detected.revision, 'D');
      expect(entry.sheetNumber, '');
      expect(entry.title, 'Manual title');
      expect(entry.discipline, 'Structural');
      expect(entry.revision, 'M1');
      expect(entry.scale, 'NTS');
      expect(entry.drawingDate, '2026-09-05');
      expect(entry.notes, 'Sacred estimator note.');
      expect(entry.documentState, DocumentState.superseded);
      expect(entry.reviewState, RegisterReviewState.signedOff);
      expect(entry.signedOffBy, 'Engr. Estimator');
      expect(entry.signedOffAt, DateTime.utc(2026, 9, 5));
    },
  );
}

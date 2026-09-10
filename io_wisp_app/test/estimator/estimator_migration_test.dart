import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  void downgradeToSix(String path) {
    final database = AppDatabase.open(path);
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
    database.database.execute('PRAGMA user_version=6');
    database.close();
  }

  test('schema 6 upgrades to 7 with retained pre-v7 snapshot', () async {
    final temp = await Directory.systemTemp.createTemp('io-wisp-v7-migration-');
    addTearDown(() => temp.delete(recursive: true));
    final path = p.join(temp.path, 'io_wisp.sqlite');
    downgradeToSix(path);

    final upgraded = AppDatabase.open(path);
    expect(upgraded.userVersion, 7);
    expect(
      upgraded.database.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('checklist_items','estimate_contents','roadmap_items','time_entries')",
      ),
      hasLength(4),
    );
    expect(upgraded.database.select('PRAGMA foreign_key_check'), isEmpty);
    upgraded.close();

    final snapshots = temp
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).contains('.pre-v7-'))
        .toList();
    expect(snapshots, hasLength(1));
    final snapshot = sqlite3.open(
      snapshots.single.path,
      mode: OpenMode.readOnly,
    );
    expect(snapshot.select('PRAGMA user_version').single['user_version'], 6);
    expect(
      snapshot.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='checklist_items'",
      ),
      isEmpty,
    );
    snapshot.close();
  });

  test('schema 7 DDL failure rolls back and clean retry succeeds', () async {
    final temp = await Directory.systemTemp.createTemp('io-wisp-v7-rollback-');
    addTearDown(() => temp.delete(recursive: true));
    final path = p.join(temp.path, 'io_wisp.sqlite');
    downgradeToSix(path);
    final blocker = sqlite3.open(path);
    blocker.execute('CREATE TABLE checklist_items(sentinel TEXT)');
    blocker.close();

    expect(() => AppDatabase.open(path), throwsA(isA<SqliteException>()));
    final after = sqlite3.open(path);
    expect(after.select('PRAGMA user_version').single['user_version'], 6);
    expect(
      after.select('SELECT version FROM schema_migrations WHERE version=7'),
      isEmpty,
    );
    expect(
      after.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='estimate_contents'",
      ),
      isEmpty,
    );
    after.execute('DROP TABLE checklist_items');
    after.close();

    final retry = AppDatabase.open(path);
    expect(retry.userVersion, 7);
    expect(retry.database.select('PRAGMA foreign_key_check'), isEmpty);
    retry.close();
  });
}

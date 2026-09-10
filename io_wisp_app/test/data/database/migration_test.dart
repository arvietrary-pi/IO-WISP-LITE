import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:io_wisp_app/data/database/app_database.dart';

void main() {
  test(
    'fresh database reaches schema version 7 and records all migrations',
    () async {
      final temp = await Directory.systemTemp.createTemp('io-wisp-migration-');
      addTearDown(() => temp.delete(recursive: true));
      final databasePath = p.join(temp.path, 'nested', 'io_wisp.sqlite');

      final first = AppDatabase.open(databasePath);
      expect(first.userVersion, AppDatabase.currentSchemaVersion);
      expect(
        first.database.select('SELECT version FROM schema_migrations'),
        hasLength(7),
      );
      expect(
        first.database.select(
          "SELECT name FROM sqlite_master WHERE type='table'",
        ),
        anyElement(
          predicate<Map<String, Object?>>((row) => row['name'] == 'projects'),
        ),
      );
      first.close();

      final reopened = AppDatabase.open(databasePath);
      expect(reopened.userVersion, 7);
      expect(
        reopened.database.select('SELECT version FROM schema_migrations'),
        hasLength(7),
      );
      reopened.close();
    },
  );
}

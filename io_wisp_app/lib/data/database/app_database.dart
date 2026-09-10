import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../domain/scope.dart';
import '../pdf/pdf_schema.dart';
import '../register/register_schema.dart';
import '../estimator/estimator_schema.dart';

class AppDatabase {
  AppDatabase._(this.database, this.path);

  static const currentSchemaVersion = 7;

  final Database database;
  final String path;

  static AppDatabase open(String databasePath) {
    final parent = Directory(File(databasePath).parent.path);
    parent.createSync(recursive: true);
    final database = sqlite3.open(databasePath);
    final appDatabase = AppDatabase._(database, databasePath);
    try {
      appDatabase._migrate();
      return appDatabase;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  int get userVersion {
    final row = database.select('PRAGMA user_version').first;
    return row['user_version'] as int;
  }

  T transaction<T>(T Function() action) {
    database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      database.execute('COMMIT');
      return result;
    } catch (_) {
      try {
        database.execute('ROLLBACK');
      } catch (_) {
        // Preserve the original database error.
      }
      rethrow;
    }
  }

  void close() => database.close();

  void _migrate() {
    database.execute('PRAGMA foreign_keys = ON');
    final version = userVersion;
    if (version > currentSchemaVersion) {
      throw StateError(
        'Database schema version $version is newer than this app supports.',
      );
    }
    if (version == currentSchemaVersion) {
      return;
    }

    if (version == 1) {
      // A consistent SQLite snapshot, including any journaled state. Do not
      // file-copy a live database. Failure aborts before migration changes.
      database.execute('VACUUM INTO ?', [
        '$path.pre-v2-${const Uuid().v4()}.sqlite',
      ]);
    }
    if (version == 2) {
      database.execute('VACUUM INTO ?', [
        '$path.pre-v3-${const Uuid().v4()}.sqlite',
      ]);
    }

    if (version == 3) {
      database.execute('VACUUM INTO ?', [
        '$path.pre-v4-${const Uuid().v4()}.sqlite',
      ]);
    }

    if (version == 4) {
      database.execute('VACUUM INTO ?', [
        '$path.pre-v5-${const Uuid().v4()}.sqlite',
      ]);
    }
    if (version == 5) {
      database.execute('VACUUM INTO ?', [
        '$path.pre-v6-${const Uuid().v4()}.sqlite',
      ]);
    }
    if (version == 6) {
      database.execute('VACUUM INTO ?', [
        '$path.pre-v7-${const Uuid().v4()}.sqlite',
      ]);
    }
    transaction(() {
      database.execute('''
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        )
      ''');
      if (version < 1) {
        database.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            name_normalized TEXT NOT NULL UNIQUE,
            location_client TEXT NOT NULL DEFAULT '',
            revision TEXT NOT NULL DEFAULT '',
            estimator TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'active',
            safe_folder_name TEXT NOT NULL,
            project_root_reference TEXT NOT NULL,
            project_directory_reference TEXT NOT NULL,
            folder_created_at TEXT
          )
        ''');
        database.execute('''
          CREATE INDEX projects_updated_at_idx
          ON projects(updated_at DESC)
        ''');
        database.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          )
        ''');
        database.execute(
          'INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)',
          [1, DateTime.now().toUtc().toIso8601String()],
        );
        database.execute('PRAGMA user_version = 1');
      }
      if (version < 2) {
        database.execute('''
          CREATE TABLE import_provenance (
            project_id TEXT PRIMARY KEY NOT NULL REFERENCES projects(id),
            imported_from_legacy INTEGER NOT NULL DEFAULT 1 CHECK(imported_from_legacy = 1),
            imported_at TEXT NOT NULL,
            legacy_format TEXT NOT NULL,
            source_fingerprint TEXT NOT NULL UNIQUE CHECK(length(source_fingerprint) = 64),
            legacy_id TEXT,
            source_filename TEXT NOT NULL,
            source_byte_count INTEGER NOT NULL,
            original_name_normalized TEXT NOT NULL,
            importer_version TEXT NOT NULL,
            accepted_warnings TEXT NOT NULL
          )
        ''');
        database.execute(
          'CREATE INDEX import_legacy_id_idx ON import_provenance(legacy_id)',
        );
        database.execute(
          'INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)',
          [2, DateTime.now().toUtc().toIso8601String()],
        );
        database.execute('PRAGMA user_version = 2');
      }
      if (version < 3) {
        database.execute('''
          CREATE TABLE managed_files (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id),
            original_name TEXT NOT NULL,
            name TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            fingerprint TEXT NOT NULL CHECK(length(fingerprint) = 64),
            byte_count INTEGER NOT NULL CHECK(byte_count >= 0),
            imported_at TEXT NOT NULL,
            state TEXT NOT NULL CHECK(state IN ('importing','ready','missing','trashing','trashed','recoveryNeeded')),
            revision_of TEXT,
            UNIQUE(project_id, id),
            UNIQUE(project_id, fingerprint),
            UNIQUE(project_id, relative_path),
            FOREIGN KEY(project_id, revision_of) REFERENCES managed_files(project_id, id)
          )
        ''');
        database.execute(
          "CREATE UNIQUE INDEX managed_operation_idx ON managed_files(project_id) WHERE state IN ('importing','trashing')",
        );
        database.execute(
          'CREATE INDEX managed_name_idx ON managed_files(project_id, name COLLATE NOCASE)',
        );
        database.execute(
          'INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)',
          [3, DateTime.now().toUtc().toIso8601String()],
        );
        database.execute('PRAGMA user_version = 3');
      }
      if (version < 4) {
        database.execute('''
          CREATE TABLE scope_revisions (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id),
            revision_order INTEGER NOT NULL CHECK(revision_order > 0),
            raw TEXT NOT NULL,
            strict INTEGER NOT NULL CHECK(strict IN (0,1)),
            applied_at TEXT NOT NULL,
            action TEXT NOT NULL CHECK(action IN ('apply','override','revert')),
            interpreter_version TEXT NOT NULL,
            parent_id TEXT,
            restored_from TEXT,
            complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0,1)),
            UNIQUE(project_id,id), UNIQUE(project_id,revision_order),
            FOREIGN KEY(project_id,parent_id) REFERENCES scope_revisions(project_id,id),
            FOREIGN KEY(project_id,restored_from) REFERENCES scope_revisions(project_id,id)
          )
        ''');
        final packageIds = scopePackages.map((p) => "'${p.id}'").join(',');
        final decisions = ScopeDecision.values
            .map((d) => "'${d.name}'")
            .join(',');
        database.execute('''
          CREATE TABLE scope_results (
            revision_id TEXT NOT NULL REFERENCES scope_revisions(id),
            package_id TEXT NOT NULL CHECK(package_id IN ($packageIds)),
            detected TEXT NOT NULL CHECK(detected IN ($decisions)),
            reason TEXT NOT NULL CHECK(length(reason)>0),
            evidence_json TEXT NOT NULL,
            manual TEXT CHECK(manual IN ($decisions)),
            manual_reason TEXT,
            effective TEXT NOT NULL CHECK(effective = COALESCE(manual,detected)),
            CHECK((manual IS NULL AND manual_reason IS NULL) OR
                  (manual IS NOT NULL AND manual_reason IS NOT NULL AND length(trim(manual_reason))>0)),
            PRIMARY KEY(revision_id,package_id)
          )
        ''');
        database.execute('''
          CREATE TABLE scope_current (
            project_id TEXT PRIMARY KEY NOT NULL REFERENCES projects(id),
            revision_id TEXT NOT NULL,
            FOREIGN KEY(project_id,revision_id) REFERENCES scope_revisions(project_id,id)
          )
        ''');
        database.execute('''
          CREATE TRIGGER scope_seal BEFORE UPDATE OF complete ON scope_revisions
          WHEN NEW.complete=1 AND (SELECT count(*) FROM scope_results WHERE revision_id=NEW.id) != ${scopePackages.length}
          BEGIN SELECT RAISE(ABORT,'Incomplete Scope Gate'); END
        ''');
        database.execute('''
          CREATE TRIGGER scope_header_insert BEFORE INSERT ON scope_revisions WHEN NEW.complete!=0
          BEGIN SELECT RAISE(ABORT,'Scope must be assembled before sealing'); END
        ''');
        for (final operation in ['UPDATE', 'DELETE']) {
          database.execute('''
            CREATE TRIGGER scope_header_${operation.toLowerCase()} BEFORE $operation ON scope_revisions WHEN OLD.complete=1
            BEGIN SELECT RAISE(ABORT,'Applied scope history is immutable'); END
          ''');
        }
        for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
          final reference = operation == 'DELETE' ? 'OLD' : 'NEW';
          final oldCheck = operation == 'UPDATE'
              ? ' OR (SELECT complete FROM scope_revisions WHERE id=OLD.revision_id)=1'
              : '';
          database.execute('''
            CREATE TRIGGER scope_result_${operation.toLowerCase()} BEFORE $operation ON scope_results
            WHEN (SELECT complete FROM scope_revisions WHERE id=$reference.revision_id)=1 $oldCheck
            BEGIN SELECT RAISE(ABORT,'Applied scope results are immutable'); END
          ''');
        }
        for (final operation in ['INSERT', 'UPDATE']) {
          database.execute('''
            CREATE TRIGGER scope_current_${operation.toLowerCase()} BEFORE $operation ON scope_current
            WHEN COALESCE((SELECT complete FROM scope_revisions WHERE id=NEW.revision_id AND project_id=NEW.project_id),0)!=1
            BEGIN SELECT RAISE(ABORT,'Current scope must be complete and belong to the project'); END
          ''');
        }
        database.execute(
          'INSERT INTO schema_migrations(version,applied_at) VALUES (?,?)',
          [4, DateTime.now().toUtc().toIso8601String()],
        );
        database.execute('PRAGMA user_version = 4');
      }
      if (version < 5) {
        createPdfSchema(database);
        database.execute(
          'INSERT INTO schema_migrations(version,applied_at) VALUES (?,?)',
          [5, DateTime.now().toUtc().toIso8601String()],
        );
        database.execute('PRAGMA user_version = 5');
      }
      if (version < 6) {
        createRegisterSchema(database);
        database.execute(
          'INSERT INTO schema_migrations(version,applied_at) VALUES (?,?)',
          [6, DateTime.now().toUtc().toIso8601String()],
        );
        database.execute('PRAGMA user_version = 6');
      }
      if (version < 7) {
        createEstimatorSchema(database);
        database.execute(
          'INSERT INTO schema_migrations(version,applied_at) VALUES (?,?)',
          [7, DateTime.now().toUtc().toIso8601String()],
        );
        database.execute('PRAGMA user_version = 7');
      }
    });
  }
}

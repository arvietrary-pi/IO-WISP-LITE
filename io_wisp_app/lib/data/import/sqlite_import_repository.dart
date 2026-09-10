import 'dart:convert';

import '../../domain/legacy_import.dart';
import '../../domain/project.dart';
import '../database/app_database.dart';
import '../projects/sqlite_project_repository.dart';
import '../settings/app_settings_repository.dart';

class SqliteImportRepository implements ImportRepository {
  SqliteImportRepository(this.database);
  final AppDatabase database;
  @override
  List<Project> projects() => SqliteProjectRepository(database).getAll();
  @override
  String get projectRoot =>
      SqliteAppSettingsRepository(database).getProjectRoot() ?? '';
  @override
  String? get activeProjectId =>
      SqliteAppSettingsRepository(database).getActiveProjectId();
  @override
  List<ImportProvenance> provenance() => database.database
      .select('SELECT * FROM import_provenance')
      .map(
        (r) => ImportProvenance(
          projectId: r['project_id'] as String,
          importedAt: DateTime.parse(r['imported_at'] as String),
          format: r['legacy_format'] as String,
          fingerprint: r['source_fingerprint'] as String,
          sourceFilename: r['source_filename'] as String,
          legacyId: r['legacy_id'] as String?,
          originalNormalizedName: r['original_name_normalized'] as String,
          sourceByteCount: r['source_byte_count'] as int,
          acceptedWarnings: (jsonDecode(
            r['accepted_warnings'] as String,
          ) as List).cast<String>(),
        ),
      )
      .toList();
  @override
  void save(
    Project project,
    ImportProvenance provenance, {
    required bool makeActive,
    required void Function() verifyBeforeCommit,
  }) {
    database.transaction(() {
      verifyBeforeCommit();
      SqliteProjectRepository(database).insert(project);
      final v = provenance;
      database.database.execute(
        '''INSERT INTO import_provenance
        (project_id, imported_at, legacy_format, source_fingerprint, legacy_id,
         source_filename, source_byte_count, original_name_normalized, importer_version, accepted_warnings)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          v.projectId,
          v.importedAt.toIso8601String(),
          v.format,
          v.fingerprint,
          v.legacyId,
          v.sourceFilename,
          v.sourceByteCount,
          v.originalNormalizedName,
          ImportProvenance.importerVersion,
          jsonEncode(v.acceptedWarnings),
        ],
      );
      if (makeActive || activeProjectId == null) {
        SqliteAppSettingsRepository(database).setActiveProjectId(project.id);
      }
    });
  }

  @override
  bool containsImport(String id, String fingerprint) =>
      database.database
          .select(
            '''
    SELECT p.id FROM projects p JOIN import_provenance i ON i.project_id = p.id
    WHERE p.id = ? AND i.source_fingerprint = ?''',
            [id, fingerprint],
          )
          .length ==
      1;
}

import '../../domain/managed_file.dart';
import '../../domain/project.dart';
import '../database/app_database.dart';
import '../projects/sqlite_project_repository.dart';

class SqliteManagedFileRepository {
  SqliteManagedFileRepository(this.database);
  final AppDatabase database;
  List<Project> get projects => SqliteProjectRepository(database).getAll();
  Project project(String id) =>
      SqliteProjectRepository(database).findById(id) ??
      (throw const FileImportException(
        'The selected project no longer exists.',
      ));
  T transaction<T>(T Function() action) => database.transaction(action);

  List<ManagedFile> list(String projectId) => database.database
      .select(
        'SELECT * FROM managed_files WHERE project_id = ? ORDER BY imported_at, id',
        [projectId],
      )
      .map(
        (r) => ManagedFile(
          id: r['id'] as String,
          projectId: r['project_id'] as String,
          originalName: r['original_name'] as String,
          name: r['name'] as String,
          relativePath: r['relative_path'] as String,
          fingerprint: FileFingerprint(
            r['fingerprint'] as String,
            r['byte_count'] as int,
          ),
          importedAt: DateTime.parse(r['imported_at'] as String),
          state: ManagedFileState.values.byName(r['state'] as String),
          revisionOf: r['revision_of'] as String?,
        ),
      )
      .toList();

  ManagedFile get(String projectId, String id) => list(projectId).firstWhere(
    (f) => f.id == id,
    orElse: () => throw const FileImportException(
      'This file does not belong to the selected project.',
    ),
  );

  void requireIdle(String projectId) {
    if (list(projectId).any(
      (f) => [
        ManagedFileState.importing,
        ManagedFileState.trashing,
        ManagedFileState.recoveryNeeded,
      ].contains(f.state),
    )) {
      throw const FileImportException(
        'A file operation is unfinished or needs recovery. Retained files must be reviewed before another change.',
        recoveryNeeded: true,
      );
    }
  }

  void insert(ManagedFile file) {
    database.database.execute(
      '''INSERT INTO managed_files
      (id,project_id,original_name,name,relative_path,fingerprint,byte_count,imported_at,state,revision_of)
      VALUES (?,?,?,?,?,?,?,?,?,?)''',
      [
        file.id,
        file.projectId,
        file.originalName,
        file.name,
        file.relativePath,
        file.fingerprint.sha256,
        file.fingerprint.byteCount,
        file.importedAt.toUtc().toIso8601String(),
        file.state.name,
        file.revisionOf,
      ],
    );
  }

  void updateState(ManagedFile file) {
    database.database.execute(
      'UPDATE managed_files SET state=?, relative_path=? WHERE project_id=? AND id=?',
      [file.state.name, file.relativePath, file.projectId, file.id],
    );
    if (database.database.updatedRows != 1) {
      throw const FileImportException(
        'File record changed during the operation.',
        recoveryNeeded: true,
      );
    }
  }

  void removePending(ManagedFile file) {
    database.database.execute(
      "DELETE FROM managed_files WHERE project_id=? AND id=? AND state='importing'",
      [file.projectId, file.id],
    );
    if (database.database.updatedRows != 1) {
      throw const FileImportException(
        'Pending record could not be removed.',
        recoveryNeeded: true,
      );
    }
  }
}

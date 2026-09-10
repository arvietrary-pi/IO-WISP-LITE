import 'package:sqlite3/sqlite3.dart';

import '../../domain/project.dart';
import '../database/app_database.dart';
import 'project_repository.dart';

class SqliteProjectRepository implements ProjectRepository {
  const SqliteProjectRepository(this._database);

  final AppDatabase _database;

  @override
  List<Project> getAll() {
    final rows = _database.database.select('''
      SELECT id, name, location_client, revision, estimator,
             created_at, updated_at, status, safe_folder_name,
             project_root_reference, project_directory_reference,
             folder_created_at
      FROM projects
      ORDER BY updated_at DESC, created_at ASC
    ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Project? findById(String id) {
    final rows = _database.database.select(
      '''
      SELECT id, name, location_client, revision, estimator,
             created_at, updated_at, status, safe_folder_name,
             project_root_reference, project_directory_reference,
             folder_created_at
      FROM projects
      WHERE id = ?
      LIMIT 1
    ''',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Project? findByNormalizedName(String normalizedName) {
    final rows = _database.database.select(
      '''
      SELECT id, name, location_client, revision, estimator,
             created_at, updated_at, status, safe_folder_name,
             project_root_reference, project_directory_reference,
             folder_created_at
      FROM projects
      WHERE name_normalized = ?
      LIMIT 1
    ''',
      [normalizedName],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  void insert(Project project) {
    _database.database.execute(
      '''
      INSERT INTO projects(
        id, name, name_normalized, location_client, revision, estimator,
        created_at, updated_at, status, safe_folder_name,
        project_root_reference, project_directory_reference, folder_created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        project.id,
        project.name,
        project.normalizedName,
        project.locationClient,
        project.revision,
        project.estimator,
        project.createdAt.toUtc().toIso8601String(),
        project.updatedAt.toUtc().toIso8601String(),
        project.status,
        project.safeFolderName,
        project.projectRootReference,
        project.projectDirectoryReference,
        project.folderCreatedAt?.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  void update(Project project) {
    _database.database.execute(
      '''
      UPDATE projects
      SET name = ?, name_normalized = ?, location_client = ?, revision = ?,
          estimator = ?, updated_at = ?, status = ?
      WHERE id = ?
    ''',
      [
        project.name,
        project.normalizedName,
        project.locationClient,
        project.revision,
        project.estimator,
        project.updatedAt.toUtc().toIso8601String(),
        project.status,
        project.id,
      ],
    );
  }

  Project _fromRow(Row row) {
    return Project(
      id: row['id'] as String,
      name: row['name'] as String,
      locationClient: row['location_client'] as String,
      revision: row['revision'] as String,
      estimator: row['estimator'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      status: row['status'] as String,
      safeFolderName: row['safe_folder_name'] as String,
      projectRootReference: row['project_root_reference'] as String,
      projectDirectoryReference: row['project_directory_reference'] as String,
      folderCreatedAt: row['folder_created_at'] == null
          ? null
          : DateTime.parse(row['folder_created_at'] as String).toUtc(),
    );
  }
}

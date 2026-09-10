import '../database/app_database.dart';

abstract class AppSettingsRepository {
  String? getProjectRoot();

  String? getActiveProjectId();

  void setProjectRoot(String path);

  void setActiveProjectId(String? id);
}

class SqliteAppSettingsRepository implements AppSettingsRepository {
  const SqliteAppSettingsRepository(this._database);

  static const projectRootKey = 'project_root';
  static const activeProjectIdKey = 'active_project_id';

  final AppDatabase _database;

  @override
  String? getProjectRoot() => _read(projectRootKey);

  @override
  String? getActiveProjectId() => _read(activeProjectIdKey);

  @override
  void setProjectRoot(String path) => _write(projectRootKey, path);

  @override
  void setActiveProjectId(String? id) {
    if (id == null) {
      _database.database.execute('DELETE FROM app_settings WHERE key = ?', [
        activeProjectIdKey,
      ]);
      return;
    }
    _write(activeProjectIdKey, id);
  }

  String? _read(String key) {
    final rows = _database.database.select(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1',
      [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void _write(String key, String value) {
    _database.database.execute(
      '''
      INSERT INTO app_settings(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    ''',
      [key, value],
    );
  }
}

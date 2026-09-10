-- Exact Phase 1 table/index definitions from commit 3940e10 app_database.dart.
CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
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
);
CREATE INDEX projects_updated_at_idx ON projects(updated_at DESC);
CREATE TABLE app_settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
INSERT INTO schema_migrations VALUES (1, '2026-09-03T00:00:00Z');
PRAGMA user_version = 1;

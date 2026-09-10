-- Exact schema 3 DDL from phase-3-verified / 6b67d46. Synthetic migration timestamps.
CREATE TABLE IF NOT EXISTS schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        );
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
CREATE INDEX projects_updated_at_idx
          ON projects(updated_at DESC);
CREATE TABLE app_settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          );
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
          );
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
          );
CREATE INDEX import_legacy_id_idx ON import_provenance(legacy_id);
CREATE UNIQUE INDEX managed_operation_idx ON managed_files(project_id) WHERE state IN ('importing','trashing');
CREATE INDEX managed_name_idx ON managed_files(project_id, name COLLATE NOCASE);
INSERT INTO schema_migrations VALUES (1,'2026-09-03T00:00:00Z'),(2,'2026-09-03T00:00:00Z'),(3,'2026-09-04T00:00:00Z');
PRAGMA user_version=3;

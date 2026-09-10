-- Exact schema from retained phase-4-verified schema4.json evidence.
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
CREATE TABLE schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        );
CREATE TABLE scope_current (
            project_id TEXT PRIMARY KEY NOT NULL REFERENCES projects(id),
            revision_id TEXT NOT NULL,
            FOREIGN KEY(project_id,revision_id) REFERENCES scope_revisions(project_id,id)
          );
CREATE TABLE scope_results (
            revision_id TEXT NOT NULL REFERENCES scope_revisions(id),
            package_id TEXT NOT NULL CHECK(package_id IN ('preliminaries','demolition','earthworks','concrete','reinforcement','structural','masonry','roofing','openings','finishes','plumbing','electrical','mechanical','fire','external','testing')),
            detected TEXT NOT NULL CHECK(detected IN ('included','rejected','held','review')),
            reason TEXT NOT NULL CHECK(length(reason)>0),
            evidence_json TEXT NOT NULL,
            manual TEXT CHECK(manual IN ('included','rejected','held','review')),
            manual_reason TEXT,
            effective TEXT NOT NULL CHECK(effective = COALESCE(manual,detected)),
            CHECK((manual IS NULL AND manual_reason IS NULL) OR
                  (manual IS NOT NULL AND manual_reason IS NOT NULL AND length(trim(manual_reason))>0)),
            PRIMARY KEY(revision_id,package_id)
          );
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
          );
CREATE INDEX import_legacy_id_idx ON import_provenance(legacy_id);
CREATE INDEX managed_name_idx ON managed_files(project_id, name COLLATE NOCASE);
CREATE UNIQUE INDEX managed_operation_idx ON managed_files(project_id) WHERE state IN ('importing','trashing');
CREATE INDEX projects_updated_at_idx
          ON projects(updated_at DESC)
        ;
CREATE TRIGGER scope_current_insert BEFORE INSERT ON scope_current
            WHEN COALESCE((SELECT complete FROM scope_revisions WHERE id=NEW.revision_id AND project_id=NEW.project_id),0)!=1
            BEGIN SELECT RAISE(ABORT,'Current scope must be complete and belong to the project'); END;
CREATE TRIGGER scope_current_update BEFORE UPDATE ON scope_current
            WHEN COALESCE((SELECT complete FROM scope_revisions WHERE id=NEW.revision_id AND project_id=NEW.project_id),0)!=1
            BEGIN SELECT RAISE(ABORT,'Current scope must be complete and belong to the project'); END;
CREATE TRIGGER scope_header_delete BEFORE DELETE ON scope_revisions WHEN OLD.complete=1
            BEGIN SELECT RAISE(ABORT,'Applied scope history is immutable'); END;
CREATE TRIGGER scope_header_insert BEFORE INSERT ON scope_revisions WHEN NEW.complete!=0
          BEGIN SELECT RAISE(ABORT,'Scope must be assembled before sealing'); END;
CREATE TRIGGER scope_header_update BEFORE UPDATE ON scope_revisions WHEN OLD.complete=1
            BEGIN SELECT RAISE(ABORT,'Applied scope history is immutable'); END;
CREATE TRIGGER scope_result_delete BEFORE DELETE ON scope_results
            WHEN (SELECT complete FROM scope_revisions WHERE id=OLD.revision_id)=1 
            BEGIN SELECT RAISE(ABORT,'Applied scope results are immutable'); END;
CREATE TRIGGER scope_result_insert BEFORE INSERT ON scope_results
            WHEN (SELECT complete FROM scope_revisions WHERE id=NEW.revision_id)=1 
            BEGIN SELECT RAISE(ABORT,'Applied scope results are immutable'); END;
CREATE TRIGGER scope_result_update BEFORE UPDATE ON scope_results
            WHEN (SELECT complete FROM scope_revisions WHERE id=NEW.revision_id)=1  OR (SELECT complete FROM scope_revisions WHERE id=OLD.revision_id)=1
            BEGIN SELECT RAISE(ABORT,'Applied scope results are immutable'); END;
CREATE TRIGGER scope_seal BEFORE UPDATE OF complete ON scope_revisions
          WHEN NEW.complete=1 AND (SELECT count(*) FROM scope_results WHERE revision_id=NEW.id) != 16
          BEGIN SELECT RAISE(ABORT,'Incomplete Scope Gate'); END;
INSERT INTO schema_migrations VALUES(1,'baseline'),(2,'baseline'),(3,'baseline'),(4,'baseline');
PRAGMA user_version=4;

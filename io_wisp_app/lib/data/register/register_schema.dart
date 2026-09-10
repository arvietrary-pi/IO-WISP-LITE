import 'package:sqlite3/sqlite3.dart';

void createRegisterSchema(Database db) {
  db.execute('''
    CREATE TABLE document_registers (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL,
      managed_file_id TEXT NOT NULL,
      source_filename TEXT NOT NULL,
      fingerprint TEXT NOT NULL CHECK(length(fingerprint)=64),
      detector_version TEXT NOT NULL,
      analyzed_at TEXT NOT NULL,
      page_count INTEGER NOT NULL CHECK(typeof(page_count)='integer' AND page_count>0),
      UNIQUE(project_id,managed_file_id),
      UNIQUE(project_id,id),
      FOREIGN KEY(project_id,managed_file_id) REFERENCES managed_files(project_id,id)
    )
  ''');
  db.execute('''
    CREATE TABLE document_register_entries (
      register_id TEXT NOT NULL REFERENCES document_registers(id) ON DELETE CASCADE,
      physical_page INTEGER NOT NULL CHECK(typeof(physical_page)='integer' AND physical_page>0),
      detected_sheet_number TEXT NOT NULL,
      detected_title TEXT NOT NULL,
      detected_discipline TEXT NOT NULL,
      detected_revision TEXT NOT NULL,
      detected_scale TEXT NOT NULL,
      detected_drawing_date TEXT NOT NULL,
      detected_summary TEXT NOT NULL,
      detected_evidence TEXT NOT NULL,
      detected_title_block_text TEXT NOT NULL,
      detected_text_sample TEXT NOT NULL,
      detected_candidates_json TEXT NOT NULL,
      detected_references_json TEXT NOT NULL,
      detected_diagnostics_json TEXT NOT NULL,
      detected_status TEXT NOT NULL CHECK(detected_status IN ('ready','review')),
      detected_confidence TEXT NOT NULL CHECK(detected_confidence IN ('high','medium','low')),
      text_item_count INTEGER NOT NULL CHECK(text_item_count>=0),
      line_count INTEGER NOT NULL CHECK(line_count>=0),
      has_readable_text INTEGER NOT NULL CHECK(has_readable_text IN (0,1)),
      manual_sheet_number TEXT,
      manual_title TEXT,
      manual_discipline TEXT,
      manual_revision TEXT,
      manual_scale TEXT,
      manual_drawing_date TEXT,
      estimator_notes TEXT NOT NULL DEFAULT '',
      review_state TEXT NOT NULL DEFAULT 'unreviewed' CHECK(review_state IN ('unreviewed','reviewed','signedOff')),
      signed_off_at TEXT,
      signed_off_by TEXT,
      document_state TEXT NOT NULL DEFAULT 'current' CHECK(document_state IN ('current','superseded')),
      CHECK((review_state='signedOff' AND signed_off_at IS NOT NULL AND length(trim(signed_off_by))>0) OR
            (review_state!='signedOff' AND signed_off_at IS NULL AND signed_off_by IS NULL)),
      PRIMARY KEY(register_id,physical_page)
    )
  ''');
  db.execute(
    'CREATE INDEX register_project_idx ON document_registers(project_id, analyzed_at DESC)',
  );
  db.execute(
    'CREATE INDEX register_sheet_idx ON document_register_entries(detected_sheet_number COLLATE NOCASE)',
  );
  db.execute('''CREATE TRIGGER register_page_insert BEFORE INSERT ON document_register_entries
    WHEN NEW.physical_page > (SELECT page_count FROM document_registers WHERE id=NEW.register_id)
    BEGIN SELECT RAISE(ABORT,'Register physical page is out of range'); END''');
  db.execute(
    '''CREATE TRIGGER register_header_page_count BEFORE UPDATE OF page_count ON document_registers
    WHEN NEW.page_count != OLD.page_count AND EXISTS(SELECT 1 FROM document_register_entries WHERE register_id=OLD.id)
    BEGIN SELECT RAISE(ABORT,'Analyzed source page count is immutable'); END''',
  );
}

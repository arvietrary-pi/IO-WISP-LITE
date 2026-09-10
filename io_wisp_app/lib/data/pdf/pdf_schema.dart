import 'package:sqlite3/sqlite3.dart';

void createPdfSchema(Database db) {
  db.execute('''
    CREATE TABLE pdf_documents (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL,
      managed_file_id TEXT NOT NULL,
      fingerprint TEXT NOT NULL CHECK(length(fingerprint)=64),
      page_count INTEGER NOT NULL CHECK(typeof(page_count)='integer' AND page_count>0),
      index_version TEXT NOT NULL,
      indexed_at TEXT NOT NULL,
      complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0,1)),
      required_complete INTEGER NOT NULL DEFAULT 1 CHECK(required_complete=1),
      UNIQUE(id,complete),
      UNIQUE(project_id,id), UNIQUE(project_id,managed_file_id),
      FOREIGN KEY(project_id,managed_file_id) REFERENCES managed_files(project_id,id),
      FOREIGN KEY(id,required_complete) REFERENCES pdf_documents(id,complete) DEFERRABLE INITIALLY DEFERRED
    )
  ''');
  db.execute('''
    CREATE TABLE pdf_pages (
      project_id TEXT NOT NULL, document_id TEXT NOT NULL,
      physical_page INTEGER NOT NULL CHECK(typeof(physical_page)='integer' AND physical_page>0),
      width REAL NOT NULL CHECK(typeof(width) IN ('integer','real') AND width>0 AND width<=1.7976931348623157e308), height REAL NOT NULL CHECK(typeof(height) IN ('integer','real') AND height>0 AND height<=1.7976931348623157e308),
      rotation INTEGER NOT NULL CHECK(rotation IN (0,90,180,270)),
      PRIMARY KEY(document_id,physical_page),
      FOREIGN KEY(project_id,document_id) REFERENCES pdf_documents(project_id,id)
    )
  ''');
  db.execute('''CREATE TRIGGER pdf_header_insert BEFORE INSERT ON pdf_documents
    WHEN NEW.complete!=0 OR NOT EXISTS(SELECT 1 FROM managed_files
      WHERE project_id=NEW.project_id AND id=NEW.managed_file_id AND fingerprint=NEW.fingerprint AND state='ready')
    BEGIN SELECT RAISE(ABORT,'Invalid PDF source or index state'); END''');
  db.execute(
    '''CREATE TRIGGER pdf_seal BEFORE UPDATE OF complete ON pdf_documents
    WHEN NEW.complete=1 AND ((SELECT count(*) FROM pdf_pages WHERE document_id=NEW.id)!=NEW.page_count
      OR (SELECT min(physical_page) FROM pdf_pages WHERE document_id=NEW.id)!=1
      OR (SELECT max(physical_page) FROM pdf_pages WHERE document_id=NEW.id)!=NEW.page_count)
    BEGIN SELECT RAISE(ABORT,'Incomplete physical page index'); END''',
  );
  db.execute('''CREATE TRIGGER pdf_header_update BEFORE UPDATE ON pdf_documents WHEN OLD.complete=1
    BEGIN SELECT RAISE(ABORT,'Complete PDF index is immutable'); END''');
  for (final op in ['INSERT', 'UPDATE', 'DELETE']) {
    final ref = op == 'DELETE' ? 'OLD' : 'NEW';
    final old = op == 'UPDATE'
        ? ' OR (SELECT complete FROM pdf_documents WHERE id=OLD.document_id)=1'
        : '';
    db.execute(
      '''CREATE TRIGGER pdf_page_${op.toLowerCase()} BEFORE $op ON pdf_pages
      WHEN (SELECT complete FROM pdf_documents WHERE id=$ref.document_id)=1 $old
      BEGIN SELECT RAISE(ABORT,'Complete PDF pages are immutable'); END''',
    );
  }
}

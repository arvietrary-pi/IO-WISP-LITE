import 'package:sqlite3/sqlite3.dart';

void createEstimatorSchema(Database db) {
  db.execute('''
    CREATE TABLE checklist_items (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
      template_key TEXT NOT NULL,
      is_done INTEGER NOT NULL DEFAULT 0 CHECK(is_done IN (0,1)),
      note TEXT NOT NULL DEFAULT '',
      evidence_page INTEGER CHECK(evidence_page IS NULL OR
        (typeof(evidence_page)='integer' AND evidence_page>0)),
      updated_at TEXT NOT NULL,
      UNIQUE(project_id,template_key)
    )
  ''');
  db.execute(
    'CREATE INDEX checklist_project_idx ON checklist_items(project_id)',
  );
  db.execute('''
    CREATE TABLE checklist_snapshots (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
      snapshot_data_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      reason TEXT NOT NULL
    )
  ''');
  db.execute('''CREATE INDEX checklist_snapshots_project_idx
    ON checklist_snapshots(project_id,created_at DESC)''');

  db.execute('''
    CREATE TABLE estimate_contents (
      project_id TEXT PRIMARY KEY NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
      scope TEXT NOT NULL DEFAULT '',
      basis TEXT NOT NULL DEFAULT '',
      assumptions TEXT NOT NULL DEFAULT '',
      exclusions TEXT NOT NULL DEFAULT '',
      rfis TEXT NOT NULL DEFAULT '',
      risks TEXT NOT NULL DEFAULT '',
      rates TEXT NOT NULL DEFAULT '',
      changes TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE estimate_content_revisions (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
      scope TEXT NOT NULL,
      basis TEXT NOT NULL,
      assumptions TEXT NOT NULL,
      exclusions TEXT NOT NULL,
      rfis TEXT NOT NULL,
      risks TEXT NOT NULL,
      rates TEXT NOT NULL,
      changes TEXT NOT NULL,
      applied_at TEXT NOT NULL,
      source TEXT NOT NULL CHECK(source IN ('manual','scope_brief_sync','revert'))
    )
  ''');
  db.execute('''CREATE INDEX estimate_content_revisions_project_idx
    ON estimate_content_revisions(project_id,applied_at DESC)''');

  db.execute('''
    CREATE TABLE roadmap_items (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
      item_key TEXT NOT NULL,
      step_order INTEGER NOT NULL CHECK(typeof(step_order)='integer' AND step_order>0),
      phase TEXT NOT NULL,
      title TEXT NOT NULL,
      purpose TEXT NOT NULL,
      outputs TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'notStarted'
        CHECK(status IN ('notStarted','inProgress','complete','deferred','notApplicable')),
      reference TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL,
      UNIQUE(project_id,item_key)
    )
  ''');
  db.execute('''CREATE INDEX roadmap_project_order_idx
    ON roadmap_items(project_id,step_order,item_key)''');
  db.execute('''
    CREATE TABLE roadmap_snapshots (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
      snapshot_data_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      reason TEXT NOT NULL
    )
  ''');
  db.execute('''CREATE INDEX roadmap_snapshots_project_idx
    ON roadmap_snapshots(project_id,created_at DESC)''');

  db.execute('''
    CREATE TABLE time_entries (
      id TEXT PRIMARY KEY NOT NULL,
      project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
      reference_type TEXT NOT NULL
        CHECK(reference_type IN ('wholeEstimate','checklistItem')),
      reference_id TEXT,
      label TEXT NOT NULL CHECK(length(trim(label))>0),
      started_at TEXT NOT NULL,
      stopped_at TEXT,
      duration_seconds INTEGER NOT NULL DEFAULT 0
        CHECK(typeof(duration_seconds)='integer' AND duration_seconds>=0),
      note TEXT NOT NULL DEFAULT '',
      is_soft_deleted INTEGER NOT NULL DEFAULT 0 CHECK(is_soft_deleted IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK((reference_type='wholeEstimate' AND reference_id IS NULL) OR
        (reference_type='checklistItem' AND length(trim(reference_id))>0))
    )
  ''');
  db.execute('''CREATE INDEX time_entries_project_idx
    ON time_entries(project_id,is_soft_deleted,started_at DESC)''');
  db.execute('''CREATE UNIQUE INDEX active_timer_per_project_idx
    ON time_entries(project_id)
    WHERE stopped_at IS NULL AND is_soft_deleted=0''');
}

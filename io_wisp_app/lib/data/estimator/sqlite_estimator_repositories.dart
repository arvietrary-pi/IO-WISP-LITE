import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/estimator_workflow.dart';
import '../database/app_database.dart';

class EstimatorPersistenceException implements Exception {
  const EstimatorPersistenceException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class _EstimatorRepository {
  _EstimatorRepository(this.db);
  final AppDatabase db;

  void requireProject(String projectId) {
    if (db.database.select('SELECT id FROM projects WHERE id=?', [
      projectId,
    ]).isEmpty) {
      throw const EstimatorPersistenceException('Project not found.');
    }
  }
}

class SqliteChecklistRepository extends _EstimatorRepository {
  SqliteChecklistRepository(super.db);

  List<ChecklistEntry> list(String projectId) {
    requireProject(projectId);
    _ensureCatalog(projectId);
    final rows = db.database.select(
      'SELECT * FROM checklist_items WHERE project_id=?',
      [projectId],
    );
    final byKey = {for (final row in rows) row['template_key'] as String: row};
    return estimatorChecklistCatalog
        .map((template) => _read(byKey[template.key]!))
        .toList(growable: false);
  }

  void _ensureCatalog(String projectId) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.transaction(() {
      for (final item in estimatorChecklistCatalog) {
        db.database.execute(
          '''INSERT OR IGNORE INTO checklist_items
          (id,project_id,template_key,is_done,note,evidence_page,updated_at)
          VALUES(?,?,?,0,'',NULL,?)''',
          [const Uuid().v4(), projectId, item.key, now],
        );
      }
    });
  }

  ChecklistEntry update({
    required String projectId,
    required String templateKey,
    required bool isDone,
    required String note,
    required int? evidencePage,
    DateTime? updatedAt,
  }) {
    if (!estimatorChecklistCatalog.any((item) => item.key == templateKey)) {
      throw const EstimatorPersistenceException('Unknown checklist item.');
    }
    if (evidencePage != null && evidencePage < 1) {
      throw const EstimatorPersistenceException(
        'Evidence must use a positive physical PDF page.',
      );
    }
    _ensureCatalog(projectId);
    final time = (updatedAt ?? DateTime.now().toUtc()).toUtc();
    db.database.execute(
      '''UPDATE checklist_items SET is_done=?,note=?,evidence_page=?,updated_at=?
      WHERE project_id=? AND template_key=?''',
      [
        isDone ? 1 : 0,
        note,
        evidencePage,
        time.toIso8601String(),
        projectId,
        templateKey,
      ],
    );
    return _read(
      db.database.select(
        'SELECT * FROM checklist_items WHERE project_id=? AND template_key=?',
        [projectId, templateKey],
      ).single,
    );
  }

  String reset(String projectId, {DateTime? now}) {
    final time = (now ?? DateTime.now().toUtc()).toUtc();
    final current = list(projectId);
    return db.transaction(() {
      final id = const Uuid().v4();
      db.database.execute('INSERT INTO checklist_snapshots VALUES(?,?,?,?,?)', [
        id,
        projectId,
        jsonEncode(current.map(_toJson).toList()),
        time.toIso8601String(),
        'user_reset',
      ]);
      db.database.execute(
        "UPDATE checklist_items SET is_done=0,note='',evidence_page=NULL,updated_at=? WHERE project_id=?",
        [time.toIso8601String(), projectId],
      );
      return id;
    });
  }

  void restoreSnapshot(String projectId, String snapshotId, {DateTime? now}) {
    final time = (now ?? DateTime.now().toUtc()).toUtc().toIso8601String();
    db.transaction(() {
      final rows = db.database.select(
        'SELECT snapshot_data_json FROM checklist_snapshots WHERE id=? AND project_id=?',
        [snapshotId, projectId],
      );
      if (rows.isEmpty) {
        throw const EstimatorPersistenceException(
          'Checklist reset snapshot was not found in this project.',
        );
      }
      final items = (jsonDecode(
        rows.single['snapshot_data_json'] as String,
      ) as List).cast<Map<String, Object?>>();
      for (final item in items) {
        db.database.execute(
          '''UPDATE checklist_items SET is_done=?,note=?,evidence_page=?,updated_at=?
          WHERE project_id=? AND template_key=?''',
          [
            item['isDone'] == true ? 1 : 0,
            item['note'] as String,
            item['evidencePage'],
            time,
            projectId,
            item['templateKey'] as String,
          ],
        );
      }
    });
  }

  Map<String, Object?> _toJson(ChecklistEntry entry) => {
    'templateKey': entry.templateKey,
    'isDone': entry.isDone,
    'note': entry.note,
    'evidencePage': entry.evidencePage,
  };

  ChecklistEntry _read(Map<String, Object?> row) => ChecklistEntry(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    templateKey: row['template_key'] as String,
    isDone: row['is_done'] == 1,
    note: row['note'] as String,
    evidencePage: row['evidence_page'] as int?,
    updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
  );
}

class SqliteEstimateContentRepository extends _EstimatorRepository {
  SqliteEstimateContentRepository(super.db);

  EstimateContent get(String projectId) {
    requireProject(projectId);
    _ensure(projectId);
    return _read(
      db.database.select('SELECT * FROM estimate_contents WHERE project_id=?', [
        projectId,
      ]).single,
    );
  }

  void _ensure(String projectId) {
    db.database.execute(
      '''INSERT OR IGNORE INTO estimate_contents
      (project_id,scope,basis,assumptions,exclusions,rfis,risks,rates,changes,updated_at)
      VALUES(?,'','','','','','','','',?)''',
      [projectId, DateTime.now().toUtc().toIso8601String()],
    );
  }

  EstimateContent save(
    EstimateContent content, {
    String source = 'manual',
    bool inExistingTransaction = false,
  }) {
    EstimateContent action() {
      requireProject(content.projectId);
      _ensure(content.projectId);
      final prior = get(content.projectId);
      if (_sameValues(prior.values, content.values)) return prior;
      _snapshot(prior, source);
      _write(content);
      return get(content.projectId);
    }

    return inExistingTransaction ? action() : db.transaction(action);
  }

  bool _sameValues(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  EstimateContent syncFromScope(
    String projectId, {
    required String scope,
    required String exclusions,
    required String rfis,
    required DateTime updatedAt,
    bool inExistingTransaction = false,
  }) {
    final prior = get(projectId);
    final next = prior.copyWith(
      scope: _replaceScopeBlock(prior.scope, scope),
      exclusions: _replaceScopeBlock(prior.exclusions, exclusions),
      rfis: _replaceScopeBlock(prior.rfis, rfis),
      updatedAt: updatedAt.toUtc(),
    );
    return save(
      next,
      source: 'scope_brief_sync',
      inExistingTransaction: inExistingTransaction,
    );
  }

  List<EstimateContentRevision> revisions(String projectId) {
    requireProject(projectId);
    return db.database
        .select(
          'SELECT * FROM estimate_content_revisions WHERE project_id=? ORDER BY applied_at DESC,rowid DESC',
          [projectId],
        )
        .map(_readRevision)
        .toList(growable: false);
  }

  EstimateContent revert(
    String projectId,
    String revisionId, {
    DateTime? now,
  }) => db.transaction(() {
    final rows = db.database.select(
      'SELECT * FROM estimate_content_revisions WHERE id=? AND project_id=?',
      [revisionId, projectId],
    );
    if (rows.isEmpty) {
      throw const EstimatorPersistenceException(
        'Estimate Content revision was not found in this project.',
      );
    }
    final selected = _readRevision(rows.single).content
        .copyWith(updatedAt: (now ?? DateTime.now().toUtc()).toUtc());
    final current = get(projectId);
    _snapshot(current, 'revert');
    _write(selected);
    return get(projectId);
  });

  void _snapshot(EstimateContent content, String source) {
    db.database.execute(
      'INSERT INTO estimate_content_revisions VALUES(${List.filled(12, '?').join(',')})',
      [
        const Uuid().v4(),
        content.projectId,
        ...content.values,
        DateTime.now().toUtc().toIso8601String(),
        source,
      ],
    );
  }

  void _write(EstimateContent content) {
    db.database.execute(
      '''UPDATE estimate_contents SET scope=?,basis=?,assumptions=?,exclusions=?,
      rfis=?,risks=?,rates=?,changes=?,updated_at=? WHERE project_id=?''',
      [
        ...content.values,
        content.updatedAt.toUtc().toIso8601String(),
        content.projectId,
      ],
    );
  }

  EstimateContent _read(Map<String, Object?> row) => EstimateContent(
    projectId: row['project_id'] as String,
    scope: row['scope'] as String,
    basis: row['basis'] as String,
    assumptions: row['assumptions'] as String,
    exclusions: row['exclusions'] as String,
    rfis: row['rfis'] as String,
    risks: row['risks'] as String,
    rates: row['rates'] as String,
    changes: row['changes'] as String,
    updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
  );

  EstimateContentRevision _readRevision(Map<String, Object?> row) =>
      EstimateContentRevision(
        id: row['id'] as String,
        content: _read({...row, 'updated_at': row['applied_at']}),
        appliedAt: DateTime.parse(row['applied_at'] as String).toUtc(),
        source: row['source'] as String,
      );

  static const _scopeStart = '--- IO WISP SCOPE BRIEF SYNC ---';
  static const _scopeEnd = '--- END SCOPE BRIEF SYNC ---';
  static String _replaceScopeBlock(String existing, String generated) {
    final start = existing.indexOf(_scopeStart);
    final end = existing.indexOf(_scopeEnd);
    var manual = existing;
    if (start >= 0 && end >= start) {
      manual =
          '${existing.substring(0, start)}${existing.substring(end + _scopeEnd.length)}';
    }
    manual = manual.trim();
    final block = '$_scopeStart\n${generated.trim()}\n$_scopeEnd';
    return manual.isEmpty ? block : '$manual\n\n$block';
  }
}

class SqliteRoadmapRepository extends _EstimatorRepository {
  SqliteRoadmapRepository(super.db);

  List<RoadmapEntry> list(String projectId) {
    requireProject(projectId);
    return db.database
        .select(
          'SELECT * FROM roadmap_items WHERE project_id=? ORDER BY step_order,item_key',
          [projectId],
        )
        .map(_read)
        .toList(growable: false);
  }

  void saveAll(String projectId, List<RoadmapEntry> entries) {
    requireProject(projectId);
    db.transaction(() {
      for (final entry in entries) {
        if (entry.projectId != projectId) {
          throw const EstimatorPersistenceException(
            'Roadmap project mismatch.',
          );
        }
        db.database.execute(
          '''
          INSERT INTO roadmap_items VALUES(${List.filled(12, '?').join(',')})
          ON CONFLICT(project_id,item_key) DO UPDATE SET
            step_order=excluded.step_order,phase=excluded.phase,title=excluded.title,
            purpose=excluded.purpose,outputs=excluded.outputs,status=excluded.status,
            reference=excluded.reference,notes=excluded.notes,updated_at=excluded.updated_at
        ''',
          [
            entry.id,
            entry.projectId,
            entry.itemKey,
            entry.stepOrder,
            entry.phase,
            entry.title,
            entry.purpose,
            entry.outputs,
            entry.status.name,
            entry.reference,
            entry.notes,
            entry.updatedAt.toUtc().toIso8601String(),
          ],
        );
      }
    });
  }

  RoadmapEntry updateUserFields(
    String projectId,
    String itemKey,
    RoadmapStatus status,
    String reference,
    String notes, {
    DateTime? now,
  }) {
    db.database.execute(
      'UPDATE roadmap_items SET status=?,reference=?,notes=?,updated_at=? WHERE project_id=? AND item_key=?',
      [
        status.name,
        reference,
        notes,
        (now ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
        projectId,
        itemKey,
      ],
    );
    if (db.database.updatedRows != 1) {
      throw const EstimatorPersistenceException('Roadmap item was not found.');
    }
    return list(projectId).firstWhere((entry) => entry.itemKey == itemKey);
  }

  String snapshot(
    String projectId, {
    String reason = 'user_reset',
    DateTime? now,
  }) {
    final entries = list(projectId);
    final id = const Uuid().v4();
    db.database.execute('INSERT INTO roadmap_snapshots VALUES(?,?,?,?,?)', [
      id,
      projectId,
      jsonEncode(entries.map(_toJson).toList()),
      (now ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
      reason,
    ]);
    return id;
  }

  void replaceAll(String projectId, List<RoadmapEntry> entries) {
    db.transaction(() {
      db.database.execute('DELETE FROM roadmap_items WHERE project_id=?', [
        projectId,
      ]);
      for (final entry in entries) {
        db.database.execute(
          'INSERT INTO roadmap_items VALUES(${List.filled(12, '?').join(',')})',
          [
            entry.id,
            entry.projectId,
            entry.itemKey,
            entry.stepOrder,
            entry.phase,
            entry.title,
            entry.purpose,
            entry.outputs,
            entry.status.name,
            entry.reference,
            entry.notes,
            entry.updatedAt.toUtc().toIso8601String(),
          ],
        );
      }
    });
  }

  void restoreSnapshot(String projectId, String snapshotId) {
    final rows = db.database.select(
      'SELECT snapshot_data_json FROM roadmap_snapshots WHERE id=? AND project_id=?',
      [snapshotId, projectId],
    );
    if (rows.isEmpty) {
      throw const EstimatorPersistenceException(
        'Roadmap reset snapshot was not found in this project.',
      );
    }
    final json = (jsonDecode(
      rows.single['snapshot_data_json'] as String,
    ) as List).cast<Map<String, Object?>>();
    replaceAll(
      projectId,
      json.map((item) => _fromJson(projectId, item)).toList(),
    );
  }

  Map<String, Object?> _toJson(RoadmapEntry entry) => {
    'id': entry.id,
    'itemKey': entry.itemKey,
    'stepOrder': entry.stepOrder,
    'phase': entry.phase,
    'title': entry.title,
    'purpose': entry.purpose,
    'outputs': entry.outputs,
    'status': entry.status.name,
    'reference': entry.reference,
    'notes': entry.notes,
    'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
  };

  RoadmapEntry _fromJson(String projectId, Map<String, Object?> row) =>
      RoadmapEntry(
        id: row['id'] as String,
        projectId: projectId,
        itemKey: row['itemKey'] as String,
        stepOrder: row['stepOrder'] as int,
        phase: row['phase'] as String,
        title: row['title'] as String,
        purpose: row['purpose'] as String,
        outputs: row['outputs'] as String,
        status: RoadmapStatus.values.byName(row['status'] as String),
        reference: row['reference'] as String,
        notes: row['notes'] as String,
        updatedAt: DateTime.parse(row['updatedAt'] as String).toUtc(),
      );

  RoadmapEntry _read(Map<String, Object?> row) => RoadmapEntry(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    itemKey: row['item_key'] as String,
    stepOrder: row['step_order'] as int,
    phase: row['phase'] as String,
    title: row['title'] as String,
    purpose: row['purpose'] as String,
    outputs: row['outputs'] as String,
    status: RoadmapStatus.values.byName(row['status'] as String),
    reference: row['reference'] as String,
    notes: row['notes'] as String,
    updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
  );
}

class SqliteTimeEntryRepository extends _EstimatorRepository {
  SqliteTimeEntryRepository(super.db);

  TimeEntry? active(String projectId) {
    requireProject(projectId);
    final rows = db.database.select(
      'SELECT * FROM time_entries WHERE project_id=? AND stopped_at IS NULL AND is_soft_deleted=0',
      [projectId],
    );
    return rows.isEmpty ? null : _read(rows.single);
  }

  List<TimeEntry> list(String projectId, {bool includeDeleted = false}) {
    requireProject(projectId);
    return db.database
        .select(
          'SELECT * FROM time_entries WHERE project_id=?${includeDeleted ? '' : ' AND is_soft_deleted=0'} ORDER BY started_at DESC',
          [projectId],
        )
        .map(_read)
        .toList(growable: false);
  }

  TimeEntry insert(TimeEntry entry) {
    requireProject(entry.projectId);
    db.database.execute(
      'INSERT INTO time_entries VALUES(${List.filled(12, '?').join(',')})',
      [
        entry.id,
        entry.projectId,
        entry.referenceType.name,
        entry.referenceId,
        entry.label,
        entry.startedAt.toUtc().toIso8601String(),
        entry.stoppedAt?.toUtc().toIso8601String(),
        entry.durationSeconds,
        entry.note,
        entry.isSoftDeleted ? 1 : 0,
        entry.createdAt.toUtc().toIso8601String(),
        entry.updatedAt.toUtc().toIso8601String(),
      ],
    );
    return get(entry.projectId, entry.id);
  }

  TimeEntry get(String projectId, String id) {
    final rows = db.database.select(
      'SELECT * FROM time_entries WHERE project_id=? AND id=?',
      [projectId, id],
    );
    if (rows.isEmpty) {
      throw const EstimatorPersistenceException(
        'Time entry was not found in this project.',
      );
    }
    return _read(rows.single);
  }

  void finish(
    String projectId,
    String id,
    DateTime stoppedAt,
    int durationSeconds, {
    bool deleted = false,
  }) {
    db.database.execute(
      'UPDATE time_entries SET stopped_at=?,duration_seconds=?,is_soft_deleted=?,updated_at=? WHERE project_id=? AND id=? AND stopped_at IS NULL',
      [
        stoppedAt.toUtc().toIso8601String(),
        durationSeconds,
        deleted ? 1 : 0,
        stoppedAt.toUtc().toIso8601String(),
        projectId,
        id,
      ],
    );
    if (db.database.updatedRows != 1) {
      throw const EstimatorPersistenceException('Active timer was not found.');
    }
  }

  TimeEntry adjust(
    String projectId,
    String id,
    int seconds,
    String note,
    DateTime now,
  ) {
    if (seconds < 0) {
      throw const EstimatorPersistenceException('Duration cannot be negative.');
    }
    db.database.execute(
      '''UPDATE time_entries SET duration_seconds=?,note=?,updated_at=?
      WHERE project_id=? AND id=? AND stopped_at IS NOT NULL AND is_soft_deleted=0''',
      [seconds, note, now.toUtc().toIso8601String(), projectId, id],
    );
    if (db.database.updatedRows != 1) {
      throw const EstimatorPersistenceException(
        'Only a completed time entry can be adjusted.',
      );
    }
    return get(projectId, id);
  }

  TimeEntry updateNote(String projectId, String id, String note, DateTime now) {
    db.database.execute(
      '''UPDATE time_entries SET note=?,updated_at=?
      WHERE project_id=? AND id=? AND is_soft_deleted=0''',
      [note, now.toUtc().toIso8601String(), projectId, id],
    );
    if (db.database.updatedRows != 1) {
      throw const EstimatorPersistenceException(
        'Time entry was not found in this project.',
      );
    }
    return get(projectId, id);
  }

  void softDelete(String projectId, String id, DateTime now) {
    db.database.execute(
      '''UPDATE time_entries SET is_soft_deleted=1,updated_at=?
      WHERE project_id=? AND id=? AND stopped_at IS NOT NULL AND is_soft_deleted=0''',
      [now.toUtc().toIso8601String(), projectId, id],
    );
    if (db.database.updatedRows != 1) {
      throw const EstimatorPersistenceException(
        'Only a completed time entry can be removed.',
      );
    }
  }

  TimeEntry _read(Map<String, Object?> row) => TimeEntry(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    referenceType: TimerReferenceType.values.byName(
      row['reference_type'] as String,
    ),
    referenceId: row['reference_id'] as String?,
    label: row['label'] as String,
    startedAt: DateTime.parse(row['started_at'] as String).toUtc(),
    stoppedAt: row['stopped_at'] == null
        ? null
        : DateTime.parse(row['stopped_at'] as String).toUtc(),
    durationSeconds: row['duration_seconds'] as int,
    note: row['note'] as String,
    isSoftDeleted: row['is_soft_deleted'] == 1,
    createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
  );
}

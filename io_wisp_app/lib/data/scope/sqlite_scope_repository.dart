import 'dart:convert';

import '../../domain/scope.dart';
import '../database/app_database.dart';

class SqliteScopeRepository implements ScopeRepository {
  SqliteScopeRepository(this.db, {this.appliedRevisionHook});
  final AppDatabase db;
  final void Function(ScopeRevision revision)? appliedRevisionHook;

  void _project(String id) {
    if (db.database.select('SELECT id FROM projects WHERE id=?', [
      id,
    ]).isEmpty) {
      throw StateError('Project not found.');
    }
  }

  @override
  ScopeRevision? current(String projectId) {
    _project(projectId);
    final rows = db.database.select(
      'SELECT revision_id FROM scope_current WHERE project_id=?',
      [projectId],
    );
    return rows.isEmpty
        ? null
        : get(projectId, rows.single['revision_id'] as String);
  }

  @override
  List<ScopeRevision> history(String projectId) {
    _project(projectId);
    return db.database
        .select(
          'SELECT id FROM scope_revisions WHERE project_id=? AND complete=1 ORDER BY revision_order DESC',
          [projectId],
        )
        .map((r) => get(projectId, r['id'] as String))
        .toList(growable: false);
  }

  @override
  ScopeRevision get(String projectId, String revisionId) {
    final rows = db.database.select(
      'SELECT * FROM scope_revisions WHERE project_id=? AND id=? AND complete=1',
      [projectId, revisionId],
    );
    if (rows.isEmpty) {
      throw StateError('Applied revision not found in this project.');
    }
    final row = rows.single;
    final resultRows = db.database.select(
      'SELECT * FROM scope_results WHERE revision_id=?',
      [revisionId],
    );
    final results = resultRows
        .map(
          (r) => ScopeResult(
            packageId: r['package_id'] as String,
            detected: ScopeDecision.values.byName(r['detected'] as String),
            reason: r['reason'] as String,
            evidence: (jsonDecode(r['evidence_json'] as String) as List)
                .cast<String>(),
            manual: r['manual'] == null
                ? null
                : ScopeDecision.values.byName(r['manual'] as String),
            manualReason: r['manual_reason'] as String?,
          ),
        )
        .toList();
    validateScopeResults(results);
    final ordered = scopePackages
        .map((p) => results.firstWhere((r) => r.packageId == p.id))
        .toList();
    return ScopeRevision(
      id: revisionId,
      projectId: projectId,
      order: row['revision_order'] as int,
      raw: row['raw'] as String,
      strict: row['strict'] == 1,
      appliedAt: DateTime.parse(row['applied_at'] as String),
      action: row['action'] as String,
      interpreterVersion: row['interpreter_version'] as String,
      parentId: row['parent_id'] as String?,
      restoredFrom: row['restored_from'] as String?,
      results: ordered,
    );
  }

  @override
  void append(ScopeRevision revision) {
    validateScopeResults(revision.results);
    db.transaction(() {
      final prior = current(revision.projectId);
      if (prior?.id != revision.parentId ||
          revision.order != (prior?.order ?? 0) + 1) {
        throw StateError('Scope changed before saving. Reopen Scope Brief.');
      }
      db.database.execute(
        '''INSERT INTO scope_revisions
        (id,project_id,revision_order,raw,strict,applied_at,action,interpreter_version,parent_id,restored_from)
        VALUES(?,?,?,?,?,?,?,?,?,?)''',
        [
          revision.id,
          revision.projectId,
          revision.order,
          revision.raw,
          revision.strict ? 1 : 0,
          revision.appliedAt.toUtc().toIso8601String(),
          revision.action,
          revision.interpreterVersion,
          revision.parentId,
          revision.restoredFrom,
        ],
      );
      for (final r in revision.results) {
        db.database.execute(
          'INSERT INTO scope_results VALUES(?,?,?,?,?,?,?,?)',
          [
            revision.id,
            r.packageId,
            r.detected.name,
            r.reason,
            jsonEncode(r.evidence),
            r.manual?.name,
            r.manualReason,
            r.effective.name,
          ],
        );
      }
      db.database.execute('UPDATE scope_revisions SET complete=1 WHERE id=?', [
        revision.id,
      ]);
      // Decode and validate what was actually written before promoting it.
      get(revision.projectId, revision.id);
      db.database.execute(
        '''INSERT INTO scope_current VALUES(?,?)
        ON CONFLICT(project_id) DO UPDATE SET revision_id=excluded.revision_id''',
        [revision.projectId, revision.id],
      );
      appliedRevisionHook?.call(revision);
    });
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/estimator_workflow_services.dart';
import 'package:io_wisp_app/application/scope_service.dart';
import 'package:io_wisp_app/data/estimator/sqlite_estimator_repositories.dart';
import 'package:io_wisp_app/data/scope/sqlite_scope_repository.dart';
import 'package:io_wisp_app/domain/estimator_workflow.dart';
import 'package:sqlite3/sqlite3.dart';

import '../files/file_test_support.dart';
import '../scope/scope_test_support.dart' show referenceBrief;

void main() {
  test('49 stable checklist templates and eight content/roadmap fields match the legacy catalog', () {
    expect(estimatorChecklistCatalog, hasLength(49));
    expect(
      estimatorChecklistCatalog.map((item) => item.sectionKey).toSet(),
      hasLength(7),
    );
    expect(
      estimatorChecklistCatalog.map((item) => item.key).toSet(),
      hasLength(49),
    );
    expect(
      estimatorChecklistCatalog.map((item) => item.itemOrder),
      List.generate(49, (index) => index + 1),
    );
    expect(estimateContentFields.map((field) => field.$1), [
      'scope',
      'basis',
      'assumptions',
      'exclusions',
      'rfis',
      'risks',
      'rates',
      'changes',
    ]);
    expect(roadmapBaseCatalog.map((item) => item.key), [
      'scope_review',
      'drawing_log',
      'quantity_takeoff',
      'rfis_clarifications',
      'pricing_recap',
      'subcontractor_quotes',
      'risk_contingency',
      'final_submission',
    ]);

    final legacy = File('../releases/v0.0.5/IO_Wisp_Lite_V0.0.5.html')
        .readAsStringSync();
    var offset = legacy.indexOf('const CHECKLIST = [');
    expect(offset, greaterThanOrEqualTo(0));
    for (final item in estimatorChecklistCatalog) {
      final title = legacy.indexOf(item.title, offset);
      final prompt = legacy.indexOf(item.prompt, title);
      expect(title, greaterThanOrEqualTo(offset), reason: item.key);
      expect(prompt, greaterThan(title), reason: item.key);
      offset = prompt + item.prompt.length;
    }
  });

  test('checklist is project isolated, persists evidence, and reset is recoverable', () {
    final context = FileTestContext();
    addTearDown(context.close);
    var repository = SqliteChecklistRepository(context.db);
    var service = ChecklistService(repository);
    expect(service.load(context.a.id), hasLength(49));
    expect(service.load(context.b.id), hasLength(49));
    final key = estimatorChecklistCatalog.first.key;
    service.save(
      projectId: context.a.id,
      templateKey: key,
      isDone: true,
      note: 'Checked against title sheet.',
      evidencePage: 3,
    );
    expect(service.load(context.a.id).first.isDone, isTrue);
    expect(service.load(context.a.id).first.evidencePage, 3);
    expect(service.load(context.b.id).first.isDone, isFalse);

    context.reopen();
    repository = SqliteChecklistRepository(context.db);
    service = ChecklistService(repository);
    expect(
      service.load(context.a.id).first.note,
      'Checked against title sheet.',
    );
    final snapshot = service.reset(context.a.id);
    expect(service.load(context.a.id).first.isDone, isFalse);
    service.undoReset(context.a.id, snapshot);
    expect(service.load(context.a.id).first.isDone, isTrue);
    expect(service.load(context.a.id).first.evidencePage, 3);
  });

  test(
    'Scope Brief sync preserves manual additions and content revisions revert',
    () {
      final context = FileTestContext();
      addTearDown(context.close);
      final content = EstimateContentService(
        SqliteEstimateContentRepository(context.db),
      );
      final scope = ScopeService(
        SqliteScopeRepository(
          context.db,
          appliedRevisionHook: content.syncFromScopeRevision,
        ),
      );
      final first = scope.apply(
        context.a.id,
        referenceBrief,
        true,
        expectedCurrent: null,
      );
      final synced = content.load(context.a.id);
      expect(synced.scope, contains('Concrete / foundations'));
      expect(synced.exclusions, contains('Preliminaries / mobilization'));
      expect(synced.exclusions, contains('Testing / commissioning'));

      content.save(
        synced.copyWith(
          scope: 'Estimator manual scope note.\n\n${synced.scope}',
          updatedAt: DateTime.utc(2026, 9, 5, 1),
        ),
      );
      final second = scope.apply(
        context.a.id,
        'Include electrical. Exclude demolition.',
        true,
        expectedCurrent: first.id,
      );
      expect(second.order, 2);
      final updated = content.load(context.a.id);
      expect(updated.scope, contains('Estimator manual scope note.'));
      expect(updated.scope, contains('Electrical / lighting'));
      expect(updated.scope, isNot(contains('Concrete / foundations')));
      expect(updated.exclusions, contains('Demolition / removal'));
      final revisions = content.revisions(context.a.id);
      expect(revisions, isNotEmpty);
      final restored = content.revert(context.a.id, revisions.last.id);
      expect(restored.values.every((value) => value.isEmpty), isTrue);
      expect(
        content.load(context.b.id).values.every((value) => value.isEmpty),
        isTrue,
      );
    },
  );

  test('roadmap merge is deterministic, preserves edits, defers removed disciplines, and reset undoes', () {
    final context = FileTestContext();
    addTearDown(context.close);
    var disciplines = <String>['Architectural', 'Structural', 'Mechanical'];
    final repository = SqliteRoadmapRepository(context.db);
    final service = RoadmapService(repository, disciplines: (_) => disciplines);
    var items = service.refresh(context.a.id);
    expect(items, hasLength(11));
    final structural = items.firstWhere(
      (item) => item.itemKey == 'discipline_structural',
    );
    service.saveUserFields(
      context.a.id,
      structural.itemKey,
      RoadmapStatus.inProgress,
      'S01.01',
      'Footings reviewed.',
    );
    disciplines = ['Structural'];
    items = service.refresh(context.a.id);
    final retained = items.firstWhere(
      (item) => item.itemKey == 'discipline_structural',
    );
    expect(retained.status, RoadmapStatus.inProgress);
    expect(retained.reference, 'S01.01');
    expect(retained.notes, 'Footings reviewed.');
    expect(
      items
          .firstWhere((item) => item.itemKey == 'discipline_architectural')
          .status,
      RoadmapStatus.deferred,
    );

    final snapshot = service.reset(context.a.id);
    expect(
      service
          .load(context.a.id)
          .firstWhere((item) => item.itemKey == 'discipline_structural')
          .status,
      RoadmapStatus.notStarted,
    );
    service.undoReset(context.a.id, snapshot);
    expect(
      service
          .load(context.a.id)
          .firstWhere((item) => item.itemKey == 'discipline_structural')
          .notes,
      'Footings reviewed.',
    );
    expect(service.refresh(context.b.id), hasLength(9));
  });

  test('timer uses UTC timestamps, resumes after reopen, auto-stops, adjusts and soft-deletes', () {
    final context = FileTestContext();
    addTearDown(context.close);
    var now = DateTime.parse('2026-09-05T08:00:00+08:00');
    var service = TimerService(
      SqliteTimeEntryRepository(context.db),
      clock: () => now,
    );
    final first = service.start(
      context.a.id,
      TimerReferenceType.wholeEstimate,
      label: 'Estimate Preparation',
    );
    now = DateTime.parse('2026-09-05T01:00:45Z');
    final second = service.start(
      context.a.id,
      TimerReferenceType.checklistItem,
      referenceId: estimatorChecklistCatalog.first.key,
      label: estimatorChecklistCatalog.first.title,
    );
    expect(
      service.updateNote(context.a.id, second.id, 'Checking title sheet.').note,
      'Checking title sheet.',
    );
    expect(
      service.repository.get(context.a.id, first.id).durationSeconds,
      3645,
    );
    expect(service.active(context.a.id)!.id, second.id);

    context.reopen();
    service = TimerService(
      SqliteTimeEntryRepository(context.db),
      clock: () => now,
    );
    now = DateTime.parse('2026-09-05T10:01:00+09:00');
    expect(service.elapsed(service.active(context.a.id)!), 15);
    final stopped = service.stop(context.a.id);
    expect(stopped.durationSeconds, 15);
    expect(service.active(context.a.id), isNull);
    expect(
      service
          .adjust(context.a.id, stopped.id, 120, 'Estimator correction')
          .durationSeconds,
      120,
    );
    service.softDelete(context.a.id, stopped.id);
    expect(
      service.history(context.a.id).any((item) => item.id == stopped.id),
      isFalse,
    );

    now = DateTime.utc(2026, 9, 5);
    final future = service.start(
      context.a.id,
      TimerReferenceType.wholeEstimate,
      label: 'Clock correction',
    );
    now = DateTime.utc(2026, 9, 4);
    expect(service.stop(context.a.id).durationSeconds, 0);
    expect(future.startedAt.isUtc, isTrue);
  });

  test(
    'database partial index rejects a second active timer in one project',
    () {
      final context = FileTestContext();
      addTearDown(context.close);
      final values = [
        'timer-a',
        context.a.id,
        'wholeEstimate',
        null,
        'Estimate',
        '2026-09-05T00:00:00Z',
        null,
        0,
        '',
        0,
        '2026-09-05T00:00:00Z',
        '2026-09-05T00:00:00Z',
      ];
      context.db.database.execute(
        'INSERT INTO time_entries VALUES(${List.filled(12, '?').join(',')})',
        values,
      );
      values[0] = 'timer-b';
      expect(
        () => context.db.database.execute(
          'INSERT INTO time_entries VALUES(${List.filled(12, '?').join(',')})',
          values,
        ),
        throwsA(isA<SqliteException>()),
      );
      values[0] = 'timer-c';
      values[1] = context.b.id;
      context.db.database.execute(
        'INSERT INTO time_entries VALUES(${List.filled(12, '?').join(',')})',
        values,
      );
    },
  );
}

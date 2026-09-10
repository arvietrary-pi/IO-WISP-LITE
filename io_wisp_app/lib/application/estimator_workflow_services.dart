import 'package:uuid/uuid.dart';

import '../data/estimator/sqlite_estimator_repositories.dart';
import '../domain/estimator_workflow.dart';
import '../domain/scope.dart';

class ChecklistService {
  ChecklistService(this.repository);
  final SqliteChecklistRepository repository;

  List<ChecklistEntry> load(String projectId) => repository.list(projectId);

  ChecklistEntry save({
    required String projectId,
    required String templateKey,
    required bool isDone,
    required String note,
    required int? evidencePage,
  }) => repository.update(
    projectId: projectId,
    templateKey: templateKey,
    isDone: isDone,
    note: note,
    evidencePage: evidencePage,
  );

  String reset(String projectId) => repository.reset(projectId);
  void undoReset(String projectId, String snapshotId) =>
      repository.restoreSnapshot(projectId, snapshotId);
}

class EstimateContentService implements ScopeContentSynchronizer {
  EstimateContentService(this.repository);
  final SqliteEstimateContentRepository repository;

  EstimateContent load(String projectId) => repository.get(projectId);
  List<EstimateContentRevision> revisions(String projectId) =>
      repository.revisions(projectId);
  EstimateContent save(EstimateContent content) => repository.save(content);
  EstimateContent revert(String projectId, String revisionId) =>
      repository.revert(projectId, revisionId);

  @override
  void syncFromScopeRevision(ScopeRevision revision) =>
      _sync(revision, inExistingTransaction: true);

  EstimateContent syncFromScope(ScopeRevision revision) => _sync(revision);

  EstimateContent _sync(
    ScopeRevision revision, {
    bool inExistingTransaction = false,
  }) {
    String linesFor(ScopeDecision decision) => revision.results
        .where((result) => result.effective == decision)
        .map(
          (result) => scopePackages
              .firstWhere((item) => item.id == result.packageId)
              .label,
        )
        .join('\n');
    final questions = revision.results
        .where(
          (result) =>
              result.effective == ScopeDecision.held ||
              result.effective == ScopeDecision.review,
        )
        .map(
          (result) =>
              'Clarify: ${scopePackages.firstWhere((item) => item.id == result.packageId).label}',
        )
        .join('\n');
    return repository.syncFromScope(
      revision.projectId,
      scope: linesFor(ScopeDecision.included),
      exclusions: linesFor(ScopeDecision.rejected),
      rfis: questions,
      updatedAt: revision.appliedAt,
      inExistingTransaction: inExistingTransaction,
    );
  }
}

typedef DisciplineProvider = Iterable<String> Function(String projectId);

class RoadmapService {
  RoadmapService(this.repository, {DisciplineProvider? disciplines})
    : _disciplines = disciplines ?? ((_) => const <String>[]);

  final SqliteRoadmapRepository repository;
  final DisciplineProvider _disciplines;

  List<RoadmapEntry> load(String projectId) {
    final existing = repository.list(projectId);
    if (existing.isEmpty) return refresh(projectId);
    return existing;
  }

  List<RoadmapEntry> refresh(String projectId) {
    final merged = mergeRoadmap(
      projectId: projectId,
      existing: repository.list(projectId),
      disciplines: _disciplines(projectId),
      now: DateTime.now().toUtc(),
    );
    repository.saveAll(projectId, merged);
    return repository.list(projectId);
  }

  RoadmapEntry saveUserFields(
    String projectId,
    String itemKey,
    RoadmapStatus status,
    String reference,
    String notes,
  ) =>
      repository.updateUserFields(projectId, itemKey, status, reference, notes);

  String reset(String projectId) {
    final snapshot = repository.snapshot(projectId);
    final defaults = mergeRoadmap(
      projectId: projectId,
      existing: const [],
      disciplines: _disciplines(projectId),
      now: DateTime.now().toUtc(),
    );
    repository.replaceAll(projectId, defaults);
    return snapshot;
  }

  void undoReset(String projectId, String snapshotId) =>
      repository.restoreSnapshot(projectId, snapshotId);
}

List<RoadmapEntry> mergeRoadmap({
  required String projectId,
  required List<RoadmapEntry> existing,
  required Iterable<String> disciplines,
  required DateTime now,
}) {
  final existingByKey = {for (final item in existing) item.itemKey: item};
  final targets = <RoadmapTemplateItem>[...roadmapBaseCatalog];
  final normalized = <String, String>{};
  for (final raw in disciplines) {
    final key = normalizeDisciplineKey(raw);
    if (key.isNotEmpty) normalized.putIfAbsent(key, () => raw.trim());
  }
  final keys = normalized.keys.toList()..sort();
  for (var index = 0; index < keys.length; index++) {
    final key = keys[index];
    final display = _disciplineTitle(key);
    targets.add(
      RoadmapTemplateItem(
        'discipline_$key',
        310 + index,
        'Discipline takeoff',
        'Review $display scope',
        'Identify $display drawing scope, interfaces, measurable work, and allowances.',
        '$display scope checklist and drawing references',
      ),
    );
  }

  final targetKeys = targets.map((item) => item.key).toSet();
  final merged = targets.map((template) {
    final prior = existingByKey[template.key];
    return RoadmapEntry(
      id: prior?.id ?? const Uuid().v4(),
      projectId: projectId,
      itemKey: template.key,
      stepOrder: template.stepOrder,
      phase: template.phase,
      title: template.title,
      purpose: template.purpose,
      outputs: template.outputs,
      status: prior?.status ?? RoadmapStatus.notStarted,
      reference: prior?.reference ?? '',
      notes: prior?.notes ?? '',
      updatedAt: prior?.updatedAt ?? now.toUtc(),
    );
  }).toList();
  for (final prior in existing.where(
    (item) => !targetKeys.contains(item.itemKey),
  )) {
    merged.add(
      RoadmapEntry(
        id: prior.id,
        projectId: projectId,
        itemKey: prior.itemKey,
        stepOrder: prior.stepOrder,
        phase: prior.phase,
        title: prior.title,
        purpose: prior.purpose,
        outputs: prior.outputs,
        status: RoadmapStatus.deferred,
        reference: prior.reference,
        notes: prior.notes,
        updatedAt: now.toUtc(),
      ),
    );
  }
  merged.sort((a, b) {
    final step = a.stepOrder.compareTo(b.stepOrder);
    return step == 0 ? a.itemKey.compareTo(b.itemKey) : step;
  });
  return List.unmodifiable(merged);
}

String _disciplineTitle(String key) => key
    .split('_')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

class TimerService {
  TimerService(this.repository, {DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final SqliteTimeEntryRepository repository;
  final DateTime Function() _clock;

  TimeEntry? active(String projectId) => repository.active(projectId);
  List<TimeEntry> history(String projectId) => repository.list(projectId);

  TimeEntry start(
    String projectId,
    TimerReferenceType referenceType, {
    String? referenceId,
    required String label,
  }) {
    if (label.trim().isEmpty) {
      throw const EstimatorPersistenceException('Timer label is required.');
    }
    if (referenceType == TimerReferenceType.checklistItem &&
        (referenceId == null ||
            !estimatorChecklistCatalog.any(
              (item) => item.key == referenceId,
            ))) {
      throw const EstimatorPersistenceException(
        'Checklist timers require a valid checklist template key.',
      );
    }
    if (referenceType == TimerReferenceType.wholeEstimate) referenceId = null;
    final now = _clock().toUtc();
    return repository.db.transaction(() {
      final prior = repository.active(projectId);
      if (prior != null) {
        repository.finish(
          projectId,
          prior.id,
          now,
          _elapsed(prior.startedAt, now),
        );
      }
      return repository.insert(
        TimeEntry(
          id: const Uuid().v4(),
          projectId: projectId,
          referenceType: referenceType,
          referenceId: referenceId,
          label: label.trim(),
          startedAt: now,
          durationSeconds: 0,
          note: '',
          isSoftDeleted: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  TimeEntry stop(String projectId) {
    final now = _clock().toUtc();
    return repository.db.transaction(() {
      final entry = repository.active(projectId);
      if (entry == null) {
        throw const EstimatorPersistenceException('No active timer to stop.');
      }
      repository.finish(
        projectId,
        entry.id,
        now,
        _elapsed(entry.startedAt, now),
      );
      return repository.get(projectId, entry.id);
    });
  }

  void discard(String projectId) {
    final now = _clock().toUtc();
    repository.db.transaction(() {
      final entry = repository.active(projectId);
      if (entry == null) {
        throw const EstimatorPersistenceException(
          'No active timer to discard.',
        );
      }
      repository.finish(projectId, entry.id, now, 0, deleted: true);
    });
  }

  TimeEntry adjust(String projectId, String id, int seconds, String note) =>
      repository.adjust(projectId, id, seconds, note, _clock().toUtc());

  TimeEntry updateNote(String projectId, String id, String note) =>
      repository.updateNote(projectId, id, note, _clock().toUtc());

  void softDelete(String projectId, String id) =>
      repository.softDelete(projectId, id, _clock().toUtc());

  int elapsed(TimeEntry entry) => entry.elapsedSecondsAt(_clock());

  int _elapsed(DateTime start, DateTime end) {
    final seconds = end.toUtc().difference(start.toUtc()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }
}

import 'package:uuid/uuid.dart';

import '../domain/scope.dart';
import '../domain/scope_interpreter.dart';

class ScopeService {
  ScopeService(this.repository, {this.interpreter = const ScopeInterpreter()});
  final ScopeRepository repository;
  final ScopeInterpreter interpreter;
  ScopeRevision? current(String projectId) => repository.current(projectId);
  List<ScopeRevision> history(String projectId) =>
      repository.history(projectId);

  ScopeRevision apply(
    String projectId,
    String raw,
    bool strict, {
    required String? expectedCurrent,
  }) {
    final prior = _prior(projectId, expectedCurrent);
    final results = interpreter.interpret(raw, strict: strict);
    final unchanged = prior != null && prior.raw.trim() == raw.trim();
    final resolved = results.map((r) {
      final old = unchanged
          ? prior.results.firstWhere((v) => v.packageId == r.packageId)
          : null;
      return old?.manual == null
          ? r
          : r.overrideWith(old!.manual, old.manualReason);
    }).toList();
    return _save(
      projectId,
      prior,
      raw,
      strict,
      resolved,
      'apply',
      ScopeInterpreter.version,
    );
  }

  ScopeRevision override(
    String projectId,
    String revisionId,
    String packageId,
    ScopeDecision? decision,
    String? note,
  ) {
    final prior = _prior(projectId, revisionId)!;
    if (!scopePackages.any((p) => p.id == packageId)) {
      throw const FormatException('Unknown scope package.');
    }
    final results = prior.results
        .map(
          (r) => r.packageId == packageId
              ? r.overrideWith(decision, note?.trim())
              : r,
        )
        .toList();
    return _save(
      projectId,
      prior,
      prior.raw,
      prior.strict,
      results,
      'override',
      prior.interpreterVersion,
    );
  }

  ScopeRevision revert(
    String projectId,
    String revisionId, {
    required String? expectedCurrent,
  }) {
    final prior = _prior(projectId, expectedCurrent);
    final selected = repository.get(projectId, revisionId);
    return _save(
      projectId,
      prior,
      selected.raw,
      selected.strict,
      selected.results,
      'revert',
      selected.interpreterVersion,
      restoredFrom: selected.id,
    );
  }

  ScopeRevision? _prior(String projectId, String? expected) {
    final prior = repository.current(projectId);
    if (prior?.id != expected) {
      throw StateError(
        'Scope changed in another view. Reopen Scope Brief before saving.',
      );
    }
    return prior;
  }

  ScopeRevision _save(
    String projectId,
    ScopeRevision? prior,
    String raw,
    bool strict,
    List<ScopeResult> results,
    String action,
    String version, {
    String? restoredFrom,
  }) {
    validateScopeResults(results);
    final revision = ScopeRevision(
      id: const Uuid().v4(),
      projectId: projectId,
      order: (prior?.order ?? 0) + 1,
      raw: raw,
      strict: strict,
      appliedAt: DateTime.now().toUtc(),
      action: action,
      interpreterVersion: version,
      results: results,
      parentId: prior?.id,
      restoredFrom: restoredFrom,
    );
    repository.append(revision);
    return revision;
  }
}

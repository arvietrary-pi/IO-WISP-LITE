import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:io_wisp_app/application/scope_service.dart';
import 'package:io_wisp_app/domain/scope.dart';
import 'package:io_wisp_app/domain/scope_interpreter.dart';

import 'scope_test_support.dart';

class _FailParser extends ScopeInterpreter {
  @override
  List<ScopeResult> interpret(String raw, {required bool strict}) =>
      throw const FormatException('Controlled parser failure');
}

class _InvalidParser extends ScopeInterpreter {
  @override
  List<ScopeResult> interpret(String raw, {required bool strict}) => [];
}

void main() {
  late ScopeTestContext c;
  setUp(() => c = ScopeTestContext());
  tearDown(() => c.close());
  ScopeRevision apply(String raw, {bool strict = true}) => c.service.apply(
    c.a.id,
    raw,
    strict,
    expectedCurrent: c.repository.current(c.a.id)?.id,
  );

  test('reference persists all fields and prior revisions across real SQLite reopen', () {
    final first = apply(referenceBrief);
    var second = c.service.override(
      c.a.id,
      first.id,
      'preliminaries',
      ScopeDecision.included,
      'Estimator instruction A',
    );
    second = c.service.override(
      c.a.id,
      second.id,
      'concrete',
      ScopeDecision.held,
      'RFI pending',
    );
    final before = c.db.database
        .select('SELECT * FROM scope_results ORDER BY revision_id,package_id')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    c.reopen();
    final restored = c.repository.current(c.a.id)!;
    expect(restored.id, second.id);
    expect(restored.raw, referenceBrief);
    expect(restored.strict, true);
    expect(restored.results, hasLength(16));
    expect(restored.appliedAt, second.appliedAt);
    expect(restored.results.first.detected, ScopeDecision.rejected);
    expect(restored.results.first.manual, ScopeDecision.included);
    expect(restored.results.first.manualReason, 'Estimator instruction A');
    expect(
      c.db.database.select(
        'SELECT * FROM scope_results ORDER BY revision_id,package_id',
      ),
      before,
    );
    expect(c.repository.history(c.a.id).map((r) => r.order), [3, 2, 1]);
    expect(c.repository.get(c.a.id, first.id).results.first.manual, isNull);
  });
  test('unchanged trimmed text preserves multiple overrides including strict change', () {
    var r = apply('Include concrete');
    r = c.service.override(
      c.a.id,
      r.id,
      'preliminaries',
      ScopeDecision.rejected,
      'Client',
    );
    r = c.service.override(
      c.a.id,
      r.id,
      'testing',
      ScopeDecision.included,
      'Estimator',
    );
    final next = apply('  Include concrete\n', strict: false);
    expect(next.results.where((r) => r.manual != null), hasLength(2));
    expect(next.results.first.detected, ScopeDecision.review);
    expect(next.results.first.effective, ScopeDecision.rejected);
  });
  for (final raw in [
    'Include electrical',
    'include concrete',
    'Include  concrete',
  ]) {
    test('changed raw resets overrides: $raw', () {
      final first = apply('Include concrete');
      c.service.override(
        c.a.id,
        first.id,
        'testing',
        ScopeDecision.included,
        'Client',
      );
      final next = apply(raw);
      expect(next.results.every((r) => r.manual == null), true);
      expect(c.repository.history(c.a.id), hasLength(3));
    });
  }
  test(
    'clear override restores detector and preserves prior manual evidence',
    () {
      var r = apply(referenceBrief);
      r = c.service.override(
        c.a.id,
        r.id,
        'preliminaries',
        ScopeDecision.included,
        'Client',
      );
      final cleared = c.service.override(
        c.a.id,
        r.id,
        'preliminaries',
        null,
        null,
      );
      expect(cleared.results.first.effective, ScopeDecision.rejected);
      expect(cleared.results.first.manualReason, isNull);
      expect(
        c.repository.get(c.a.id, r.id).results.first.manualReason,
        'Client',
      );
    },
  );
  test(
    'revert copies old snapshot into new revision; never rewrites history',
    () {
      final first = apply(referenceBrief, strict: false);
      final second = apply('Include electrical');
      final restored = c.service.revert(
        c.a.id,
        first.id,
        expectedCurrent: second.id,
      );
      expect(restored.order, 3);
      expect(restored.restoredFrom, first.id);
      expect(restored.parentId, second.id);
      expect(restored.raw, first.raw);
      expect(restored.strict, false);
      expect(c.repository.get(c.a.id, second.id).raw, 'Include electrical');
    },
  );
  for (final parser in [_FailParser(), _InvalidParser()]) {
    test(
      'failed parser/invalid output keeps prior state: ${parser.runtimeType}',
      () {
        final prior = apply(referenceBrief);
        expect(
          () => ScopeService(
            c.repository,
            interpreter: parser,
          ).apply(c.a.id, 'new', true, expectedCurrent: prior.id),
          throwsFormatException,
        );
        expect(c.repository.current(c.a.id)!.id, prior.id);
        expect(c.repository.history(c.a.id), hasLength(1));
      },
    );
  }
  for (final boundary in ['header', 'result', 'seal', 'current']) {
    test(
      'transaction rollback after $boundary failure preserves complete prior revision',
      () {
        final prior = apply(referenceBrief);
        final sql = switch (boundary) {
          'header' => 'BEFORE INSERT ON scope_revisions',
          'result' =>
            "BEFORE INSERT ON scope_results WHEN NEW.package_id='testing'",
          'seal' => 'BEFORE UPDATE OF complete ON scope_revisions',
          _ => 'BEFORE UPDATE ON scope_current',
        };
        c.db.database.execute(
          "CREATE TRIGGER controlled_failure $sql BEGIN SELECT RAISE(ABORT,'controlled failure'); END",
        );
        expect(
          () => apply('Include electrical'),
          throwsA(isA<SqliteException>()),
        );
        expect(c.repository.current(c.a.id)!.id, prior.id);
        expect(
          c.db.database.select('SELECT * FROM scope_revisions'),
          hasLength(1),
        );
        expect(
          c.db.database.select('SELECT * FROM scope_results'),
          hasLength(16),
        );
        c.reopen();
        expect(c.repository.current(c.a.id)!.id, prior.id);
      },
    );
  }
  test('project isolation and cross-project revision/override rejection', () {
    final a = apply(referenceBrief);
    final b = c.service.apply(
      c.b.id,
      'Include electrical',
      false,
      expectedCurrent: null,
    );
    expect(c.repository.history(c.b.id).single.raw, 'Include electrical');
    expect(() => c.repository.get(c.b.id, a.id), throwsStateError);
    expect(
      () => c.service.override(
        c.b.id,
        a.id,
        'concrete',
        ScopeDecision.included,
        'Client',
      ),
      throwsStateError,
    );
    expect(
      () => c.service.revert(c.b.id, a.id, expectedCurrent: b.id),
      throwsStateError,
    );
    expect(c.repository.current(c.a.id)!.id, a.id);
    expect(c.repository.current(c.b.id)!.id, b.id);
  });
  test('stale view cannot apply over newer revision', () {
    final first = apply(referenceBrief);
    final next = apply('Include concrete');
    expect(
      () => c.service.apply(
        c.a.id,
        'Include electrical',
        true,
        expectedCurrent: first.id,
      ),
      throwsStateError,
    );
    expect(() => c.repository.append(first), throwsStateError);
    expect(c.repository.current(c.a.id)!.id, next.id);
  });
  test('manual reason is required; unknown packages and projects fail', () {
    final first = apply(referenceBrief);
    expect(
      () => c.service.override(
        c.a.id,
        first.id,
        'concrete',
        ScopeDecision.included,
        ' ',
      ),
      throwsFormatException,
    );
    expect(
      () => c.service.override(c.a.id, first.id, 'unknown', null, null),
      throwsFormatException,
    );
    expect(
      () => c.service.apply('missing', '', true, expectedCurrent: null),
      throwsStateError,
    );
    expect(c.repository.history(c.a.id), hasLength(1));
  });
  test('sealed revisions/results cannot be updated, deleted, or extended', () {
    final r = apply(referenceBrief);
    for (final sql in [
      "UPDATE scope_revisions SET raw='changed'",
      'DELETE FROM scope_revisions',
      "UPDATE scope_results SET reason='changed'",
      'DELETE FROM scope_results',
      "INSERT INTO scope_results SELECT * FROM scope_results WHERE revision_id='${r.id}'",
    ]) {
      expect(() => c.db.database.execute(sql), throwsA(isA<SqliteException>()));
    }
    expect(c.repository.current(c.a.id)!.raw, referenceBrief);
  });
  test(
    'empty brief applies explicit empty revision without corrupting old gate',
    () {
      final r = apply(referenceBrief);
      final empty = apply('');
      expect(
        empty.results.every((v) => v.effective == ScopeDecision.held),
        true,
      );
      expect(
        c.repository
            .get(c.a.id, r.id)
            .results
            .where((v) => v.effective == ScopeDecision.included),
        hasLength(14),
      );
    },
  );
}

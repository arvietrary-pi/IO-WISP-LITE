import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/domain/scope.dart';
import 'package:io_wisp_app/features/scope/scope_page.dart';

import 'scope_test_support.dart';

Future<void> scopeUiScenario(
  WidgetTester tester,
  ScopeTestContext c, {
  void Function(String)? checkpoint,
}) async {
  Future<void> settle() => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );
  Future<void> mount() async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScopePage(project: c.a, service: c.service),
      ),
    );
    await settle();
  }

  Future<void> click(String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await settle();
    await tester.tap(f);
    await settle();
  }

  Future<void> enter(String key, String text) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await settle();
    // Windows may retain a stale native text-input connection after a button
    // takes focus. Re-establish focus before delivering the next edit.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(f);
    await settle();
    await tester.enterText(f, text);
    await settle();
    expect(tester.widget<TextField>(f).controller!.text, text);
  }

  await mount();
  await enter('scopeRaw', referenceBrief);
  await click('applyScope');
  expect(
    find.text('14 Included / 2 Rejected / 0 Held / 0 Review'),
    findsOneWidget,
  );
  final initial = c.repository.current(c.a.id)!;
  expect(initial.results, hasLength(16));
  checkpoint?.call('Reference applied: 14 Included / 2 Rejected / 0 Held.');
  await click('override-preliminaries');
  await tester.tap(find.byKey(const ValueKey('overrideDecision')));
  await settle();
  await tester.tap(find.text('Included').last);
  await settle();
  await enter('overrideReason', 'Disposable estimator instruction');
  await click('saveOverride');
  await tester.pump(const Duration(milliseconds: 500));
  await settle();
  expect(
    c.repository.current(c.a.id)!.results.first.manual,
    ScopeDecision.included,
  );
  expect(find.text('Detected: Rejected'), findsWidgets);
  expect(find.text('Effective: Included • MANUAL OVERRIDE'), findsOneWidget);
  final manual = c.repository.current(c.a.id)!;
  checkpoint?.call(
    'Manual inclusion saved; detector still Rejected with evidence.',
  );
  await tester.pumpWidget(const SizedBox());
  await settle();
  c.reopen();
  await mount();
  expect(c.repository.current(c.a.id)!.id, manual.id);
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('scopeRaw')))
        .controller!
        .text,
    referenceBrief,
  );
  expect(
    find.text('15 Included / 1 Rejected / 0 Held / 0 Review'),
    findsOneWidget,
  );
  checkpoint?.call(
    'UI disposed, SQLite closed/reopened, applied revision and override restored.',
  );
  await enter('scopeRaw', 'Include electrical');
  expect(find.byKey(const ValueKey('scopeDirty')), findsOneWidget);
  expect(c.repository.current(c.a.id)!.id, manual.id);
  expect(
    find.text('15 Included / 1 Rejected / 0 Held / 0 Review'),
    findsOneWidget,
  );
  await click('applyScope');
  expect(
    c.repository.current(c.a.id)!.results.every((r) => r.manual == null),
    true,
  );
  expect(
    find.text('1 Included / 0 Rejected / 15 Held / 0 Review'),
    findsOneWidget,
  );
  expect(
    c.repository.get(c.a.id, manual.id).results.first.manual,
    ScopeDecision.included,
  );
  final changed = c.repository.current(c.a.id)!;
  checkpoint?.call(
    'Changed source resets overrides only on Apply; previous revision intact.',
  );
  c.db.database.execute(
    "CREATE TRIGGER fail_native_scope BEFORE INSERT ON scope_results WHEN NEW.package_id='testing' BEGIN SELECT RAISE(ABORT,'controlled native failure'); END",
  );
  await enter('scopeRaw', 'Include all');
  await click('applyScope');
  expect(find.byKey(const ValueKey('scopeError')), findsOneWidget);
  expect(find.byKey(const ValueKey('scopeNotice')), findsNothing);
  expect(c.repository.current(c.a.id)!.id, changed.id);
  expect(c.db.database.select('SELECT * FROM scope_revisions'), hasLength(3));
  expect(c.db.database.select('SELECT * FROM scope_results'), hasLength(48));
  c.db.database.execute('DROP TRIGGER fail_native_scope');
  checkpoint?.call(
    'Late package-write failure displayed; prior current and 48 historical result rows intact.',
  );
  await click('discardScopeDraft');
  await click('scopeHistory');
  await click('history-1');
  expect(find.textContaining('Raw brief:'), findsWidgets);
  await click('revert-1');
  await click('confirmRevert');
  expect(c.repository.current(c.a.id)!.restoredFrom, initial.id);
  expect(
    find.text('14 Included / 2 Rejected / 0 Held / 0 Review'),
    findsOneWidget,
  );
  expect(c.repository.current(c.b.id), isNull);
  checkpoint?.call(
    'History viewed, revision 1 restored as new revision 4; Beta scope remains empty.',
  );
}

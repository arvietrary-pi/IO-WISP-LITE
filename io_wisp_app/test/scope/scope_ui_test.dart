import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/app.dart';
import 'package:io_wisp_app/application/project_management_service.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/settings/app_settings_repository.dart';
import 'package:io_wisp_app/data/storage/app_storage_paths.dart';
import 'package:io_wisp_app/data/storage/project_storage.dart';
import 'package:io_wisp_app/features/scope/scope_page.dart';

import 'scope_test_support.dart';
import 'scope_ui_scenario.dart';

void main() {
  late ScopeTestContext c;
  setUp(() => c = ScopeTestContext());
  tearDown(() => c.close());
  testWidgets('dashboard opens Scope Brief for the selected project', (
    tester,
  ) async {
    final manager = ProjectManager(
      database: c.db,
      projects: SqliteProjectRepository(c.db),
      settings: SqliteAppSettingsRepository(c.db),
      storage: const WindowsProjectStorage(),
      paths: WindowsAppStoragePaths(
        environment: {'APPDATA': c.temp.path, 'USERPROFILE': c.temp.path},
      ),
    )..initialize();
    manager.switchActiveProject(c.a.id);
    c.service.apply(c.a.id, referenceBrief, true, expectedCurrent: null);
    await tester.pumpWidget(IOWispApp(manager: manager, scope: c.service));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('projectScope')));
    await tester.pumpAndSettle();
    expect(find.text('Scope Brief — Alpha'), findsOneWidget);
    expect(
      find.text('14 Included / 2 Rejected / 0 Held / 0 Review'),
      findsOneWidget,
    );
  });
  testWidgets(
    'complete apply, override, reopen, edit, failure, history and revert flow',
    (tester) async {
      await scopeUiScenario(tester, c);
    },
  );
  testWidgets(
    'same widget switched between projects cannot retain another project draft',
    (tester) async {
      c.service.apply(c.a.id, referenceBrief, true, expectedCurrent: null);
      await tester.pumpWidget(
        MaterialApp(
          home: ScopePage(project: c.a, service: c.service),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('scopeRaw')),
        'Unapplied A draft',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ScopePage(project: c.b, service: c.service),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('scopeRaw')))
            .controller!
            .text,
        '',
      );
      expect(find.text('No applied Scope Brief yet.'), findsOneWidget);
      expect(find.textContaining('14 Included'), findsNothing);
      expect(c.repository.current(c.a.id)!.raw, referenceBrief);
      await tester.tap(find.byKey(const ValueKey('applyScope')));
      await tester.pumpAndSettle();
      expect(c.repository.current(c.b.id)!.raw, '');
      expect(c.repository.current(c.a.id)!.raw, referenceBrief);
    },
  );
  testWidgets('non-strict toggle is draft until Apply and persists Review', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScopePage(project: c.a, service: c.service),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('scopeStrict')));
    await tester.pumpAndSettle();
    expect(c.repository.current(c.a.id), isNull);
    await tester.tap(find.byKey(const ValueKey('applyScope')));
    await tester.pumpAndSettle();
    expect(
      find.text('0 Included / 0 Rejected / 0 Held / 16 Review'),
      findsOneWidget,
    );
    expect(c.repository.current(c.a.id)!.strict, false);
  });
  testWidgets('invalid input retains gate and shows no stale success notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScopePage(project: c.a, service: c.service),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('scopeRaw')),
      referenceBrief,
    );
    await tester.tap(find.byKey(const ValueKey('applyScope')));
    await tester.pumpAndSettle();
    final id = c.repository.current(c.a.id)!.id;
    await tester.enterText(
      find.byKey(const ValueKey('scopeRaw')),
      'Invalid\u0000brief',
    );
    await tester.tap(find.byKey(const ValueKey('applyScope')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scopeError')), findsOneWidget);
    expect(find.byKey(const ValueKey('scopeNotice')), findsNothing);
    expect(c.repository.current(c.a.id)!.id, id);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/estimator_workflow_services.dart';
import 'package:io_wisp_app/data/estimator/sqlite_estimator_repositories.dart';
import 'package:io_wisp_app/domain/estimator_workflow.dart';
import 'package:io_wisp_app/features/estimator/estimator_workspace_page.dart';

import '../files/file_test_support.dart';

void main() {
  testWidgets(
    'estimator workspace edits checklist/content and runs a persisted item timer',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final context = FileTestContext();
      addTearDown(context.close);
      final checklistRepository = SqliteChecklistRepository(context.db);
      final contentRepository = SqliteEstimateContentRepository(context.db);
      final timerRepository = SqliteTimeEntryRepository(context.db);
      final timer = TimerService(timerRepository);

      await tester.pumpWidget(
        MaterialApp(
          home: EstimatorWorkspacePage(
            project: context.a,
            checklist: ChecklistService(checklistRepository),
            content: EstimateContentService(contentRepository),
            roadmap: RoadmapService(SqliteRoadmapRepository(context.db)),
            timer: timer,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('0 of 49 complete'), findsOneWidget);
      expect(find.textContaining('Project identity recorded'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(checklistRepository.list(context.a.id).first.isDone, isTrue);
      await tester.tap(find.text('Start timer').first);
      await tester.pump();
      expect(
        timer.active(context.a.id)!.referenceType,
        TimerReferenceType.checklistItem,
      );
      expect(
        find.textContaining('Project identity recorded •'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('activeTimerNote')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('activeTimerNoteField')),
        'Reviewed title sheet.',
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(timer.active(context.a.id)!.note, 'Reviewed title sheet.');

      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.enterText(
        find.byKey(const ValueKey('content-scope')),
        'Manual estimator scope.',
      );
      await tester.pump();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        contentRepository.get(context.a.id).scope,
        'Manual estimator scope.',
      );
      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.byType(Tab).at(2));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Confirm project and estimate basis'), findsOneWidget);
      expect(
        SqliteRoadmapRepository(context.db).list(context.a.id),
        hasLength(8),
      );

      await tester.tap(find.byKey(const ValueKey('stopTimer')));
      await tester.pump();
      expect(timer.active(context.a.id), isNull);
      expect(timer.history(context.a.id), hasLength(1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

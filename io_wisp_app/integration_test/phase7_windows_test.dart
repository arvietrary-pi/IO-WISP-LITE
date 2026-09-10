import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:io_wisp_app/application/estimator_workflow_services.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/estimator/sqlite_estimator_repositories.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/domain/project.dart';
import 'package:io_wisp_app/features/estimator/estimator_workspace_page.dart';
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Phase 7 Windows workflow persists across a true process restart',
    (tester) async {
      const supplied = String.fromEnvironment('WISP_PHASE7_ROOT');
      if (supplied.isEmpty) {
        throw StateError(
          'WISP_PHASE7_ROOT is required for native verification.',
        );
      }
      final root = Directory(supplied)..createSync(recursive: true);
      const restart = bool.fromEnvironment('WISP_PHASE7_RESTART');
      final database = AppDatabase.open('${root.path}/phase7.sqlite');
      final projects = SqliteProjectRepository(database);
      final checklistRepository = SqliteChecklistRepository(database);
      final contentRepository = SqliteEstimateContentRepository(database);
      final roadmapRepository = SqliteRoadmapRepository(database);
      final timeRepository = SqliteTimeEntryRepository(database);
      final checklist = ChecklistService(checklistRepository);
      final content = EstimateContentService(contentRepository);
      final roadmap = RoadmapService(
        roadmapRepository,
        disciplines: (_) => const ['Structural'],
      );
      final timer = TimerService(timeRepository);
      final contractFile = File('${root.path}/restart-contract.json');
      final checkpoints = <String>[];
      void checkpoint(String value) {
        checkpoints.add(value);
        debugPrint('P7: $value');
      }

      try {
        late Project project;
        if (!restart) {
          final now = DateTime.now().toUtc();
          Directory('${root.path}/Native Phase 7').createSync();
          project = Project(
            id: const Uuid().v4(),
            name: 'Native Phase 7',
            locationClient: 'Disposable verification',
            revision: 'P7',
            estimator: 'Integration test',
            createdAt: now,
            updatedAt: now,
            safeFolderName: 'Native Phase 7',
            projectRootReference: root.path,
            projectDirectoryReference: 'Native Phase 7',
            folderCreatedAt: now,
          );
          projects.insert(project);
          await tester.pumpWidget(
            MaterialApp(
              home: EstimatorWorkspacePage(
                project: project,
                checklist: checklist,
                content: content,
                roadmap: roadmap,
                timer: timer,
              ),
            ),
          );
          await tester.pump();
          expect(find.text('0 of 49 complete'), findsOneWidget);
          await tester.tap(find.byType(Checkbox).first);
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('startEstimateTimer')));
          await tester.pump();
          await tester.tap(find.byType(Tab).at(1));
          await tester.pumpAndSettle(const Duration(milliseconds: 100));
          await tester.enterText(
            find.byKey(const ValueKey('content-basis')),
            'Native persisted estimate basis.',
          );
          await tester.pump(const Duration(milliseconds: 700));
          expect(content.load(project.id).basis, contains('Native persisted'));
          expect(roadmap.refresh(project.id), hasLength(9));
          checkpoint(
            'Saved checklist, eight-area content, nine-row discipline roadmap, and active timer.',
          );
          contractFile.writeAsStringSync(
            jsonEncode({
              'pid': pid,
              'projectId': project.id,
              'timerId': timer.active(project.id)!.id,
            }),
          );
        } else {
          final contract = jsonDecode(
            contractFile.readAsStringSync(),
          ) as Map<String, dynamic>;
          expect(contract['pid'], isNot(pid));
          project = projects.findById(contract['projectId'] as String)!;
          expect(checklist.load(project.id), hasLength(49));
          expect(checklist.load(project.id).first.isDone, isTrue);
          expect(
            content.load(project.id).basis,
            'Native persisted estimate basis.',
          );
          expect(roadmap.load(project.id), hasLength(9));
          final active = timer.active(project.id)!;
          expect(active.id, contract['timerId']);
          expect(timer.elapsed(active), greaterThanOrEqualTo(0));
          final completed = timer.stop(project.id);
          expect(completed.durationSeconds, greaterThanOrEqualTo(0));
          checkpoint(
            'A distinct process reopened schema 7 and restored all Phase 7 records and the active timestamp timer.',
          );
          await tester.pumpWidget(
            MaterialApp(
              home: EstimatorWorkspacePage(
                project: project,
                checklist: checklist,
                content: content,
                roadmap: roadmap,
                timer: timer,
              ),
            ),
          );
          await tester.pump();
          expect(find.text('1 of 49 complete'), findsOneWidget);
          expect(find.text('No active timer'), findsOneWidget);
        }
        expect(database.userVersion, 7);
        expect(database.database.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          database.database
              .select('PRAGMA integrity_check')
              .single
              .values
              .single,
          'ok',
        );
        File('${root.path}/${restart ? 'restart' : 'first'}-evidence.json')
            .writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert({
                'pid': pid,
                'restart': restart,
                'schema': database.userVersion,
                'checkpoints': checkpoints,
                for (final table in [
                  'checklist_items',
                  'estimate_contents',
                  'estimate_content_revisions',
                  'roadmap_items',
                  'time_entries',
                ])
                  table: database.database
                      .select('SELECT * FROM $table')
                      .map((row) => Map<String, Object?>.from(row))
                      .toList(),
              }),
            );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      } finally {
        database.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

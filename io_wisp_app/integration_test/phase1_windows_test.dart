import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:io_wisp_app/app.dart';
import 'package:io_wisp_app/application/project_management_service.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/settings/app_settings_repository.dart';
import 'package:io_wisp_app/data/storage/app_storage_paths.dart';
import 'package:io_wisp_app/data/storage/project_storage.dart';

// Runs in a native Windows test runner. All SQLite and filesystem operations
// use a new disposable directory. No production paths or main() are invoked.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 1 edit, switch, root change and database reopen', (
    tester,
  ) async {
    final temp = await Directory.systemTemp.createTemp(
      'io-wisp-native-integration-',
    );
    final paths = _TestPaths(temp.path);
    AppDatabase? database;
    late ProjectManager manager;
    void open() {
      database = AppDatabase.open(paths.databasePath);
      manager = ProjectManager(
        database: database!,
        projects: SqliteProjectRepository(database!),
        settings: SqliteAppSettingsRepository(database!),
        paths: paths,
        storage: const WindowsProjectStorage(),
      )..initialize();
    }

    Future<void> click(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> waitFor(Finder finder) async {
      for (
        var attempt = 0;
        attempt < 100 && finder.evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsOneWidget);
    }

    Future<void> fill(String prefix) async {
      final fields = find.byType(TextFormField);
      for (var i = 0; i < 4; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(
          fields.at(i),
          '$prefix ${['name', 'client', 'revision', 'estimator'][i]}',
        );
      }
      await tester.pump();
      // Click while the last edited controller still has focus: no Enter/blur.
      await click(find.byKey(const ValueKey('saveProjectButton')));
    }

    Future<void> select(String name) async {
      await click(find.byType(DropdownButtonFormField<String>));
      await click(find.text(name).last);
    }

    Future<void> assertEditor(String prefix) async {
      await click(find.text('Edit project'));
      final fields = find.byType(TextFormField);
      for (var i = 0; i < 4; i++) {
        expect(
          tester.widget<TextFormField>(fields.at(i)).controller!.text,
          '$prefix ${['name', 'client', 'revision', 'estimator'][i]}',
        );
      }
      await click(find.byTooltip('Back'));
    }

    try {
      open();
      await tester.pumpWidget(IOWispApp(manager: manager));
      await tester.pumpAndSettle();
      expect(find.text('No projects yet'), findsOneWidget);
      await click(find.text('New project'));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('saveProjectButton')),
            )
            .onPressed,
        isNull,
      );
      await fill('Alpha');
      final alpha = manager.loadState().activeProject!;
      await click(find.text('Edit project'));
      await fill('Alpha edited');
      await click(find.text('New project'));
      await fill('Beta');
      final beta = manager.loadState().activeProject!;
      await click(find.text('Edit project'));
      await fill('Beta edited');
      expect(alpha.id, isNot(beta.id));
      await select('Alpha edited name');
      expect(manager.loadState().activeProject!.id, alpha.id);
      await assertEditor('Alpha edited');
      await select('Beta edited name');
      await assertEditor('Beta edited');

      final before = database!.database
          .select('SELECT * FROM projects ORDER BY id')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      final newRoot = p.join(temp.path, 'changed root with spaces');
      final rootField = find.byType(TextField);
      await tester.ensureVisible(rootField);
      await tester.enterText(rootField, newRoot);
      await click(find.text('Save root'));
      await waitFor(find.textContaining('Project storage root saved.'));
      expect(manager.loadState().projectRoot, newRoot);
      expect(
        database!.database.select('SELECT * FROM projects ORDER BY id'),
        before,
      );
      // Dispose the full widget tree AND close SQLite, then construct new
      // repositories, manager, controllers and UI. OS process restart is a
      // separate release-executable acceptance check, not claimed by this test.
      await select('Alpha edited name');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final closed = database!.database;
      database!.close();
      database = null;
      expect(() => closed.select('SELECT 1'), throwsStateError);
      open();
      await tester.pumpWidget(IOWispApp(manager: manager));
      await tester.pumpAndSettle();
      expect(manager.loadState().activeProject!.id, alpha.id);
      expect(manager.loadState().projectRoot, newRoot);
      expect(
        database!.database.select('SELECT * FROM projects ORDER BY id'),
        before,
      );
      await assertEditor('Alpha edited');
      await select('Beta edited name');
      await assertEditor('Beta edited');
      for (final original in [alpha, beta]) {
        expect(
          await Directory(
            p.join(
              original.projectRootReference,
              original.projectDirectoryReference,
            ),
          ).exists(),
          isTrue,
        );
        expect(
          await Directory(p.join(newRoot, original.projectDirectoryReference))
              .exists(),
          isFalse,
        );
      }
      await click(find.text('New project'));
      await fill('Gamma');
      expect(manager.loadState().activeProject!.projectRootReference, newRoot);
      expect(manager.loadState().projects, hasLength(3));

      // Invalid root must not change the configured root or claim success.
      await tester.ensureVisible(rootField);
      await tester.enterText(rootField, 'relative-path');
      await click(find.text('Save root'));
      expect(
        find.textContaining('Project storage root was not saved.'),
        findsOneWidget,
      );
      expect(manager.loadState().projectRoot, newRoot);
      await click(find.text('New project'));
      await fill('Gamma');
      expect(find.textContaining('Project was not saved.'), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(manager.loadState().projects, hasLength(3));
      await click(find.byTooltip('Back'));
      expect(manager.loadState().projects, hasLength(3));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      database?.close();
      await temp.delete(recursive: true);
    }
  });
}

class _TestPaths implements AppStoragePaths {
  _TestPaths(this.root);
  final String root;
  @override
  String get databasePath => p.join(root, 'db', 'io_wisp.sqlite');
  @override
  String get defaultProjectRoot => p.join(root, 'original project root');
}

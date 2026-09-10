import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:io_wisp_app/app.dart';
import 'package:io_wisp_app/application/project_management_service.dart';
import 'package:io_wisp_app/application/legacy_import_service.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/import/legacy_json_reader.dart';
import 'package:io_wisp_app/data/import/sqlite_import_repository.dart';
import 'package:io_wisp_app/data/import/windows_import_folders.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/settings/app_settings_repository.dart';
import 'package:io_wisp_app/data/storage/app_storage_paths.dart';
import 'package:io_wisp_app/data/storage/project_storage.dart';
import 'package:io_wisp_app/domain/legacy_import.dart';

// Real native Flutter UI + read-only reader + SQLite + Windows filesystem.
// The OS file dialog is checked separately in the release workflow.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Phase 2 preview, cancel, confirm, reopen, repeat and controlled rollback',
    (tester) async {
      final temp = await Directory.systemTemp.createTemp(
        'wisp-phase2-integration-',
      );
      final paths = _Paths(temp.path);
      AppDatabase? db;
      late SqliteImportRepository repo;
      late ProjectManager manager;
      late LegacyImportService importer;
      final picker = _Picker();
      final fixture = File('${temp.path}/fixture.json');
      // Confirmed envelope structure; entirely synthetic, with deferred and unsafe fields.
      fixture.writeAsStringSync(
        jsonEncode({
          'io_assistant': 'IO Wisp Lite',
          'app_version': 'V0.0.5',
          'api_used': false,
          'project': {
            'id': 'project-native-fixture',
            'name': 'Native Import Fixture',
            'location': 'Synthetic Client',
            'revision': 'A',
            'estimator': 'Test Estimator',
            'folderName': r'..\outside',
            'scopeBrief': {},
            'sheets': [],
          },
          'document': {'title': 'Native Import Fixture', 'page_count': 0},
          'table_of_contents': [],
        }),
      );
      final bytes = fixture.readAsBytesSync();
      picker.path = fixture.path;
      void open() {
        db = AppDatabase.open(paths.databasePath);
        manager = ProjectManager(
          database: db!,
          projects: SqliteProjectRepository(db!),
          settings: SqliteAppSettingsRepository(db!),
          paths: paths,
          storage: const WindowsProjectStorage(),
        )..initialize();
        repo = SqliteImportRepository(db!);
        importer = LegacyImportService(
          reader: const ReadOnlyLegacyJsonReader(),
          repository: repo,
          folders: WindowsImportFolders(),
        );
      }

      Future<void> click(String key) async {
        final f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      Future<void> waitFor(String text) async {
        for (
          var i = 0;
          i < 100 && find.textContaining(text).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining(text), findsWidgets);
      }

      Future<void> preview() async {
        await click('importExistingProject');
        await click('selectLegacyJson');
        await waitFor('Project candidates: 1');
      }

      Future<void> mount() async {
        await tester.pumpWidget(
          IOWispApp(manager: manager, importer: importer, importPicker: picker),
        );
        await tester.pumpAndSettle();
      }

      try {
        open();
        await mount();
        await preview();
        expect(repo.projects(), isEmpty);
        expect(Directory(paths.defaultProjectRoot).existsSync(), false);
        expect(find.textContaining('Unsafe, absolute'), findsWidgets);
        await click('cancelImport');
        expect(repo.projects(), isEmpty);
        await preview();
        await click('acceptImportFindings');
        await click('confirmImport');
        await waitFor('Import completed with warnings');
        expect(repo.projects(), hasLength(1));
        final original = repo.projects().single;
        expect(repo.provenance(), hasLength(1));
        expect(
          Directory(
            '${original.projectRootReference}\\${original.safeFolderName}',
          ).listSync(),
          isEmpty,
        );
        await click('openImportedProject');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        db!.close();
        db = null;
        open();
        await mount();
        expect(repo.projects().single.id, original.id);
        expect(repo.activeProjectId, original.id);
        expect(
          repo.projects().single.projectDirectoryReference,
          original.projectDirectoryReference,
        );
        await preview();
        expect(
          find.textContaining('Exact previously imported'),
          findsOneWidget,
        );
        await click('acceptImportFindings');
        await click('confirmImport');
        await waitFor('Duplicate skipped');
        await click('cancelImport');
        // Failure injected only into this disposable database.
        db!.database.execute(
          "CREATE TRIGGER fail_import BEFORE INSERT ON import_provenance BEGIN SELECT RAISE(ABORT, 'controlled failure'); END",
        );
        final other = File('${temp.path}/other.json')
          ..writeAsStringSync(
            jsonEncode({
              'io_assistant': 'IO Wisp Lite',
              'app_version': 'V0.0.5',
              'project': {'name': 'Rollback Fixture'},
            }),
          );
        picker.path = other.path;
        await preview();
        await click('acceptImportFindings');
        await click('confirmImport');
        await waitFor('Import failed and rolled back');
        expect(repo.projects(), hasLength(1));
        expect(Directory(paths.defaultProjectRoot).listSync(), hasLength(1));
        expect(fixture.readAsBytesSync(), bytes);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        db?.close();
        await temp.delete(recursive: true);
      }
    },
  );
}

class _Picker implements LegacyFilePicker {
  String? path;
  @override
  Future<String?> selectJson() async => path;
}

class _Paths implements AppStoragePaths {
  _Paths(this.root);
  final String root;
  @override
  String get databasePath => '$root/test.sqlite';
  @override
  String get defaultProjectRoot => '$root\\projects';
}

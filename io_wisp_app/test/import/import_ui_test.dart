import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/legacy_import_service.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/import/legacy_json_reader.dart';
import 'package:io_wisp_app/data/import/sqlite_import_repository.dart';
import 'package:io_wisp_app/data/import/windows_import_folders.dart';
import 'package:io_wisp_app/data/import/windows_legacy_picker.dart';
import 'package:io_wisp_app/data/settings/app_settings_repository.dart';
import 'package:io_wisp_app/domain/legacy_import.dart';
import 'package:io_wisp_app/features/import/legacy_import_page.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late SqliteImportRepository repo;
  late LegacyImportService service;
  late String path;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wisp-import-ui-');
    db = AppDatabase.open('${temp.path}/test.sqlite');
    SqliteAppSettingsRepository(db).setProjectRoot('${temp.path}\\projects');
    repo = SqliteImportRepository(db);
    service = LegacyImportService(
      reader: _ImmediateReader(),
      repository: repo,
      folders: WindowsImportFolders(),
    );
    path = File('test/fixtures/legacy_v005.json').absolute.path;
  });
  tearDown(() async {
    db.close();
    await temp.delete(recursive: true);
  });
  Future<void> show(WidgetTester tester, {String? selected}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LegacyImportPage(
                    service: service,
                    picker: _Picker(selected),
                  ),
                ),
              ),
              child: const Text('Open importer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open importer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selectLegacyJson')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'preview shows mappings/deferred fields and cancellation makes no writes',
    (tester) async {
      await show(tester, selected: path);
      expect(find.text('Preview only — no changes made'), findsOneWidget);
      expect(find.textContaining('Project candidates: 1'), findsOneWidget);
      expect(find.textContaining('project.scopeBrief:'), findsOneWidget);
      expect(
        find.textContaining('project.location → Location / client:'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirmImport')))
            .onPressed,
        isNull,
      );
      expect(repo.projects(), isEmpty);
      expect(Directory(repo.projectRoot).existsSync(), false);
      await tester.tap(find.byKey(const ValueKey('cancelImport')));
      await tester.pumpAndSettle();
      expect(find.text('Open importer'), findsOneWidget);
      expect(repo.projects(), isEmpty);
      expect(Directory(repo.projectRoot).existsSync(), false);
    },
  );
  testWidgets('file picker cancellation leaves no preview and no changes', (
    tester,
  ) async {
    await show(tester);
    expect(find.textContaining('Source:'), findsNothing);
    expect(repo.projects(), isEmpty);
  });
  testWidgets(
    'acknowledgment and confirm produce one imported project and result navigation',
    (tester) async {
      await show(tester, selected: path);
      await tester.tap(find.byKey(const ValueKey('acceptImportFindings')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('confirmImport'));
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.projects(), hasLength(1));
      expect(repo.provenance(), hasLength(1));
      expect(find.text('Import completed with warnings'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('openImportedProject')));
      await tester.pumpAndSettle();
      expect(find.text('Open importer'), findsOneWidget);
    },
  );
  testWidgets('fatal source cannot be confirmed', (tester) async {
    final invalid = File('${temp.path}/bad.json')..writeAsStringSync('{');
    await show(tester, selected: invalid.path);
    expect(find.textContaining('Malformed,'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirmImport')))
          .onPressed,
      isNull,
    );
    expect(repo.projects(), isEmpty);
  });
  testWidgets('transaction failure is visibly rolled back', (tester) async {
    db.database.execute(
      "CREATE TRIGGER fail_import BEFORE INSERT ON import_provenance BEGIN SELECT RAISE(ABORT, 'controlled'); END",
    );
    await show(tester, selected: path);
    await tester.tap(find.byKey(const ValueKey('acceptImportFindings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmImport')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Import failed and rolled back.'),
      findsOneWidget,
    );
    expect(repo.projects(), isEmpty);
    expect(Directory(repo.projectRoot).listSync(), isEmpty);
  });
  test(
    'Windows picker channel returns selected path or cancellation',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(WindowsLegacyFilePicker.channel, (
        call,
      ) async {
        expect(call.method, 'selectJson');
        return path;
      });
      expect(await const WindowsLegacyFilePicker().selectJson(), path);
      messenger.setMockMethodCallHandler(
        WindowsLegacyFilePicker.channel,
        (_) async => null,
      );
      expect(await const WindowsLegacyFilePicker().selectJson(), isNull);
      messenger.setMockMethodCallHandler(WindowsLegacyFilePicker.channel, null);
    },
  );
}

class _Picker implements LegacyFilePicker {
  _Picker(this.path);
  final String? path;
  @override
  Future<String?> selectJson() async => path;
}

class _ImmediateReader implements LegacySourceReader {
  @override
  Future<LegacySource> read(String path) async =>
      LegacyJsonParser.parse(File(path).readAsBytesSync(), 'synthetic.json');
}

import 'dart:io';
import 'dart:convert';

import 'package:io_wisp_app/data/storage/project_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:io_wisp_app/domain/managed_file.dart';
import 'package:io_wisp_app/features/files/project_files_page.dart';

import '../test/files/file_test_support.dart';

class _Picker implements SourceFilePicker {
  String? path;
  @override
  Future<String?> selectSource() async => path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Phase 3 import, duplicate, conflict, revision, missing, trash and reopen',
    (tester) async {
      debugPrint('P3 creating disposable context');
      final c = FileTestContext();
      final picker = _Picker();
      Future<void> mount() async {
        debugPrint('P3 mount');
        await tester.pumpWidget(
          MaterialApp(
            home: ProjectFilesPage(
              project: c.a,
              service: c.service,
              picker: picker,
            ),
          ),
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
      }

      Future<void> click(String key) async {
        debugPrint('P3 click $key');
        final f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
      }

      Future<void> waitText(String text) async {
        debugPrint('P3 wait $text');
        if (find.byType(AlertDialog).evaluate().isEmpty) {
          final scrollable = find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pump();
        }
        for (
          var i = 0;
          i < 100 && find.textContaining(text).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining(text), findsWidgets);
      }

      try {
        final source = c.source('native synthetic opaque bytes');
        picker.path = source.path;
        await mount();
        await click('selectSourceFile');
        await waitText('Source bytes verified unchanged');
        final first = c.repository.list(c.a.id).single;
        expect(source.readAsStringSync(), 'native synthetic opaque bytes');
        expect(c.managed(first).readAsStringSync(), source.readAsStringSync());
        await click('selectSourceFile');
        await waitText('Identical content already recorded');
        expect(c.repository.list(c.a.id), hasLength(1));
        picker.path = c.source('revision bytes', folder: 'second').path;
        await click('selectSourceFile');
        await waitText('Same filename, different content');
        expect(c.repository.list(c.a.id), hasLength(1));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
        expect(c.repository.list(c.a.id), hasLength(1));
        await click('selectSourceFile');
        await click('importRevision');
        await waitText('Source bytes verified unchanged');
        expect(c.repository.list(c.a.id), hasLength(2));
        expect(c.repository.list(c.a.id).last.revisionOf, first.id);
        expect(
          c.managed(first).readAsStringSync(),
          'native synthetic opaque bytes',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
        c.reopen();
        await mount();
        await waitText('source.pdf — ready');
        expect(c.repository.list(c.a.id), hasLength(2));
        picker.path = c.source('new name bytes', folder: 'third').path;
        await click('selectSourceFile');
        await tester.enterText(
          find.byKey(const ValueKey('newManagedName')),
          'source-new.pdf',
        );
        await click('importNewName');
        await waitText('Imported source-new.pdf');
        expect(c.repository.list(c.a.id), hasLength(3));
        c.db.database.execute(
          "CREATE TRIGGER fail_native_file BEFORE UPDATE ON managed_files WHEN NEW.state='ready' BEGIN SELECT RAISE(ABORT,'controlled native failure'); END",
        );
        picker.path = c.source('rollback bytes', name: 'failure.bin').path;
        await click('selectSourceFile');
        await waitText('Import not completed');
        expect(c.repository.list(c.a.id), hasLength(3));
        expect(Directory('${c.temp.path}/Alpha/imports').listSync(), isEmpty);
        c.db.database.execute('DROP TRIGGER fail_native_file');
        final trashButton = find.text('Move managed copy to trash').first;
        await tester.ensureVisible(trashButton);
        await tester.tap(trashButton);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
        await click('confirmTrash');
        await waitText('Managed copy moved to trash');
        expect(c.repository.list(c.a.id).first.state, ManagedFileState.trashed);
        final second = c.repository.list(c.a.id).last;
        c.managed(second).deleteSync();
        await tester.ensureVisible(find.text('Refresh file status'));
        await tester.tap(find.text('Refresh file status'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
        await waitText('Managed file is missing');
        expect(Directory('${c.temp.path}/Beta').listSync(), isEmpty);
        expect(source.readAsStringSync(), 'native synthetic opaque bytes');
        if (const bool.fromEnvironment('WISP_EXPLORER')) {
          await const WindowsProjectStorage().openProjectDirectory(
            rootPath: c.a.projectRootReference,
            directoryReference: c.a.projectDirectoryReference,
          );
          final target = '${c.temp.path}\\Alpha';
          final explorer = await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            "\$shell = New-Object -ComObject Shell.Application; for (\$i=0; \$i -lt 40; \$i++) { \$matches = @(\$shell.Windows() | Where-Object { \$_.Document.Folder.Self.Path -eq '$target' }); if (\$matches.Count -gt 0) { \$matches | ForEach-Object { \$_.Document.Folder.Self.Path; \$_.Quit() }; exit 0 }; Start-Sleep -Milliseconds 250 }; exit 1",
          ]);
          expect(
            explorer.exitCode,
            0,
            reason: '${explorer.stdout} ${explorer.stderr}',
          );
          debugPrint('P3 Explorer target observed: ${explorer.stdout}');
        }
        if (const bool.fromEnvironment('WISP_KEEP_EVIDENCE')) {
          c.db.database.execute(
            "INSERT OR REPLACE INTO app_settings VALUES('active_project_id',?),('project_root',?)",
            [c.a.id, c.temp.path],
          );
          final snapshot = {
            'projects': c.db.database
                .select('SELECT * FROM projects')
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
            'files': c.db.database
                .select('SELECT * FROM managed_files')
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
            'externalSource': source.path,
            'sourceBytes': source.readAsStringSync(),
          };
          File('${c.temp.path}/native-snapshot.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(snapshot),
          );
          final target = Directory('${c.temp.path}/AppData/IO WISP')
            ..createSync(recursive: true);
          c.db.database.execute('VACUUM INTO ?', [
            '${target.path}/io_wisp.sqlite',
          ]);
          debugPrint('P3 retained disposable evidence: ${c.temp.path}');
        }
        // Actual Windows storage/UI and close/reopen; OS picker is substituted.
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
        if (const bool.fromEnvironment('WISP_KEEP_EVIDENCE')) {
          c.db.close();
        } else {
          c.close();
        }
      }
    },
  );
}

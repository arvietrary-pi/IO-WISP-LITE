import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/data/storage/windows_source_picker.dart';
import 'package:io_wisp_app/domain/managed_file.dart';

import 'file_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('source picker channel selection and cancellation', () async {
    const channel = MethodChannel('io_wisp/legacy_import');
    final calls = <String>[];
    String? value = 'synthetic-selected-token';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return value;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(await const WindowsSourceFilePicker().selectSource(), value);
    value = null;
    expect(await const WindowsSourceFilePicker().selectSource(), isNull);
    expect(calls, ['selectSource', 'selectSource']);
  });
  group('native safety boundaries', () {
    late FileTestContext c;
    setUp(() => c = FileTestContext());
    tearDown(() => c.close());
    test('managed junction rejected and target project untouched', () async {
      final path = '${c.temp.path}\\Alpha\\sources';
      final target = '${c.temp.path}\\Beta';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "New-Item -ItemType Junction -Path '$path' -Target '$target' | Out-Null",
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      try {
        await expectLater(
          c.service.importFile(c.a.id, c.source('abc').path),
          throwsA(isA<FileSystemException>()),
        );
        expect(Directory(target).listSync(), isEmpty);
        expect(c.repository.list(c.a.id), isEmpty);
      } finally {
        Directory(path).deleteSync();
      }
    });
    test('hard linked external and managed files are rejected without modifying either link', () async {
      final source = c.source('abc');
      final second = '${c.temp.path}\\alias.pdf';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "New-Item -ItemType HardLink -Path '$second' -Target '${source.path}' | Out-Null",
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        () => c.store.openSource(source.path),
        throwsA(isA<FileImportException>()),
      );
      File(second).deleteSync();
      final file = (await c.service.importFile(c.a.id, source.path)).file!;
      final managedLink = '${c.temp.path}\\managed-alias';
      final link = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "New-Item -ItemType HardLink -Path '$managedLink' -Target '${c.managed(file).path}' | Out-Null",
      ]);
      expect(link.exitCode, 0);
      expect(
        (await c.service.list(c.a.id)).single.state,
        ManagedFileState.recoveryNeeded,
      );
      await expectLater(c.service.trash(c.a.id, file.id), throwsA(anything));
      expect(File(managedLink).readAsStringSync(), 'abc');
    });
    test('physical folder identity rejects DOS short-path project aliases', () async {
      final short = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(New-Object -ComObject Scripting.FileSystemObject).GetFolder('${c.temp.path}').ShortPath",
      ]);
      expect(short.exitCode, 0);
      final alias = short.stdout.toString().trim();
      expect(alias, isNotEmpty);
      c.db.database.execute(
        'UPDATE projects SET project_root_reference=?, project_directory_reference=? WHERE id=?',
        [alias, 'Alpha', c.b.id],
      );
      expect(
        () => c.store.openProject(c.a, c.repository.projects),
        throwsA(isA<FileImportException>()),
      );
    });
    test('source folder traversal/device injection fails before any copy', () {
      for (final source in [
        r'\\server\share\a',
        r'\\?\C:\a',
        r'C:\a\..\b',
        r'C:a',
        'relative.pdf',
      ]) {
        expect(() => c.store.openSource(source), throwsA(anything));
      }
      expect(c.repository.list(c.a.id), isEmpty);
    });
    test('interrupted after finalize is visible on reopen without deleting final file', () async {
      final f = (await c.service.importFile(
        c.a.id,
        c.source('abc').path,
      )).file!;
      // Exact crash shape between successful rename and ready commit.
      c.db.database.execute(
        "UPDATE managed_files SET state='importing' WHERE id=?",
        [f.id],
      );
      c.reopen();
      expect(
        (await c.service.list(c.a.id)).single.state,
        ManagedFileState.recoveryNeeded,
      );
      expect(c.managed(f).readAsStringSync(), 'abc');
      await expectLater(
        c.service.importFile(c.a.id, c.source('other', name: 'other').path),
        throwsA(isA<FileImportException>()),
      );
    });
    test('interrupted trash retains provenance and moved file', () async {
      final f = (await c.service.importFile(
        c.a.id,
        c.source('abc').path,
      )).file!;
      final trash = await c.service.trash(c.a.id, f.id);
      c.db.database.execute(
        "UPDATE managed_files SET state='trashing',relative_path=? WHERE id=?",
        [f.relativePath, f.id],
      );
      c.reopen();
      expect(
        (await c.service.list(c.a.id)).single.state,
        ManagedFileState.recoveryNeeded,
      );
      expect(c.managed(trash).readAsStringSync(), 'abc');
    });
    test('missing whole project retains visible provenance', () async {
      final f = (await c.service.importFile(
        c.a.id,
        c.source('abc').path,
      )).file!;
      final old = Directory('${c.temp.path}/Alpha');
      old.renameSync('${c.temp.path}/renamed');
      final result = (await c.service.list(c.a.id)).single;
      expect(result.id, f.id);
      expect(result.state, ManagedFileState.recoveryNeeded);
      expect(
        File('${c.temp.path}/renamed/${f.relativePath}').readAsStringSync(),
        'abc',
      );
    });
    test(
      'trash destination collision preserves both files and record',
      () async {
        final f = (await c.service.importFile(
          c.a.id,
          c.source('abc').path,
        )).file!;
        final sentinel = File('${c.temp.path}/Alpha/trash/${f.leaf}')
          ..writeAsStringSync('unrelated');
        await expectLater(
          c.service.trash(c.a.id, f.id),
          throwsA(isA<FileImportException>()),
        );
        expect(c.managed(f).readAsStringSync(), 'abc');
        expect(sentinel.readAsStringSync(), 'unrelated');
        expect(c.repository.list(c.a.id).single.state, ManagedFileState.ready);
      },
    );
    test('concurrent import on one service cannot double-submit', () async {
      final source = c.source('x' * 200000);
      final first = c.service.importFile(c.a.id, source.path);
      await expectLater(
        c.service.importFile(c.a.id, source.path),
        throwsA(isA<FileImportException>()),
      );
      await first;
      expect(c.repository.list(c.a.id), hasLength(1));
    });
    test(
      'existing managed file capability cannot write or delete content',
      () async {
        final f = (await c.service.importFile(
          c.a.id,
          c.source('abc').path,
        )).file!;
        final lease = c.store.openProject(c.a, c.repository.projects);
        final held = lease.openManaged(f.relativePath)!;
        try {
          expect(() => held.write([1]), throwsA(isA<FileImportException>()));
          expect(held.removeOwned(), isFalse);
        } finally {
          held.close();
          lease.close();
        }
        expect(c.managed(f).readAsStringSync(), 'abc');
      },
    );
  }, skip: !Platform.isWindows);
}

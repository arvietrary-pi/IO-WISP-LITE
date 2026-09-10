import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/legacy_import_service.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/import/legacy_json_reader.dart';
import 'package:io_wisp_app/data/import/sqlite_import_repository.dart';
import 'package:io_wisp_app/data/import/windows_import_folders.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/settings/app_settings_repository.dart';
import 'package:io_wisp_app/domain/legacy_import.dart';
import 'package:io_wisp_app/domain/project.dart';

import 'legacy_parser_test.dart' show fixture;

void main() {
  late Directory temp;
  late AppDatabase database;
  late SqliteImportRepository repository;
  late LegacyImportService service;
  late File source;
  late String root;
  late DateTime now;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wisp-import-service-');
    root = '${temp.path}\\projects';
    database = AppDatabase.open('${temp.path}/test.sqlite');
    SqliteAppSettingsRepository(database).setProjectRoot(root);
    repository = SqliteImportRepository(database);
    now = DateTime(2026, 9, 3, 12);
    service = LegacyImportService(
      reader: const ReadOnlyLegacyJsonReader(),
      repository: repository,
      folders: WindowsImportFolders(),
      clock: () => now,
    );
    source = File('${temp.path}/source.json')
      ..writeAsStringSync(jsonEncode(fixture()));
  });
  tearDown(() async {
    database.close();
    await temp.delete(recursive: true);
  });
  Future<ImportResult> confirm(
    ImportPreview preview, {
    ConflictDecision decision = ConflictDecision.importSeparate,
    bool active = true,
  }) => service.confirm(
    preview,
    confirmed: true,
    acceptedFindings: true,
    decision: decision,
    makeActive: active,
  );

  test(
    'preview and cancellation do not create root, rows or settings',
    () async {
      final settings = database.database
          .select('SELECT * FROM app_settings')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final preview = await service.preview(source.path);
      expect(
        preview.blocked,
        false,
        reason: preview.findings.map((f) => f.message).join('\n'),
      );
      expect(Directory(root).existsSync(), false);
      expect(repository.projects(), isEmpty);
      expect(repository.provenance(), isEmpty);
      service.cancel();
      expect((await confirm(preview)).outcome, ImportOutcome.failed);
      expect(database.database.select('SELECT * FROM app_settings'), settings);
      expect(Directory(root).existsSync(), false);
    },
  );
  test('confirmation and acknowledgment cannot be bypassed', () async {
    final preview = await service.preview(source.path);
    for (final flags in [
      [false, true],
      [true, false],
    ]) {
      final result = await service.confirm(
        preview,
        confirmed: flags[0],
        acceptedFindings: flags[1],
        decision: ConflictDecision.importSeparate,
      );
      expect(result.outcome, ImportOutcome.failed);
    }
    expect(repository.projects(), isEmpty);
    expect(Directory(root).existsSync(), false);
  });
  test('successful import persists stable identity, provenance and active project after close/reopen', () async {
    final bytes = source.readAsBytesSync();
    final result = await confirm(await service.preview(source.path));
    expect(
      result.outcome,
      ImportOutcome.completedWithWarnings,
      reason: result.message,
    );
    final project = result.project!;
    expect(project.id, matches(r'^[0-9a-f-]{14}4[0-9a-f-]{21}$'));
    expect(project.id, isNot('project-synthetic001'));
    expect(Directory('$root\\${project.safeFolderName}').listSync(), isEmpty);
    final rows = database.database
        .select('SELECT * FROM projects')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final audits = database.database
        .select('SELECT * FROM import_provenance')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    database.close();
    database = AppDatabase.open('${temp.path}/test.sqlite');
    repository = SqliteImportRepository(database);
    expect(database.database.select('SELECT * FROM projects'), rows);
    expect(database.database.select('SELECT * FROM import_provenance'), audits);
    expect(repository.activeProjectId, project.id);
    expect(source.readAsBytesSync(), bytes);
    expect(audits.single['imported_from_legacy'], 1);
    expect(audits.single['source_filename'], 'source.json');
    expect(audits.single['accepted_warnings'], contains('project.scopeBrief'));
  });
  test('exact previously imported bytes skipped even after rename or different filename', () async {
    final first = await confirm(await service.preview(source.path));
    final renamed = first.project!.copyWith(name: 'Changed name');
    SqliteProjectRepository(database).update(renamed);
    final copy = File('${temp.path}/renamed-source.json')
      ..writeAsBytesSync(source.readAsBytesSync());
    final preview = await service.preview(copy.path);
    expect(preview.duplicate, DuplicateStatus.exactSource);
    expect((await confirm(preview)).outcome, ImportOutcome.skipped);
    expect(repository.projects(), hasLength(1));
  });
  test('same legacy ID changed source requires decision; separate import preserves original', () async {
    final first = await confirm(await service.preview(source.path));
    final v = fixture();
    v['project']['revision'] = 'Rev B';
    source.writeAsStringSync(jsonEncode(v));
    var preview = await service.preview(source.path);
    expect(preview.duplicate, DuplicateStatus.likelyProject);
    expect(preview.displayName, 'Synthetic Workshop (import 2)');
    expect(
      (await confirm(preview, decision: ConflictDecision.undecided)).outcome,
      ImportOutcome.failed,
    );
    expect(
      (await confirm(preview, decision: ConflictDecision.skip)).outcome,
      ImportOutcome.skipped,
    );
    preview = await service.preview(source.path);
    final second = await confirm(preview, active: false);
    expect(second.outcome, ImportOutcome.completedWithWarnings);
    expect(repository.projects(), hasLength(2));
    expect(repository.activeProjectId, first.project!.id);
    expect(
      SqliteProjectRepository(database).findById(first.project!.id)!.revision,
      'Rev A',
    );
    expect(
      second.project!.safeFolderName,
      isNot(first.project!.safeFolderName),
    );
  });
  test(
    'same name from a different source is distinct from legacy identity match',
    () async {
      final now = DateTime.utc(2026, 1, 1);
      SqliteProjectRepository(database).insert(
        Project(
          id: 'existing-synthetic',
          name: 'Synthetic Workshop',
          locationClient: '',
          revision: '',
          estimator: '',
          createdAt: now,
          updatedAt: now,
          safeFolderName: 'existing',
          projectRootReference: root,
          projectDirectoryReference: 'existing',
        ),
      );
      final preview = await service.preview(source.path);
      expect(preview.duplicate, DuplicateStatus.sameName);
      expect(preview.needsDecision, true);
      expect(preview.displayName, endsWith('(import 2)'));
    },
  );
  test('changed source, changed database, age, root and folder all invalidate previews', () async {
    var preview = await service.preview(source.path);
    source.writeAsStringSync('${source.readAsStringSync()} ');
    expect((await confirm(preview)).outcome, ImportOutcome.failed);
    preview = await service.preview(source.path);
    SqliteAppSettingsRepository(database).setActiveProjectId('changed');
    expect((await confirm(preview)).outcome, ImportOutcome.failed);
    preview = await service.preview(source.path);
    now = now.add(const Duration(minutes: 16));
    expect((await confirm(preview)).outcome, ImportOutcome.failed);
    preview = await service.preview(source.path);
    SqliteAppSettingsRepository(database).setProjectRoot('${temp.path}\\other');
    expect((await confirm(preview)).outcome, ImportOutcome.failed);
    SqliteAppSettingsRepository(database).setProjectRoot(root);
    preview = await service.preview(source.path);
    Directory('$root\\${preview.folderName}').createSync(recursive: true);
    expect((await confirm(preview)).outcome, ImportOutcome.failed);
    expect(repository.projects(), isEmpty);
  });
  test('folder collisions are disclosed and never reused', () async {
    var preview = await service.preview(source.path);
    final old = Directory('$root\\${preview.folderName}')
      ..createSync(recursive: true);
    final sentinel = File('${old.path}/sentinel.txt')
      ..writeAsStringSync('untouched');
    preview = await service.preview(source.path);
    expect(preview.folderCollision, true);
    expect(preview.folderName, endsWith('(2)'));
    final result = await confirm(preview);
    expect(result.outcome, ImportOutcome.completedWithWarnings);
    expect(sentinel.readAsStringSync(), 'untouched');
  });
  test(
    'folder failure produces no record and preserves active selection',
    () async {
      final preview = await service.preview(source.path);
      File(root).writeAsStringSync('Synthetic root obstruction');
      final result = await confirm(preview);
      expect(result.outcome, ImportOutcome.failed);
      expect(repository.projects(), isEmpty);
      expect(File(root).readAsStringSync(), 'Synthetic root obstruction');
      expect(repository.activeProjectId, isNull);
    },
  );
  test('SQL failure after folder creation rolls back row, audit, active and only owned folder', () async {
    Directory(root).createSync();
    final sentinel = File('$root/sentinel.txt')..writeAsStringSync('keep');
    database.database.execute(
      "CREATE TRIGGER fail_import BEFORE INSERT ON import_provenance BEGIN SELECT RAISE(ABORT, 'controlled failure'); END",
    );
    final result = await confirm(await service.preview(source.path));
    expect(result.outcome, ImportOutcome.failed);
    expect(result.message, contains('rolled back'));
    expect(repository.projects(), isEmpty);
    expect(repository.provenance(), isEmpty);
    expect(repository.activeProjectId, isNull);
    expect(Directory(root).listSync(), hasLength(1));
    expect(sentinel.readAsStringSync(), 'keep');
  });
  test(
    'failure retains nonempty new folder and reports inconsistency',
    () async {
      service = LegacyImportService(
        reader: const ReadOnlyLegacyJsonReader(),
        repository: repository,
        folders: _NonemptyFolders(WindowsImportFolders()),
        clock: () => now,
      );
      database.database.execute(
        "CREATE TRIGGER fail_import BEFORE INSERT ON import_provenance BEGIN SELECT RAISE(ABORT, 'controlled failure'); END",
      );
      final result = await confirm(await service.preview(source.path));
      expect(result.outcome, ImportOutcome.inconsistent);
      expect(result.message, contains('retained'));
      expect(repository.projects(), isEmpty);
      expect(Directory(root).listSync(), hasLength(1));
      expect(
        Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .single
            .readAsStringSync(),
        'external file',
      );
    },
  );
  test(
    'dangerous imported paths never leave configured root or get stored',
    () async {
      final v = fixture();
      v['project']['folderName'] = r'C:\not-accessed\..\outside';
      v['project']['sourceFile'] = r'..\..\private.pdf';
      v['project']['name'] = 'CON';
      v['project']['location'] = r'..\escape';
      source.writeAsStringSync(jsonEncode(v));
      final preview = await service.preview(source.path);
      expect(preview.blocked, false);
      final result = await confirm(preview);
      expect(result.outcome, ImportOutcome.completedWithWarnings);
      expect(result.project!.projectRootReference, root);
      expect(result.project!.safeFolderName, startsWith('_CON_'));
      expect(
        database.database.select('SELECT * FROM import_provenance').toString(),
        isNot(contains('private.pdf')),
      );
    },
  );
  test('reserved device and traversal references are refused by filesystem adapter', () {
    final folders = WindowsImportFolders();
    for (final name in ['CON', 'NUL.txt', '../escape', r'C:\escape', 'A/B']) {
      expect(
        () => folders.create(root, name),
        throwsA(isA<FileSystemException>()),
      );
    }
    for (final path in ['relative', r'\\server\share', r'\\?\C:\escape']) {
      expect(
        () => folders.propose(path, 'Project'),
        throwsA(isA<FileSystemException>()),
      );
    }
  });
  test(
    'owned lease resists rename and will not delete a nonempty directory',
    () {
      final lease = WindowsImportFolders().create(root, 'Owned');
      final dir = Directory('$root\\Owned');
      try {
        expect(
          () => dir.renameSync('$root\\Other'),
          throwsA(isA<FileSystemException>()),
        );
        File('${dir.path}/keep.txt').writeAsStringSync('keep');
        expect(lease.rollback(), false);
      } finally {
        lease.close();
      }
      expect(dir.existsSync(), true);
    },
  );
  test('junction in root is blocked without following it', () async {
    final target = Directory('${temp.path}\\outside')..createSync();
    final link = '${temp.path}\\junction';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "New-Item -ItemType Junction -Path '$link' -Target '${target.path}' | Out-Null",
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    try {
      expect(
        () => WindowsImportFolders().propose(link, 'Project'),
        throwsA(isA<FileSystemException>()),
      );
      expect(target.listSync(), isEmpty);
    } finally {
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "[System.IO.Directory]::Delete('$link')",
      ]);
    }
  });
}

class _NonemptyFolders implements ImportFolderStore {
  _NonemptyFolders(this.delegate);
  final ImportFolderStore delegate;
  @override
  String propose(String root, String name) => delegate.propose(root, name);
  @override
  ImportFolderLease create(String root, String name) {
    final lease = delegate.create(root, name);
    File('$root\\$name\\external.txt').writeAsStringSync('external file');
    return lease;
  }
}

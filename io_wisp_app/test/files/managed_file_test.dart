import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/managed_file_service.dart';
import 'package:io_wisp_app/domain/managed_file.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:uuid/uuid.dart';

import 'file_test_support.dart';

void main() {
  for (final name in [
    '',
    '..',
    '../a.pdf',
    r'..\a.pdf',
    '/a.pdf',
    r'C:\a.pdf',
    r'\\server\a',
    'a:b',
    'a?',
    'a*',
    'a<',
    'a>',
    'a|',
    'a"',
    'a\u0000',
    'name.',
    'name ',
    'CON',
    'con.pdf',
    'NUL.tar.gz',
    'COM¹.txt',
    'LPT9.pdf',
  ]) {
    test(
      'reject unsafe filename ${name.replaceAll('\u0000', '<NUL>')}',
      () => expect(ManagedNameRules.valid(name), isFalse),
    );
  }
  test('safe filename contract', () {
    expect(ManagedNameRules.valid('Drawing A-01.pdf'), isTrue);
    expect(ManagedNameRules.valid('x' * 101), isFalse);
  });

  group('Windows managed file contract', () {
    late FileTestContext c;
    setUp(() => c = FileTestContext());
    tearDown(() => c.close());
    test('existing folders remain valid; layout idempotent; unrelated file retained', () {
      final sentinel = File('${c.temp.path}/Alpha/keep.txt')
        ..writeAsStringSync('keep');
      final lease = c.store.openProject(c.a, c.repository.projects);
      lease.ensureLayout();
      lease.ensureLayout();
      lease.close();
      for (final name in ['sources', 'outputs', 'imports', 'trash']) {
        expect(Directory('${c.temp.path}/Alpha/$name').existsSync(), isTrue);
      }
      expect(sentinel.readAsStringSync(), 'keep');
      expect(Directory('${c.temp.path}/Beta').listSync(), isEmpty);
    });
    test(
      'successful opaque import SHA-256 source unchanged and actual DB reopen',
      () async {
        final source = c.source('abc');
        final modified = source.lastModifiedSync();
        final file = (await c.service.importFile(c.a.id, source.path)).file!;
        expect(
          file.fingerprint.sha256,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        );
        expect(file.fingerprint.byteCount, 3);
        expect(file.state, ManagedFileState.ready);
        expect(source.readAsStringSync(), 'abc');
        expect(source.lastModifiedSync(), modified);
        expect(c.managed(file).readAsStringSync(), 'abc');
        c.reopen();
        final reopened = (await c.service.list(c.a.id)).single;
        expect(reopened.id, file.id);
        expect(reopened.relativePath, file.relativePath);
        expect(reopened.state, ManagedFileState.ready);
        expect(c.repository.list(c.b.id), isEmpty);
      },
    );
    test('empty source and multi-chunk source preserve byte counts', () async {
      for (final size in [0, 200000]) {
        final source = c.source('x' * size, name: '$size.bin');
        final file = (await c.service.importFile(c.a.id, source.path)).file!;
        expect(file.fingerprint.byteCount, size);
        expect(c.managed(file).readAsBytesSync(), source.readAsBytesSync());
      }
    });
    test(
      'same content same name and different name reuse existing record',
      () async {
        final source = c.source('abc');
        final first = await c.service.importFile(c.a.id, source.path);
        for (final path in [
          source.path,
          c.source('abc', name: 'renamed.bin').path,
        ]) {
          final repeat = await c.service.importFile(c.a.id, path);
          expect(repeat.duplicate, isTrue);
          expect(repeat.file!.id, first.file!.id);
        }
        expect(c.repository.list(c.a.id), hasLength(1));
      },
    );
    test('same name different bytes explicit revision/new name/skip never overwrite', () async {
      final first = (await c.service.importFile(
        c.a.id,
        c.source('one').path,
      )).file!;
      final different = c.source('two', folder: 'external2');
      await expectLater(
        c.service.importFile(c.a.id, different.path),
        throwsA(isA<FileNameConflict>()),
      );
      expect(c.repository.list(c.a.id), hasLength(1));
      final skip = await c.service.importFile(
        c.a.id,
        different.path,
        choice: FileCollisionChoice.skip,
        expectedConflictId: first.id,
      );
      expect(skip.skipped, isTrue);
      final revision = (await c.service.importFile(
        c.a.id,
        different.path,
        choice: FileCollisionChoice.revision,
        expectedConflictId: first.id,
      )).file!;
      expect(revision.revisionOf, first.id);
      expect(c.managed(first).readAsStringSync(), 'one');
      final third = c.source('three', folder: 'external3');
      await expectLater(
        c.service.importFile(
          c.a.id,
          third.path,
          choice: FileCollisionChoice.newName,
          newName: 'source.pdf',
          expectedConflictId: revision.id,
        ),
        throwsA(isA<FileImportException>()),
      );
      final renamed = (await c.service.importFile(
        c.a.id,
        third.path,
        choice: FileCollisionChoice.newName,
        newName: 'source-new.pdf',
        expectedConflictId: revision.id,
      )).file!;
      expect(renamed.name, 'source-new.pdf');
      expect(renamed.originalName, 'source.pdf');
      expect(c.managed(revision).readAsStringSync(), 'two');
    });
    test('stale conflict decision requires renewed visible decision', () async {
      final first = (await c.service.importFile(
        c.a.id,
        c.source('one').path,
      )).file!;
      await expectLater(
        c.service.importFile(
          c.a.id,
          c.source('two', folder: 'other').path,
          choice: FileCollisionChoice.revision,
          expectedConflictId: 'wrong',
        ),
        throwsA(isA<FileNameConflict>()),
      );
      expect(c.managed(first).readAsStringSync(), 'one');
    });
    for (final boundary in [
      'permission',
      'create',
      'write',
      'partial',
      'flush',
      'hash',
      'sourceChanged',
      'finalize',
    ]) {
      test('$boundary failure cleans only operation-owned artifacts', () async {
        final source = c.source('unchanged');
        final lease = c.store.openProject(c.a, c.repository.projects)
          ..ensureLayout();
        lease.close();
        final sentinel = File('${c.temp.path}/Alpha/imports/unrelated.part')
          ..writeAsStringSync('keep');
        final service = ManagedFileService(
          repository: c.repository,
          store: FaultStore(c.store, boundary),
        );
        await expectLater(
          service.importFile(c.a.id, source.path),
          throwsA(isA<FileImportException>()),
        );
        expect(c.repository.list(c.a.id), isEmpty);
        expect(source.readAsStringSync(), 'unchanged');
        expect(sentinel.readAsStringSync(), 'keep');
        expect(Directory('${c.temp.path}/Alpha/sources').listSync(), isEmpty);
        expect(
          Directory('${c.temp.path}/Alpha/imports').listSync(),
          hasLength(1),
        );
        expect(Directory('${c.temp.path}/Beta').listSync(), isEmpty);
      });
    }
    test('DB failure after finalized copy rolls back held file only', () async {
      c.db.database.execute(
        "CREATE TRIGGER fail_ready BEFORE UPDATE ON managed_files WHEN NEW.state='ready' BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      final source = c.source('bytes');
      await expectLater(
        c.service.importFile(c.a.id, source.path),
        throwsA(anything),
      );
      expect(c.repository.list(c.a.id), isEmpty);
      expect(Directory('${c.temp.path}/Alpha/sources').listSync(), isEmpty);
      expect(source.readAsStringSync(), 'bytes');
    });
    test('DB failure before copy makes no pending artifact', () async {
      c.db.database.execute(
        "CREATE TRIGGER fail_insert BEFORE INSERT ON managed_files BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(
        c.service.importFile(c.a.id, c.source('bytes').path),
        throwsA(anything),
      );
      expect(Directory('${c.temp.path}/Alpha/imports').listSync(), isEmpty);
      expect(c.repository.list(c.a.id), isEmpty);
    });
    test(
      'uncertain cleanup retains staged bytes and journal across restart',
      () async {
        final service = ManagedFileService(
          repository: c.repository,
          store: FaultStore(c.store, 'uncertain'),
        );
        await expectLater(
          service.importFile(c.a.id, c.source('bytes').path),
          throwsA(
            isA<FileImportException>().having(
              (e) => e.recoveryNeeded,
              'recovery',
              true,
            ),
          ),
        );
        final pending = c.repository.list(c.a.id).single;
        expect(
          File('${c.temp.path}/Alpha/${pending.stagingPath}').readAsBytesSync(),
          [1, 2, 3],
        );
        c.reopen();
        expect(
          (await c.service.list(c.a.id)).single.state,
          ManagedFileState.recoveryNeeded,
        );
        await expectLater(
          c.service.importFile(c.a.id, c.source('next', name: 'next').path),
          throwsA(isA<FileImportException>()),
        );
      },
    );
    test('missing file preserves provenance and repeat does not invent replacement', () async {
      final source = c.source('abc');
      final f = (await c.service.importFile(c.a.id, source.path)).file!;
      c.managed(f).deleteSync();
      expect(
        (await c.service.list(c.a.id)).single.state,
        ManagedFileState.missing,
      );
      final duplicate = await c.service.importFile(c.a.id, source.path);
      expect(duplicate.duplicate, isTrue);
      expect(duplicate.file!.state, ManagedFileState.missing);
      expect(c.managed(f).existsSync(), isFalse);
      expect(duplicate.file!.fingerprint.sha256, f.fingerprint.sha256);
    });
    test(
      'altered managed bytes report recovery and remain untouched',
      () async {
        final f = (await c.service.importFile(
          c.a.id,
          c.source('abc').path,
        )).file!;
        c.managed(f).writeAsStringSync('altered');
        expect(
          (await c.service.list(c.a.id)).single.state,
          ManagedFileState.recoveryNeeded,
        );
        expect(c.managed(f).readAsStringSync(), 'altered');
      },
    );
    test('project isolation identical bytes allowed independently cross-project file ID blocked', () async {
      final source = c.source('abc');
      final a = (await c.service.importFile(c.a.id, source.path)).file!;
      final b = (await c.service.importFile(c.b.id, source.path)).file!;
      expect(a.id, isNot(b.id));
      await expectLater(
        c.service.trash(c.a.id, b.id),
        throwsA(isA<FileImportException>()),
      );
      expect(c.managed(b).readAsStringSync(), 'abc');
    });
    test('overlapping project folder references are rejected', () {
      c.db.database.execute(
        'UPDATE projects SET project_directory_reference=? WHERE id=?',
        ['Alpha', c.b.id],
      );
      expect(
        () => c.store.openProject(c.a, c.repository.projects),
        throwsA(isA<FileImportException>()),
      );
    });
    test(
      'managed traversal absolute and cross-project references rejected',
      () {
        final lease = c.store.openProject(c.a, c.repository.projects)
          ..ensureLayout();
        try {
          for (final path in [
            '../Beta/thing',
            r'C:\outside',
            'sources/../../Beta/a',
            'sources/NUL.pdf',
            r'sources/a\b',
            '/sources/a',
          ]) {
            expect(
              () => lease.openManaged(path),
              throwsA(isA<FileImportException>()),
            );
          }
        } finally {
          lease.close();
        }
      },
    );
    test(
      'held identity prevents directory replacement and external source writes',
      () async {
        final source = c.source('abc');
        final heldSource = c.store.openSource(source.path);
        final lease = c.store.openProject(c.a, c.repository.projects)
          ..ensureLayout();
        try {
          expect(
            () => source.writeAsStringSync('overwrite'),
            throwsA(isA<FileSystemException>()),
          );
          expect(
            () => source.renameSync('${source.path}.moved'),
            throwsA(isA<FileSystemException>()),
          );
          expect(
            () =>
                Directory('${c.temp.path}/Alpha/sources')
                    .renameSync('${c.temp.path}/Alpha/replaced'),
            throwsA(isA<FileSystemException>()),
          );
        } finally {
          heldSource.close();
          lease.close();
        }
        expect(source.readAsStringSync(), 'abc');
      },
    );
    test('atomic finalize refuses existing target; cleanup never deletes existing file', () {
      final lease = c.store.openProject(c.a, c.repository.projects)
        ..ensureLayout();
      final sentinel = File('${c.temp.path}/Alpha/sources/existing')
        ..writeAsStringSync('keep');
      final staged = lease.createStaging(const Uuid().v4());
      try {
        staged.write([1, 2, 3]);
        staged.flush();
        expect(
          () => staged.moveTo('sources/existing'),
          throwsA(isA<FileImportException>()),
        );
        expect(staged.removeOwned(), isTrue);
      } finally {
        staged.close();
        lease.close();
      }
      expect(sentinel.readAsStringSync(), 'keep');
    });
    test('trash preserves bytes and provenance through restart and duplicate repeat', () async {
      final source = c.source('abc');
      final f = (await c.service.importFile(c.a.id, source.path)).file!;
      final trashed = await c.service.trash(c.a.id, f.id);
      expect(c.managed(f).existsSync(), isFalse);
      expect(c.managed(trashed).readAsStringSync(), 'abc');
      c.reopen();
      expect(
        (await c.service.list(c.a.id)).single.state,
        ManagedFileState.trashed,
      );
      expect(
        (await c.service.importFile(c.a.id, source.path)).duplicate,
        isTrue,
      );
      expect(source.readAsStringSync(), 'abc');
    });
    test('trash database failure safely reverses move', () async {
      final f = (await c.service.importFile(
        c.a.id,
        c.source('abc').path,
      )).file!;
      c.db.database.execute(
        "CREATE TRIGGER fail_trash BEFORE UPDATE ON managed_files WHEN NEW.state='trashed' BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(c.service.trash(c.a.id, f.id), throwsA(anything));
      expect(c.managed(f).readAsStringSync(), 'abc');
      expect(c.repository.list(c.a.id).single.state, ManagedFileState.ready);
    });
    test(
      'same-project revision foreign key rejects cross-project relationship',
      () async {
        final a = (await c.service.importFile(
          c.a.id,
          c.source('abc').path,
        )).file!;
        final b = (await c.service.importFile(
          c.b.id,
          c.source('def', name: 'b').path,
        )).file!;
        expect(
          () => c.db.database.execute(
            'UPDATE managed_files SET revision_of=? WHERE id=?',
            [b.id, a.id],
          ),
          throwsA(anything),
        );
        expect(SqliteProjectRepository(c.db).getAll(), hasLength(2));
      },
    );
  }, skip: !Platform.isWindows);
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:io_wisp_app/application/managed_pdf_service.dart';
import 'package:io_wisp_app/data/pdf/pdfium_renderer.dart';
import 'package:io_wisp_app/data/pdf/sqlite_pdf_repository.dart';
import 'package:io_wisp_app/domain/managed_file.dart';
import 'package:io_wisp_app/domain/pdf_document.dart';

import '../files/file_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FileTestContext c;
  ManagedPdfService service() => ManagedPdfService(
    c.repository,
    c.store,
    SqlitePdfRepository(c.db),
    PdfiumRenderer(),
  );
  Future<ManagedFile> import(String name) async => (await c.service.importFile(
    c.a.id,
    p.normalize(File('test/fixtures/pdf/$name').absolute.path),
  )).file!;
  Matcher failure(PdfFailureKind kind) =>
      throwsA(isA<PdfFailure>().having((e) => e.kind, 'kind', kind));
  setUp(() => c = FileTestContext());
  tearDown(() => c.close());
  for (final input in ['', '1.5', 'abc', 'A01', '1e1', 'NaN']) {
    test(
      'reject direct input "$input"',
      () => expect(
        () => PageRequest.parse(input, 19),
        throwsA(isA<PdfFailure>()),
      ),
    );
  }
  for (final value in [-999, 0, 1, 10, 19, 999]) {
    test('direct integer $value clamps visibly to physical range', () {
      final r = PageRequest.parse('$value', 19);
      expect(r.page, value.clamp(1, 19));
      expect(r.warning, value < 1 || value > 19 ? isNotNull : isNull);
    });
  }
  test(
    'huge integer is handled visibly without overflow',
    () => expect(PageRequest.parse('9' * 100, 19).page, 19),
  );
  test(
    'no selection',
    () => expect(
      service().open(c.a.id, '', RenderCancellation()),
      failure(PdfFailureKind.noSource),
    ),
  );
  test(
    'missing record',
    () => expect(
      service().open(c.a.id, 'missing', RenderCancellation()),
      failure(PdfFailureKind.missingRecord),
    ),
  );
  test('cross-project identity rejected before accessing file', () async {
    final file = await import('one.pdf');
    expect(
      service().open(c.b.id, file.id, RenderCancellation()),
      failure(PdfFailureKind.projectMismatch),
    );
    expect(Directory('${c.temp.path}/Beta').listSync(), isEmpty);
  });
  test(
    'missing managed file does not recreate directories or source',
    () async {
      final file = await import('one.pdf');
      c.managed(file).deleteSync();
      Directory('${c.temp.path}/Alpha/sources').deleteSync();
      await expectLater(
        service().open(c.a.id, file.id, RenderCancellation()),
        failure(PdfFailureKind.missingFile),
      );
      expect(Directory('${c.temp.path}/Alpha/sources').existsSync(), isFalse);
      expect(SqlitePdfRepository(c.db).find(c.a.id, file.id), isNull);
    },
  );
  test('changed bytes rejected with original provenance retained', () async {
    final file = await import('one.pdf');
    c.managed(file).writeAsStringSync('changed');
    await expectLater(
      service().open(c.a.id, file.id, RenderCancellation()),
      failure(PdfFailureKind.changedSource),
    );
    expect(
      c.repository.get(c.a.id, file.id).fingerprint.sha256,
      file.fingerprint.sha256,
    );
  });
  for (final state in [
    ManagedFileState.importing,
    ManagedFileState.trashing,
    ManagedFileState.trashed,
    ManagedFileState.recoveryNeeded,
  ]) {
    test('reject unusable source state ${state.name}', () async {
      final file = await import('one.pdf');
      c.repository.updateState(file.withState(state));
      await expectLater(
        service().open(c.a.id, file.id, RenderCancellation()),
        failure(PdfFailureKind.unusableSource),
      );
    });
  }
  for (final item in [
    ('not-pdf.pdf', PdfFailureKind.notPdf),
    ('corrupt.pdf', PdfFailureKind.unsupported),
    ('password.pdf', PdfFailureKind.unsupported),
    ('zero.pdf', PdfFailureKind.zeroPages),
  ]) {
    test('real renderer error ${item.$1}', () async {
      final file = await import(item.$1);
      await expectLater(
        service().open(c.a.id, file.id, RenderCancellation()),
        failure(item.$2),
      );
      expect(c.db.database.select('SELECT * FROM pdf_documents'), isEmpty);
      // All error paths must have closed their deny-write read lease.
      final f = c.managed(file);
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(bytes);
    });
  }
  test(
    'read-only lease locks source and exposes bounded random reads',
    () async {
      final file = await import('one.pdf');
      final before = c.managed(file).readAsBytesSync();
      final tree = Directory('${c.temp.path}/Alpha')
          .listSync(recursive: true)
          .map((e) => e.path)
          .toList();
      final lease =
          c.store.openProject(c.a, c.repository.projects) as ManagedReadLease;
      final source = lease.openReadOnlyManaged(file.relativePath)!;
      try {
        final bytes = Uint8List(5);
        expect(source.readAt(bytes, 0, 5), 5);
        expect(String.fromCharCodes(bytes), '%PDF-');
        expect(source.readAt(bytes, 1, 5), 5);
        expect(String.fromCharCodes(bytes), 'PDF-1');
        expect(
          () => source.readAt(bytes, -1, 5),
          throwsA(isA<FileImportException>()),
        );
        expect(
          () => c.managed(file).writeAsStringSync('bad'),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          () => lease.openReadOnlyManaged('../one.pdf'),
          throwsA(isA<FileImportException>()),
        );
        expect(
          () => lease.openReadOnlyManaged('trash/${file.leaf}'),
          throwsA(isA<FileImportException>()),
        );
      } finally {
        source.close();
        lease.close();
      }
      expect(
        () => source.readAt(Uint8List(1), 0, 1),
        throwsA(isA<FileImportException>()),
      );
      expect(c.managed(file).readAsBytesSync(), before);
      expect(
        Directory('${c.temp.path}/Alpha')
            .listSync(recursive: true)
            .map((e) => e.path)
            .toList(),
        tree,
      );
    },
  );
  test('geometry, rotation, real rendering, invalid page, cancellation and disposal', () async {
    final file = await import('geometry.pdf');
    final s = await service().open(c.a.id, file.id, RenderCancellation());
    expect(s.index.pages.map((p) => p.rotation), [0, 0, 90]);
    expect(s.index.pages[0].width < s.index.pages[0].height, isTrue);
    expect(s.index.pages[1].width > s.index.pages[1].height, isTrue);
    for (final n in [1, 2, 3]) {
      final r = await s.document.render(n, 1, RenderCancellation());
      expect(r.pixels.any((b) => b < 200), isTrue);
      r.dispose();
    }
    await expectLater(
      s.document.render(4, 1, RenderCancellation()),
      failure(PdfFailureKind.render),
    );
    await expectLater(
      s.document.render(1, 1, RenderCancellation()..cancel()),
      failure(PdfFailureKind.cancelled),
    );
    final cancel = RenderCancellation();
    final pending = s.document.render(1, 3, cancel);
    cancel.cancel();
    await expectLater(pending, failure(PdfFailureKind.cancelled));
    await s.dispose();
    await s.dispose();
    await expectLater(
      s.document.render(1, 1, RenderCancellation()),
      failure(PdfFailureKind.cancelled),
    );
    c.managed(file).writeAsBytesSync(c.managed(file).readAsBytesSync());
  });
  test(
    'oversize geometry degrades raster resolution without rejecting PDF',
    () async {
      final file = await import('huge-page.pdf');
      final s = await service().open(c.a.id, file.id, RenderCancellation());
      try {
        final r = await s.document.render(1, 3, RenderCancellation());
        expect(r.width * r.height, lessThanOrEqualTo(4194304));
        expect(r.diagnostic, isNotNull);
        r.dispose();
      } finally {
        await s.dispose();
      }
    },
  );
  test(
    'same managed source and index reopen after real SQLite closure',
    () async {
      final file = await import('one.pdf');
      final s = await service().open(c.a.id, file.id, RenderCancellation());
      final id = s.index.id;
      await s.dispose();
      c.reopen();
      final reopened = await service().open(
        c.a.id,
        file.id,
        RenderCancellation(),
      );
      expect(reopened.index.id, id);
      final r = await reopened.document.render(1, 1, RenderCancellation());
      r.dispose();
      await reopened.dispose();
    },
  );
  test(
    'cancelled opening commits no partial index and releases handle',
    () async {
      final file = await import('one.pdf');
      final cancel = RenderCancellation()..cancel();
      await expectLater(
        service().open(c.a.id, file.id, cancel),
        failure(PdfFailureKind.cancelled),
      );
      expect(c.db.database.select('SELECT * FROM pdf_documents'), isEmpty);
    },
  );
  test('read-only managed capability rejects hard-link aliases', () async {
    final file = await import('one.pdf');
    final alias = '${c.temp.path}\\alias.pdf';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "New-Item -ItemType HardLink -Path '$alias' -Target '${c.managed(file).path}' | Out-Null",
    ]);
    expect(result.exitCode, 0);
    final lease =
        c.store.openProject(c.a, c.repository.projects) as ManagedReadLease;
    try {
      expect(
        () => lease.openReadOnlyManaged(file.relativePath),
        throwsA(isA<FileImportException>()),
      );
    } finally {
      lease.close();
    }
    expect(File(alias).readAsBytesSync(), c.managed(file).readAsBytesSync());
  });
  test('read-only managed capability rejects junction without creating files', () async {
    final junction = '${c.temp.path}\\Alpha\\sources';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "New-Item -ItemType Junction -Path '$junction' -Target '${c.temp.path}\\Beta' | Out-Null",
    ]);
    expect(result.exitCode, 0);
    final lease =
        c.store.openProject(c.a, c.repository.projects) as ManagedReadLease;
    try {
      expect(
        () => lease.openReadOnlyManaged('sources/missing.pdf'),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory('${c.temp.path}/Beta').listSync(), isEmpty);
    } finally {
      lease.close();
      Directory(junction).deleteSync();
    }
  });
  test('untrusted managed path cannot redirect to another file', () async {
    final file = await import('one.pdf');
    c.db.database.execute(
      'UPDATE managed_files SET relative_path=? WHERE id=?',
      ['sources/other.pdf', file.id],
    );
    await expectLater(
      service().open(c.a.id, file.id, RenderCancellation()),
      failure(PdfFailureKind.storage),
    );
    expect(c.db.database.select('SELECT * FROM pdf_documents'), isEmpty);
  });
  test('invalid native render scale returns explicit resource state', () async {
    final file = await import('one.pdf');
    final s = await service().open(c.a.id, file.id, RenderCancellation());
    try {
      for (final scale in [double.nan, 0.0, 4.0]) {
        await expectLater(
          s.document.render(1, scale, RenderCancellation()),
          failure(PdfFailureKind.resource),
        );
      }
    } finally {
      await s.dispose();
    }
  });
}

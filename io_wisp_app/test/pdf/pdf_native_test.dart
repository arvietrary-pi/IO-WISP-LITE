import 'package:path/path.dart' as p;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/managed_pdf_service.dart';
import 'package:io_wisp_app/data/pdf/pdfium_renderer.dart';
import 'package:io_wisp_app/data/pdf/sqlite_pdf_repository.dart';
import 'package:io_wisp_app/domain/pdf_document.dart';

import '../files/file_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real PDFium opens protected managed Sample and renders physical pages 1,10,19', () async {
    final c = FileTestContext();
    addTearDown(c.close);
    final imported = await c.service.importFile(
      c.a.id,
      p.normalize(File('../test_assets/Sample.pdf').absolute.path),
    );
    final service = ManagedPdfService(
      c.repository,
      c.store,
      SqlitePdfRepository(c.db),
      PdfiumRenderer(),
    );
    stdout.writeln('Managed import completed');
    final timer = Stopwatch()..start();
    final session = await service.open(
      c.a.id,
      imported.file!.id,
      RenderCancellation(),
    );
    try {
      expect(session.index.pages, hasLength(19));
      for (final n in [1, 10, 19]) {
        final raster = await session.document.render(
          n,
          1,
          RenderCancellation(),
        );
        try {
          expect(raster.pixels.length, raster.width * raster.height * 4);
          expect(raster.pixels.any((b) => b < 200), isTrue);
          // Raw measurements retained by test reporter.
          // ignore: avoid_print
          stdout.writeln(
            'PDF page $n: ${raster.width}x${raster.height}; ${timer.elapsedMilliseconds} ms; RSS ${ProcessInfo.currentRss}; ${raster.diagnostic}',
          );
        } finally {
          raster.dispose();
        }
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

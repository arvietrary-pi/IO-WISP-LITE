import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/document_register_service.dart';
import 'package:io_wisp_app/application/managed_pdf_service.dart';
import 'package:io_wisp_app/data/pdf/pdfium_renderer.dart';
import 'package:io_wisp_app/data/pdf/sqlite_pdf_repository.dart';
import 'package:io_wisp_app/data/register/sqlite_register_repository.dart';
import 'package:io_wisp_app/domain/document_register.dart';
import 'package:path/path.dart' as p;

import '../files/file_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native PDFium analysis matches Sample.pdf physical-page ground truth',
    () async {
      final context = FileTestContext();
      addTearDown(context.close);
      final imported = await context.service.importFile(
        context.a.id,
        p.normalize(File('../test_assets/Sample.pdf').absolute.path),
      );
      final pdf = ManagedPdfService(
        context.repository,
        context.store,
        SqlitePdfRepository(context.db),
        PdfiumRenderer(),
      );
      final service = DocumentRegisterService(
        repository: SqliteRegisterRepository(context.db),
        pdf: pdf,
      );
      final register = await service.analyze(context.a.id, imported.file!.id);
      const expected = [
        'A00.01',
        'A00.04',
        'A00.11',
        'A00.12',
        '',
        'A01.02',
        'A01.03',
        'A01.11',
        'A02.01',
        'A02.02',
        'A02.03',
        'A02.04',
        'A02.05',
        'A02.06',
        'A02.07',
        'A02.08',
        'A04.01',
        'A04.02',
        'A05.01',
      ];
      expect(register.entries, hasLength(19));
      expect(
        register.entries.map((entry) => entry.physicalPage),
        List.generate(19, (i) => i + 1),
      );
      expect(
        register.entries.map((entry) => entry.detected.sheetNumber),
        expected,
      );
      expect(register.entries[4].detected.status, RegisterEntryStatus.review);
      expect(
        register.entries[4].detected.diagnostics,
        contains(PageDiagnostic.noSheetNumber),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

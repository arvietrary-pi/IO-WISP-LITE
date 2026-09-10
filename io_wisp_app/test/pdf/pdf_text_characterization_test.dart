import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:io_wisp_app/data/pdf/pdfium_renderer.dart';

Uint8List _rotatedTextFixture() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R 9 0 R] /Count 4 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Rotate 0 /Resources << /Font << /F1 11 0 R >> >> /Contents 4 0 R >>',
    '<< /Length 34 >>\nstream\nBT /F1 12 Tf 20 20 Td (ROT0) Tj ET\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Rotate 90 /Resources << /Font << /F1 11 0 R >> >> /Contents 6 0 R >>',
    '<< /Length 35 >>\nstream\nBT /F1 12 Tf 20 20 Td (ROT90) Tj ET\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Rotate 180 /Resources << /Font << /F1 11 0 R >> >> /Contents 8 0 R >>',
    '<< /Length 36 >>\nstream\nBT /F1 12 Tf 20 20 Td (ROT180) Tj ET\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Rotate 270 /Resources << /Font << /F1 11 0 R >> >> /Contents 10 0 R >>',
    '<< /Length 36 >>\nstream\nBT /F1 12 Tf 20 20 Td (ROT270) Tj ET\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  var byteOffset = ascii.encode(output.toString()).length;
  for (var i = 0; i < objects.length; i++) {
    offsets.add(byteOffset);
    final value = '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
    output.write(value);
    byteOffset += ascii.encode(value).length;
  }
  final xref = byteOffset;
  output.write('xref\n0 ${objects.length + 1}\n');
  output.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(output.toString()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'PDFium structured text rectangles remain in pre-rotation PDF space',
    () async {
      await PdfrxEntryFunctions.instance.init();
      final document = await PdfDocument.openData(_rotatedTextFixture());
      addTearDown(document.dispose);

      expect(document.pages.map((page) => page.rotation.index), [0, 1, 2, 3]);
      final bounds = <PdfRect>[];
      for (final page in document.pages) {
        final text = await page.loadStructuredText();
        expect(text.fullText, startsWith('ROT'));
        bounds.add(text.fragments.first.bounds);
      }

      // FPDFText_GetCharBox is unaffected by /Rotate. Every text object was
      // authored at the same unrotated PDF point, so its raw rectangle stays at
      // the same location while the page's oriented dimensions change.
      for (final rect in bounds.skip(1)) {
        expect(rect.left, closeTo(bounds.first.left, .01));
        expect(rect.bottom, closeTo(bounds.first.bottom, .01));
      }
      final oriented = [
        for (var index = 0; index < bounds.length; index++)
          orientPdfTextRect(document.pages[index], bounds[index], 'text'),
      ];
      expect(oriented[0].x, closeTo(bounds[0].left, .01));
      expect(oriented[0].y, closeTo(100 - bounds[0].bottom, .01));
      expect(oriented[1].x, closeTo(100 - bounds[1].top, .01));
      expect(oriented[1].y, closeTo(bounds[1].right, .01));
      expect(oriented[2].x, closeTo(200 - bounds[2].right, .01));
      expect(oriented[2].y, closeTo(bounds[2].top, .01));
      expect(oriented[3].x, closeTo(bounds[3].bottom, .01));
      expect(oriented[3].y, closeTo(200 - bounds[3].left, .01));
      expect(document.pages.map((page) => (page.width, page.height)), [
        (200.0, 100.0),
        (100.0, 200.0),
        (200.0, 100.0),
        (100.0, 200.0),
      ]);
    },
  );
}

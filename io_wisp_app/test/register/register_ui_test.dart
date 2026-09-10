import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/document_register_service.dart';
import 'package:io_wisp_app/data/register/sqlite_register_repository.dart';
import 'package:io_wisp_app/domain/document_register.dart';
import 'package:io_wisp_app/domain/managed_file.dart';
import 'package:io_wisp_app/domain/pdf_document.dart';
import 'package:io_wisp_app/domain/sheet_detector.dart';
import 'package:io_wisp_app/features/register/document_register_page.dart';

import '../files/file_test_support.dart';
import 'document_register_test.dart' show detected;

class _Raster implements PageRaster {
  @override
  int get width => 20;
  @override
  int get height => 20;
  @override
  Uint8List get pixels => Uint8List(20 * 20 * 4);
  @override
  String? get diagnostic => null;
  @override
  void dispose() {}
}

class _Document implements PdfRenderDocument {
  @override
  final pages = const [
    PhysicalPage(1, 200, 100, 0),
    PhysicalPage(2, 200, 100, 0),
  ];
  @override
  Future<PositionalTextPage> extractText(int physicalPage) => Future.value(
    PositionalTextPage(
      physicalPage: physicalPage,
      width: 200,
      height: 100,
      rotation: 0,
      items: const [],
    ),
  );
  @override
  Future<PageRaster> render(
    int physicalPage,
    double scale,
    RenderCancellation cancel,
  ) async => _Raster();
  @override
  Future<void> dispose() async {}
}

class _Pdf implements PdfDocumentService {
  _Pdf(this.file);
  final ManagedFile file;
  @override
  Future<PdfSession> open(
    String projectId,
    String managedFileId,
    RenderCancellation cancel,
  ) async => PdfSession(
    file,
    PdfIndex(
      'pdf',
      projectId,
      managedFileId,
      file.fingerprint.sha256,
      'test',
      const [PhysicalPage(1, 200, 100, 0), PhysicalPage(2, 200, 100, 0)],
    ),
    _Document(),
    () {},
  );
}

void main() {
  testWidgets(
    'Document Register edits, filters, reviews, and opens physical page',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final context = FileTestContext();
      addTearDown(context.close);
      final file = ManagedFile(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        projectId: context.a.id,
        originalName: 'plans.pdf',
        name: 'plans.pdf',
        relativePath: 'sources/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa--plans.pdf',
        fingerprint: FileFingerprint(List.filled(64, 'a').join(), 100),
        importedAt: DateTime.utc(2026, 9, 5),
        state: ManagedFileState.ready,
      );
      context.repository.transaction(() => context.repository.insert(file));
      final repository = SqliteRegisterRepository(context.db);
      repository.saveDetection(
        projectId: context.a.id,
        managedFileId: file.id,
        sourceFilename: file.name,
        fingerprint: file.fingerprint.sha256,
        detectorVersion: SheetDetector.version,
        entries: [
          detected(page: 1, sheet: 'A01.01'),
          detected(page: 2, sheet: 'S02.01'),
        ],
      );
      final pdf = _Pdf(file);
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentRegisterPage(
            projectId: context.a.id,
            projectName: context.a.name,
            file: file,
            service: DocumentRegisterService(repository: repository, pdf: pdf),
            pdf: pdf,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Physical page'), findsOneWidget);
      expect(find.text('A01.01'), findsOneWidget);
      expect(find.text('S02.01'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('editRegisterPage-1')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('editRegisterPage-1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('registerOverrideField-0')),
        'A01.01M',
      );
      await tester.enterText(
        find.byKey(const ValueKey('registerNotes')),
        'Estimator checked.',
      );
      await tester.tap(find.byKey(const ValueKey('saveRegisterOverrides')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('A01.01M'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('registerSearch')),
        'S02.01',
      );
      await tester.pump();
      expect(find.text('A01.01M'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'S02.01',
        ),
        findsOneWidget,
      );

      final reviewMenu = tester.widget<PopupMenuButton<RegisterReviewState>>(
        find.byType(PopupMenuButton<RegisterReviewState>),
      );
      reviewMenu.onSelected!(RegisterReviewState.reviewed);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        repository.find(context.a.id, file.id)!.entries[1].reviewState,
        RegisterReviewState.reviewed,
      );

      tester
          .widget<TextButton>(find.byKey(const ValueKey('openRegisterPage-2')))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Physical PDF page 2 of 2'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

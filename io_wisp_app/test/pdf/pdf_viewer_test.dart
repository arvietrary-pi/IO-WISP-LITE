import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/application/pdf_viewer_controller.dart';
import 'package:io_wisp_app/domain/managed_file.dart';
import 'package:io_wisp_app/domain/pdf_document.dart';
import 'package:io_wisp_app/domain/document_register.dart';
import 'package:io_wisp_app/features/pdf/pdf_viewer_page.dart';

class FakeRaster implements PageRaster {
  bool disposed = false;
  @override
  int get width => 2;
  @override
  int get height => 2;
  @override
  Uint8List get pixels => Uint8List.fromList(List.filled(16, 128));
  @override
  String? get diagnostic => null;
  @override
  void dispose() {
    disposed = true;
  }
}

class FakeDocument implements PdfRenderDocument {
  FakeDocument({this.auto = true, int count = 3})
    : pages = List.generate(
        count,
        (i) => PhysicalPage(i + 1, i == 1 ? 800 : 400, 600, 0),
      );
  final bool auto;
  @override
  final List<PhysicalPage> pages;

  @override
  Future<PositionalTextPage> extractText(int physicalPage) => Future.value(
    PositionalTextPage(
      physicalPage: physicalPage,
      width: pages[physicalPage - 1].width,
      height: pages[physicalPage - 1].height,
      rotation: pages[physicalPage - 1].rotation,
      items: const [],
    ),
  );
  final requests = <int>[];
  final completions = <Completer<PageRaster>>[];
  int closes = 0;
  @override
  Future<PageRaster> render(int page, double scale, RenderCancellation cancel) {
    requests.add(page);
    final result = Completer<PageRaster>();
    completions.add(result);
    if (auto) result.complete(FakeRaster());
    return result.future;
  }

  @override
  Future<void> dispose() async {
    closes++;
  }
}

class FakeService implements PdfDocumentService {
  FakeService(this.document);
  final FakeDocument document;
  PdfFailure? failure;
  Completer<PdfSession>? opening;
  @override
  Future<PdfSession> open(
    String project,
    String file,
    RenderCancellation cancel,
  ) async {
    if (failure != null) throw failure!;
    if (opening != null) return opening!.future;
    return makeSession(project, file, document);
  }
}

PdfSession makeSession(String project, String file, FakeDocument doc) =>
    PdfSession(
      ManagedFile(
        id: file,
        projectId: project,
        originalName: '$file.pdf',
        name: '$file.pdf',
        relativePath: 'sources/$file',
        fingerprint: FileFingerprint('a' * 64, 10),
        importedAt: DateTime.utc(2026),
        state: ManagedFileState.ready,
      ),
      PdfIndex('index', project, file, 'a' * 64, 'fake', doc.pages),
      doc,
      () {},
    );
Future<void> waitFor(bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Viewer did not converge');
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('first/last boundaries, direct input and one-page navigation', () async {
    final c = PdfViewerController(FakeService(FakeDocument(count: 1)));
    addTearDown(c.dispose);
    await c.open('a', 'one');
    await waitFor(() => !c.loading);
    expect(c.previousEnabled, isFalse);
    expect(c.nextEnabled, isFalse);
    expect(c.zoom, 1);
    c.next();
    c.previous();
    expect(c.page, 1);
    c.go('1.5');
    expect(c.warning, contains('whole'));
    expect(c.page, 1);
    c.go('999');
    expect(c.warning, contains('outside'));
    expect(c.page, 1);
    await waitFor(() => !c.loading);
  });
  test(
    'rapid requests discard stale raster and converge on newest physical page',
    () async {
      final doc = FakeDocument(auto: false);
      final c = PdfViewerController(FakeService(doc));
      addTearDown(c.dispose);
      await c.open('a', 'f');
      c.go('2');
      c.go('3');
      expect(c.image, isNull);
      final stale = FakeRaster();
      doc.completions.first.complete(stale);
      await waitFor(() => doc.requests.length == 2);
      expect(doc.requests, [1, 3]);
      expect(stale.disposed, isTrue);
      final latest = FakeRaster();
      doc.completions.last.complete(latest);
      await waitFor(() => !c.loading);
      expect(c.page, 3);
      expect(c.image, isNotNull);
      expect(latest.disposed, isTrue);
      c.first();
      expect(c.page, 1);
      expect(c.image, isNull);
      doc.completions.last.completeError(
        const PdfFailure(PdfFailureKind.render, 'Injected render failure'),
      );
      await waitFor(() => !c.loading);
      expect(c.error, contains('Injected'));
      expect(c.image, isNull);
    },
  );
  test('old project/source completion cannot become current', () async {
    final doc = FakeDocument(auto: false);
    final service = FakeService(doc);
    final c = PdfViewerController(service);
    addTearDown(c.dispose);
    await c.open('Alpha', 'sourceA');
    await c.open('Beta', 'sourceB');
    expect(c.image, isNull);
    expect(c.session!.file.projectId, 'Beta');
    final stale = FakeRaster();
    doc.completions.first.complete(stale);
    await waitFor(() => doc.completions.length == 2);
    expect(stale.disposed, isTrue);
    doc.completions.last.complete(FakeRaster());
    await waitFor(() => !c.loading);
    expect(c.session!.file.id, 'sourceB');
  });
  test('disposed viewer drops and disposes in-flight raster', () async {
    final doc = FakeDocument(auto: false);
    final c = PdfViewerController(FakeService(doc));
    await c.open('a', 'f');
    c.dispose();
    final raster = FakeRaster();
    doc.completions.first.complete(raster);
    await waitFor(() => raster.disposed);
    expect(c.image, isNull);
    expect(doc.closes, 1);
  });
  test('late source open after disposal releases its session', () async {
    final doc = FakeDocument();
    final service = FakeService(doc)..opening = Completer<PdfSession>();
    final c = PdfViewerController(service);
    final open = c.open('a', 'f');
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    service.opening!.complete(makeSession('a', 'f', doc));
    await open;
    expect(doc.closes, 1);
    expect(c.session, isNull);
  });
  test(
    'zoom steps/bounds and fit responds to viewport and page geometry',
    () async {
      final c = PdfViewerController(FakeService(FakeDocument()));
      addTearDown(c.dispose);
      await c.open('a', 'f');
      await waitFor(() => !c.loading);
      c.zoomBy(.15);
      expect(c.zoom, 1.15);
      c.zoomBy(100);
      expect(c.zoom, 3);
      c.zoomBy(-100);
      expect(c.zoom, .2);
      c.viewport(600);
      c.fitWidth();
      expect(c.zoom, 1.5);
      c.go('2');
      expect(c.zoom, .75);
      c.viewport(800);
      expect(c.zoom, 1);
      c.zoomBy(.15);
      expect(c.fit, isFalse);
      await waitFor(() => !c.loading);
    },
  );
  testWidgets(
    'viewer filename, physical label, entry, controls, zoom and fit',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PdfViewerPage(
            projectId: 'a',
            projectName: 'Alpha',
            managedFileId: 'one',
            filename: 'one.pdf',
            service: FakeService(FakeDocument()),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Alpha — one.pdf'), findsOneWidget);
      expect(find.text('Physical PDF page 1 of 3'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('pdfPrevious')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('pdfNext')));
      await settle(tester);
      expect(find.text('Physical PDF page 2 of 3'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pdfPageEntry')), '999');
      await tester.tap(find.byKey(const ValueKey('pdfGo')));
      await settle(tester);
      expect(find.text('Physical PDF page 3 of 3'), findsOneWidget);
      expect(find.textContaining('outside'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('pdfNext')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('pdfZoomIn')));
      await settle(tester);
      expect(find.text('115%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdfFitWidth')));
      await settle(tester);
      expect(find.byKey(const ValueKey('pdfRaster')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('loading then error has no old raster and retry recovers', (
    tester,
  ) async {
    final doc = FakeDocument(auto: false);
    final service = FakeService(doc);
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerPage(
          projectId: 'a',
          projectName: 'Alpha',
          managedFileId: 'one',
          filename: 'one.pdf',
          service: service,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('pdfLoading')), findsOneWidget);
    doc.completions.first.completeError(
      const PdfFailure(PdfFailureKind.render, 'Failed raster'),
    );
    await settle(tester);
    expect(find.text('Failed raster'), findsOneWidget);
    expect(find.byKey(const ValueKey('pdfRaster')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pdfRetry')));
    await tester.pump();
    doc.completions.last.complete(FakeRaster());
    await settle(tester);
    expect(find.byKey(const ValueKey('pdfRaster')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'same widget switched project/source cannot display Alpha raster',
    (tester) async {
      final doc = FakeDocument(auto: false);
      final service = FakeService(doc);
      Widget page(String project, String file) => MaterialApp(
        home: PdfViewerPage(
          projectId: project,
          projectName: project,
          managedFileId: file,
          filename: '$file.pdf',
          service: service,
        ),
      );
      await tester.pumpWidget(page('Alpha', 'a'));
      await tester.pump();
      await tester.pumpWidget(page('Beta', 'b'));
      await tester.pump();
      final stale = FakeRaster();
      doc.completions.first.complete(stale);
      await tester.pump();
      expect(stale.disposed, isTrue);
      expect(find.text('Beta — b.pdf'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdfRaster')), findsNothing);
      doc.completions.last.complete(FakeRaster());
      await settle(tester);
      expect(find.byKey(const ValueKey('pdfRaster')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

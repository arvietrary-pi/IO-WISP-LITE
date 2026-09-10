import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:io_wisp_app/application/managed_file_service.dart';
import 'package:io_wisp_app/application/managed_pdf_service.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/import/windows_import_folders.dart';
import 'package:io_wisp_app/data/pdf/pdfium_renderer.dart';
import 'package:io_wisp_app/data/pdf/sqlite_pdf_repository.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/storage/sqlite_managed_file_repository.dart';
import 'package:io_wisp_app/domain/managed_file.dart';
import 'package:io_wisp_app/domain/pdf_document.dart';
import 'package:io_wisp_app/domain/project.dart';
import 'package:io_wisp_app/features/files/project_files_page.dart';
import 'package:io_wisp_app/features/pdf/pdf_viewer_page.dart';

class _Picker implements SourceFilePicker {
  _Picker(this.path);
  final String path;
  @override
  Future<String?> selectSource() async => path;
}

class _Offline extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('HTTP forbidden during offline PDF acceptance');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Phase5 Windows actual managed PDF raster, navigation and process reopen offline',
    (tester) async {
      const supplied = String.fromEnvironment('WISP_PHASE5_ROOT');
      final base =
          supplied.isEmpty
                ? Directory.systemTemp.createTempSync('wisp-p5-native-')
                : Directory(supplied)
            ..createSync(recursive: true);
      final restart = const bool.fromEnvironment('WISP_PHASE5_RESTART');
      final evidence = Directory(
        '${base.path}/${restart ? 'restart' : 'first'}',
      )..createSync();
      final priorHttp = HttpOverrides.current;
      final offline = _Offline();
      HttpOverrides.global = offline;
      final sample = p.normalize(
        File(
          const String.fromEnvironment(
            'WISP_SAMPLE_PATH',
            defaultValue: '../test_assets/Sample.pdf',
          ),
        ).absolute.path,
      );
      final originalHash = sha256
          .convert(File(sample).readAsBytesSync())
          .toString();
      final db = AppDatabase.open('${base.path}/app.sqlite');
      final projects = SqliteProjectRepository(db);
      final files = SqliteManagedFileRepository(db);
      final store = WindowsProjectFileStore();
      final imports = ManagedFileService(repository: files, store: store);
      final pdf = ManagedPdfService(
        files,
        store,
        SqlitePdfRepository(db),
        PdfiumRenderer(),
      );
      final boundary = GlobalKey();
      final metrics = <Map<String, Object?>>[];
      final checkpoints = <String>[];
      void note(String s) {
        checkpoints.add(s);
        debugPrint('P5: $s');
      }

      Future<void> until(bool Function() done) async {
        await tester.pump();
        final watch = Stopwatch()..start();
        while (!done()) {
          if (watch.elapsed > const Duration(seconds: 90)) {
            throw StateError(
              'Native viewer timed out; ${find.byKey(const ValueKey('pdfError')).evaluate().map((e) => (e.widget as Text).data)}',
            );
          }
          await tester.pump(const Duration(milliseconds: 40));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await tester.pump();
      }

      Widget wrap(Widget child) => RepaintBoundary(
        key: boundary,
        child: MaterialApp(home: child),
      );
      Future<void> raster(int page, {String? label}) async {
        await until(
          () =>
              find.byKey(const ValueKey('pdfRaster')).evaluate().isNotEmpty &&
              find.byKey(const ValueKey('pdfLoading')).evaluate().isEmpty,
        );
        expect(find.text('Physical PDF page $page of 19'), findsOneWidget);
        final raw = tester
            .widget<RawImage>(find.byKey(const ValueKey('pdfRaster')))
            .image!;
        final data = (await raw.toByteData(format: ui.ImageByteFormat.png))!;
        final pixels = (await raw.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(pixels.buffer.asUint8List().any((v) => v < 200), isTrue);
        final name = label ?? 'page-$page';
        File('${evidence.path}/$name.png')
            .writeAsBytesSync(data.buffer.asUint8List());
        metrics.add({
          'name': name,
          'page': page,
          'width': raw.width,
          'height': raw.height,
          'pngSha256': sha256.convert(data.buffer.asUint8List()).toString(),
          'rss': ProcessInfo.currentRss,
        });
        await tester.pump();
        final screenshot =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          File('${evidence.path}/$name-ui.png').writeAsBytesSync(
            (await screenshot.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List(),
          );
        } finally {
          screenshot.dispose();
        }
        note(
          'Rendered physical PDF page $page: ${raw.width}x${raw.height} ($name).',
        );
      }

      Future<void> direct(String value) async {
        final field = find.byKey(const ValueKey('pdfPageEntry'));
        tester.testTextInput.unregister();
        tester.testTextInput.register();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.tap(field);
        await tester.pump();
        await tester.enterText(field, value);
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text, value);
        await tester.tap(find.byKey(const ValueKey('pdfGo')));
        await tester.pump();
      }

      try {
        Project create(String name) {
          Directory('${base.path}/$name').createSync();
          final now = DateTime.now().toUtc();
          final project = Project(
            id: const Uuid().v4(),
            name: name,
            locationClient: 'Synthetic',
            revision: '',
            estimator: 'Test',
            createdAt: now,
            updatedAt: now,
            safeFolderName: name,
            projectRootReference: base.path,
            projectDirectoryReference: name,
            folderCreatedAt: now,
          );
          projects.insert(project);
          return project;
        }

        late Project alpha, beta;
        late ManagedFile source;
        if (restart) {
          final prior = jsonDecode(
            File('${base.path}/restart-contract.json').readAsStringSync(),
          ) as Map<String, dynamic>;
          expect(prior['pid'], isNot(pid));
          alpha = projects.findById(prior['alpha'] as String)!;
          beta = projects.findById(prior['beta'] as String)!;
          source = files.get(alpha.id, prior['file'] as String);
          expect(source.fingerprint.sha256, originalHash);
          expect(
            SqlitePdfRepository(db).find(alpha.id, source.id)!.id,
            prior['index'],
          );
          note(
            'Full prior process ${prior['pid']} exited; current process $pid reopens same UUID, managed file and index.',
          );
          await tester.pumpWidget(
            wrap(
              PdfViewerPage(
                projectId: alpha.id,
                projectName: alpha.name,
                managedFileId: source.id,
                filename: source.name,
                service: pdf,
              ),
            ),
          );
          await raster(1, label: 'offline-reopened-page-1');
          await direct('19');
          await raster(19, label: 'offline-reopened-page-19');
        } else {
          expect(projects.getAll(), isEmpty);
          alpha = create('Alpha');
          beta = create('Beta');
          await tester.pumpWidget(
            wrap(
              ProjectFilesPage(
                project: alpha,
                service: imports,
                picker: _Picker(sample),
                pdf: pdf,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('selectSourceFile')));
          await until(
            () => files
                .list(alpha.id)
                .any((f) => f.state == ManagedFileState.ready),
          );
          await until(
            () => find
                .byKey(ValueKey('viewPdf-${files.list(alpha.id).single.id}'))
                .evaluate()
                .isNotEmpty,
          );
          source = files.list(alpha.id).single;
          expect(source.fingerprint.sha256, originalHash);
          await tester.ensureVisible(
            find.byKey(ValueKey('viewPdf-${source.id}')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('viewPdf-${source.id}')));
          await raster(1);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(const ValueKey('pdfPrevious')),
                )
                .onPressed,
            isNull,
          );
          await direct('10');
          await raster(10);
          await direct('19');
          await raster(19);
          expect(
            tester
                .widget<OutlinedButton>(find.byKey(const ValueKey('pdfNext')))
                .onPressed,
            isNull,
          );
          await direct('999');
          await raster(19, label: 'clamped-page-19');
          expect(find.textContaining('outside'), findsOneWidget);
          await direct('1.5');
          expect(find.textContaining('whole'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('pdfFirst')));
          await raster(1, label: 'first-boundary');
          await tester.tap(find.byKey(const ValueKey('pdfZoomIn')));
          await raster(1, label: 'zoom-115');
          expect(find.text('115%'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('pdfZoomOut')));
          await raster(1, label: 'zoom-100');
          await tester.tap(find.byKey(const ValueKey('pdfFitWidth')));
          await raster(1, label: 'fit-width');
          await tester.tap(find.byKey(const ValueKey('pdfNext')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('pdfNext')));
          await tester.pump();
          await direct('19');
          await raster(19, label: 'rapid-latest-19');
          note(
            'Direct entry, invalid entry, visible clamp, boundaries, zoom, fit and rapid navigation passed.',
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            wrap(
              ProjectFilesPage(
                project: beta,
                service: imports,
                picker: _Picker(sample),
                pdf: pdf,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('No managed files recorded.'), findsOneWidget);
          expect(find.byKey(const ValueKey('pdfRaster')), findsNothing);
          await tester.pumpWidget(
            wrap(
              PdfViewerPage(
                projectId: beta.id,
                projectName: beta.name,
                managedFileId: source.id,
                filename: source.name,
                service: pdf,
              ),
            ),
          );
          await until(
            () => find.byKey(const ValueKey('pdfError')).evaluate().isNotEmpty,
          );
          expect(find.textContaining('does not belong'), findsOneWidget);
          expect(find.byKey(const ValueKey('pdfRaster')), findsNothing);
          await tester.pumpWidget(wrap(const SizedBox()));
          await tester.pumpAndSettle();
          final fixture = p.normalize(
            File('test/fixtures/pdf/geometry.pdf').absolute.path,
          );
          final geometry = (await imports.importFile(alpha.id, fixture)).file!;
          final geo = await pdf.open(
            alpha.id,
            geometry.id,
            RenderCancellation(),
          );
          for (final page in geo.index.pages) {
            final r = await geo.document.render(
              page.number,
              1,
              RenderCancellation(),
            );
            try {
              expect(r.width > 0 && r.height > 0, isTrue);
              note(
                'Synthetic geometry ${page.number}: ${page.width}x${page.height}, rotation ${page.rotation}.',
              );
            } finally {
              r.dispose();
            }
          }
          await geo.dispose();
          final managed = File('${base.path}/Alpha/${geometry.relativePath}');
          final bytes = managed.readAsBytesSync();
          managed.deleteSync();
          await expectLater(
            pdf.open(alpha.id, geometry.id, RenderCancellation()),
            throwsA(
              isA<PdfFailure>().having(
                (e) => e.kind,
                'missing',
                PdfFailureKind.missingFile,
              ),
            ),
          );
          managed.writeAsStringSync('Changed disposable fixture');
          await expectLater(
            pdf.open(alpha.id, geometry.id, RenderCancellation()),
            throwsA(
              isA<PdfFailure>().having(
                (e) => e.kind,
                'changed',
                PdfFailureKind.changedSource,
              ),
            ),
          );
          managed.writeAsBytesSync(bytes);
          final restored = await pdf.open(
            alpha.id,
            geometry.id,
            RenderCancellation(),
          );
          await restored.dispose();
          note(
            'Missing/changed disposable source errors and exact-byte recovery passed.',
          );
          File('${base.path}/restart-contract.json').writeAsStringSync(
            jsonEncode({
              'pid': pid,
              'alpha': alpha.id,
              'beta': beta.id,
              'file': source.id,
              'index': SqlitePdfRepository(db).find(alpha.id, source.id)!.id,
              'sourceHash': originalHash,
            }),
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(files.list(beta.id), isEmpty);
        expect(Directory('${base.path}/Beta').listSync(), isEmpty);
        expect(
          sha256.convert(File(sample).readAsBytesSync()).toString(),
          originalHash,
        );
        expect(
          sha256
              .convert(
                File('${base.path}/Alpha/${source.relativePath}')
                    .readAsBytesSync(),
              )
              .toString(),
          originalHash,
        );
        expect(offline.attempts, 0);
        expect(db.database.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          db.database.select('PRAGMA integrity_check').single.values.single,
          'ok',
        );
        File('${evidence.path}/native-evidence.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'pid': pid,
            'restart': restart,
            'sampleHash': originalHash,
            'httpDenied': true,
            'httpAttempts': offline.attempts,
            'checkpoints': checkpoints,
            'rasters': metrics,
            'schema': db.userVersion,
            for (final t in [
              'projects',
              'managed_files',
              'pdf_documents',
              'pdf_pages',
            ])
              t: db.database
                  .select('SELECT * FROM $t')
                  .map((r) => Map<String, Object?>.from(r))
                  .toList(),
          }),
        );
        note(
          'Protected Sample and managed copy hashes unchanged; Beta isolated; SQLite healthy; HTTP attempts zero.',
        );
        debugPrint('PHASE5_NATIVE_EVIDENCE=${evidence.path}');
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        db.close();
        HttpOverrides.global = priorHttp;
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

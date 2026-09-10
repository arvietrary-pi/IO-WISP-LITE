import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/domain/document_register.dart';
import 'package:io_wisp_app/domain/sheet_detector.dart';

DetectedRegisterEntry detected({
  required int page,
  String sheet = 'A01.01',
  String revision = 'A',
  bool readable = true,
  List<String> references = const [],
}) => DetectedRegisterEntry(
  physicalPage: page,
  sheetNumber: sheet,
  title: 'Floor Plan',
  discipline: 'Architectural',
  revision: revision,
  scale: '1:100',
  drawingDate: '',
  summary: 'Floor Plan covering dimensions and setting out.',
  evidence: sheet,
  titleBlockText: sheet,
  textSample: sheet,
  candidates: sheet.isEmpty ? const [] : [sheet],
  references: references,
  diagnostics: readable ? const [] : const [PageDiagnostic.noReadableText],
  status: sheet.isEmpty || !readable
      ? RegisterEntryStatus.review
      : RegisterEntryStatus.ready,
  confidence: sheet.isEmpty || !readable ? 'low' : 'high',
  textItemCount: readable ? 2 : 0,
  lineCount: readable ? 1 : 0,
  hasReadableText: readable,
);

DocumentRegisterEntry entry({
  required int page,
  String sheet = 'A01.01',
  String revision = 'A',
  bool readable = true,
  List<String> references = const [],
  RegisterReviewState review = RegisterReviewState.reviewed,
  DocumentState state = DocumentState.current,
}) => DocumentRegisterEntry(
  registerId: 'register',
  detected: detected(
    page: page,
    sheet: sheet,
    revision: revision,
    readable: readable,
    references: references,
  ),
  reviewState: review,
  documentState: state,
);

DocumentRegister register({
  required String id,
  required String file,
  required String fingerprint,
  required List<DocumentRegisterEntry> entries,
}) => DocumentRegister(
  id: id,
  projectId: 'project',
  managedFileId: file,
  sourceFilename: '$file.pdf',
  fingerprint: fingerprint,
  detectorVersion: SheetDetector.version,
  analyzedAt: DateTime.utc(2026),
  entries: entries,
);

void main() {
  group('V0.0.5 deterministic detector', () {
    test('ports all rule catalogs and exact title-block boundary', () {
      expect(SheetDetector.titleRules, hasLength(30));
      expect(SheetDetector.topics, hasLength(10));
      const detector = SheetDetector();
      const page = PositionalTextPage(
        physicalPage: 1,
        width: 100,
        height: 100,
        rotation: 0,
        items: [
          PositionalTextItem(
            text: 'A99.99 floor plan',
            x: 40,
            y: 62,
            width: 30,
            height: 6,
          ),
        ],
      );
      final result = detector.detect(page);
      expect(result.sheetNumber, 'A99.99');
      expect(result.title, 'Floor Plan');
      expect(result.titleBlockText, contains('A99.99'));
      expect(result.status, RegisterEntryStatus.ready);
    });

    test('preserves the exact PDF-point line clustering tolerance', () {
      const detector = SheetDetector();
      const page = PositionalTextPage(
        physicalPage: 1,
        width: 200,
        height: 100,
        rotation: 0,
        items: [
          PositionalTextItem(
            text: 'A01.02',
            x: 100,
            y: 90,
            width: 30,
            height: 10,
          ),
          PositionalTextItem(
            text: 'site plan',
            x: 132,
            y: 94.8,
            width: 40,
            height: 10,
          ),
          PositionalTextItem(
            text: 'separate',
            x: 100,
            y: 99.61,
            width: 30,
            height: 10,
          ),
        ],
      );
      final result = detector.detect(page);
      // 10 * .48 = 4.8 points: the first two fragments cluster; the third does not.
      expect(result.lineCount, 2);
      expect(result.sheetNumber, 'A01.02');
    });

    test('emits all five page diagnostics deterministically', () {
      const detector = SheetDetector();
      const blank = PositionalTextPage(
        physicalPage: 1,
        width: 100,
        height: 100,
        rotation: 0,
        items: [],
      );
      final blankResult = detector.detect(blank);
      expect(blankResult.diagnostics, contains(PageDiagnostic.noReadableText));
      expect(blankResult.diagnostics, contains(PageDiagnostic.noSheetNumber));
      expect(blankResult.diagnostics, contains(PageDiagnostic.noTitleKeyword));

      const noBlock = PositionalTextPage(
        physicalPage: 2,
        width: 100,
        height: 100,
        rotation: 0,
        items: [
          PositionalTextItem(
            text: 'A01.01 floor plan A02.02',
            x: 5,
            y: 10,
            width: 70,
            height: 5,
          ),
        ],
      );
      final result = detector.detect(noBlock);
      expect(result.diagnostics, contains(PageDiagnostic.noTitleBlock));
      expect(
        result.diagnostics,
        contains(PageDiagnostic.multipleSheetCandidates),
      );
    });
  });

  test('manual values resolve over detected without mutating detection', () {
    final original = entry(page: 1);
    final overridden = DocumentRegisterEntry(
      registerId: original.registerId,
      detected: original.detected,
      manualSheetNumber: '',
      manualTitle: 'Estimator title',
      manualDiscipline: 'Structural',
      manualRevision: 'B',
      manualScale: 'NTS',
      manualDrawingDate: '2026-09-05',
      notes: 'Checked against addendum.',
      reviewState: RegisterReviewState.signedOff,
      signedOffAt: DateTime.utc(2026, 9, 5),
      signedOffBy: 'Estimator',
    );
    expect(overridden.sheetNumber, '');
    expect(overridden.title, 'Estimator title');
    expect(overridden.detected.sheetNumber, 'A01.01');
  });

  test('implements all nine cross-drawing document-control flag types', () {
    final current = register(
      id: 'one',
      file: 'one',
      fingerprint: List.filled(64, 'a').join(),
      entries: [
        entry(
          page: 1,
          sheet: '',
          revision: '',
          readable: false,
          review: RegisterReviewState.unreviewed,
          references: const ['A09.99', 'A02.02'],
        ),
        entry(page: 2, sheet: 'A01.01', revision: 'A'),
        entry(page: 3, sheet: 'A01.01', revision: 'B'),
        entry(page: 4, sheet: 'A02.02', state: DocumentState.superseded),
      ],
    );
    final duplicateSource = register(
      id: 'two',
      file: 'two',
      fingerprint: List.filled(64, 'a').join(),
      entries: [entry(page: 1, sheet: 'A03.01')],
    );
    final types = const DocumentControlAnalyzer()
        .analyze([current, duplicateSource])
        .map((flag) => flag.type)
        .toSet();
    expect(types, containsAll(DocumentControlFlagType.values));
  });

  final focusedFlagCases =
      <(String, DocumentControlFlagType, List<DocumentRegister>)>[
        (
          'missing sheet numbers',
          DocumentControlFlagType.missingSheetNumbers,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '1').join(),
              entries: [entry(page: 1, sheet: '')],
            ),
          ],
        ),
        (
          'duplicate sheet numbers',
          DocumentControlFlagType.duplicateSheetNumbers,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '2').join(),
              entries: [entry(page: 1), entry(page: 2)],
            ),
          ],
        ),
        (
          'missing revisions',
          DocumentControlFlagType.missingRevisions,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '3').join(),
              entries: [entry(page: 1, revision: '')],
            ),
          ],
        ),
        (
          'mixed revisions',
          DocumentControlFlagType.mixedRevisions,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '4').join(),
              entries: [
                entry(page: 1, sheet: 'A01', revision: 'A'),
                entry(page: 2, sheet: 'A02', revision: 'B'),
              ],
            ),
          ],
        ),
        (
          'referenced drawings not provided',
          DocumentControlFlagType.referencedDrawingsNotProvided,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '5').join(),
              entries: [
                entry(page: 1, references: const ['A99.99']),
              ],
            ),
          ],
        ),
        (
          'superseded drawings still referenced',
          DocumentControlFlagType.supersededDrawingsReferenced,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '6').join(),
              entries: [
                entry(page: 1, sheet: 'A01', references: const ['A02']),
                entry(page: 2, sheet: 'A02', state: DocumentState.superseded),
              ],
            ),
          ],
        ),
        (
          'unreviewed pages',
          DocumentControlFlagType.unreviewedPages,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '7').join(),
              entries: [entry(page: 1, review: RegisterReviewState.unreviewed)],
            ),
          ],
        ),
        (
          'blank unreadable text',
          DocumentControlFlagType.blankUnreadableText,
          [
            register(
              id: 'r',
              file: 'f',
              fingerprint: List.filled(64, '8').join(),
              entries: [entry(page: 1, readable: false)],
            ),
          ],
        ),
        (
          'duplicate source documents',
          DocumentControlFlagType.duplicateSourceDocuments,
          [
            register(
              id: 'r1',
              file: 'f1',
              fingerprint: List.filled(64, '9').join(),
              entries: [entry(page: 1, sheet: 'A01')],
            ),
            register(
              id: 'r2',
              file: 'f2',
              fingerprint: List.filled(64, '9').join(),
              entries: [entry(page: 1, sheet: 'A02')],
            ),
          ],
        ),
      ];
  for (final flagCase in focusedFlagCases) {
    test('focused flag: ${flagCase.$1}', () {
      final types = const DocumentControlAnalyzer()
          .analyze(flagCase.$3)
          .map((flag) => flag.type);
      expect(types, contains(flagCase.$2));
    });
  }
}

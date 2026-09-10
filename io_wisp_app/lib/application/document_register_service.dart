import '../data/register/sqlite_register_repository.dart';
import '../domain/document_register.dart';
import '../domain/pdf_document.dart';
import '../domain/sheet_detector.dart';

class DocumentRegisterService {
  DocumentRegisterService({
    required this.repository,
    required this.pdf,
    this.detector = const SheetDetector(),
  });

  final SqliteRegisterRepository repository;
  final PdfDocumentService pdf;
  final SheetDetector detector;
  bool _analyzing = false;

  DocumentRegister? load(String projectId, String managedFileId) =>
      repository.find(projectId, managedFileId);

  List<DocumentRegister> registers(String projectId) =>
      repository.listProject(projectId);

  Iterable<String> disciplines(String projectId) => repository
      .listProject(projectId)
      .expand((register) => register.entries)
      .where((entry) => entry.documentState == DocumentState.current)
      .map((entry) => entry.discipline.trim())
      .where((value) => value.isNotEmpty && value.toLowerCase() != 'unknown')
      .toSet();

  List<DocumentControlFlag> flags(String projectId) =>
      const DocumentControlAnalyzer().analyze(
        repository.listProject(projectId),
      );

  Future<DocumentRegister> analyze(
    String projectId,
    String managedFileId,
  ) async {
    if (_analyzing) {
      throw const RegisterPersistenceException(
        'A Document Register analysis is already running.',
      );
    }
    _analyzing = true;
    PdfSession? session;
    try {
      session = await pdf.open(projectId, managedFileId, RenderCancellation());
      final results = <DetectedRegisterEntry>[];
      for (final page in session.index.pages) {
        final extracted = await session.document.extractText(page.number);
        if (extracted.physicalPage != page.number) {
          throw const RegisterPersistenceException(
            'Text extraction returned the wrong physical PDF page.',
          );
        }
        results.add(detector.detect(extracted));
      }
      return repository.saveDetection(
        projectId: projectId,
        managedFileId: managedFileId,
        sourceFilename: session.file.name,
        fingerprint: session.file.fingerprint.sha256,
        detectorVersion: SheetDetector.version,
        entries: results,
      );
    } finally {
      await session?.dispose();
      _analyzing = false;
    }
  }

  DocumentRegister updateOverrides(
    String projectId,
    String managedFileId,
    int physicalPage,
    RegisterEntryOverrides overrides,
  ) => repository.updateOverrides(
    projectId,
    managedFileId,
    physicalPage,
    overrides,
  );

  DocumentRegister setReviewState(
    String projectId,
    String managedFileId,
    int physicalPage,
    RegisterReviewState state, {
    String? signedOffBy,
  }) => repository.setReviewState(
    projectId,
    managedFileId,
    physicalPage,
    state,
    signedOffBy: signedOffBy,
  );

  List<DocumentRegisterEntry> filter(
    DocumentRegister register, {
    String query = '',
    String? discipline,
    RegisterReviewState? reviewState,
    RegisterEntryStatus? status,
  }) {
    final normalized = query.trim().toLowerCase();
    return register.entries
        .where((entry) {
          final haystack = [
            entry.physicalPage.toString(),
            entry.sheetNumber,
            entry.title,
            entry.discipline,
            entry.revision,
            entry.detected.summary,
            entry.notes,
          ].join(' ').toLowerCase();
          return (normalized.isEmpty || haystack.contains(normalized)) &&
              (discipline == null || entry.discipline == discipline) &&
              (reviewState == null || entry.reviewState == reviewState) &&
              (status == null || entry.detected.status == status);
        })
        .toList(growable: false);
  }
}

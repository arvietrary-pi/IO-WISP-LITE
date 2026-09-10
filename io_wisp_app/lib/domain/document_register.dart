enum RegisterReviewState { unreviewed, reviewed, signedOff }

enum RegisterEntryStatus { ready, review }

enum DocumentState { current, superseded }

enum PageDiagnostic {
  noReadableText,
  noSheetNumber,
  noTitleKeyword,
  noTitleBlock,
  multipleSheetCandidates,
}

extension PageDiagnosticText on PageDiagnostic {
  String message({int candidateCount = 0}) => switch (this) {
    PageDiagnostic.noReadableText => 'No readable embedded text detected.',
    PageDiagnostic.noSheetNumber => 'No sheet number detected.',
    PageDiagnostic.noTitleKeyword => 'No drawing-title keyword detected.',
    PageDiagnostic.noTitleBlock =>
      'Title-block region not identified; full-page text used.',
    PageDiagnostic.multipleSheetCandidates =>
      '${candidateCount < 2 ? 'Multiple' : candidateCount} sheet-number candidates detected.',
  };
}

class PositionalTextItem {
  const PositionalTextItem({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String text;

  /// Oriented top-left PDF-point coordinates. [y] is the text baseline-like
  /// lower edge used by the V0.0.5 clustering and title-block rules.
  final double x, y, width, height;
}

class PositionalTextPage {
  const PositionalTextPage({
    required this.physicalPage,
    required this.width,
    required this.height,
    required this.rotation,
    required this.items,
  });

  final int physicalPage, rotation;
  final double width, height;
  final List<PositionalTextItem> items;
}

class DetectedRegisterEntry {
  const DetectedRegisterEntry({
    required this.physicalPage,
    required this.sheetNumber,
    required this.title,
    required this.discipline,
    required this.revision,
    required this.scale,
    required this.drawingDate,
    required this.summary,
    required this.evidence,
    required this.titleBlockText,
    required this.textSample,
    required this.candidates,
    required this.references,
    required this.diagnostics,
    required this.status,
    required this.confidence,
    required this.textItemCount,
    required this.lineCount,
    required this.hasReadableText,
  });

  final int physicalPage, textItemCount, lineCount;
  final String sheetNumber,
      title,
      discipline,
      revision,
      scale,
      drawingDate,
      summary,
      evidence,
      titleBlockText,
      textSample,
      confidence;
  final List<String> candidates, references;
  final List<PageDiagnostic> diagnostics;
  final RegisterEntryStatus status;
  final bool hasReadableText;
}

class DocumentRegisterEntry {
  const DocumentRegisterEntry({
    required this.registerId,
    required this.detected,
    this.manualSheetNumber,
    this.manualTitle,
    this.manualDiscipline,
    this.manualRevision,
    this.manualScale,
    this.manualDrawingDate,
    this.notes = '',
    this.reviewState = RegisterReviewState.unreviewed,
    this.signedOffAt,
    this.signedOffBy,
    this.documentState = DocumentState.current,
  });

  final String registerId;
  final DetectedRegisterEntry detected;
  final String? manualSheetNumber,
      manualTitle,
      manualDiscipline,
      manualRevision,
      manualScale,
      manualDrawingDate;
  final String notes;
  final RegisterReviewState reviewState;
  final DateTime? signedOffAt;
  final String? signedOffBy;
  final DocumentState documentState;

  int get physicalPage => detected.physicalPage;
  String get sheetNumber => manualSheetNumber ?? detected.sheetNumber;
  String get title => manualTitle ?? detected.title;
  String get discipline => manualDiscipline ?? detected.discipline;
  String get revision => manualRevision ?? detected.revision;
  String get scale => manualScale ?? detected.scale;
  String get drawingDate => manualDrawingDate ?? detected.drawingDate;

  DocumentRegisterEntry copyWith({
    String? Function()? manualSheetNumber,
    String? Function()? manualTitle,
    String? Function()? manualDiscipline,
    String? Function()? manualRevision,
    String? Function()? manualScale,
    String? Function()? manualDrawingDate,
    String? notes,
    RegisterReviewState? reviewState,
    DateTime? Function()? signedOffAt,
    String? Function()? signedOffBy,
    DocumentState? documentState,
  }) => DocumentRegisterEntry(
    registerId: registerId,
    detected: detected,
    manualSheetNumber: manualSheetNumber == null
        ? this.manualSheetNumber
        : manualSheetNumber(),
    manualTitle: manualTitle == null ? this.manualTitle : manualTitle(),
    manualDiscipline: manualDiscipline == null
        ? this.manualDiscipline
        : manualDiscipline(),
    manualRevision: manualRevision == null
        ? this.manualRevision
        : manualRevision(),
    manualScale: manualScale == null ? this.manualScale : manualScale(),
    manualDrawingDate: manualDrawingDate == null
        ? this.manualDrawingDate
        : manualDrawingDate(),
    notes: notes ?? this.notes,
    reviewState: reviewState ?? this.reviewState,
    signedOffAt: signedOffAt == null ? this.signedOffAt : signedOffAt(),
    signedOffBy: signedOffBy == null ? this.signedOffBy : signedOffBy(),
    documentState: documentState ?? this.documentState,
  );
}

class DocumentRegister {
  const DocumentRegister({
    required this.id,
    required this.projectId,
    required this.managedFileId,
    required this.sourceFilename,
    required this.fingerprint,
    required this.detectorVersion,
    required this.analyzedAt,
    required this.entries,
  });

  final String id,
      projectId,
      managedFileId,
      sourceFilename,
      fingerprint,
      detectorVersion;
  final DateTime analyzedAt;
  final List<DocumentRegisterEntry> entries;
}

class RegisterEntryOverrides {
  const RegisterEntryOverrides({
    this.sheetNumber,
    this.title,
    this.discipline,
    this.revision,
    this.scale,
    this.drawingDate,
    required this.notes,
    required this.documentState,
  });

  /// Null clears an override. Empty text is a deliberate blank override.
  final String? sheetNumber, title, discipline, revision, scale, drawingDate;
  final String notes;
  final DocumentState documentState;
}

enum DocumentControlFlagType {
  missingSheetNumbers,
  duplicateSheetNumbers,
  missingRevisions,
  mixedRevisions,
  referencedDrawingsNotProvided,
  supersededDrawingsReferenced,
  unreviewedPages,
  blankUnreadableText,
  duplicateSourceDocuments,
}

class DocumentControlFlag {
  const DocumentControlFlag(this.type, this.message, this.physicalPages);
  final DocumentControlFlagType type;
  final String message;
  final List<int> physicalPages;
}

class DocumentControlAnalyzer {
  const DocumentControlAnalyzer();

  List<DocumentControlFlag> analyze(List<DocumentRegister> registers) {
    final flags = <DocumentControlFlag>[];
    final entries = [for (final register in registers) ...register.entries];
    void add(
      DocumentControlFlagType type,
      String message,
      Iterable<DocumentRegisterEntry> affected,
    ) {
      final pages = affected.map((entry) => entry.physicalPage).toSet().toList()
        ..sort();
      if (pages.isNotEmpty) {
        flags.add(DocumentControlFlag(type, message, pages));
      }
    }

    add(
      DocumentControlFlagType.missingSheetNumbers,
      'Missing sheet numbers require estimator review.',
      entries.where((entry) => entry.sheetNumber.trim().isEmpty),
    );

    final sheets = <String, List<DocumentRegisterEntry>>{};
    for (final entry in entries) {
      final key = entry.sheetNumber.trim().toUpperCase();
      if (key.isNotEmpty) (sheets[key] ??= []).add(entry);
    }
    final duplicateSheets = sheets.entries.where(
      (group) => group.value.length > 1,
    );
    for (final group in duplicateSheets) {
      add(
        DocumentControlFlagType.duplicateSheetNumbers,
        'Duplicate sheet number ${group.key}.',
        group.value,
      );
    }

    add(
      DocumentControlFlagType.missingRevisions,
      'Missing revisions require estimator review.',
      entries.where((entry) => entry.revision.trim().isEmpty),
    );
    for (final register in registers) {
      final revisions = register.entries
          .map((entry) => entry.revision.trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      if (revisions.length > 1) {
        add(
          DocumentControlFlagType.mixedRevisions,
          'Mixed revisions detected within ${register.sourceFilename}.',
          register.entries.where((entry) => entry.revision.trim().isNotEmpty),
        );
      }
    }

    final provided = sheets.keys.toSet();
    final superseded = entries
        .where((entry) => entry.documentState == DocumentState.superseded)
        .map((entry) => entry.sheetNumber.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final entry in entries) {
      final missing = entry.detected.references
          .map((value) => value.toUpperCase())
          .where((value) => value != entry.sheetNumber.toUpperCase())
          .where((value) => value != entry.detected.sheetNumber.toUpperCase())
          .where((value) => !provided.contains(value))
          .toSet();
      if (missing.isNotEmpty) {
        add(
          DocumentControlFlagType.referencedDrawingsNotProvided,
          'Referenced drawing(s) not provided: ${missing.join(', ')}.',
          [entry],
        );
      }
      final old = entry.detected.references
          .map((value) => value.toUpperCase())
          .where((value) => value != entry.sheetNumber.toUpperCase())
          .where((value) => value != entry.detected.sheetNumber.toUpperCase())
          .where(superseded.contains)
          .toSet();
      if (old.isNotEmpty) {
        add(
          DocumentControlFlagType.supersededDrawingsReferenced,
          'Superseded drawing(s) still referenced: ${old.join(', ')}.',
          [entry],
        );
      }
    }

    add(
      DocumentControlFlagType.unreviewedPages,
      'Unreviewed pages remain in the register.',
      entries.where(
        (entry) => entry.reviewState == RegisterReviewState.unreviewed,
      ),
    );
    add(
      DocumentControlFlagType.blankUnreadableText,
      'Blank or unreadable embedded text requires manual attention.',
      entries.where((entry) => !entry.detected.hasReadableText),
    );

    final sources = <String, List<DocumentRegister>>{};
    for (final register in registers) {
      (sources[register.fingerprint] ??= []).add(register);
    }
    for (final group in sources.values.where((value) => value.length > 1)) {
      flags.add(
        DocumentControlFlag(
          DocumentControlFlagType.duplicateSourceDocuments,
          'Duplicate source documents share SHA-256 ${group.first.fingerprint}.',
          [
            for (final register in group)
              ...register.entries.map((e) => e.physicalPage),
          ],
        ),
      );
    }
    return List.unmodifiable(flags);
  }
}

import 'project.dart';

class ImportNameRules {
  static bool safeSegment(String value) =>
      FolderNamePolicy.isSafeFolderName(value) &&
      !RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(value);
  static String folderPart(String value) {
    var safe = FolderNamePolicy.sanitizeSegment(value);
    if (!safeSegment(safe)) safe = '_$safe';
    if (safe.length > 55) safe = safe.substring(0, 55);
    return safe.replaceAll(RegExp(r'[. ]+$'), '');
  }
}

enum FindingLevel { fatal, warning, information, deferred }

class ImportFinding {
  const ImportFinding(this.level, this.code, this.field, this.message);
  final FindingLevel level;
  final String code;
  final String field;
  final String message;
  String get acceptanceCode => '$code:$field';
}

class FieldMapping {
  const FieldMapping(
    this.source,
    this.destination,
    this.value,
    this.normalized,
  );
  final String source;
  final String destination;
  final String value;
  final bool normalized;
}

class ImportCandidate {
  ImportCandidate({
    required this.draft,
    required this.legacyId,
    required this.createdAt,
    required this.updatedAt,
    required List<FieldMapping> mappings,
  }) : mappings = List.unmodifiable(mappings);
  final ProjectDraft draft;
  final String? legacyId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<FieldMapping> mappings;
}

class LegacySource {
  LegacySource({
    required this.filename,
    required this.fingerprint,
    required this.byteCount,
    required this.format,
    required this.candidate,
    required List<ImportFinding> findings,
  }) : findings = List.unmodifiable(findings);
  final String filename;
  final String fingerprint;
  final int byteCount;
  final String format;
  final ImportCandidate? candidate;
  final List<ImportFinding> findings;
  bool get blocked =>
      candidate == null || findings.any((f) => f.level == FindingLevel.fatal);
}

enum DuplicateStatus { unrelated, exactSource, likelyProject, sameName }

enum ConflictDecision { undecided, skip, importSeparate }

class ImportPreview {
  ImportPreview({
    required this.source,
    required this.displayName,
    required this.folderName,
    required this.root,
    required this.duplicate,
    required List<String> matchingNames,
    required this.folderCollision,
    required this.stateToken,
    required this.date,
    required List<ImportFinding> findings,
  }) : matchingNames = List.unmodifiable(matchingNames),
       findings = List.unmodifiable(findings);
  final LegacySource source;
  final String displayName;
  final String folderName;
  final String root;
  final DuplicateStatus duplicate;
  final List<String> matchingNames;
  final bool folderCollision;
  final String stateToken;
  final DateTime date;
  final List<ImportFinding> findings;
  bool get blocked =>
      source.blocked || findings.any((f) => f.level == FindingLevel.fatal);
  bool get needsDecision =>
      duplicate == DuplicateStatus.likelyProject ||
      duplicate == DuplicateStatus.sameName;
}

class ImportProvenance {
  ImportProvenance({
    required this.projectId,
    required this.importedAt,
    required this.format,
    required this.fingerprint,
    required this.sourceFilename,
    required this.legacyId,
    required this.originalNormalizedName,
    required this.sourceByteCount,
    required List<String> acceptedWarnings,
  }) : acceptedWarnings = List.unmodifiable(acceptedWarnings);
  static const importerVersion = 'legacy-json/1';
  final String projectId;
  final DateTime importedAt;
  final String format;
  final String fingerprint;
  final String sourceFilename;
  final String? legacyId;
  final String originalNormalizedName;
  final int sourceByteCount;
  final List<String> acceptedWarnings;
}

enum ImportOutcome {
  completed,
  completedWithWarnings,
  skipped,
  failed,
  inconsistent,
}

class ImportResult {
  const ImportResult(this.outcome, this.message, {this.project});
  final ImportOutcome outcome;
  final String message;
  final Project? project;
}

abstract class LegacySourceReader {
  Future<LegacySource> read(String selectedPath);
}

abstract class LegacyFilePicker {
  Future<String?> selectJson();
}

abstract class ImportRepository {
  List<Project> projects();
  List<ImportProvenance> provenance();
  String get projectRoot;
  String? get activeProjectId;
  void save(
    Project project,
    ImportProvenance provenance, {
    required bool makeActive,
    required void Function() verifyBeforeCommit,
  });
  bool containsImport(String id, String fingerprint);
}

abstract class ImportFolderLease {
  String get root;
  String get name;
  bool verify();

  /// Delete by the held identity only. False means retained; never recursive.
  bool rollback();
  void close();
}

abstract class ImportFolderStore {
  /// Read-only. Must not create the configured root during preview.
  String propose(String root, String preferredName);
  ImportFolderLease create(String root, String exactName);
}

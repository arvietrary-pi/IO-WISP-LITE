import 'dart:typed_data';

import 'project.dart';
import 'legacy_import.dart';

enum ManagedFileState {
  importing,
  ready,
  missing,
  trashing,
  trashed,
  recoveryNeeded,
}

enum FileCollisionChoice { revision, newName, skip }

class FileFingerprint {
  const FileFingerprint(this.sha256, this.byteCount);
  final String sha256;
  final int byteCount;
  bool matches(FileFingerprint other) =>
      sha256 == other.sha256 && byteCount == other.byteCount;
}

class ManagedFile {
  const ManagedFile({
    required this.id,
    required this.projectId,
    required this.originalName,
    required this.name,
    required this.relativePath,
    required this.fingerprint,
    required this.importedAt,
    required this.state,
    this.revisionOf,
  });
  final String id, projectId, originalName, name, relativePath;
  final FileFingerprint fingerprint;
  final DateTime importedAt;
  final ManagedFileState state;
  final String? revisionOf;
  String get leaf => '$id--$name';
  String get stagingPath => 'imports/$id.part';
  ManagedFile withState(ManagedFileState value, {String? path}) => ManagedFile(
    id: id,
    projectId: projectId,
    originalName: originalName,
    name: name,
    relativePath: path ?? relativePath,
    fingerprint: fingerprint,
    importedAt: importedAt,
    state: value,
    revisionOf: revisionOf,
  );
}

class ManagedNameRules {
  static bool valid(String value) =>
      value.length <= 100 &&
      ImportNameRules.safeSegment(value) &&
      value.trim() == value;
  static void require(String value) {
    if (!valid(value)) {
      throw const FileImportException(
        'Use a safe filename of 1–100 characters, without paths or Windows device names.',
      );
    }
  }
}

class FileImportException implements Exception {
  const FileImportException(this.message, {this.recoveryNeeded = false});
  final String message;
  final bool recoveryNeeded;
  @override
  String toString() => message;
}

class FileNameConflict extends FileImportException {
  const FileNameConflict(this.existing)
    : super(
        'This filename already has different content. Choose a revision, a new name, or cancel.',
      );
  final ManagedFile existing;
}

class FileImportResult {
  const FileImportResult(
    this.file, {
    this.duplicate = false,
    this.skipped = false,
  });
  final ManagedFile? file;
  final bool duplicate, skipped;
}

abstract interface class SourceFilePicker {
  /// Transient platform selection token; never persisted in provenance.
  Future<String?> selectSource();
}

abstract interface class ReadOnlySource {
  String get basename;
  Future<FileFingerprint> fingerprint();
  Future<void> copyTo(OwnedManagedFile destination);
  void close();
}

abstract interface class OwnedManagedFile {
  void write(List<int> bytes);
  void flush();
  Future<FileFingerprint> fingerprint();

  /// Atomic, must fail if destination exists. Never replace.
  void moveTo(String relativePath);

  /// Only a newly created, still held file is eligible for rollback deletion.
  bool removeOwned();
  void close();
}

abstract interface class ProjectFileLease {
  void verify();
  void ensureLayout();
  OwnedManagedFile createStaging(String fileId);
  OwnedManagedFile? openManaged(String relativePath);
  void close();
}

/// Platform-neutral capability boundary. Implementations hold stable identities,
/// reject aliases/reparse escapes, and never recursively delete directories.
abstract interface class ProjectFileStore {
  ProjectFileLease openProject(Project project, Iterable<Project> allProjects);
  ReadOnlySource openSource(String selection);
}

/// Optional narrow capability for viewing an existing managed source. No writes,
/// path export, directory creation, move, or delete authority is returned.
abstract interface class ManagedReadLease implements ProjectFileLease {
  ManagedReadSource? openReadOnlyManaged(String relativePath);
}

abstract interface class ManagedReadSource {
  Future<FileFingerprint> fingerprint();
  int readAt(Uint8List buffer, int position, int size);
  void close();
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../domain/legacy_import.dart';
import '../domain/project.dart';

class LegacyImportService {
  LegacyImportService({
    required this.reader,
    required this.repository,
    required this.folders,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final LegacySourceReader reader;
  final ImportRepository repository;
  final ImportFolderStore folders;
  final DateTime Function() clock;
  ImportPreview? _issued;
  String? _selectedPath;
  bool _busy = false;

  void cancel() {
    if (_busy) return;
    _issued = null;
    _selectedPath = null;
  }

  String _stateToken() {
    final projects = repository.projects()
      ..sort((a, b) => a.id.compareTo(b.id));
    final provenance = repository.provenance()
      ..sort((a, b) => a.projectId.compareTo(b.projectId));
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              repository.projectRoot,
              repository.activeProjectId,
              projects
                  .map(
                    (p) => [
                      p.id,
                      p.name,
                      p.locationClient,
                      p.revision,
                      p.estimator,
                      p.updatedAt.toIso8601String(),
                      p.projectRootReference,
                      p.projectDirectoryReference,
                      p.status,
                    ],
                  )
                  .toList(),
              provenance
                  .map(
                    (p) => [
                      p.projectId,
                      p.fingerprint,
                      p.legacyId,
                      p.originalNormalizedName,
                    ],
                  )
                  .toList(),
            ]),
          ),
        )
        .toString();
  }

  static String preferredFolder(String name, String client, DateTime date) {
    return FolderNamePolicy.forProject(
      name: ImportNameRules.folderPart(name),
      locationClient: ImportNameRules.folderPart(client),
      date: date,
    );
  }

  Future<ImportPreview> preview(String selectedPath) async {
    if (_busy) throw StateError('An import is already running.');
    cancel();
    final source = await reader.read(selectedPath);
    final findings = [...source.findings];
    final projects = repository.projects();
    final provenance = repository.provenance();
    final candidate = source.candidate;
    var duplicate = DuplicateStatus.unrelated;
    final matches = <String>{};
    if (candidate != null && !source.blocked) {
      final originalName = ProjectNameRules.normalize(candidate.draft.name);
      for (final p in provenance) {
        if (p.fingerprint == source.fingerprint) {
          duplicate = DuplicateStatus.exactSource;
          matches.add(p.projectId);
        }
      }
      if (duplicate != DuplicateStatus.exactSource) {
        for (final p in provenance) {
          if ((candidate.legacyId != null &&
                  p.legacyId == candidate.legacyId) ||
              p.originalNormalizedName == originalName) {
            duplicate = DuplicateStatus.likelyProject;
            matches.add(p.projectId);
          }
        }
        for (final p in projects.where(
          (p) => p.normalizedName == originalName,
        )) {
          if (duplicate == DuplicateStatus.unrelated) {
            duplicate = DuplicateStatus.sameName;
          }
          matches.add(p.id);
        }
      }
    }
    var name = candidate?.draft.name ?? '';
    final used = projects.map((p) => p.normalizedName).toSet();
    for (
      var suffix = 2;
      used.contains(ProjectNameRules.normalize(name));
      suffix++
    ) {
      name = '${candidate!.draft.name} (import $suffix)';
    }
    if (candidate != null && name != candidate.draft.name) {
      findings.add(
        const ImportFinding(
          FindingLevel.information,
          'separate-name',
          'project.name',
          'The proposed separate project has an explicit name suffix to preserve Phase 1 duplicate-name protection.',
        ),
      );
    }
    final date = clock();
    final root = repository.projectRoot;
    var folder = '';
    var collision = false;
    if (!source.blocked) {
      final preferred = preferredFolder(
        name,
        candidate!.draft.locationClient,
        date,
      );
      try {
        folder = folders.propose(root, preferred);
        collision = folder != preferred;
        if (collision) {
          findings.add(
            const ImportFinding(
              FindingLevel.warning,
              'folder-collision',
              'folder',
              'An existing filesystem entry has the preferred name. The proposed unused suffix is shown; existing entries are left untouched.',
            ),
          );
        }
      } catch (_) {
        findings.add(
          const ImportFinding(
            FindingLevel.fatal,
            'destination',
            'folder',
            'Cannot safely use this project root. Use a short, ordinary local drive folder, without junctions or symbolic links, and refresh the preview.',
          ),
        );
      }
    }
    final result = ImportPreview(
      source: source,
      displayName: name,
      folderName: folder,
      root: root,
      duplicate: duplicate,
      matchingNames: projects
          .where((p) => matches.contains(p.id))
          .map((p) => p.name)
          .toList(),
      folderCollision: collision,
      stateToken: _stateToken(),
      date: date,
      findings: findings,
    );
    _selectedPath = selectedPath;
    _issued = result;
    return result;
  }

  Future<ImportResult> confirm(
    ImportPreview preview, {
    required bool confirmed,
    required bool acceptedFindings,
    required ConflictDecision decision,
    bool makeActive = true,
  }) async {
    if (_busy) {
      return const ImportResult(
        ImportOutcome.failed,
        'An import is already running.',
      );
    }
    if (!confirmed || !acceptedFindings) {
      return const ImportResult(
        ImportOutcome.failed,
        'Explicit confirmation and review of the findings are required. No changes made.',
      );
    }
    if (!identical(_issued, preview) || _selectedPath == null) {
      return const ImportResult(
        ImportOutcome.failed,
        'This preview was cancelled or replaced. Load the source again. No changes made.',
      );
    }
    if (preview.blocked) {
      return const ImportResult(
        ImportOutcome.failed,
        'Fatal validation findings block this import. No changes made.',
      );
    }
    if (preview.needsDecision && decision == ConflictDecision.undecided) {
      return const ImportResult(
        ImportOutcome.failed,
        'Choose Skip or Import as separate project. No changes made.',
      );
    }
    if (preview.duplicate == DuplicateStatus.exactSource ||
        decision == ConflictDecision.skip) {
      cancel();
      return const ImportResult(
        ImportOutcome.skipped,
        'Duplicate skipped. No project or folder was created.',
      );
    }
    _busy = true;
    ImportFolderLease? lease;
    var committed = false;
    Project? project;
    try {
      final fresh = await reader.read(_selectedPath!);
      if (fresh.blocked ||
          fresh.fingerprint != preview.source.fingerprint ||
          _stateToken() != preview.stateToken ||
          clock().difference(preview.date).abs() >
              const Duration(minutes: 15)) {
        return const ImportResult(
          ImportOutcome.failed,
          'The source, project state or preview age changed. Refresh the preview and review it again. No changes made.',
        );
      }
      final candidate = fresh.candidate!;
      final proposed = folders.propose(
        preview.root,
        preferredFolder(
          preview.displayName,
          candidate.draft.locationClient,
          preview.date,
        ),
      );
      if (proposed != preview.folderName) {
        return const ImportResult(
          ImportOutcome.failed,
          'The folder preview is stale. Refresh it before importing. No changes made.',
        );
      }
      final id = const Uuid().v4();
      lease = folders.create(preview.root, preview.folderName);
      final now = clock().toUtc();
      project = Project(
        id: id,
        name: preview.displayName,
        locationClient: candidate.draft.locationClient,
        revision: candidate.draft.revision,
        estimator: candidate.draft.estimator,
        createdAt: candidate.createdAt ?? now,
        updatedAt: candidate.updatedAt ?? candidate.createdAt ?? now,
        safeFolderName: lease.name,
        projectRootReference: lease.root,
        projectDirectoryReference: lease.name,
        folderCreatedAt: now,
      );
      final provenance = ImportProvenance(
        projectId: id,
        importedAt: now,
        format: fresh.format,
        fingerprint: fresh.fingerprint,
        sourceFilename: fresh.filename,
        legacyId: candidate.legacyId,
        sourceByteCount: fresh.byteCount,
        originalNormalizedName: ProjectNameRules.normalize(
          candidate.draft.name,
        ),
        acceptedWarnings: preview.findings
            .where(
              (f) =>
                  f.level == FindingLevel.warning ||
                  f.level == FindingLevel.deferred,
            )
            .map((f) => f.acceptanceCode)
            .toList(),
      );
      repository.save(
        project,
        provenance,
        makeActive: makeActive,
        verifyBeforeCommit: () {
          if (_stateToken() != preview.stateToken || !lease!.verify()) {
            throw StateError('Import state changed before commit.');
          }
        },
      );
      committed = true;
      if (!repository.containsImport(id, fresh.fingerprint) ||
          !lease.verify()) {
        return ImportResult(
          ImportOutcome.inconsistent,
          'Import needs attention: the database committed but the record and folder could not both be verified. Nothing was removed. Keep the source and inspect the project storage.',
          project: project,
        );
      }
      final warnings = provenance.acceptedWarnings.isNotEmpty;
      return ImportResult(
        warnings
            ? ImportOutcome.completedWithWarnings
            : ImportOutcome.completed,
        warnings
            ? 'Import completed with warnings. Project details and provenance saved; deferred data and referenced files were not migrated.'
            : 'Import completed. Project details, provenance and the new empty folder were verified.',
        project: project,
      );
    } catch (_) {
      if (committed) {
        return ImportResult(
          ImportOutcome.inconsistent,
          'The database committed but final verification failed. No folder was removed. Inspect project storage before trying again.',
          project: project,
        );
      }
      var removed = lease == null;
      try {
        if (lease != null) removed = lease.rollback();
      } catch (_) {
        removed = false;
      }
      return ImportResult(
        removed ? ImportOutcome.failed : ImportOutcome.inconsistent,
        removed
            ? 'Import failed and rolled back. No project record or new project folder remains. Check the configured root and database, then prepare a new preview.'
            : 'Import failed. The database was rolled back, but the new folder could not be removed safely (it may contain files). It was retained: ${lease!.root}\\${lease.name}. No existing folder was removed.',
      );
    } finally {
      lease?.close();
      _busy = false;
      cancel();
    }
  }
}

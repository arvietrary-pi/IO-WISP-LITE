import 'package:uuid/uuid.dart';

import '../domain/managed_file.dart';
import '../data/storage/sqlite_managed_file_repository.dart';

class ManagedFileService {
  ManagedFileService({required this.repository, required this.store});
  final SqliteManagedFileRepository repository;
  final ProjectFileStore store;
  bool _busy = false;

  ProjectFileLease _open(String projectId) =>
      store.openProject(repository.project(projectId), repository.projects);

  void _validateRecord(ManagedFile f) {
    ManagedNameRules.require(f.name);
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(f.id) ||
        !['sources/${f.leaf}', 'trash/${f.leaf}'].contains(f.relativePath)) {
      throw const FileImportException(
        'Stored file reference is unsafe. Recovery is required.',
        recoveryNeeded: true,
      );
    }
  }

  Future<ManagedFile> _inspect(ProjectFileLease lease, ManagedFile file) async {
    _validateRecord(file);
    if ([
      ManagedFileState.importing,
      ManagedFileState.trashing,
      ManagedFileState.recoveryNeeded,
    ].contains(file.state)) {
      return file.withState(ManagedFileState.recoveryNeeded);
    }
    OwnedManagedFile? held;
    try {
      held = lease.openManaged(file.relativePath);
      final state = held == null
          ? ManagedFileState.missing
          : !(await held.fingerprint()).matches(file.fingerprint)
          ? ManagedFileState.recoveryNeeded
          : file.relativePath.startsWith('trash/')
          ? ManagedFileState.trashed
          : ManagedFileState.ready;
      final result = file.withState(state);
      if (state != file.state) {
        repository.transaction(() => repository.updateState(result));
      }
      return result;
    } finally {
      held?.close();
    }
  }

  Future<List<ManagedFile>> list(String projectId) async {
    ProjectFileLease lease;
    try {
      lease = _open(projectId);
    } catch (_) {
      return repository
          .list(projectId)
          .map((f) => f.withState(ManagedFileState.recoveryNeeded))
          .toList();
    }
    try {
      final result = <ManagedFile>[];
      for (final file in repository.list(projectId)) {
        try {
          result.add(await _inspect(lease, file));
        } catch (_) {
          result.add(file.withState(ManagedFileState.recoveryNeeded));
        }
      }
      return result;
    } finally {
      lease.close();
    }
  }

  Future<FileImportResult> importFile(
    String projectId,
    String selection, {
    FileCollisionChoice? choice,
    String? newName,
    String? expectedConflictId,
  }) async {
    if (_busy) {
      throw const FileImportException('A file operation is already running.');
    }
    _busy = true;
    ProjectFileLease? lease;
    ReadOnlySource? source;
    OwnedManagedFile? staged;
    ManagedFile? pending;
    bool committed = false;
    try {
      lease = _open(projectId);
      repository.requireIdle(projectId);
      source = store.openSource(selection);
      ManagedNameRules.require(source.basename);
      final hash = await source.fingerprint();
      final existing = repository.list(projectId);
      for (final file in existing) {
        if (file.fingerprint.sha256 == hash.sha256) {
          final inspected = await _inspect(lease, file);
          return FileImportResult(inspected, duplicate: true);
        }
      }
      final collisions = existing
          .where((f) => f.name.toLowerCase() == source!.basename.toLowerCase())
          .toList();
      final conflict = collisions.isEmpty ? null : collisions.last;
      var name = source.basename;
      String? revisionOf;
      if (conflict != null) {
        if (choice == null || expectedConflictId != conflict.id) {
          throw FileNameConflict(conflict);
        }
        if (choice == FileCollisionChoice.skip) {
          return const FileImportResult(null, skipped: true);
        }
        if (choice == FileCollisionChoice.revision) {
          revisionOf = conflict.id;
        }
        if (choice == FileCollisionChoice.newName) {
          ManagedNameRules.require(newName ?? '');
          name = newName!;
          if (existing.any((f) => f.name.toLowerCase() == name.toLowerCase())) {
            throw const FileImportException(
              'That name is already used. Choose another safe name.',
            );
          }
        }
      } else if (choice != null) {
        throw const FileImportException(
          'The conflict changed. Select the source again.',
        );
      }
      lease.ensureLayout();
      final id = const Uuid().v4();
      final record = ManagedFile(
        id: id,
        projectId: projectId,
        originalName: source.basename,
        name: name,
        relativePath: 'sources/$id--$name',
        fingerprint: hash,
        importedAt: DateTime.now().toUtc(),
        state: ManagedFileState.importing,
        revisionOf: revisionOf,
      );
      repository.transaction(() {
        repository.requireIdle(projectId);
        // Any concurrent completed change invalidates our decisions.
        final now = repository.list(projectId);
        if (now.length != existing.length ||
            now.map((f) => '${f.id}:${f.state.name}').join() !=
                existing.map((f) => '${f.id}:${f.state.name}').join()) {
          throw const FileImportException(
            'Project file state changed. Select the source again.',
          );
        }
        repository.insert(record);
      });
      pending = record;
      staged = lease.createStaging(id);
      await source.copyTo(staged);
      staged.flush();
      if (!(await staged.fingerprint()).matches(hash) ||
          !(await source.fingerprint()).matches(hash)) {
        throw const FileImportException(
          'Source or copied bytes changed. Import was not finalized.',
        );
      }
      staged.moveTo(record.relativePath);
      lease.verify();
      final ready = record.withState(ManagedFileState.ready);
      repository.transaction(() => repository.updateState(ready));
      committed = true;
      return FileImportResult(ready);
    } catch (error) {
      if (pending != null && !committed) {
        // Held file identity is the only deletion authority; no path-based cleanup.
        bool removed = false;
        try {
          removed = staged == null || staged.removeOwned();
        } catch (_) {
          /* retain */
        }
        staged?.close();
        staged = null;
        if (removed) {
          try {
            repository.transaction(() => repository.removePending(pending!));
          } catch (_) {
            throw const FileImportException(
              'Import failed. Pending provenance remains; recovery is required.',
              recoveryNeeded: true,
            );
          }
        } else {
          throw const FileImportException(
            'Import failed. The operation-owned artifact and provenance were retained because safe cleanup could not be established. Recovery is required.',
            recoveryNeeded: true,
          );
        }
      }
      rethrow;
    } finally {
      staged?.close();
      source?.close();
      lease?.close();
      _busy = false;
    }
  }

  Future<ManagedFile> trash(String projectId, String fileId) async {
    if (_busy) {
      throw const FileImportException('A file operation is already running.');
    }
    _busy = true;
    ProjectFileLease? lease;
    OwnedManagedFile? held;
    ManagedFile? original;
    bool journaled = false, moved = false;
    try {
      lease = _open(projectId);
      repository.requireIdle(projectId);
      original = repository.get(projectId, fileId);
      _validateRecord(original);
      if (original.state != ManagedFileState.ready) {
        throw const FileImportException(
          'Only an available managed source can be moved to trash.',
        );
      }
      held = lease.openManaged(original.relativePath);
      if (held == null) {
        final missing = original.withState(ManagedFileState.missing);
        repository.transaction(() => repository.updateState(missing));
        throw const FileImportException(
          'Managed file is missing. Provenance was preserved.',
        );
      }
      if (!(await held.fingerprint()).matches(original.fingerprint)) {
        throw const FileImportException(
          'Managed bytes changed. File retained for review.',
          recoveryNeeded: true,
        );
      }
      lease.ensureLayout();
      repository.transaction(() {
        repository.requireIdle(projectId);
        repository.updateState(original!.withState(ManagedFileState.trashing));
      });
      journaled = true;
      final trashed = original.withState(
        ManagedFileState.trashed,
        path: 'trash/${original.leaf}',
      );
      held.moveTo(trashed.relativePath);
      moved = true;
      lease.verify();
      repository.transaction(() => repository.updateState(trashed));
      return trashed;
    } catch (_) {
      if (journaled) {
        try {
          if (moved) held!.moveTo(original!.relativePath);
          repository.transaction(() => repository.updateState(original!));
        } catch (_) {
          throw const FileImportException(
            'Trash operation needs recovery. File and provenance retained; nothing was deleted.',
            recoveryNeeded: true,
          );
        }
      }
      rethrow;
    } finally {
      held?.close();
      lease?.close();
      _busy = false;
    }
  }
}

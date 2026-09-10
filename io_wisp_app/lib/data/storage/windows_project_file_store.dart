part of '../import/windows_import_folders.dart';

/// Shares Phase 2's handle-relative ancestor traversal and NT create primitive.
class WindowsProjectFileStore implements ProjectFileStore {
  final WindowsImportFolders _folders = WindowsImportFolders();
  late final _FileApi _files = _FileApi(_folders._api);

  String _location(Project project) {
    if (project.projectRootReference.split(RegExp(r'[\\/]')).contains('.')) {
      throw const FileImportException(
        'Relative path components are not allowed.',
      );
    }
    final root = _folders._root(project.projectRootReference);
    _folders._checkName(root, project.projectDirectoryReference);
    return p.windows.join(root, project.projectDirectoryReference);
  }

  @override
  ProjectFileLease openProject(Project project, Iterable<Project> allProjects) {
    final path = _location(project);
    final key = path.toLowerCase();
    for (final other in allProjects.where((v) => v.id != project.id)) {
      final otherKey = _location(other).toLowerCase();
      if (key == otherKey ||
          p.windows.isWithin(key, otherKey) ||
          p.windows.isWithin(otherKey, key)) {
        throw const FileImportException(
          'Projects have overlapping storage references. Recovery is required.',
          recoveryNeeded: true,
        );
      }
    }
    final handles = _folders._ancestors(
      _folders._root(project.projectRootReference),
      create: false,
      guarded: true,
    );
    if (handles.isEmpty) {
      throw const FileImportException('The project root is missing.');
    }
    try {
      final child = _folders._api.open(
        project.projectDirectoryReference,
        handles.last,
        disposition: 1,
        guarded: true,
      );
      handles.add(child);
      _folders._api.requireOrdinary(child);
      // Compare physical, normalized paths as well: DOS short-name aliases must
      // not give two UUIDs access to the same directory or nested directories.
      final physical = _files.finalPath(child).toLowerCase();
      for (final other in allProjects.where((v) => v.id != project.id)) {
        final otherHandles = _folders._ancestors(
          _location(other),
          create: false,
          guarded: true,
        );
        try {
          if (otherHandles.isEmpty) continue;
          final otherPhysical = _files
              .finalPath(otherHandles.last)
              .toLowerCase();
          if (physical == otherPhysical ||
              p.windows.isWithin(physical, otherPhysical) ||
              p.windows.isWithin(otherPhysical, physical)) {
            throw const FileImportException(
              'Projects refer to overlapping physical folders. Recovery is required.',
              recoveryNeeded: true,
            );
          }
        } finally {
          _folders._release(otherHandles);
        }
      }
      return _ProjectFiles(_folders, _files, path, handles);
    } catch (_) {
      _folders._release(handles);
      rethrow;
    }
  }

  @override
  ReadOnlySource openSource(String selection) {
    if (selection.split(RegExp(r'[\\/]')).contains('.')) {
      throw const FileImportException(
        'Relative path components are not allowed.',
      );
    }
    // Validate BEFORE normalization to prevent traversal or device-path aliases.
    final path = _folders._root(selection);
    final name = p.windows.basename(path);
    ManagedNameRules.require(name);
    final parents = _folders._ancestors(
      p.windows.dirname(path),
      create: false,
      guarded: true,
    );
    if (parents.isEmpty) {
      throw const FileImportException('Selected source is missing.');
    }
    int? handle;
    try {
      handle = _folders._api.open(
        name,
        parents.last,
        disposition: 1,
        file: true,
      );
      _files.requireFile(handle);
      return _Source(_files, handle, name, () => _folders._release(parents));
    } catch (_) {
      if (handle != null) _folders._api.closeHandle(handle);
      _folders._release(parents);
      rethrow;
    }
  }
}

class _ProjectFiles implements ManagedReadLease {
  _ProjectFiles(this.folders, this.api, this.path, this.handles);
  final WindowsImportFolders folders;
  final _FileApi api;
  final String path;
  final List<int> handles;
  final Map<String, int> dirs = {};
  bool closed = false;
  static const layout = ['sources', 'outputs', 'imports', 'trash'];

  void _live() {
    if (closed) throw const FileImportException('Storage lease is closed.');
    for (final h in [...handles, ...dirs.values]) {
      folders._api.requireOrdinary(h);
    }
  }

  int _directory(String name, {bool create = false}) {
    _live();
    if (!layout.contains(name)) {
      throw const FileImportException('Invalid managed directory.');
    }
    if (dirs.containsKey(name)) return dirs[name]!;
    final h = folders._api.open(
      name,
      handles.last,
      disposition: create ? 3 : 1,
      allowMissing: !create,
      guarded: true,
      // Native rename opens its destination directory for FILE_WRITE_DATA.
      // Deny delete/rename of this directory, allow that internal write open.
      // All operations stay handle-relative and recheck reparse attributes.
      shareWrite: true,
    );
    if (h == 0) return 0;
    try {
      folders._api.requireOrdinary(h);
      dirs[name] = h;
      return h;
    } catch (_) {
      folders._api.closeHandle(h);
      rethrow;
    }
  }

  List<String> _parts(String relative) {
    _live();
    final parts = relative.split('/');
    if (parts.length != 2 ||
        !layout.contains(parts[0]) ||
        !ImportNameRules.safeSegment(parts[1]) ||
        parts[1].length > 150 ||
        p.windows.join(path, parts[0], parts[1]).length > 248) {
      throw const FileImportException(
        'Unsafe or overlong managed file reference.',
      );
    }
    return parts;
  }

  @override
  void ensureLayout() {
    for (final name in layout) {
      _directory(name, create: true);
    }
  }

  @override
  void verify() => _live();

  @override
  OwnedManagedFile createStaging(String fileId) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(fileId)) {
      throw const FileImportException('Invalid managed file ID.');
    }
    final parts = _parts('imports/$fileId.part');
    final h = folders._api.open(
      parts[1],
      _directory(parts[0], create: true),
      disposition: 2,
      owned: true,
      file: true,
      writable: true,
    );
    return _OwnedFile(api, h, this, created: true);
  }

  @override
  OwnedManagedFile? openManaged(String relativePath) {
    final parts = _parts(relativePath);
    final dir = _directory(parts[0]);
    if (dir == 0) return null;
    final h = folders._api.open(
      parts[1],
      dir,
      disposition: 1,
      owned: true,
      file: true,
      allowMissing: true,
    );
    if (h == 0) return null;
    try {
      api.requireFile(h);
      return _OwnedFile(api, h, this, created: false);
    } catch (_) {
      folders._api.closeHandle(h);
      rethrow;
    }
  }

  @override
  ManagedReadSource? openReadOnlyManaged(String relativePath) {
    final parts = _parts(relativePath);
    if (parts[0] != 'sources') {
      throw const FileImportException('Only managed sources can be viewed.');
    }
    final dir = _directory(parts[0]);
    if (dir == 0) return null;
    final h = folders._api.open(
      parts[1],
      dir,
      disposition: 1,
      file: true,
      allowMissing: true,
    );
    if (h == 0) return null;
    try {
      api.requireFile(h);
      return _ManagedReader(api, h, this);
    } catch (_) {
      folders._api.closeHandle(h);
      rethrow;
    }
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    folders._release(dirs.values.toList());
    folders._release(handles);
  }
}

class _ManagedReader implements ManagedReadSource {
  _ManagedReader(this.api, this.handle, this.project);
  final _FileApi api;
  final int handle;
  final _ProjectFiles project;
  bool closed = false;
  void _live() {
    if (closed) throw const FileImportException('Source reader is closed.');
    project.verify();
  }

  @override
  Future<FileFingerprint> fingerprint() {
    _live();
    return api.fingerprint(handle);
  }

  @override
  int readAt(Uint8List buffer, int position, int size) {
    _live();
    if (position < 0 || size < 0 || size > buffer.length) {
      throw const FileImportException('Invalid source read range.');
    }
    return using((arena) {
      if (api._seek(handle, position, nullptr, 0) == 0) {
        throw const FileImportException('Cannot seek managed source.');
      }
      final chunk = arena<Uint8>(65536);
      final count = arena<Uint32>();
      var total = 0;
      while (total < size) {
        final remaining = size - total;
        if (api._read(
              handle,
              chunk,
              remaining < 65536 ? remaining : 65536,
              count,
              nullptr,
            ) ==
            0) {
          throw const FileImportException('Managed source read failed.');
        }
        if (count.value == 0) break;
        buffer.setRange(
          total,
          total + count.value,
          chunk.asTypedList(count.value),
        );
        total += count.value;
      }
      return total;
    });
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    api.directories.closeHandle(handle);
  }
}

class _Source implements ReadOnlySource {
  _Source(this.api, this.handle, this.basename, this.releaseParents);
  final _FileApi api;
  final int handle;
  @override
  final String basename;
  final void Function() releaseParents;
  bool closed = false;
  @override
  Future<FileFingerprint> fingerprint() => api.fingerprint(handle);
  @override
  Future<void> copyTo(OwnedManagedFile destination) =>
      api.readChunks(handle, destination.write);
  @override
  void close() {
    if (closed) return;
    closed = true;
    api.directories.closeHandle(handle);
    releaseParents();
  }
}

class _OwnedFile implements OwnedManagedFile {
  _OwnedFile(this.api, this.handle, this.project, {required this.created});
  final _FileApi api;
  final int handle;
  final _ProjectFiles project;
  final bool created;
  bool closed = false;
  @override
  void write(List<int> bytes) {
    if (!created || closed) {
      throw const FileImportException('Existing managed files are immutable.');
    }
    api.write(handle, bytes);
  }

  @override
  void flush() {
    if (closed || api.flush(handle) == 0) {
      throw const FileImportException('File flush failed.');
    }
  }

  @override
  Future<FileFingerprint> fingerprint() => api.fingerprint(handle);
  @override
  void moveTo(String relativePath) {
    if (closed) throw const FileImportException('File lease is closed.');
    final parts = project._parts(relativePath);
    api.rename(handle, project._directory(parts[0], create: true), parts[1]);
  }

  @override
  bool removeOwned() {
    if (!created || closed) return false;
    return using((arena) {
      final flag = arena<Int32>()..value = 1;
      return api.directories.setInfo(handle, 4, flag.cast(), 4) != 0;
    });
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    api.directories.closeHandle(handle);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _FileApi {
  _FileApi(this.directories);
  final _DirectoryApi directories;
  late final _finalPath = directories._kernel
      .lookupFunction<
        Uint32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32),
        int Function(int, Pointer<Utf16>, int, int)
      >('GetFinalPathNameByHandleW');
  String finalPath(int handle) => using((arena) {
    final buffer = arena<Uint16>(32768).cast<Utf16>();
    final size = _finalPath(handle, buffer, 32768, 0);
    if (size == 0 || size >= 32768) {
      throw const FileImportException(
        'Cannot establish physical project directory identity.',
      );
    }
    return buffer.toDartString(length: size);
  });
  late final _read = directories._kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile');
  late final _write = directories._kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');
  late final _seek = directories._kernel
      .lookupFunction<
        Int32 Function(IntPtr, Int64, Pointer<Int64>, Uint32),
        int Function(int, int, Pointer<Int64>, int)
      >('SetFilePointerEx');
  late final flush = directories._kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'FlushFileBuffers',
      );
  late final _set = directories._nt
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<_IoStatus>,
          Pointer<Void>,
          Uint32,
          Uint32,
        ),
        int Function(int, Pointer<_IoStatus>, Pointer<Void>, int, int)
      >('NtSetInformationFile');

  void requireFile(int h) {
    using((arena) {
      final attrs = arena<Uint32>(2);
      // FILE_STANDARD_INFO: NumberOfLinks at offset 16. Refuse hard-link aliases.
      final standard = arena<Uint8>(24);
      if (directories._getInfo(h, 9, attrs.cast(), 8) == 0 ||
          (attrs.value & (0x10 | 0x400)) != 0 ||
          directories._getInfo(h, 1, standard.cast(), 24) == 0 ||
          (standard + 16).cast<Uint32>().value != 1) {
        throw const FileImportException(
          'Expected an ordinary file without reparse points or hard links.',
        );
      }
    });
  }

  Future<void> readChunks(int h, void Function(List<int>) consume) async {
    if (_seek(h, 0, nullptr, 0) == 0) {
      throw const FileImportException('Cannot read file position.');
    }
    final bytes = calloc<Uint8>(65536);
    final count = calloc<Uint32>();
    try {
      while (true) {
        if (_read(h, bytes, 65536, count, nullptr) == 0) {
          throw const FileImportException('File read failed.');
        }
        if (count.value == 0) break;
        consume(bytes.asTypedList(count.value));
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      calloc.free(bytes);
      calloc.free(count);
    }
  }

  Future<FileFingerprint> fingerprint(int h) async {
    final result = _DigestSink();
    final sink = sha256.startChunkedConversion(result);
    var size = 0;
    await readChunks(h, (bytes) {
      sink.add(bytes);
      size += bytes.length;
    });
    sink.close();
    return FileFingerprint(result.value.toString(), size);
  }

  void write(int h, List<int> bytes) {
    using((arena) {
      final buffer = arena<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final count = arena<Uint32>();
      if (_write(h, buffer, bytes.length, count, nullptr) == 0 ||
          count.value != bytes.length) {
        throw const FileImportException(
          'Managed copy write failed or was incomplete.',
        );
      }
    });
  }

  void rename(int h, int targetDirectory, String name) {
    using((arena) {
      // FILE_RENAME_INFORMATION, native pointer alignment; ReplaceIfExists=FALSE.
      final offset = 2 * sizeOf<IntPtr>() + 4;
      final length = offset + name.length * 2;
      final data = arena<Uint8>(length + 2);
      (data + sizeOf<IntPtr>()).cast<IntPtr>().value = targetDirectory;
      (data + 2 * sizeOf<IntPtr>()).cast<Uint32>().value = name.length * 2;
      (data + offset)
          .cast<Uint16>()
          .asTypedList(name.length)
          .setAll(0, name.codeUnits);
      final status = arena<_IoStatus>();
      if (_set(h, status, data.cast(), length, 10) < 0) {
        throw const FileImportException(
          'Atomic file move failed; destination may already exist or be inaccessible.',
        );
      }
    });
  }
}

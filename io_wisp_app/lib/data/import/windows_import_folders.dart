import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

import '../../domain/legacy_import.dart';
import '../../domain/managed_file.dart';
import '../../domain/project.dart';

part '../storage/windows_project_file_store.dart';

// Windows-only adapter. NT directory create returns the new directory handle
// atomically (FILE_CREATE), unlike Directory.create's reuse-if-exists behavior.
// Every ancestor is held without share-write/delete until the operation ends.
// No path from imported JSON reaches this adapter.
class WindowsImportFolders implements ImportFolderStore {
  late final _DirectoryApi _api = _DirectoryApi();

  String _root(String root) {
    if (!Platform.isWindows) {
      throw const FileSystemException(
        'Windows folder adapter is unavailable on this platform.',
      );
    }
    // Phase 2 deliberately supports local drive roots only. No UNC/device paths.
    if (!RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(root) ||
        root.contains('..') ||
        root.contains('\u0000')) {
      throw const FileSystemException(
        'Import requires a local absolute Windows project root without traversal.',
      );
    }
    final normalized = p.windows.normalize(root);
    if (normalized.length > 220) {
      throw const FileSystemException(
        'Configured root is too long for safe project folders.',
      );
    }
    return normalized;
  }

  List<int> _ancestors(
    String root, {
    required bool create,
    bool guarded = false,
  }) {
    final handles = <int>[];
    try {
      final drive = root.substring(0, 3);
      handles.add(
        _api.open('\\??\\$drive', 0, disposition: 1, guarded: guarded),
      );
      _api.requireOrdinary(handles.last);
      for (final part
          in root.substring(3).split('\\').where((s) => s.isNotEmpty)) {
        if (!ImportNameRules.safeSegment(part)) {
          throw const FileSystemException(
            'Configured root contains an unsafe component.',
          );
        }
        final handle = _api.open(
          part,
          handles.last,
          disposition: create ? 3 : 1,
          allowMissing: !create,
          guarded: guarded,
        );
        if (handle == 0) {
          _release(handles);
          return [];
        }
        handles.add(handle);
        _api.requireOrdinary(handle);
      }
      return handles;
    } catch (_) {
      _release(handles);
      rethrow;
    }
  }

  void _release(List<int> handles) {
    for (final handle in handles.reversed) {
      _api.closeHandle(handle);
    }
  }

  void _checkName(String root, String name) {
    if (!ImportNameRules.safeSegment(name) ||
        name.length > 160 ||
        p.windows.join(root, name).length > 248) {
      throw const FileSystemException(
        'Proposed project folder is unsafe or too long. Choose a shorter configured root.',
      );
    }
  }

  @override
  String propose(String root, String preferredName) {
    final normalized = _root(root);
    _checkName(normalized, preferredName);
    final handles = _ancestors(normalized, create: false);
    try {
      if (handles.isEmpty) return preferredName;
      for (var suffix = 1; suffix <= 9999; suffix++) {
        final name = suffix == 1 ? preferredName : '$preferredName ($suffix)';
        _checkName(normalized, name);
        // Any entity (including a dangling link, junction or file) collides.
        if (FileSystemEntity.typeSync(
              p.windows.join(normalized, name),
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound) {
          return name;
        }
      }
      throw const FileSystemException(
        'No unused project folder name is available.',
      );
    } finally {
      _release(handles);
    }
  }

  @override
  ImportFolderLease create(String root, String exactName) {
    final normalized = _root(root);
    _checkName(normalized, exactName);
    final handles = _ancestors(normalized, create: true);
    try {
      final child = _api.open(
        exactName,
        handles.last,
        disposition: 2,
        owned: true,
      );
      return _WindowsFolderLease(_api, normalized, exactName, handles, child);
    } catch (_) {
      _release(handles);
      rethrow;
    }
  }
}

class _WindowsFolderLease implements ImportFolderLease {
  _WindowsFolderLease(
    this.api,
    this.root,
    this.name,
    this.ancestors,
    this.handle,
  );
  final _DirectoryApi api;
  @override
  final String root;
  @override
  final String name;
  final List<int> ancestors;
  final int handle;
  bool closed = false;
  @override
  bool verify() {
    if (closed) return false;
    try {
      api.requireOrdinary(handle);
      for (final ancestor in ancestors) {
        api.requireOrdinary(ancestor);
      }
      return Directory(p.windows.join(root, name)).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  @override
  bool rollback() {
    if (!verify()) return false;
    // Kernel deletion-by-handle refuses a nonempty directory and cannot target
    // a substitute directory with the same pathname. Never recursive.
    final flag = calloc<Int32>()..value = 1;
    try {
      return api.setInfo(handle, 4, flag.cast(), sizeOf<Int32>()) != 0;
    } finally {
      calloc.free(flag);
    }
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    api.closeHandle(handle);
    for (final parent in ancestors.reversed) {
      api.closeHandle(parent);
    }
  }
}

final class _UnicodeString extends Struct {
  @Uint16()
  external int length;
  @Uint16()
  external int maximumLength;
  external Pointer<Utf16> buffer;
}

final class _ObjectAttributes extends Struct {
  @Uint32()
  external int length;
  @IntPtr()
  external int rootDirectory;
  external Pointer<_UnicodeString> name;
  @Uint32()
  external int attributes;
  external Pointer<Void> securityDescriptor;
  external Pointer<Void> securityQuality;
}

final class _IoStatus extends Struct {
  @IntPtr()
  external int status;
  @UintPtr()
  external int information;
}

class _DirectoryApi {
  _DirectoryApi();
  final _nt = DynamicLibrary.open('ntdll.dll');
  final _kernel = DynamicLibrary.open('kernel32.dll');
  late final _create = _nt
      .lookupFunction<
        Int32 Function(
          Pointer<IntPtr>,
          Uint32,
          Pointer<_ObjectAttributes>,
          Pointer<_IoStatus>,
          Pointer<Int64>,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
        ),
        int Function(
          Pointer<IntPtr>,
          int,
          Pointer<_ObjectAttributes>,
          Pointer<_IoStatus>,
          Pointer<Int64>,
          int,
          int,
          int,
          int,
          Pointer<Void>,
          int,
        )
      >('NtCreateFile');
  late final closeHandle = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  late final setInfo = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('SetFileInformationByHandle');
  late final _getInfo = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('GetFileInformationByHandleEx');

  int open(
    String name,
    int parent, {
    required int disposition,
    bool owned = false,
    bool allowMissing = false,
    bool file = false,
    bool writable = false,
    bool guarded = false,
    bool shareWrite = false,
  }) {
    return using((arena) {
      final unicode = arena<_UnicodeString>();
      unicode.ref
        ..buffer = name.toNativeUtf16(allocator: arena)
        ..length = name.length * 2
        ..maximumLength = (name.length + 1) * 2;
      final attributes = arena<_ObjectAttributes>();
      attributes.ref
        ..length = sizeOf<_ObjectAttributes>()
        ..rootDirectory = parent
        ..name = unicode
        ..attributes = 0x40;
      final status = arena<_IoStatus>();
      final output = arena<IntPtr>();
      final result = _create(
        output,
        0x100080 |
            (owned ? 0x10000 : 0) |
            (file || guarded ? 1 : 0) |
            (writable ? 2 : 0),
        attributes,
        status,
        nullptr,
        file ? 0x80 : 0x10,
        file && owned ? 0 : (shareWrite ? 3 : 1),
        disposition,
        file ? 0x200060 : 0x200021,
        nullptr,
        0,
      );
      if (result < 0) {
        final code = result & 0xffffffff;
        if (allowMissing && (code == 0xc0000034 || code == 0xc000003a)) {
          return 0;
        }
        throw FileSystemException(
          code == 0xc0000035
              ? 'The proposed folder now exists. Refresh the preview.'
              : 'Cannot safely access the configured root or create the project folder (Windows status ${code.toRadixString(16)}).',
        );
      }
      return output.value;
    });
  }

  void requireOrdinary(int handle) {
    using((arena) {
      final info = arena<Uint32>(2);
      if (_getInfo(handle, 9, info.cast(), 8) == 0 ||
          (info.value & 0x10) == 0 ||
          (info.value & 0x400) != 0) {
        throw const FileSystemException(
          'A project-root component is a symbolic link, junction, reparse point or unreadable directory. Choose an ordinary local folder.',
        );
      }
    });
  }
}

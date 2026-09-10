import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/project.dart';

class ProjectDirectory {
  const ProjectDirectory({
    required this.rootPath,
    required this.folderName,
    required this.absolutePath,
  });

  final String rootPath;
  final String folderName;
  final String absolutePath;
}

abstract class ProjectStorage {
  Future<void> ensureRoot(String rootPath);

  Future<ProjectDirectory> createProjectDirectory({
    required String rootPath,
    required String preferredFolderName,
  });

  Future<bool> removeOwnedEmptyDirectory(ProjectDirectory directory);

  Future<void> openProjectDirectory({
    required String rootPath,
    required String directoryReference,
  });
}

class WindowsProjectStorage implements ProjectStorage {
  const WindowsProjectStorage();

  @override
  Future<void> ensureRoot(String rootPath) async {
    final normalizedRoot = _normalizedAbsolutePath(rootPath);
    await Directory(normalizedRoot).create(recursive: true);
  }

  @override
  Future<ProjectDirectory> createProjectDirectory({
    required String rootPath,
    required String preferredFolderName,
  }) async {
    if (!FolderNamePolicy.isSafeFolderName(preferredFolderName)) {
      throw const FileSystemException(
        'The generated project folder name is unsafe.',
      );
    }
    final normalizedRoot = _normalizedAbsolutePath(rootPath);
    await ensureRoot(normalizedRoot);

    for (var suffix = 1; suffix < 10000; suffix++) {
      final folderName = suffix == 1
          ? preferredFolderName
          : '$preferredFolderName ($suffix)';
      final candidate = _withinRoot(normalizedRoot, folderName);
      final directory = Directory(candidate);
      if (await directory.exists()) {
        continue;
      }
      try {
        await directory.create();
      } on FileSystemException {
        if (await directory.exists()) {
          continue;
        }
        rethrow;
      }
      return ProjectDirectory(
        rootPath: normalizedRoot,
        folderName: folderName,
        absolutePath: candidate,
      );
    }
    throw const FileSystemException(
      'Could not find an unused project folder name.',
    );
  }

  @override
  Future<bool> removeOwnedEmptyDirectory(ProjectDirectory directory) async {
    final normalizedRoot = _normalizedAbsolutePath(directory.rootPath);
    final candidate = _withinRoot(normalizedRoot, directory.folderName);
    if (p.normalize(candidate) != p.normalize(directory.absolutePath)) {
      return false;
    }
    final target = Directory(candidate);
    if (!await target.exists()) {
      return true;
    }
    try {
      final entries = await target.list(followLinks: false).toList();
      if (entries.isNotEmpty) {
        return false;
      }
      await target.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> openProjectDirectory({
    required String rootPath,
    required String directoryReference,
  }) async {
    final normalizedRoot = _normalizedAbsolutePath(rootPath);
    final candidate = _withinRoot(normalizedRoot, directoryReference);
    final directory = Directory(candidate);
    if (!await directory.exists()) {
      throw FileSystemException(
        'The project folder no longer exists.',
        candidate,
      );
    }
    await Process.start('explorer.exe', [candidate]);
  }

  String _normalizedAbsolutePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !p.isAbsolute(trimmed)) {
      throw const FileSystemException('Project root must be an absolute path.');
    }
    return p.normalize(Directory(trimmed).absolute.path);
  }

  String _withinRoot(String rootPath, String childName) {
    if (!FolderNamePolicy.isSafeFolderName(childName)) {
      throw const FileSystemException(
        'The project folder reference is unsafe.',
      );
    }
    final candidate = p.normalize(p.join(rootPath, childName));
    final root = p.normalize(rootPath);
    final rootPrefix = root.endsWith(p.separator)
        ? root
        : '$root${p.separator}';
    final comparableCandidate = candidate.toLowerCase();
    final comparableRoot = root.toLowerCase();
    final comparablePrefix = rootPrefix.toLowerCase();
    if (comparableCandidate != comparableRoot &&
        !comparableCandidate.startsWith(comparablePrefix)) {
      throw const FileSystemException(
        'The project folder would escape its root.',
      );
    }
    return candidate;
  }
}

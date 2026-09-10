import 'dart:io';

import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/import/windows_import_folders.dart';
import 'package:io_wisp_app/data/storage/sqlite_managed_file_repository.dart';
import 'package:io_wisp_app/application/managed_file_service.dart';
import 'package:io_wisp_app/domain/project.dart';
import 'package:io_wisp_app/domain/managed_file.dart';
import 'package:uuid/uuid.dart';

class FileTestContext {
  FileTestContext() {
    temp = Directory.systemTemp.createTempSync('wisp-f3-');
    db = AppDatabase.open('${temp.path}/app.sqlite');
    repository = SqliteManagedFileRepository(db);
    a = addProject('Alpha');
    b = addProject('Beta');
    service = ManagedFileService(repository: repository, store: store);
  }
  late Directory temp;
  late AppDatabase db;
  late SqliteManagedFileRepository repository;
  late ManagedFileService service;
  late Project a, b;
  final store = WindowsProjectFileStore();
  Project addProject(String name) {
    Directory('${temp.path}/$name').createSync();
    final now = DateTime.now().toUtc();
    final project = Project(
      id: const Uuid().v4(),
      name: name,
      locationClient: '',
      revision: '',
      estimator: '',
      createdAt: now,
      updatedAt: now,
      safeFolderName: name,
      projectRootReference: temp.path,
      projectDirectoryReference: name,
      folderCreatedAt: now,
    );
    SqliteProjectRepository(db).insert(project);
    return project;
  }

  File source(
    String text, {
    String name = 'source.pdf',
    String folder = 'external',
  }) {
    Directory('${temp.path}/$folder').createSync();
    return File('${temp.path}/$folder/$name')..writeAsStringSync(text);
  }

  File managed(ManagedFile file) => File(
    '${temp.path}/${file.projectId == a.id ? 'Alpha' : 'Beta'}/${file.relativePath}',
  );
  void reopen() {
    db.close();
    db = AppDatabase.open('${temp.path}/app.sqlite');
    repository = SqliteManagedFileRepository(db);
    service = ManagedFileService(repository: repository, store: store);
  }

  void close() {
    db.close();
    temp.deleteSync(recursive: true);
  }
}

/// Failure boundaries exercise the real native adapter underneath a contract proxy.
class FaultStore implements ProjectFileStore {
  FaultStore(this.inner, this.boundary);
  final ProjectFileStore inner;
  final String boundary;
  @override
  ProjectFileLease openProject(Project project, Iterable<Project> all) =>
      _FaultLease(inner.openProject(project, all), boundary);
  @override
  ReadOnlySource openSource(String selection) {
    if (boundary == 'permission') {
      throw const FileImportException('Simulated permission denial.');
    }
    return _FaultSource(inner.openSource(selection), boundary);
  }
}

class _FaultSource implements ReadOnlySource {
  _FaultSource(this.inner, this.boundary);
  final ReadOnlySource inner;
  final String boundary;
  int hashes = 0;
  @override
  String get basename => inner.basename;
  @override
  Future<FileFingerprint> fingerprint() async {
    final hash = await inner.fingerprint();
    if (boundary == 'sourceChanged' && hashes++ > 0) {
      return const FileFingerprint('changed', 0);
    }
    return hash;
  }

  @override
  Future<void> copyTo(OwnedManagedFile file) async {
    if (boundary == 'partial' || boundary == 'uncertain') {
      file.write([1, 2, 3]);
      throw const FileImportException('Interrupted copy.');
    }
    await inner.copyTo(file);
  }

  @override
  void close() => inner.close();
}

class _FaultLease implements ProjectFileLease {
  _FaultLease(this.inner, this.boundary);
  final ProjectFileLease inner;
  final String boundary;
  @override
  void ensureLayout() => inner.ensureLayout();
  @override
  void verify() => inner.verify();
  @override
  OwnedManagedFile createStaging(String id) {
    if (boundary == 'create') {
      throw const FileImportException('Staging create denied.');
    }
    return _FaultFile(inner.createStaging(id), boundary);
  }

  @override
  OwnedManagedFile? openManaged(String path) => inner.openManaged(path);
  @override
  void close() => inner.close();
}

class _FaultFile implements OwnedManagedFile {
  _FaultFile(this.inner, this.boundary);
  final OwnedManagedFile inner;
  final String boundary;
  @override
  void write(List<int> bytes) {
    if (boundary == 'write') throw const FileImportException('Disk full.');
    inner.write(bytes);
  }

  @override
  void flush() {
    if (boundary == 'flush') throw const FileImportException('Flush failed.');
    inner.flush();
  }

  @override
  Future<FileFingerprint> fingerprint() async => boundary == 'hash'
      ? const FileFingerprint('wrong', 0)
      : await inner.fingerprint();
  @override
  void moveTo(String path) {
    if (boundary == 'finalize') {
      throw const FileImportException('Finalize failed.');
    }
    inner.moveTo(path);
  }

  @override
  bool removeOwned() => boundary == 'uncertain' ? false : inner.removeOwned();
  @override
  void close() => inner.close();
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/projects/project_repository.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/domain/project.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late ProjectRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('io-wisp-repository-');
    database = AppDatabase.open(p.join(temp.path, 'io_wisp.sqlite'));
    repository = SqliteProjectRepository(database);
  });

  tearDown(() async {
    database.close();
    await temp.delete(recursive: true);
  });

  test('inserts, lists, and finds stable project records', () {
    final project = _project('project-1', 'First Project');
    repository.insert(project);

    expect(repository.getAll(), hasLength(1));
    expect(repository.findById(project.id)?.name, 'First Project');
    expect(repository.findByNormalizedName('first project')?.id, project.id);
    expect(repository.findById('missing'), isNull);
  });

  test('database uniqueness rejects duplicate normalized names', () {
    repository.insert(_project('project-1', 'First Project'));

    expect(
      () => repository.insert(_project('project-2', '  first   project ')),
      throwsA(isA<Exception>()),
    );
    expect(repository.getAll(), hasLength(1));
  });

  test('transaction rolls back project rows after a failure', () {
    expect(
      () => database.transaction(() {
        repository.insert(_project('project-1', 'First Project'));
        throw StateError('simulated transaction failure');
      }),
      throwsStateError,
    );
    expect(repository.getAll(), isEmpty);
  });

  test(
    'updates identity values without changing the UUID or folder reference',
    () {
      final original = _project('project-1', 'First Project');
      repository.insert(original);
      final updated = original.copyWith(
        name: 'Renamed Project',
        locationClient: 'Updated client',
        updatedAt: DateTime(2026, 9, 4).toUtc(),
      );
      repository.update(updated);

      final loaded = repository.findById(original.id)!;
      expect(loaded.name, 'Renamed Project');
      expect(loaded.locationClient, 'Updated client');
      expect(loaded.safeFolderName, original.safeFolderName);
      expect(loaded.id, original.id);
    },
  );
}

Project _project(String id, String name) {
  final now = DateTime(2026, 9, 3).toUtc();
  return Project(
    id: id,
    name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
    locationClient: 'Client',
    revision: 'Rev A',
    estimator: 'Estimator',
    createdAt: now,
    updatedAt: now,
    safeFolderName: '$name - 2026-09-03',
    projectRootReference: r'C:\Temp\IO WISP Projects',
    projectDirectoryReference: '$name - 2026-09-03',
    folderCreatedAt: now,
  );
}

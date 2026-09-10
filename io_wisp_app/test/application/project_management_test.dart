import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:io_wisp_app/application/project_management_service.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/projects/project_repository.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/settings/app_settings_repository.dart';
import 'package:io_wisp_app/data/storage/app_storage_paths.dart';
import 'package:io_wisp_app/data/storage/project_storage.dart';
import 'package:io_wisp_app/domain/project.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late ProjectRepository repository;
  late AppSettingsRepository settings;
  late ProjectManager manager;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('io-wisp-manager-');
    database = AppDatabase.open(p.join(temp.path, 'db', 'io_wisp.sqlite'));
    repository = SqliteProjectRepository(database);
    settings = SqliteAppSettingsRepository(database);
    manager = ProjectManager(
      database: database,
      projects: repository,
      settings: settings,
      paths: _TestPaths(temp.path),
      storage: const WindowsProjectStorage(),
    );
    manager.initialize();
  });

  tearDown(() async {
    database.close();
    await temp.delete(recursive: true);
  });

  test(
    'creates one record, one managed folder, and restores it as active',
    () async {
      final project = await manager.createProject(
        const ProjectDraft(
          name: 'Phase 1 Project',
          locationClient: 'Test Client',
          revision: 'Rev A',
          estimator: 'Arvie',
        ),
      );

      final state = manager.loadState();
      expect(state.projects, hasLength(1));
      expect(state.activeProject?.id, project.id);
      expect(state.activeProject?.name, 'Phase 1 Project');
      expect(await Directory(project.projectRootReference).exists(), isTrue);
      expect(
        await Directory(
          p.join(
            project.projectRootReference,
            project.projectDirectoryReference,
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'different display names with the same sanitized folder get a safe suffix',
    () async {
      final first = await manager.createProject(
        const ProjectDraft(
          name: 'A/B',
          locationClient: 'Client',
          revision: '',
          estimator: '',
        ),
      );
      final second = await manager.createProject(
        const ProjectDraft(
          name: 'A:B',
          locationClient: 'Client',
          revision: '',
          estimator: '',
        ),
      );

      expect(first.id, isNot(second.id));
      expect(second.safeFolderName, endsWith('(2)'));
      expect(repository.getAll(), hasLength(2));
    },
  );

  test('folder creation failure leaves the database unchanged', () async {
    final failingStorage = _FailingStorage();
    final failingManager = ProjectManager(
      database: database,
      projects: repository,
      settings: settings,
      paths: _TestPaths(temp.path),
      storage: failingStorage,
    )..initialize();

    await expectLater(
      failingManager.createProject(
        const ProjectDraft(
          name: 'Will Not Be Created',
          locationClient: '',
          revision: '',
          estimator: '',
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(repository.getAll(), isEmpty);
  });

  test('database failure cleans only the newly created empty folder', () async {
    final failingRepository = _FailingInsertRepository(repository);
    final failingManager = ProjectManager(
      database: database,
      projects: failingRepository,
      settings: settings,
      paths: _TestPaths(temp.path),
      storage: const WindowsProjectStorage(),
    )..initialize();

    await expectLater(
      failingManager.createProject(
        const ProjectDraft(
          name: 'Database Failure',
          locationClient: 'Test Client',
          revision: '',
          estimator: '',
        ),
      ),
      throwsA(isA<ProjectCreationException>()),
    );
    expect(repository.getAll(), isEmpty);
    final root = Directory(p.join(temp.path, 'projects'));
    expect(await root.exists(), isTrue);
    expect(await root.list().toList(), isEmpty);
  });

  void reopen() {
    final path = database.path;
    final closedConnection = database.database;
    database.close();
    expect(() => closedConnection.select('SELECT 1'), throwsStateError);
    database = AppDatabase.open(path);
    repository = SqliteProjectRepository(database);
    settings = SqliteAppSettingsRepository(database);
    manager = ProjectManager(
      database: database,
      projects: repository,
      settings: settings,
      paths: _TestPaths(temp.path),
      storage: const WindowsProjectStorage(),
    )..initialize();
  }

  test(
    'edited projects and active UUID survive closing and reopening SQLite',
    () async {
      final first = await manager.createProject(
        const ProjectDraft(
          name: 'First',
          locationClient: '',
          revision: 'A',
          estimator: 'E1',
        ),
      );
      final second = await manager.createProject(
        const ProjectDraft(
          name: 'Second',
          locationClient: '',
          revision: 'B',
          estimator: 'E2',
        ),
      );
      for (final project in [first, second]) {
        expect(
          project.id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
        await manager.updateProject(
          project.id,
          ProjectDraft(
            name: '${project.name} edited',
            locationClient: '${project.name} test client',
            revision: '${project.name} revised',
            estimator: '${project.name} test estimator',
          ),
        );
      }
      expect(first.id, isNot(second.id));
      manager.switchActiveProject(second.id);
      manager.switchActiveProject(first.id);
      final before = database.database
          .select('SELECT * FROM projects ORDER BY id')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      reopen();
      expect(
        database.database.select('SELECT * FROM projects ORDER BY id'),
        before,
      );
      expect(manager.loadState().projects, hasLength(2));
      expect(manager.loadState().activeProject?.id, first.id);
      expect(settings.getActiveProjectId(), first.id);
      for (final original in [first, second]) {
        final restored = repository.findById(original.id)!;
        expect(restored.name, '${original.name} edited');
        expect(restored.locationClient, '${original.name} test client');
        expect(restored.revision, '${original.name} revised');
        expect(restored.estimator, '${original.name} test estimator');
        expect(restored.createdAt, original.createdAt);
        expect(restored.projectRootReference, original.projectRootReference);
        expect(
          restored.projectDirectoryReference,
          original.projectDirectoryReference,
        );
        expect(restored.safeFolderName, original.safeFolderName);
        expect(restored.folderCreatedAt, original.folderCreatedAt);
        expect(
          await Directory(
            p.join(
              restored.projectRootReference,
              restored.projectDirectoryReference,
            ),
          ).exists(),
          isTrue,
        );
      }
      manager.switchActiveProject(second.id);
      reopen();
      expect(manager.loadState().activeProject?.id, second.id);
      expect(
        database.database.select('SELECT * FROM projects ORDER BY id'),
        before,
      );
    },
  );

  test(
    'root changes preserve old references and files across SQLite reopen',
    () async {
      final first = await manager.createProject(
        const ProjectDraft(
          name: 'Old root project',
          locationClient: 'Disposable client',
          revision: 'A',
          estimator: 'Test estimator',
        ),
      );
      final oldFolder = p.join(
        first.projectRootReference,
        first.projectDirectoryReference,
      );
      final sentinel = File(p.join(oldFolder, 'disposable-sentinel.txt'));
      await sentinel.writeAsString('Synthetic test data only.');
      final newRoot = p.join(temp.path, 'different project root with spaces');
      await manager.configureProjectRoot(newRoot);
      reopen();
      expect(manager.loadState().projectRoot, newRoot);
      expect(
        repository.findById(first.id)!.projectRootReference,
        first.projectRootReference,
      );
      final second = await manager.createProject(
        const ProjectDraft(
          name: 'New root project',
          locationClient: 'Other disposable client',
          revision: 'B',
          estimator: 'Other test estimator',
        ),
      );
      expect(second.projectRootReference, newRoot);
      await manager.updateProject(
        first.id,
        const ProjectDraft(
          name: 'Renamed old project',
          locationClient: 'Changed client',
          revision: 'C',
          estimator: 'Changed estimator',
        ),
      );
      manager.switchActiveProject(first.id);
      reopen();
      expect(manager.loadState().activeProject?.id, first.id);
      expect(manager.loadState().projectRoot, newRoot);
      expect(
        repository.findById(first.id)!.projectDirectoryReference,
        first.projectDirectoryReference,
      );
      expect(
        repository.findById(first.id)!.projectRootReference,
        first.projectRootReference,
      );
      expect(repository.findById(second.id)!.projectRootReference, newRoot);
      expect(await sentinel.readAsString(), 'Synthetic test data only.');
      expect(
        await Directory(p.join(newRoot, second.projectDirectoryReference))
            .exists(),
        isTrue,
      );
      expect(
        await Directory(p.join(newRoot, first.projectDirectoryReference))
            .exists(),
        isFalse,
      );
      await expectLater(
        manager.configureProjectRoot('relative-root'),
        throwsA(isA<FileSystemException>()),
      );
      reopen();
      expect(manager.loadState().projectRoot, newRoot);
      expect(manager.loadState().projects, hasLength(2));
    },
  );
}

class _TestPaths implements AppStoragePaths {
  _TestPaths(this.root);

  final String root;

  @override
  String get databasePath => p.join(root, 'db', 'io_wisp.sqlite');

  @override
  String get defaultProjectRoot => p.join(root, 'projects');
}

class _FailingStorage implements ProjectStorage {
  @override
  Future<ProjectDirectory> createProjectDirectory({
    required String rootPath,
    required String preferredFolderName,
  }) {
    return Future<ProjectDirectory>.error(
      const FileSystemException('simulated folder creation failure'),
    );
  }

  @override
  Future<void> ensureRoot(String rootPath) => Future.value();

  @override
  Future<bool> removeOwnedEmptyDirectory(ProjectDirectory directory) =>
      Future.value(true);

  @override
  Future<void> openProjectDirectory({
    required String rootPath,
    required String directoryReference,
  }) => Future.value();
}

class _FailingInsertRepository implements ProjectRepository {
  _FailingInsertRepository(this.delegate);

  final ProjectRepository delegate;

  @override
  List<Project> getAll() => delegate.getAll();

  @override
  Project? findById(String id) => delegate.findById(id);

  @override
  Project? findByNormalizedName(String normalizedName) =>
      delegate.findByNormalizedName(normalizedName);

  @override
  void insert(Project project) => throw StateError('simulated SQLite failure');

  @override
  void update(Project project) => delegate.update(project);
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:io_wisp_app/app.dart';
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
  late ProjectManager manager;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('io-wisp-widget-');
    database = AppDatabase.open(p.join(temp.path, 'io_wisp.sqlite'));
    repository = SqliteProjectRepository(database);
    manager = ProjectManager(
      database: database,
      projects: repository,
      settings: SqliteAppSettingsRepository(database),
      paths: _TestPaths(temp.path),
      storage: const _ImmediateStorage(),
    )..initialize();
  });

  tearDown(() async {
    database.close();
    await temp.delete(recursive: true);
  });

  testWidgets('uses the current textbox value at Create Project time', (
    tester,
  ) async {
    await tester.pumpWidget(IOWispApp(manager: manager));
    await tester.pumpAndSettle();
    expect(find.text('No projects yet'), findsOneWidget);

    final newButton = find.byKey(const ValueKey('newProjectButton'));
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(newButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('projectNameField')),
      'Phase 1 Project',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('projectNameField')))
          .controller!
          .text,
      'Phase 1 Project',
    );
    // No blur, Enter, or intermediate save occurs here.
    final saveButton = find.byKey(const ValueKey('saveProjectButton'));
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final state = manager.loadState();
    expect(state.projects, hasLength(1));
    expect(state.activeProject?.name, 'Phase 1 Project');
    expect(find.text('Phase 1 Project'), findsWidgets);
  });

  testWidgets('rapid repeated confirmation creates only one project', (
    tester,
  ) async {
    await tester.pumpWidget(IOWispApp(manager: manager));
    await tester.pumpAndSettle();
    final newButton = find.byKey(const ValueKey('newProjectButton'));
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(newButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('projectNameField')),
      'Only Once',
    );
    await tester.pump();
    final button = find.byKey(const ValueKey('saveProjectButton'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(manager.loadState().projects, hasLength(1));
  });

  testWidgets('blank name is rejected visibly and cannot be confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(IOWispApp(manager: manager));
    await tester.pumpAndSettle();
    final newButton = find.byKey(const ValueKey('newProjectButton'));
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(newButton);
    await tester.pumpAndSettle();

    final buttonFinder = find.byKey(const ValueKey('saveProjectButton'));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);
    expect(find.text('Create Project'), findsOneWidget);
    expect(manager.loadState().projects, isEmpty);
  });

  testWidgets(
    'database failure is shown without claiming the project was saved',
    (tester) async {
      repository = _FailingInsertRepository();
      manager = ProjectManager(
        database: database,
        projects: repository,
        settings: SqliteAppSettingsRepository(database),
        paths: _TestPaths(temp.path),
        storage: const _ImmediateStorage(),
      )..initialize();

      await tester.pumpWidget(IOWispApp(manager: manager));
      await tester.pumpAndSettle();
      final newButton = find.byKey(const ValueKey('newProjectButton'));
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();
      await tester.tap(newButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('projectNameField')),
        'Database Failure',
      );
      await tester.pump();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('saveProjectButton')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.textContaining('Project was not saved.'), findsOneWidget);
      expect(
        find.textContaining('no project record or project folder'),
        findsOneWidget,
      );
      expect(repository.getAll(), isEmpty);
    },
  );

  testWidgets('failed root save clears the previous success notice', (
    tester,
  ) async {
    manager = ProjectManager(
      database: database,
      projects: repository,
      settings: SqliteAppSettingsRepository(database),
      paths: _TestPaths(temp.path),
      storage: const _RootValidationStorage(),
    )..initialize();
    await tester.pumpWidget(IOWispApp(manager: manager));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save root'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Project storage root saved.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'relative-root');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save root'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Project storage root was not saved.'),
      findsOneWidget,
    );
    expect(find.textContaining('Project storage root saved.'), findsNothing);
    expect(
      manager.loadState().projectRoot,
      _TestPaths(temp.path).defaultProjectRoot,
    );
  });
}

class _RootValidationStorage extends _ImmediateStorage {
  const _RootValidationStorage();

  @override
  Future<void> ensureRoot(String rootPath) async {
    if (!p.isAbsolute(rootPath)) {
      throw const FileSystemException('Project root must be an absolute path.');
    }
  }
}

class _TestPaths implements AppStoragePaths {
  _TestPaths(this.root);

  final String root;

  @override
  String get databasePath => p.join(root, 'io_wisp.sqlite');

  @override
  String get defaultProjectRoot => p.join(root, 'projects');
}

class _ImmediateStorage implements ProjectStorage {
  const _ImmediateStorage();

  @override
  Future<ProjectDirectory> createProjectDirectory({
    required String rootPath,
    required String preferredFolderName,
  }) {
    return Future.value(
      ProjectDirectory(
        rootPath: rootPath,
        folderName: preferredFolderName,
        absolutePath: p.join(rootPath, preferredFolderName),
      ),
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
  @override
  List<Project> getAll() => const <Project>[];

  @override
  Project? findById(String id) => null;

  @override
  Project? findByNormalizedName(String normalizedName) => null;

  @override
  void insert(Project project) {
    throw StateError('simulated SQLite failure');
  }

  @override
  void update(Project project) {
    throw StateError('simulated SQLite failure');
  }
}

import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../data/projects/project_repository.dart';
import '../data/settings/app_settings_repository.dart';
import '../data/storage/app_storage_paths.dart';
import '../data/storage/project_storage.dart';
import '../domain/project.dart';

class ProjectManagerState {
  const ProjectManagerState({
    required this.projects,
    required this.activeProject,
    required this.projectRoot,
  });

  final List<Project> projects;
  final Project? activeProject;
  final String projectRoot;
}

class ProjectCreationException implements Exception {
  const ProjectCreationException({
    required this.message,
    this.directoryPath,
    this.directoryRetained = false,
  });

  final String message;
  final String? directoryPath;
  final bool directoryRetained;

  @override
  String toString() => message;
}

class ProjectManager {
  ProjectManager({
    required this._database,
    required this._projects,
    required this._settings,
    required this._paths,
    required this._storage,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final ProjectRepository _projects;
  final AppSettingsRepository _settings;
  final AppStoragePaths _paths;
  final ProjectStorage _storage;
  final Uuid _uuid;

  void initialize() {
    if (_settings.getProjectRoot() == null) {
      _settings.setProjectRoot(_paths.defaultProjectRoot);
    }
  }

  ProjectManagerState loadState() {
    final projects = _projects.getAll();
    final storedActiveId = _settings.getActiveProjectId();
    Project? active;

    if (storedActiveId != null) {
      active = _projects.findById(storedActiveId);
    }
    if (active == null && projects.isNotEmpty) {
      active = projects.first;
      _database.transaction(() => _settings.setActiveProjectId(active!.id));
    }
    if (active == null && storedActiveId != null) {
      _database.transaction(() => _settings.setActiveProjectId(null));
    }

    return ProjectManagerState(
      projects: projects,
      activeProject: active,
      projectRoot: _settings.getProjectRoot() ?? _paths.defaultProjectRoot,
    );
  }

  Future<Project> createProject(ProjectDraft draft) async {
    final name = ProjectNameRules.displayValue(draft.name);
    final validationError = ProjectNameRules.validationError(name);
    if (validationError != null) {
      throw ProjectValidationException(validationError);
    }

    final normalizedName = ProjectNameRules.normalize(name);
    if (_projects.findByNormalizedName(normalizedName) != null) {
      throw const ProjectValidationException(
        'A project with this name already exists. Choose a different name.',
      );
    }

    final root = _settings.getProjectRoot() ?? _paths.defaultProjectRoot;
    final preferredFolder = FolderNamePolicy.forProject(
      name: name,
      locationClient: draft.locationClient,
    );
    final directory = await _storage.createProjectDirectory(
      rootPath: root,
      preferredFolderName: preferredFolder,
    );
    final now = DateTime.now().toUtc();
    final project = Project(
      id: _uuid.v4(),
      name: name,
      locationClient: draft.locationClient.trim(),
      revision: draft.revision.trim(),
      estimator: draft.estimator.trim(),
      createdAt: now,
      updatedAt: now,
      safeFolderName: directory.folderName,
      projectRootReference: directory.rootPath,
      projectDirectoryReference: directory.folderName,
      folderCreatedAt: now,
    );

    try {
      _database.transaction(() {
        if (_projects.findByNormalizedName(project.normalizedName) != null) {
          throw const ProjectValidationException(
            'A project with this name already exists. Choose a different name.',
          );
        }
        _projects.insert(project);
        _settings.setActiveProjectId(project.id);
      });
      return project;
    } catch (error) {
      final removed = await _storage.removeOwnedEmptyDirectory(directory);
      final detail = removed
          ? 'The failed operation left no project record or project folder.'
          : 'The folder could not be removed safely and was left untouched: '
                '${directory.absolutePath}';
      throw ProjectCreationException(
        message: 'Project creation failed. $detail',
        directoryPath: directory.absolutePath,
        directoryRetained: !removed,
      );
    }
  }

  Future<Project> updateProject(String id, ProjectDraft draft) async {
    final existing = _projects.findById(id);
    if (existing == null) {
      throw const ProjectValidationException(
        'The selected project no longer exists.',
      );
    }
    final name = ProjectNameRules.displayValue(draft.name);
    final validationError = ProjectNameRules.validationError(name);
    if (validationError != null) {
      throw ProjectValidationException(validationError);
    }
    final normalizedName = ProjectNameRules.normalize(name);
    final duplicate = _projects.findByNormalizedName(normalizedName);
    if (duplicate != null && duplicate.id != id) {
      throw const ProjectValidationException(
        'A project with this name already exists. Choose a different name.',
      );
    }
    final updated = existing.copyWith(
      name: name,
      locationClient: draft.locationClient.trim(),
      revision: draft.revision.trim(),
      estimator: draft.estimator.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    _database.transaction(() => _projects.update(updated));
    return updated;
  }

  void switchActiveProject(String id) {
    if (_projects.findById(id) == null) {
      throw const ProjectValidationException(
        'The selected project no longer exists.',
      );
    }
    _database.transaction(() => _settings.setActiveProjectId(id));
  }

  Future<void> configureProjectRoot(String root) async {
    final trimmed = root.trim();
    await _storage.ensureRoot(trimmed);
    _database.transaction(() => _settings.setProjectRoot(trimmed));
  }

  Future<void> openProjectFolder(Project project) {
    return _storage.openProjectDirectory(
      rootPath: project.projectRootReference,
      directoryReference: project.projectDirectoryReference,
    );
  }
}

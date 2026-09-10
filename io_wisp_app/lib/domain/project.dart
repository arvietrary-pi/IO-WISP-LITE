import 'package:path/path.dart' as p;

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.locationClient,
    required this.revision,
    required this.estimator,
    required this.createdAt,
    required this.updatedAt,
    required this.safeFolderName,
    required this.projectRootReference,
    required this.projectDirectoryReference,
    this.folderCreatedAt,
    this.status = 'active',
  });

  final String id;
  final String name;
  final String locationClient;
  final String revision;
  final String estimator;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String safeFolderName;
  final String projectRootReference;
  final String projectDirectoryReference;
  final DateTime? folderCreatedAt;
  final String status;

  String get normalizedName => ProjectNameRules.normalize(name);

  Project copyWith({
    String? name,
    String? locationClient,
    String? revision,
    String? estimator,
    DateTime? updatedAt,
    String? status,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      locationClient: locationClient ?? this.locationClient,
      revision: revision ?? this.revision,
      estimator: estimator ?? this.estimator,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      safeFolderName: safeFolderName,
      projectRootReference: projectRootReference,
      projectDirectoryReference: projectDirectoryReference,
      folderCreatedAt: folderCreatedAt,
      status: status ?? this.status,
    );
  }
}

class ProjectDraft {
  const ProjectDraft({
    required this.name,
    required this.locationClient,
    required this.revision,
    required this.estimator,
  });

  final String name;
  final String locationClient;
  final String revision;
  final String estimator;

  factory ProjectDraft.fromProject(Project project) {
    return ProjectDraft(
      name: project.name,
      locationClient: project.locationClient,
      revision: project.revision,
      estimator: project.estimator,
    );
  }
}

class ProjectNameRules {
  const ProjectNameRules._();

  static String normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String? validationError(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a project name.';
    }
    return null;
  }

  static String displayValue(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class FolderNamePolicy {
  const FolderNamePolicy._();

  static const _reservedNames = <String>{
    'AUX',
    'CON',
    'NUL',
    'PRN',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  static String forProject({
    required String name,
    required String locationClient,
    DateTime? date,
  }) {
    final day = date ?? DateTime.now();
    final dateText =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final projectPart = sanitizeSegment(name, fallback: 'Project');
    final clientPart = sanitizeSegment(locationClient, fallback: 'Project');
    return sanitizeSegment(
      '${projectPart}_$clientPart - $dateText',
      fallback: 'Project - $dateText',
    );
  }

  static String sanitizeSegment(String value, {String fallback = 'Project'}) {
    var cleaned = value.trim();
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F<>:"/\\|?*]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'^[. ]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      cleaned = fallback;
    }

    final stem = p.basenameWithoutExtension(cleaned).toUpperCase();
    if (_reservedNames.contains(stem)) {
      cleaned = '_$cleaned';
    }
    return cleaned;
  }

  static bool isSafeFolderName(String value) {
    if (value.isEmpty || value == '.' || value == '..') {
      return false;
    }
    if (value.contains('/') || value.contains('\\')) {
      return false;
    }
    if (RegExp(r'[\x00-\x1F<>:"|?*]').hasMatch(value)) {
      return false;
    }
    if (value != value.trimRight() || value.endsWith('.')) {
      return false;
    }
    return !_reservedNames.contains(
      p.basenameWithoutExtension(value).toUpperCase(),
    );
  }
}

class ProjectValidationException implements Exception {
  const ProjectValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

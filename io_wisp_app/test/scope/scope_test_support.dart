import 'dart:io';

import 'package:io_wisp_app/application/scope_service.dart';
import 'package:io_wisp_app/data/database/app_database.dart';
import 'package:io_wisp_app/data/projects/sqlite_project_repository.dart';
import 'package:io_wisp_app/data/scope/sqlite_scope_repository.dart';
import 'package:io_wisp_app/domain/project.dart';

const referenceBrief = 'Exclude Prelims and Testing. Include all others.';

class ScopeTestContext {
  ScopeTestContext() {
    temp = Directory.systemTemp.createTempSync('wisp-f4-');
    db = AppDatabase.open('${temp.path}/app.sqlite');
    a = addProject('Alpha');
    b = addProject('Beta');
    connect();
  }
  late Directory temp;
  late AppDatabase db;
  late SqliteScopeRepository repository;
  late ScopeService service;
  late Project a, b;
  Project addProject(String name) {
    final now = DateTime.now().toUtc();
    final p = Project(
      id: name,
      name: name,
      locationClient: 'Disposable',
      revision: 'A',
      estimator: 'Test',
      createdAt: now,
      updatedAt: now,
      safeFolderName: name,
      projectRootReference: temp.path,
      projectDirectoryReference: name,
    );
    SqliteProjectRepository(db).insert(p);
    return p;
  }

  void connect() {
    repository = SqliteScopeRepository(db);
    service = ScopeService(repository);
  }

  void reopen() {
    db.close();
    db = AppDatabase.open('${temp.path}/app.sqlite');
    connect();
  }

  void close({bool keep = false}) {
    db.close();
    if (!keep) temp.deleteSync(recursive: true);
  }
}

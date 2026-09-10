import 'application/managed_pdf_service.dart';
import 'data/pdf/pdfium_renderer.dart';
import 'data/pdf/sqlite_pdf_repository.dart';
import 'application/managed_file_service.dart';
import 'application/scope_service.dart';
import 'data/scope/sqlite_scope_repository.dart';
import 'data/storage/sqlite_managed_file_repository.dart';
import 'data/storage/windows_source_picker.dart';
import 'application/document_register_service.dart';
import 'data/register/sqlite_register_repository.dart';
import 'application/estimator_workflow_services.dart';
import 'data/estimator/sqlite_estimator_repositories.dart';

import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'application/project_management_service.dart';
import 'application/legacy_import_service.dart';
import 'data/import/legacy_json_reader.dart';
import 'data/import/sqlite_import_repository.dart';
import 'data/import/windows_import_folders.dart';
import 'data/import/windows_legacy_picker.dart';
import 'data/database/app_database.dart';
import 'data/projects/sqlite_project_repository.dart';
import 'data/settings/app_settings_repository.dart';
import 'data/storage/app_storage_paths.dart';
import 'data/storage/project_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    runApp(
      const StartupErrorApp(
        error: 'This build targets Windows desktop. Android structure is present for future work.',
      ),
    );
    return;
  }

  try {
    final paths = WindowsAppStoragePaths();
    final database = AppDatabase.open(paths.databasePath);
    final manager = ProjectManager(
      database: database,
      projects: SqliteProjectRepository(database),
      settings: SqliteAppSettingsRepository(database),
      paths: paths,
      storage: const WindowsProjectStorage(),
    )..initialize();
    final importer = LegacyImportService(
      reader: const ReadOnlyLegacyJsonReader(),
      repository: SqliteImportRepository(database),
      folders: WindowsImportFolders(),
    );
    final pdf = ManagedPdfService(
      SqliteManagedFileRepository(database),
      WindowsProjectFileStore(),
      SqlitePdfRepository(database),
      PdfiumRenderer(),
    );
    final register = DocumentRegisterService(
      repository: SqliteRegisterRepository(database),
      pdf: pdf,
    );
    final content = EstimateContentService(
      SqliteEstimateContentRepository(database),
    );
    runApp(
      IOWispApp(
        manager: manager,
        pdf: pdf,
        register: register,
        checklist: ChecklistService(SqliteChecklistRepository(database)),
        content: content,
        roadmap: RoadmapService(
          SqliteRoadmapRepository(database),
          disciplines: register.disciplines,
        ),
        timer: TimerService(SqliteTimeEntryRepository(database)),
        scope: ScopeService(
          SqliteScopeRepository(
            database,
            appliedRevisionHook: content.syncFromScopeRevision,
          ),
        ),
        files: ManagedFileService(
          repository: SqliteManagedFileRepository(database),
          store: WindowsProjectFileStore(),
        ),
        sourcePicker: const WindowsSourceFilePicker(),
        importer: importer,
        importPicker: const WindowsLegacyFilePicker(),
      ),
    );
  } catch (error) {
    runApp(StartupErrorApp(error: error));
  }
}

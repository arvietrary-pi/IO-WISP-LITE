import 'domain/pdf_document.dart';
import 'application/managed_file_service.dart';
import 'application/scope_service.dart';
import 'domain/managed_file.dart';
import 'application/document_register_service.dart';
import 'application/estimator_workflow_services.dart';

import 'package:flutter/material.dart';

import 'application/project_management_service.dart';
import 'application/legacy_import_service.dart';
import 'domain/legacy_import.dart';
import 'features/projects/project_list_page.dart';

class IOWispApp extends StatelessWidget {
  const IOWispApp({
    super.key,
    required this.manager,
    this.importer,
    this.importPicker,
    this.files,
    this.sourcePicker,
    this.scope,
    this.pdf,
    this.register,
    this.checklist,
    this.content,
    this.roadmap,
    this.timer,
  });

  final ManagedFileService? files;
  final SourceFilePicker? sourcePicker;
  final ScopeService? scope;
  final PdfDocumentService? pdf;
  final DocumentRegisterService? register;
  final ChecklistService? checklist;
  final EstimateContentService? content;
  final RoadmapService? roadmap;
  final TimerService? timer;
  final ProjectManager manager;
  final LegacyImportService? importer;
  final LegacyFilePicker? importPicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IO WISP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0b6477)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: ProjectListPage(
        manager: manager,
        importer: importer,
        importPicker: importPicker,
        files: files,
        sourcePicker: sourcePicker,
        scope: scope,
        pdf: pdf,
        register: register,
        checklist: checklist,
        content: content,
        roadmap: roadmap,
        timer: timer,
      ),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IO WISP',
      home: Scaffold(
        appBar: AppBar(title: const Text('IO WISP')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IO WISP could not start',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'The local database or application storage could not be opened. Existing files were not changed.',
                      ),
                      const SizedBox(height: 12),
                      SelectableText('$error'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

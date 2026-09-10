import '../../domain/pdf_document.dart';
import '../../application/managed_file_service.dart';
import '../../application/scope_service.dart';
import '../scope/scope_page.dart';
import '../../domain/managed_file.dart';
import '../files/project_files_page.dart';
import '../../application/document_register_service.dart';
import '../../application/estimator_workflow_services.dart';
import '../estimator/estimator_workspace_page.dart';

import 'package:flutter/material.dart';

import '../../application/project_management_service.dart';
import '../../application/legacy_import_service.dart';
import '../../domain/legacy_import.dart';
import '../../domain/project.dart';
import '../import/legacy_import_page.dart';
import 'project_editor_page.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({
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
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  late final TextEditingController _rootController;
  ProjectManagerState? _state;
  String? _errorMessage;
  String? _noticeMessage;
  bool _loading = true;
  bool _rootSaving = false;

  @override
  void initState() {
    super.initState();
    _rootController = TextEditingController();
    _loadState();
  }

  @override
  void dispose() {
    _rootController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('IO WISP'),
        actions: [
          if (widget.importer != null && widget.importPicker != null)
            TextButton.icon(
              key: const ValueKey('importExistingProject'),
              onPressed: _importProject,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import Existing Project'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              child: Text(
                'Phase 7 • v0.0.6+1',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadState,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _IntroCard(),
                          if (state?.activeProject != null &&
                              widget.scope != null)
                            FilledButton.icon(
                              key: const ValueKey('projectScope'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ScopePage(
                                    project: state!.activeProject!,
                                    service: widget.scope!,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.rule_outlined),
                              label: const Text('Scope Brief'),
                            ),
                          if (state?.activeProject != null &&
                              widget.checklist != null &&
                              widget.content != null &&
                              widget.roadmap != null &&
                              widget.timer != null)
                            FilledButton.icon(
                              key: const ValueKey('estimatorWorkflow'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => EstimatorWorkspacePage(
                                    project: state!.activeProject!,
                                    checklist: widget.checklist!,
                                    content: widget.content!,
                                    roadmap: widget.roadmap!,
                                    timer: widget.timer!,
                                    scope: widget.scope,
                                    register: widget.register,
                                    pdf: widget.pdf,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Estimator workflow'),
                            ),
                          if (state?.activeProject != null &&
                              widget.files != null &&
                              widget.sourcePicker != null)
                            FilledButton.icon(
                              key: const ValueKey('projectFiles'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ProjectFilesPage(
                                    project: state!.activeProject!,
                                    service: widget.files!,
                                    picker: widget.sourcePicker!,
                                    pdf: widget.pdf,
                                    register: widget.register,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.file_copy_outlined),
                              label: const Text('Project files'),
                            ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _ErrorBanner(message: _errorMessage!),
                          ],
                          if (_noticeMessage != null) ...[
                            const SizedBox(height: 16),
                            _NoticeBanner(message: _noticeMessage!),
                          ],
                          const SizedBox(height: 16),
                          _ProjectRootCard(
                            controller: _rootController,
                            saving: _rootSaving,
                            onSave: _saveRoot,
                          ),
                          const SizedBox(height: 16),
                          if (state == null || state.projects.isEmpty)
                            _EmptyState(onCreate: _createProject)
                          else
                            _ProjectsCard(
                              state: state,
                              onCreate: _createProject,
                              onSwitch: _switchProject,
                              onEdit: _editProject,
                              onOpenFolder: _openFolder,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _loadState() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final state = widget.manager.loadState();
      if (!mounted) return;
      _rootController.text = state.projectRoot;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'The project list could not be loaded. $error';
      });
    }
  }

  Future<void> _createProject() async {
    final saved = await Navigator.of(context).push<Project>(
      MaterialPageRoute(
        builder: (_) => ProjectEditorPage(manager: widget.manager),
      ),
    );
    if (!mounted || saved == null) return;
    await _loadState();
    if (!mounted) return;
    setState(() => _noticeMessage = 'Project “${saved.name}” is now active.');
  }

  Future<void> _importProject() async {
    final imported = await Navigator.of(context).push<Project>(
      MaterialPageRoute(
        builder: (_) => LegacyImportPage(
          service: widget.importer!,
          picker: widget.importPicker!,
        ),
      ),
    );
    if (!mounted) return;
    await _loadState();
    if (!mounted) return;
    if (imported != null) {
      setState(
        () => _noticeMessage =
            'Imported project “${imported.name}” is now active.',
      );
    }
  }

  Future<void> _editProject(Project project) async {
    final saved = await Navigator.of(context).push<Project>(
      MaterialPageRoute(
        builder: (_) =>
            ProjectEditorPage(manager: widget.manager, project: project),
      ),
    );
    if (!mounted || saved == null) return;
    await _loadState();
    if (!mounted) return;
    setState(() => _noticeMessage = 'Project details saved.');
  }

  Future<void> _switchProject(String id) async {
    try {
      widget.manager.switchActiveProject(id);
      await _loadState();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'The project could not be selected. $error',
      );
    }
  }

  Future<void> _openFolder(Project project) async {
    try {
      await widget.manager.openProjectFolder(project);
      if (!mounted) return;
      setState(
        () => _noticeMessage = 'Opened the project folder in Windows Explorer.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'The project folder could not be opened. $error',
      );
    }
  }

  Future<void> _saveRoot() async {
    final root = _rootController.text.trim();
    if (root.isEmpty || _rootSaving) {
      setState(() {
        _noticeMessage = null;
        _errorMessage = 'Enter an absolute project storage path.';
      });
      return;
    }
    setState(() {
      _rootSaving = true;
      _errorMessage = null;
      _noticeMessage = null;
    });
    try {
      await widget.manager.configureProjectRoot(root);
      await _loadState();
      if (!mounted) return;
      setState(
        () => _noticeMessage =
            'Project storage root saved. Existing folders were not moved.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rootSaving = false;
        _errorMessage = 'Project storage root was not saved. $error';
      });
    }
    if (mounted) setState(() => _rootSaving = false);
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.offline_bolt_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Project dashboard',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Set up and switch between local estimating projects. Import and track unchanged source copies from Project files.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectRootCard extends StatelessWidget {
  const _ProjectRootCard({
    required this.controller,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Project storage',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'New project folders are created here. Existing project folders stay where they were created if this setting changes.',
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Configured project root',
                      helperText: 'Use an absolute Windows path. Default: Documents\\IO WISP Projects',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: saving ? null : onSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save root'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'No projects yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first project to establish its local database record and managed Windows folder.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('newProjectButton'),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard({
    required this.state,
    required this.onCreate,
    required this.onSwitch,
    required this.onEdit,
    required this.onOpenFolder,
  });

  final ProjectManagerState state;
  final VoidCallback onCreate;
  final ValueChanged<String> onSwitch;
  final ValueChanged<Project> onEdit;
  final ValueChanged<Project> onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final active = state.activeProject;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved projects',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('New project'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey(active?.id),
              initialValue: active?.id,
              decoration: const InputDecoration(labelText: 'Project selector'),
              items: state.projects
                  .map(
                    (project) => DropdownMenuItem<String>(
                      value: project.id,
                      child: Text(project.name),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) onSwitch(id);
              },
            ),
            const SizedBox(height: 18),
            if (active != null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Active project',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _DetailLine(
                      label: 'Location / client',
                      value: active.locationClient,
                    ),
                    _DetailLine(
                      label: 'Set / revision',
                      value: active.revision,
                    ),
                    _DetailLine(label: 'Estimator', value: active.estimator),
                    _DetailLine(label: 'Folder', value: active.safeFolderName),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => onEdit(active),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit project'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => onOpenFolder(active),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Open project folder'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Text(
              '${state.projects.length} project${state.projects.length == 1 ? '' : 's'} saved locally',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text('$label: ${value.isEmpty ? 'Not set' : value}'),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      color: scheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

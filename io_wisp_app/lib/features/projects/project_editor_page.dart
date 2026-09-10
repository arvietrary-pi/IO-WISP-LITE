import 'package:flutter/material.dart';

import '../../application/project_management_service.dart';
import '../../domain/project.dart';

class ProjectEditorPage extends StatefulWidget {
  const ProjectEditorPage({super.key, required this.manager, this.project});

  final ProjectManager manager;
  final Project? project;

  @override
  State<ProjectEditorPage> createState() => _ProjectEditorPageState();
}

class _ProjectEditorPageState extends State<ProjectEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _revisionController;
  late final TextEditingController _estimatorController;
  String? _errorMessage;
  bool _saving = false;

  bool get _isNew => widget.project == null;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _nameController = TextEditingController(text: project?.name ?? '');
    _locationController = TextEditingController(
      text: project?.locationClient ?? '',
    );
    _revisionController = TextEditingController(text: project?.revision ?? '');
    _estimatorController = TextEditingController(
      text: project?.estimator ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _revisionController.dispose();
    _estimatorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'New project' : 'Edit project')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isNew
                            ? 'Create an offline project'
                            : 'Project details',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isNew
                            ? 'The project is saved only after the folder and database record are both ready.'
                            : 'Save the current values explicitly. The existing project folder will not be renamed automatically.',
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const ValueKey('projectNameField'),
                        controller: _nameController,
                        autofocus: _isNew,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Project name *',
                          hintText: 'e.g. 3 Hope Street Residence',
                        ),
                        validator: ProjectNameRules.validationError,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _locationController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Location / client',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _revisionController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Set / revision',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _estimatorController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Estimator',
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 20),
                        _ErrorBanner(message: _errorMessage!),
                      ],
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _nameController,
                          builder: (context, value, child) {
                            final hasName = value.text.trim().isNotEmpty;
                            return FilledButton.icon(
                              key: const ValueKey('saveProjectButton'),
                              onPressed: _saving || !hasName ? null : _save,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _isNew ? Icons.add : Icons.save_outlined,
                                    ),
                              label: Text(
                                _isNew ? 'Create Project' : 'Save Changes',
                              ),
                            );
                          },
                        ),
                      ),
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

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    // Read the controllers at confirmation time. No Enter key or blur is required.
    final draft = ProjectDraft(
      name: _nameController.text,
      locationClient: _locationController.text,
      revision: _revisionController.text,
      estimator: _estimatorController.text,
    );
    try {
      final saved = _isNew
          ? await widget.manager.createProject(draft)
          : await widget.manager.updateProject(widget.project!.id, draft);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'Project was not saved. $error';
      });
    }
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
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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

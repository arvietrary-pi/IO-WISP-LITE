import '../../domain/pdf_document.dart';
import '../pdf/pdf_viewer_page.dart';
import '../../application/document_register_service.dart';
import '../register/document_register_page.dart';

import 'package:flutter/material.dart';

import '../../application/managed_file_service.dart';
import '../../domain/managed_file.dart';
import '../../domain/project.dart';

class ProjectFilesPage extends StatefulWidget {
  const ProjectFilesPage({
    super.key,
    required this.project,
    required this.service,
    required this.picker,
    this.pdf,
    this.register,
  });
  final Project project;
  final ManagedFileService service;
  final SourceFilePicker picker;
  final PdfDocumentService? pdf;
  final DocumentRegisterService? register;
  @override
  State<ProjectFilesPage> createState() => _ProjectFilesPageState();
}

class _ProjectFilesPageState extends State<ProjectFilesPage> {
  List<ManagedFile> _files = [];
  bool _busy = false;
  bool _choosing = false;
  String? _message;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final files = await widget.service.list(widget.project.id);
      if (mounted && generation == _loadGeneration) {
        setState(() => _files = files);
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _message = 'Files could not be checked. $e');
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProjectFilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      _files = [];
      _message = null;
      _load();
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final selection = await widget.picker.selectSource();
      if (selection == null || !mounted) return;
      FileImportResult result;
      try {
        result = await widget.service.importFile(widget.project.id, selection);
      } on FileNameConflict catch (conflict) {
        if (!mounted) return;
        setState(() => _choosing = true);
        final name = TextEditingController();
        final decision = await showDialog<(FileCollisionChoice, String)?>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Same filename, different content'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${conflict.existing.name} already exists. The existing copy will be preserved.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('newManagedName'),
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'New safe filename (include extension)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const ValueKey('importNewName'),
                onPressed: () => Navigator.pop(ctx, (
                  FileCollisionChoice.newName,
                  name.text,
                )),
                child: const Text('Use new name'),
              ),
              FilledButton(
                key: const ValueKey('importRevision'),
                onPressed: () =>
                    Navigator.pop(ctx, (FileCollisionChoice.revision, '')),
                child: const Text('Import as revision'),
              ),
            ],
          ),
        );
        // Keep controller alive until the dialog's reverse animation completes.
        Future<void>.delayed(const Duration(seconds: 1), name.dispose);
        if (mounted) setState(() => _choosing = false);
        if (decision == null) {
          if (mounted) setState(() => _message = 'Import cancelled.');
          return;
        }
        result = await widget.service.importFile(
          widget.project.id,
          selection,
          choice: decision.$1,
          newName: decision.$2,
          expectedConflictId: conflict.existing.id,
        );
      }
      if (mounted) {
        setState(
          () => _message = result.duplicate
              ? 'Identical content already recorded: ${result.file!.name} (${result.file!.state.name}). No copy created.'
              : 'Imported ${result.file!.name}. Source bytes verified unchanged.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Import not completed. $e');
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trash(ManagedFile file) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move managed copy to trash?'),
        content: Text(
          '${file.name}\nThe selected external source remains unchanged. Provenance and the managed copy are retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirmTrash'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.trash(widget.project.id, file.id);
      if (mounted) {
        setState(
          () => _message = 'Managed copy moved to trash. Provenance retained.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'Trash operation not completed. $e');
      }
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text('Files — ${widget.project.name}')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Import an unchanged copy of an explicitly selected file. Files are stored without parsing or analysis.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                key: const ValueKey('selectSourceFile'),
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_copy_outlined),
                label: const Text('Import source file'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _load,
                child: const Text('Refresh file status'),
              ),
            ],
          ),
          if (_busy && !_choosing) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(_message!),
            ),
          if (_files.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No managed files recorded.'),
            ),
          for (final file in _files)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${file.name} — ${file.state.name}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SelectableText(
                      'Original: ${file.originalName}\nFile ID: ${file.id}\nPath: ${file.relativePath}\nSHA-256: ${file.fingerprint.sha256}\nBytes: ${file.fingerprint.byteCount}\nImported (UTC): ${file.importedAt.toUtc().toIso8601String()}${file.revisionOf == null ? '' : '\nRevision of: ${file.revisionOf}'}',
                    ),
                    if (file.state == ManagedFileState.recoveryNeeded)
                      Text(
                        'Recovery needed. Retained staging reference: ${file.stagingPath}. Do not remove uncertain files.',
                      ),
                    if (file.state == ManagedFileState.missing)
                      const Text(
                        'Managed file is missing. Provenance is preserved; no replacement was created.',
                      ),
                    if (widget.pdf != null)
                      TextButton(
                        key: ValueKey("viewPdf-${file.id}"),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PdfViewerPage(
                                    projectId: widget.project.id,
                                    projectName: widget.project.name,
                                    managedFileId: file.id,
                                    filename: file.name,
                                    service: widget.pdf!,
                                  ),
                                ),
                              ),
                        child: const Text("Open / View PDF"),
                      ),
                    if (widget.pdf != null && widget.register != null)
                      TextButton(
                        key: ValueKey('documentRegister-${file.id}'),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DocumentRegisterPage(
                                    projectId: widget.project.id,
                                    projectName: widget.project.name,
                                    file: file,
                                    service: widget.register!,
                                    pdf: widget.pdf!,
                                  ),
                                ),
                              ),
                        child: const Text('Document Register'),
                      ),
                    if (file.state == ManagedFileState.ready)
                      TextButton(
                        onPressed: _busy ? null : () => _trash(file),
                        child: const Text('Move managed copy to trash'),
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

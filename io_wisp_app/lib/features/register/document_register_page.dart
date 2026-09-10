import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/document_register_service.dart';
import '../../domain/document_register.dart';
import '../../domain/managed_file.dart';
import '../../domain/pdf_document.dart';
import '../pdf/pdf_viewer_page.dart';

class DocumentRegisterPage extends StatefulWidget {
  const DocumentRegisterPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.file,
    required this.service,
    required this.pdf,
  });

  final String projectId, projectName;
  final ManagedFile file;
  final DocumentRegisterService service;
  final PdfDocumentService pdf;

  @override
  State<DocumentRegisterPage> createState() => _DocumentRegisterPageState();
}

class _DocumentRegisterPageState extends State<DocumentRegisterPage> {
  final _search = TextEditingController();
  DocumentRegister? _register;
  List<DocumentControlFlag> _flags = const [];
  String? _discipline;
  RegisterReviewState? _review;
  RegisterEntryStatus? _status;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    try {
      setState(() {
        _register = widget.service.load(widget.projectId, widget.file.id);
        _flags = widget.service.flags(widget.projectId);
      });
    } catch (error) {
      setState(
        () => _message = 'Document Register could not be loaded. $error',
      );
    }
  }

  Future<void> _analyze() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message =
          'Reading embedded positional text one physical page at a time…';
    });
    try {
      final register = await widget.service.analyze(
        widget.projectId,
        widget.file.id,
      );
      if (!mounted) return;
      setState(() {
        _register = register;
        _flags = widget.service.flags(widget.projectId);
        _message =
            'Analysis completed for ${register.entries.length} physical PDF pages. Detected fields were refreshed; estimator overrides were preserved.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Analysis not completed. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(DocumentRegisterEntry entry) async {
    final controllers = [
      TextEditingController(text: entry.sheetNumber),
      TextEditingController(text: entry.title),
      TextEditingController(text: entry.discipline),
      TextEditingController(text: entry.revision),
      TextEditingController(text: entry.scale),
      TextEditingController(text: entry.drawingDate),
      TextEditingController(text: entry.notes),
    ];
    var useOverrides = [
      entry.manualSheetNumber != null,
      entry.manualTitle != null,
      entry.manualDiscipline != null,
      entry.manualRevision != null,
      entry.manualScale != null,
      entry.manualDrawingDate != null,
    ];
    var state = entry.documentState;
    final result = await showDialog<(RegisterEntryOverrides,)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Physical PDF page ${entry.physicalPage}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Detected values remain stored separately. Select Override only for fields where estimator input must control the displayed value.',
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              key: ValueKey('registerOverrideField-$i'),
                              controller: controllers[i],
                              enabled: useOverrides[i],
                              decoration: InputDecoration(
                                labelText: const [
                                  'Sheet number',
                                  'Drawing title',
                                  'Discipline',
                                  'Revision',
                                  'Scale',
                                  'Drawing date',
                                ][i],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Checkbox(
                            value: useOverrides[i],
                            onChanged: (value) => setDialogState(() {
                              useOverrides = [...useOverrides];
                              useOverrides[i] = value ?? false;
                              if (!useOverrides[i]) {
                                controllers[i].text = [
                                  entry.detected.sheetNumber,
                                  entry.detected.title,
                                  entry.detected.discipline,
                                  entry.detected.revision,
                                  entry.detected.scale,
                                  entry.detected.drawingDate,
                                ][i];
                              }
                            }),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('Override'),
                          ),
                        ],
                      ),
                    ),
                  DropdownButtonFormField<DocumentState>(
                    initialValue: state,
                    decoration: const InputDecoration(
                      labelText: 'Document state',
                    ),
                    items: DocumentState.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => state = value ?? DocumentState.current,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('registerNotes'),
                    controller: controllers[6],
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Estimator notes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    'Detection evidence: ${entry.detected.evidence}\nDiagnostics: ${entry.detected.diagnostics.map((value) => value.message(candidateCount: entry.detected.candidates.length)).join(' ')}',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('saveRegisterOverrides'),
              onPressed: () => Navigator.pop(context, (
                RegisterEntryOverrides(
                  sheetNumber: useOverrides[0]
                      ? controllers[0].text.trim()
                      : null,
                  title: useOverrides[1] ? controllers[1].text.trim() : null,
                  discipline: useOverrides[2]
                      ? controllers[2].text.trim()
                      : null,
                  revision: useOverrides[3] ? controllers[3].text.trim() : null,
                  scale: useOverrides[4] ? controllers[4].text.trim() : null,
                  drawingDate: useOverrides[5]
                      ? controllers[5].text.trim()
                      : null,
                  notes: controllers[6].text.trim(),
                  documentState: state,
                ),
              )),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    if (result == null || !mounted) return;
    try {
      final register = widget.service.updateOverrides(
        widget.projectId,
        widget.file.id,
        entry.physicalPage,
        result.$1,
      );
      setState(() {
        _register = register;
        _flags = widget.service.flags(widget.projectId);
        _message =
            'Estimator overrides saved for physical PDF page ${entry.physicalPage}.';
      });
    } catch (error) {
      setState(() => _message = 'Overrides not saved. $error');
    }
  }

  Future<void> _setReview(
    DocumentRegisterEntry entry,
    RegisterReviewState state,
  ) async {
    String? estimator;
    if (state == RegisterReviewState.signedOff) {
      final controller = TextEditingController(text: entry.signedOffBy ?? '');
      estimator = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estimator sign-off'),
          content: TextField(
            key: const ValueKey('registerSigner'),
            controller: controller,
            decoration: const InputDecoration(labelText: 'Estimator name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Sign off'),
            ),
          ],
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
      if (estimator == null || estimator.trim().isEmpty || !mounted) return;
    }
    try {
      final register = widget.service.setReviewState(
        widget.projectId,
        widget.file.id,
        entry.physicalPage,
        state,
        signedOffBy: estimator,
      );
      setState(() {
        _register = register;
        _flags = widget.service.flags(widget.projectId);
      });
    } catch (error) {
      setState(() => _message = 'Review state not saved. $error');
    }
  }

  void _openPage(DocumentRegisterEntry entry) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerPage(
            projectId: widget.projectId,
            projectName: widget.projectName,
            managedFileId: widget.file.id,
            filename: widget.file.name,
            service: widget.pdf,
            initialPhysicalPage: entry.physicalPage,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final register = _register;
    final disciplines =
        register?.entries.map((entry) => entry.discipline).toSet().toList() ??
        <String>[];
    disciplines.sort();
    final entries = register == null
        ? const <DocumentRegisterEntry>[]
        : widget.service.filter(
            register,
            query: _search.text,
            discipline: _discipline,
            reviewState: _review,
            status: _status,
          );
    return Scaffold(
      appBar: AppBar(title: Text('Document Register — ${widget.file.name}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Physical PDF page is the 1-based source page used for navigation. Drawing sheet numbers are separate, editable identifiers.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('analyzeDocumentRegister'),
                onPressed: _busy ? null : _analyze,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(
                  register == null
                      ? 'Analyze PDF'
                      : 'Re-analyze detected fields',
                ),
              ),
              if (register != null)
                Text(
                  '${register.entries.length} physical pages • ${_flags.length} active control flags',
                ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(_message!),
            ),
          if (_flags.isNotEmpty)
            ExpansionTile(
              initiallyExpanded: true,
              title: Text('Document-control flags (${_flags.length})'),
              children: [
                for (final flag in _flags)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(flag.message),
                    subtitle: Text(
                      'Physical page(s): ${flag.physicalPages.join(', ')}',
                    ),
                  ),
              ],
            ),
          if (register == null && !_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No Document Register has been generated for this managed PDF.',
              ),
            ),
          if (register != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    key: const ValueKey('registerSearch'),
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Search register',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _discipline,
                    decoration: const InputDecoration(labelText: 'Discipline'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All disciplines'),
                      ),
                      ...disciplines.map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      ),
                    ],
                    onChanged: (value) => setState(() => _discipline = value),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<RegisterReviewState?>(
                    isExpanded: true,
                    initialValue: _review,
                    decoration: const InputDecoration(
                      labelText: 'Reviewed state',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All states'),
                      ),
                      ...RegisterReviewState.values.map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _review = value),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<RegisterEntryStatus?>(
                    isExpanded: true,
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All statuses'),
                      ),
                      ...RegisterEntryStatus.values.map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Physical page')),
                  DataColumn(label: Text('Effective sheet')),
                  DataColumn(label: Text('Title')),
                  DataColumn(label: Text('Discipline')),
                  DataColumn(label: Text('Revision')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Reviewed')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: [
                  for (final entry in entries)
                    DataRow(
                      key: ValueKey('registerRow-${entry.physicalPage}'),
                      cells: [
                        DataCell(Text('${entry.physicalPage}')),
                        DataCell(
                          Text(
                            entry.sheetNumber.isEmpty ? '—' : entry.sheetNumber,
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 190,
                            child: Text(
                              entry.title.isEmpty ? '—' : entry.title,
                            ),
                          ),
                        ),
                        DataCell(Text(entry.discipline)),
                        DataCell(
                          Text(entry.revision.isEmpty ? '—' : entry.revision),
                        ),
                        DataCell(
                          Text(
                            '${entry.detected.status.name} / ${entry.documentState.name}',
                          ),
                        ),
                        DataCell(
                          PopupMenuButton<RegisterReviewState>(
                            onSelected: (value) => _setReview(entry, value),
                            itemBuilder: (_) => RegisterReviewState.values
                                .map(
                                  (value) => PopupMenuItem(
                                    key: ValueKey('reviewChoice-${value.name}'),
                                    value: value,
                                    child: Text(value.name),
                                  ),
                                )
                                .toList(),
                            child: Text(entry.reviewState.name),
                          ),
                        ),
                        DataCell(
                          Wrap(
                            children: [
                              TextButton(
                                key: ValueKey(
                                  'editRegisterPage-${entry.physicalPage}',
                                ),
                                onPressed: () => _edit(entry),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                key: ValueKey(
                                  'openRegisterPage-${entry.physicalPage}',
                                ),
                                onPressed: () => _openPage(entry),
                                child: const Text('Open page'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

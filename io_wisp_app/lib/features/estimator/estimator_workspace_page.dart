import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/document_register_service.dart';
import '../../application/estimator_workflow_services.dart';
import '../../application/scope_service.dart';
import '../../domain/document_register.dart';
import '../../domain/estimator_workflow.dart';
import '../../domain/pdf_document.dart';
import '../../domain/project.dart';
import '../pdf/pdf_viewer_page.dart';

class EstimatorWorkspacePage extends StatefulWidget {
  const EstimatorWorkspacePage({
    super.key,
    required this.project,
    required this.checklist,
    required this.content,
    required this.roadmap,
    required this.timer,
    this.scope,
    this.register,
    this.pdf,
  });

  final Project project;
  final ChecklistService checklist;
  final EstimateContentService content;
  final RoadmapService roadmap;
  final TimerService timer;
  final ScopeService? scope;
  final DocumentRegisterService? register;
  final PdfDocumentService? pdf;

  @override
  State<EstimatorWorkspacePage> createState() => _EstimatorWorkspacePageState();
}

class _EstimatorWorkspacePageState extends State<EstimatorWorkspacePage> {
  int _timerRevision = 0;

  void _timerChanged() => setState(() => _timerRevision++);

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.project.name} — Estimator workflow'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Checklist'),
            Tab(text: 'Estimate Content'),
            Tab(text: 'Roadmap'),
            Tab(text: 'Time log'),
          ],
        ),
      ),
      body: Column(
        children: [
          _ActiveTimerBanner(
            key: ValueKey(_timerRevision),
            projectId: widget.project.id,
            service: widget.timer,
            onChanged: _timerChanged,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ChecklistTab(
                  projectId: widget.project.id,
                  checklist: widget.checklist,
                  timer: widget.timer,
                  onTimerChanged: _timerChanged,
                  openEvidence: _openEvidence,
                ),
                _ContentTab(
                  projectId: widget.project.id,
                  service: widget.content,
                  scope: widget.scope,
                ),
                _RoadmapTab(
                  projectId: widget.project.id,
                  service: widget.roadmap,
                ),
                _TimeLogTab(
                  projectId: widget.project.id,
                  service: widget.timer,
                  revision: _timerRevision,
                  onChanged: _timerChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openEvidence(int physicalPage) async {
    final registerService = widget.register;
    final pdf = widget.pdf;
    if (registerService == null || pdf == null) {
      _message('The PDF viewer is not available in this build.');
      return;
    }
    final matches = registerService
        .registers(widget.project.id)
        .where(
          (register) => register.entries.any(
            (entry) =>
                entry.physicalPage == physicalPage &&
                entry.documentState == DocumentState.current,
          ),
        )
        .toList();
    if (matches.isEmpty) {
      _message(
        'No current Document Register contains physical PDF page $physicalPage.',
      );
      return;
    }
    DocumentRegister? selected = matches.length == 1 ? matches.single : null;
    selected ??= await showDialog<DocumentRegister>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Open physical PDF page $physicalPage from'),
        children: [
          for (final register in matches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, register),
              child: Text(register.sourceFilename),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerPage(
          projectId: widget.project.id,
          projectName: widget.project.name,
          managedFileId: selected!.managedFileId,
          filename: selected.sourceFilename,
          service: pdf,
          initialPhysicalPage: physicalPage,
        ),
      ),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _ActiveTimerBanner extends StatefulWidget {
  const _ActiveTimerBanner({
    super.key,
    required this.projectId,
    required this.service,
    required this.onChanged,
  });
  final String projectId;
  final TimerService service;
  final VoidCallback onChanged;

  @override
  State<_ActiveTimerBanner> createState() => _ActiveTimerBannerState();
}

class _ActiveTimerBannerState extends State<_ActiveTimerBanner> {
  Timer? _ticker;
  TimeEntry? _active;

  @override
  void initState() {
    super.initState();
    _reload();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _active != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _reload() => _active = widget.service.active(widget.projectId);

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                active == null
                    ? 'No active timer'
                    : '${active.label} • ${_duration(widget.service.elapsed(active))}',
                key: const ValueKey('activeTimerLabel'),
              ),
            ),
            if (active == null)
              FilledButton.icon(
                key: const ValueKey('startEstimateTimer'),
                onPressed: () {
                  widget.service.start(
                    widget.projectId,
                    TimerReferenceType.wholeEstimate,
                    label: 'Estimate Preparation',
                  );
                  setState(_reload);
                  widget.onChanged();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start estimate'),
              )
            else ...[
              IconButton(
                key: const ValueKey('activeTimerNote'),
                tooltip: 'Edit timer note',
                onPressed: () => _editNote(active),
                icon: const Icon(Icons.note_alt_outlined),
              ),
              FilledButton(
                key: const ValueKey('stopTimer'),
                onPressed: () {
                  widget.service.stop(widget.projectId);
                  setState(_reload);
                  widget.onChanged();
                },
                child: const Text('Stop'),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('discardTimer'),
                onPressed: () {
                  widget.service.discard(widget.projectId);
                  setState(_reload);
                  widget.onChanged();
                },
                child: const Text('Discard'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(TimeEntry active) async {
    var note = active.note;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Active timer note'),
        content: TextFormField(
          key: const ValueKey('activeTimerNoteField'),
          initialValue: active.note,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Estimator note'),
          onChanged: (value) => note = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (save == true) {
      widget.service.updateNote(widget.projectId, active.id, note);
      setState(_reload);
      widget.onChanged();
    }
  }
}

class _ChecklistTab extends StatefulWidget {
  const _ChecklistTab({
    required this.projectId,
    required this.checklist,
    required this.timer,
    required this.onTimerChanged,
    required this.openEvidence,
  });
  final String projectId;
  final ChecklistService checklist;
  final TimerService timer;
  final VoidCallback onTimerChanged;
  final Future<void> Function(int page) openEvidence;

  @override
  State<_ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends State<_ChecklistTab> {
  late List<ChecklistEntry> _entries;
  final _debounce = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    _entries = widget.checklist.load(widget.projectId);
  }

  @override
  void dispose() {
    for (final timer in _debounce.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _save(
    ChecklistEntry old, {
    bool? done,
    String? note,
    int? Function()? page,
  }) {
    widget.checklist.save(
      projectId: widget.projectId,
      templateKey: old.templateKey,
      isDone: done ?? old.isDone,
      note: note ?? old.note,
      evidencePage: page == null ? old.evidencePage : page(),
    );
    setState(() => _entries = widget.checklist.load(widget.projectId));
  }

  @override
  Widget build(BuildContext context) {
    final sections = estimatorChecklistCatalog
        .map((item) => item.sectionKey)
        .toSet();
    final done = _entries.where((entry) => entry.isDone).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$done of 49 complete',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            OutlinedButton(
              key: const ValueKey('resetChecklist'),
              onPressed: _reset,
              child: const Text('Reset checklist'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: done / 49),
        for (final section in sections)
          ExpansionTile(
            initiallyExpanded: section == 'sec_set_control',
            title: Text(
              estimatorChecklistCatalog
                  .firstWhere((item) => item.sectionKey == section)
                  .sectionTitle,
            ),
            children: [
              for (final template in estimatorChecklistCatalog.where(
                (item) => item.sectionKey == section,
              ))
                _ChecklistRow(
                  key: ValueKey(template.key),
                  template: template,
                  entry: _entries.firstWhere(
                    (entry) => entry.templateKey == template.key,
                  ),
                  onDone: (value) => _save(
                    _entries.firstWhere(
                      (entry) => entry.templateKey == template.key,
                    ),
                    done: value,
                  ),
                  onNote: (value) {
                    _debounce[template.key]?.cancel();
                    _debounce[template.key] = Timer(
                      const Duration(milliseconds: 500),
                      () {
                        final current = _entries.firstWhere(
                          (entry) => entry.templateKey == template.key,
                        );
                        _save(current, note: value);
                      },
                    );
                  },
                  onEvidence: (value) {
                    final trimmed = value.trim();
                    final page = int.tryParse(trimmed);
                    if (trimmed.isNotEmpty && (page == null || page < 1)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Evidence must use a positive physical PDF page.',
                          ),
                        ),
                      );
                      return;
                    }
                    _save(
                      _entries.firstWhere(
                        (entry) => entry.templateKey == template.key,
                      ),
                      page: () => trimmed.isEmpty ? null : page,
                    );
                  },
                  onOpenEvidence: () {
                    final page = _entries
                        .firstWhere(
                          (entry) => entry.templateKey == template.key,
                        )
                        .evidencePage;
                    if (page != null) widget.openEvidence(page);
                  },
                  onStartTimer: () {
                    widget.timer.start(
                      widget.projectId,
                      TimerReferenceType.checklistItem,
                      referenceId: template.key,
                      label: template.title,
                    );
                    widget.onTimerChanged();
                  },
                ),
            ],
          ),
      ],
    );
  }

  void _reset() {
    final snapshot = widget.checklist.reset(widget.projectId);
    setState(() => _entries = widget.checklist.load(widget.projectId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        content: const Text('Checklist reset. A recovery snapshot was saved.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            widget.checklist.undoReset(widget.projectId, snapshot);
            if (mounted) {
              setState(
                () => _entries = widget.checklist.load(widget.projectId),
              );
            }
          },
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    super.key,
    required this.template,
    required this.entry,
    required this.onDone,
    required this.onNote,
    required this.onEvidence,
    required this.onOpenEvidence,
    required this.onStartTimer,
  });
  final ChecklistTemplateItem template;
  final ChecklistEntry entry;
  final ValueChanged<bool> onDone;
  final ValueChanged<String> onNote, onEvidence;
  final VoidCallback onOpenEvidence, onStartTimer;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: entry.isDone,
            onChanged: (value) => onDone(value ?? false),
            title: Text('${template.itemOrder}. ${template.title}'),
            subtitle: Text(template.prompt),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: entry.note,
                  decoration: const InputDecoration(
                    labelText: 'Estimator note / evidence',
                  ),
                  onChanged: onNote,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 150,
                child: TextFormField(
                  initialValue: entry.evidencePage?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Physical page'),
                  onFieldSubmitted: onEvidence,
                ),
              ),
              IconButton(
                tooltip: 'Open evidence page',
                onPressed: entry.evidencePage == null ? null : onOpenEvidence,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              TextButton.icon(
                onPressed: onStartTimer,
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Start timer'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ContentTab extends StatefulWidget {
  const _ContentTab({
    required this.projectId,
    required this.service,
    this.scope,
  });
  final String projectId;
  final EstimateContentService service;
  final ScopeService? scope;
  @override
  State<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<_ContentTab> {
  late EstimateContent _content;
  late List<TextEditingController> _controllers;
  Timer? _autosave;
  String _status = 'Saved';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _content = widget.service.load(widget.projectId);
    _controllers = _content.values
        .map((value) => TextEditingController(text: value))
        .toList();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() => _status = 'Unsaved changes');
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 600), _save);
  }

  void _save() {
    final values = _controllers.map((controller) => controller.text).toList();
    _content = widget.service.save(
      EstimateContent(
        projectId: widget.projectId,
        scope: values[0],
        basis: values[1],
        assumptions: values[2],
        exclusions: values[3],
        rfis: values[4],
        risks: values[5],
        rates: values[6],
        changes: values[7],
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (mounted) setState(() => _status = 'Saved');
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(_status, key: const ValueKey('contentSaveStatus')),
          OutlinedButton(
            key: const ValueKey('syncScopeContent'),
            onPressed: widget.scope?.current(widget.projectId) == null
                ? null
                : _sync,
            child: const Text('Sync from Scope Brief'),
          ),
          OutlinedButton(
            onPressed: _showHistory,
            child: const Text('Revision history'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < estimateContentFields.length; index++) ...[
        TextField(
          key: ValueKey('content-${estimateContentFields[index].$1}'),
          controller: _controllers[index],
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: estimateContentFields[index].$2,
            helperText: estimateContentFields[index].$3,
            alignLabelWithHint: true,
          ),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 14),
      ],
    ],
  );

  void _sync() {
    _autosave?.cancel();
    _save();
    _content = widget.service.syncFromScope(
      widget.scope!.current(widget.projectId)!,
    );
    for (var index = 0; index < _controllers.length; index++) {
      _controllers[index].text = _content.values[index];
    }
    setState(() => _status = 'Saved from Scope Brief');
  }

  Future<void> _showHistory() async {
    final revisions = widget.service.revisions(widget.projectId);
    final selected = await showDialog<EstimateContentRevision>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Estimate Content revisions'),
        children: [
          if (revisions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No earlier revisions.'),
            ),
          for (final revision in revisions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, revision),
              child: Text(
                '${revision.appliedAt.toIso8601String()} • ${revision.source}',
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    _content = widget.service.revert(widget.projectId, selected.id);
    for (var index = 0; index < _controllers.length; index++) {
      _controllers[index].text = _content.values[index];
    }
    if (mounted) setState(() => _status = 'Previous revision restored');
  }
}

class _RoadmapTab extends StatefulWidget {
  const _RoadmapTab({required this.projectId, required this.service});
  final String projectId;
  final RoadmapService service;
  @override
  State<_RoadmapTab> createState() => _RoadmapTabState();
}

class _RoadmapTabState extends State<_RoadmapTab> {
  late List<RoadmapEntry> _items;
  @override
  void initState() {
    super.initState();
    _items = widget.service.load(widget.projectId);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 10,
        children: [
          FilledButton.icon(
            key: const ValueKey('refreshRoadmap'),
            onPressed: () => setState(
              () => _items = widget.service.refresh(widget.projectId),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh from drawings'),
          ),
          OutlinedButton(
            key: const ValueKey('resetRoadmap'),
            onPressed: _reset,
            child: const Text('Reset roadmap'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      for (final item in _items)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${item.phase} • ${item.outputs}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<RoadmapStatus>(
                        key: ValueKey('roadmapStatus-${item.itemKey}'),
                        isExpanded: true,
                        initialValue: item.status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: RoadmapStatus.values
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(status.name),
                              ),
                            )
                            .toList(),
                        onChanged: (status) {
                          if (status != null) _save(item, status: status);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: item.reference,
                        decoration: const InputDecoration(
                          labelText: 'Drawing/specification reference',
                        ),
                        onFieldSubmitted: (value) =>
                            _save(item, reference: value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: item.notes,
                        decoration: const InputDecoration(
                          labelText: 'Estimator notes',
                        ),
                        onFieldSubmitted: (value) => _save(item, notes: value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  void _save(
    RoadmapEntry item, {
    RoadmapStatus? status,
    String? reference,
    String? notes,
  }) {
    widget.service.saveUserFields(
      widget.projectId,
      item.itemKey,
      status ?? item.status,
      reference ?? item.reference,
      notes ?? item.notes,
    );
    setState(() => _items = widget.service.load(widget.projectId));
  }

  void _reset() {
    final snapshot = widget.service.reset(widget.projectId);
    setState(() => _items = widget.service.load(widget.projectId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        content: const Text('Roadmap reset. A recovery snapshot was saved.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            widget.service.undoReset(widget.projectId, snapshot);
            if (mounted) {
              setState(() => _items = widget.service.load(widget.projectId));
            }
          },
        ),
      ),
    );
  }
}

class _TimeLogTab extends StatelessWidget {
  const _TimeLogTab({
    required this.projectId,
    required this.service,
    required this.revision,
    required this.onChanged,
  });
  final String projectId;
  final TimerService service;
  final int revision;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = service
        .history(projectId)
        .where((entry) => !entry.isActive)
        .toList();
    return ListView(
      key: ValueKey(revision),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Completed time entries',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No completed time entries.'),
          ),
        for (final entry in entries)
          ListTile(
            title: Text(entry.label),
            subtitle: Text(
              '${entry.startedAt.toIso8601String()} • ${_duration(entry.durationSeconds)}${entry.note.isEmpty ? '' : '\n${entry.note}'}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Adjust duration and note',
                  onPressed: () => _adjust(context, entry),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove from time log',
                  onPressed: () {
                    service.softDelete(projectId, entry.id);
                    onChanged();
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _adjust(BuildContext context, TimeEntry entry) async {
    final minutes = TextEditingController(
      text: (entry.durationSeconds / 60).round().toString(),
    );
    final note = TextEditingController(text: entry.note);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adjust time entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration in minutes',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      final value = int.tryParse(minutes.text);
      if (value != null && value >= 0) {
        service.adjust(projectId, entry.id, value * 60, note.text);
        onChanged();
      }
    }
    minutes.dispose();
    note.dispose();
  }
}

String _duration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

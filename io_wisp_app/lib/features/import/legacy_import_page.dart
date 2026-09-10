import 'package:flutter/material.dart';

import '../../application/legacy_import_service.dart';
import '../../domain/legacy_import.dart';
import '../../domain/project.dart';

class LegacyImportPage extends StatefulWidget {
  const LegacyImportPage({
    super.key,
    required this.service,
    required this.picker,
  });
  final LegacyImportService service;
  final LegacyFilePicker picker;
  @override
  State<LegacyImportPage> createState() => _LegacyImportPageState();
}

class _LegacyImportPageState extends State<LegacyImportPage> {
  ImportPreview? _preview;
  ImportResult? _result;
  String? _error;
  bool _busy = false;
  bool _reviewed = false;
  ConflictDecision _decision = ConflictDecision.undecided;

  @override
  void dispose() {
    widget.service.cancel();
    super.dispose();
  }

  Future<void> _select() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _result = null;
      _reviewed = false;
      _decision = ConflictDecision.undecided;
    });
    widget.service.cancel();
    try {
      final path = await widget.picker.selectJson();
      if (path != null) {
        final preview = await widget.service.preview(path);
        if (mounted) setState(() => _preview = preview);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The source could not be selected or validated. No import changes were made.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy || _result != null || _preview == null || !_reviewed) return;
    setState(() => _busy = true);
    final result = await widget.service.confirm(
      _preview!,
      confirmed: true,
      acceptedFindings: _reviewed,
      decision: _decision,
    );
    if (mounted) {
      setState(() {
        _result = result;
        _busy = false;
      });
    }
  }

  String _duplicateText(DuplicateStatus status) => switch (status) {
    DuplicateStatus.unrelated =>
      'Unrelated project — no duplicate evidence found',
    DuplicateStatus.exactSource =>
      'Exact previously imported source — will be skipped',
    DuplicateStatus.likelyProject =>
      'Likely duplicate project — legacy identity or original name matches',
    DuplicateStatus.sameName =>
      'Same name from a different source — decision required',
  };

  String get _action {
    final preview = _preview;
    if (preview == null || preview.blocked) return 'Import blocked';
    if (preview.duplicate == DuplicateStatus.exactSource ||
        _decision == ConflictDecision.skip) {
      return 'Skip — no changes';
    }
    if (preview.needsDecision && _decision == ConflictDecision.undecided) {
      return 'Choose a conflict decision';
    }
    return 'Ready to import — create a separate project and empty folder';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final result = _result;
    final success =
        result?.outcome == ImportOutcome.completed ||
        result?.outcome == ImportOutcome.completedWithWarnings;
    final canConfirm =
        !_busy &&
        result == null &&
        preview != null &&
        !preview.blocked &&
        _reviewed &&
        (!preview.needsDecision || _decision != ConflictDecision.undecided);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import Existing Project'),
          automaticallyImplyLeading: !_busy,
        ),
        body: Column(
          children: [
            if (_busy)
              const LinearProgressIndicator(key: ValueKey('importProgress')),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('importScroll'),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (result == null) ...[
                          Text(
                            'Preview only — no changes made',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Import project details from one IO Wisp Lite V0.0.5 JSON export. Drawings, Scope Brief, checklist, pricing and referenced files remain for later phases. Keep the original JSON.',
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: const ValueKey('selectLegacyJson'),
                              onPressed: _busy ? null : _select,
                              icon: const Icon(Icons.file_open_outlined),
                              label: Text(
                                _busy
                                    ? 'Validating source…'
                                    : 'Select JSON file',
                              ),
                            ),
                          ),
                        ],
                        if (_error != null)
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (result != null) ...[
                          Text(switch (result.outcome) {
                            ImportOutcome.completed => 'Import completed',
                            ImportOutcome.completedWithWarnings =>
                              'Import completed with warnings',
                            ImportOutcome.skipped => 'Duplicate skipped',
                            ImportOutcome.failed => 'Import failed',
                            ImportOutcome.inconsistent =>
                              'Import needs attention',
                          }, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 16),
                          SelectableText(result.message),
                          if (result.project != null) ...[
                            const SizedBox(height: 12),
                            SelectableText(
                              'Project: ${result.project!.name}\nUUID: ${result.project!.id}\nFolder: ${result.project!.safeFolderName}',
                            ),
                          ],
                          if (!success)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                onPressed: _select,
                                child: const Text('Select another source'),
                              ),
                            ),
                        ],
                        if (preview != null && result == null) ...[
                          const SizedBox(height: 20),
                          SelectableText(
                            'Source: ${preview.source.filename}\nFormat: ${preview.source.format}\nProject candidates: ${preview.source.candidate == null ? 0 : 1}',
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            'Proposed display name: ${preview.displayName}\nProposed safe folder: ${preview.folderName.isEmpty ? "Unavailable" : preview.folderName}\nConfigured root: ${preview.root}',
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Mapped and normalized fields',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final mapping
                              in preview.source.candidate?.mappings ??
                                  <FieldMapping>[])
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: SelectableText(
                                '${mapping.source} → ${mapping.destination}: ${mapping.value.isEmpty ? "(empty)" : mapping.value}${mapping.normalized ? " [normalized]" : ""}',
                              ),
                            ),
                          const SizedBox(height: 18),
                          Text(
                            'Duplicate status',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(_duplicateText(preview.duplicate)),
                          if (preview.matchingNames.isNotEmpty)
                            Text(
                              'Matching projects: ${preview.matchingNames.join(", ")}',
                            ),
                          if (preview.folderCollision)
                            const Text(
                              'Folder-name collision: an unused suffix is proposed.',
                            ),
                          if (preview.needsDecision) ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<ConflictDecision>(
                              key: const ValueKey('importConflict'),
                              initialValue: _decision,
                              decoration: const InputDecoration(
                                labelText: 'Conflict decision',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: ConflictDecision.undecided,
                                  child: Text('Choose a decision'),
                                ),
                                DropdownMenuItem(
                                  value: ConflictDecision.skip,
                                  child: Text('Skip this project'),
                                ),
                                DropdownMenuItem(
                                  value: ConflictDecision.importSeparate,
                                  child: Text('Import as a separate project'),
                                ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      _decision = value!;
                                      _reviewed = false;
                                    }),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Proposed action: $_action',
                            key: const ValueKey('importAction'),
                          ),
                          for (final level in FindingLevel.values) ...[
                            const SizedBox(height: 18),
                            Text(switch (level) {
                              FindingLevel.fatal => 'Fatal — import blocked',
                              FindingLevel.warning =>
                                'Warnings and unsupported fields',
                              FindingLevel.information =>
                                'Information and normalization',
                              FindingLevel.deferred =>
                                'Deferred — not migrated',
                            }, style: Theme.of(context).textTheme.titleMedium),
                            if (!preview.findings.any((f) => f.level == level))
                              const Text('None'),
                            for (final finding in preview.findings.where(
                              (f) => f.level == level,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SelectableText(
                                  '${finding.field}: ${finding.message}',
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preview != null && result == null)
                    CheckboxListTile(
                      key: const ValueKey('acceptImportFindings'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _reviewed,
                      onChanged: _busy || preview.blocked
                          ? null
                          : (value) => setState(() => _reviewed = value!),
                      title: const Text(
                        'I reviewed the mappings and findings, including data that will not be migrated.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const ValueKey('cancelImport'),
                        onPressed: _busy
                            ? null
                            : () {
                                widget.service.cancel();
                                Navigator.of(context).pop<Project>();
                              },
                        child: Text(result == null ? 'Cancel' : 'Close'),
                      ),
                      const SizedBox(width: 12),
                      if (success)
                        FilledButton(
                          key: const ValueKey('openImportedProject'),
                          onPressed: () =>
                              Navigator.of(context).pop(result!.project),
                          child: const Text('Open imported project'),
                        )
                      else if (result == null)
                        FilledButton(
                          key: const ValueKey('confirmImport'),
                          onPressed: canConfirm ? _confirm : null,
                          child: const Text('Confirm Import'),
                        ),
                    ],
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

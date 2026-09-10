import 'package:flutter/material.dart';

import '../../application/scope_service.dart';
import '../../domain/project.dart';
import '../../domain/scope.dart';

class ScopePage extends StatefulWidget {
  const ScopePage({super.key, required this.project, required this.service});
  final Project project;
  final ScopeService service;
  @override
  State<ScopePage> createState() => _ScopePageState();
}

class _ScopePageState extends State<ScopePage> {
  final _raw = TextEditingController();
  bool _strict = true, _loaded = false;
  ScopeRevision? _current;
  String? _error, _notice;
  bool get _dirty =>
      _raw.text != (_current?.raw ?? '') ||
      _strict != (_current?.strict ?? true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ScopePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.service != widget.service) {
      _current = null;
      _raw.clear();
      _strict = true;
      _loaded = false;
      _error = null;
      _notice = null;
      _load();
    }
  }

  void _load() {
    try {
      _current = widget.service.current(widget.project.id);
      _raw.text = _current?.raw ?? '';
      _strict = _current?.strict ?? true;
      _loaded = true;
    } catch (e) {
      _error = 'Scope Brief could not be loaded. $e';
    }
  }

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  void _save(ScopeRevision Function() action, {bool replaceDraft = false}) {
    setState(() {
      _notice = null;
      _error = null;
    });
    try {
      final revision = action();
      setState(() {
        _current = revision;
        if (replaceDraft) {
          _raw.text = revision.raw;
          _strict = revision.strict;
        }
        _notice = 'Revision ${revision.order} saved.';
      });
    } catch (e) {
      setState(
        () => _error =
            'Scope was not saved. The prior applied revision is unchanged. $e',
      );
    }
  }

  Future<void> _override(ScopeResult result) async {
    final projectId = widget.project.id;
    final revisionId = _current!.id;
    final note = TextEditingController(text: result.manualReason ?? '');
    var choice = result.manual?.name ?? result.detected.name;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            'Override ${scopePackages.firstWhere((p) => p.id == result.packageId).label}',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Detected: ${result.detected.label}. ${result.reason}'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('overrideDecision'),
                  initialValue: choice,
                  items: [
                    const DropdownMenuItem(
                      value: 'detector',
                      child: Text('Use detector (clear override)'),
                    ),
                    ...ScopeDecision.values.map(
                      (d) =>
                          DropdownMenuItem(value: d.name, child: Text(d.label)),
                    ),
                  ],
                  onChanged: (v) => update(() => choice = v!),
                  decoration: const InputDecoration(
                    labelText: 'Manual decision',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('overrideReason'),
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason / estimator instruction (required)',
                  ),
                  onChanged: (_) => update(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('saveOverride'),
              onPressed: choice == 'detector' || note.text.trim().isNotEmpty
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Save override'),
            ),
          ],
        ),
      ),
    );
    final reason = note.text;
    // Dialog's closing animation may still reference the controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    note.dispose();
    if (accepted != true || !mounted || widget.project.id != projectId) return;
    _save(
      () => widget.service.override(
        projectId,
        revisionId,
        result.packageId,
        choice == 'detector' ? null : ScopeDecision.values.byName(choice),
        reason,
      ),
    );
  }

  Future<void> _history() async {
    final projectId = widget.project.id;
    final currentId = _current?.id;
    List<ScopeRevision> history;
    try {
      history = widget.service.history(widget.project.id);
    } catch (e) {
      setState(() {
        _notice = null;
        _error = 'History could not be loaded. $e';
      });
      return;
    }
    final selected = await showDialog<ScopeRevision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Applied revision history'),
        content: SizedBox(
          width: 800,
          height: 520,
          child: ListView(
            children: history
                .map(
                  (r) => ExpansionTile(
                    key: ValueKey('history-${r.order}'),
                    title: Text(
                      'Revision ${r.order} • ${r.action}${r.id == _current?.id ? ' • current' : ''}',
                    ),
                    subtitle: Text(
                      '${r.appliedAt.toUtc().toIso8601String()} • ${r.strict ? 'Strict' : 'Non-strict'}',
                    ),
                    children: [
                      SelectableText(
                        'Revision ID: ${r.id}\nInterpreter: ${r.interpreterVersion}\n${r.restoredFrom == null ? '' : 'Restored from: ${r.restoredFrom}\n'}Raw brief:\n${r.raw.isEmpty ? '(empty)' : r.raw}',
                      ),
                      ...r.results.map(
                        (v) => ListTile(
                          title: Text(
                            '${scopePackages.firstWhere((p) => p.id == v.packageId).label}: ${v.effective.label}',
                          ),
                          subtitle: Text(
                            'Detected: ${v.detected.label}\n${v.reason}\n${v.evidence.join('\n')}\nManual: ${v.manual?.label ?? 'None'}${v.manualReason == null ? '' : ' — ${v.manualReason}'}',
                          ),
                        ),
                      ),
                      if (r.id != _current?.id)
                        FilledButton(
                          key: ValueKey('revert-${r.order}'),
                          onPressed: () => Navigator.pop(context, r),
                          child: const Text('Revert as a new revision'),
                        ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted || selected == null || widget.project.id != projectId) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore revision ${selected.order}?'),
        content: const Text(
          'This saves a new revision with the selected raw text, strict mode and manual decisions. Prior history stays intact. Any unapplied editor changes will be replaced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirmRevert'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore revision'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true || widget.project.id != projectId) return;
    _save(
      () => widget.service.revert(
        projectId,
        selected.id,
        expectedCurrent: currentId,
      ),
      replaceDraft: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final counts = {
      for (final d in ScopeDecision.values)
        d: current?.results.where((r) => r.effective == d).length ?? 0,
    };
    return Scaffold(
      appBar: AppBar(title: Text('Scope Brief — ${widget.project.name}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Paste or type the scope instructions. Apply saves a complete revision. Editor changes are not saved until Apply.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('scopeRaw'),
                  controller: _raw,
                  enabled: _loaded,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Raw Scope Brief',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                SwitchListTile(
                  key: const ValueKey('scopeStrict'),
                  value: _strict,
                  title: const Text('Strict scope mode'),
                  subtitle: const Text(
                    'Unmentioned packages: Hold / clarify in strict mode; Review in non-strict mode.',
                  ),
                  onChanged: _loaded
                      ? (v) => setState(() => _strict = v)
                      : null,
                ),
                const Text(
                  'Exclusions take precedence. Applying changed trimmed text clears prior manual overrides. Empty text produces all Hold / clarify (or Review).',
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('applyScope'),
                      onPressed: _loaded
                          ? () => _save(
                              () => widget.service.apply(
                                widget.project.id,
                                _raw.text,
                                _strict,
                                expectedCurrent: _current?.id,
                              ),
                            )
                          : null,
                      child: const Text('Apply Scope Brief'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('scopeHistory'),
                      onPressed: current == null ? null : _history,
                      child: const Text('Revision history'),
                    ),
                    if (_dirty)
                      TextButton(
                        key: const ValueKey('discardScopeDraft'),
                        onPressed: () => setState(() {
                          _raw.text = current?.raw ?? '';
                          _strict = current?.strict ?? true;
                        }),
                        child: const Text('Discard editor changes'),
                      ),
                  ],
                ),
                if (_dirty)
                  const Text(
                    'Unapplied editor changes. The gate below still shows the last saved revision.',
                    key: ValueKey('scopeDirty'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      key: const ValueKey('scopeError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_notice != null)
                  Text(_notice!, key: const ValueKey('scopeNotice')),
                const SizedBox(height: 18),
                if (current == null)
                  const Text('No applied Scope Brief yet.')
                else ...[
                  Text(
                    'Applied revision ${current.order} • ${current.appliedAt.toUtc().toIso8601String()} • ${current.strict ? 'Strict' : 'Non-strict'}',
                  ),
                  Text(
                    '${counts[ScopeDecision.included]} Included / ${counts[ScopeDecision.rejected]} Rejected / ${counts[ScopeDecision.held]} Held / ${counts[ScopeDecision.review]} Review',
                    key: const ValueKey('scopeCounts'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...current.results.map(
                    (r) => Card(
                      key: ValueKey('scope-${r.packageId}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scopePackages
                                  .firstWhere((p) => p.id == r.packageId)
                                  .label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Effective: ${r.effective.label}${r.manual == null ? '' : ' • MANUAL OVERRIDE'}',
                            ),
                            Text('Detected: ${r.detected.label}'),
                            Text('Detector reason: ${r.reason}'),
                            SelectableText(
                              'Source: ${r.evidence.isEmpty ? 'No inclusion/exclusion matched in revision ${current.order}.' : r.evidence.join('\n')}',
                            ),
                            Text(
                              'Manual decision: ${r.manual?.label ?? 'None'}${r.manualReason == null ? '' : '\nManual reason: ${r.manualReason}'}',
                            ),
                            TextButton(
                              key: ValueKey('override-${r.packageId}'),
                              onPressed: _dirty ? null : () => _override(r),
                              child: const Text('Set / clear manual override'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

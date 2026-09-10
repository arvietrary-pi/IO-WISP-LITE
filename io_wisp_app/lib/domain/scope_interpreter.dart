import 'scope.dart';

/// No UI, database, platform, clock, or network dependencies.
class ScopeInterpreter {
  const ScopeInterpreter();
  static const version = 'scope/1';
  static const maxLength = 64000;
  static const _exclude =
      r'not\s+included|do\s+not\s+include|out\s+of\s+scope|exclusions?|exclude(?:d|s)?|excluding|but\s+not|except';
  static const _include =
      r'scope\s+of\s+work|in\s+scope|inclusions?|include(?:d|s)?';
  static const _clarify = r'clarifications?|rfis?|questions?|undecided';
  static final _directive = RegExp(
    '\\b(?:$_exclude|$_include|$_clarify)\\b|^\\s*scope\\b',
    caseSensitive: false,
  );
  static final _excluded = RegExp('^(?:$_exclude)\$', caseSensitive: false);
  static final _clarified = RegExp('^(?:$_clarify)\$', caseSensitive: false);
  static final _all = RegExp(
    r'^(?:all|all\s+(?:others?|remaining|work|works|scope|trades?|packages?|other\s+(?:work|works|scope|trades?|packages?))|everything(?:\s+else)?|the\s+rest|remaining\s+(?:work|works|scope|trades?|packages?))[.!?]?$',
    caseSensitive: false,
  );

  List<ScopeResult> interpret(String raw, {required bool strict}) {
    if (raw.length > maxLength ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(raw)) {
      throw const FormatException(
        'Scope Brief must be at most 64,000 characters and contain no control characters other than tabs/newlines.',
      );
    }
    final clauses = <({String section, String payload, String source})>[];
    var section = 'included';
    // Separators retain section state for legacy heading/list syntax.
    for (final line in raw.split(RegExp(r'[\r\n;,/.!?]+'))) {
      final matches = _directive.allMatches(line).toList();
      void add(String payload, String source) {
        payload = payload
            .trim()
            .replaceFirst(RegExp(r'^[-*•\d.)\s:]+'), '')
            .trim();
        if (payload.isNotEmpty) {
          clauses.add((
            section: section,
            payload: payload,
            source: source.trim(),
          ));
        }
      }

      if (matches.isEmpty) {
        add(line, line);
        continue;
      }
      add(
        line.substring(0, matches.first.start),
        line.substring(0, matches.first.start),
      );
      for (var i = 0; i < matches.length; i++) {
        final m = matches[i];
        final word = m.group(0)!;
        section = _excluded.hasMatch(word)
            ? 'excluded'
            : _clarified.hasMatch(word)
            ? 'clarifications'
            : 'included';
        final end = i + 1 < matches.length ? matches[i + 1].start : line.length;
        add(line.substring(m.end, end), line.substring(m.start, end));
      }
    }
    final all = clauses
        .where((c) => c.section == 'included' && _all.hasMatch(c.payload))
        .toList();
    return scopePackages
        .map((package) {
          final excluded = <String>[];
          final included = <String>[];
          final clarified = <String>[];
          for (final clause in clauses) {
            final terms = package.terms
                .where((term) => _matches(clause.payload, term))
                .toList();
            if (terms.isEmpty) continue;
            final target = clause.section == 'excluded'
                ? excluded
                : clause.section == 'included'
                ? included
                : clarified;
            target.add('${clause.source} [matched: ${terms.join(', ')}]');
          }
          final decision = excluded.isNotEmpty
              ? ScopeDecision.rejected
              : included.isNotEmpty || all.isNotEmpty
              ? ScopeDecision.included
              : strict
              ? ScopeDecision.held
              : ScopeDecision.review;
          return ScopeResult(
            packageId: package.id,
            detected: decision,
            reason: excluded.isNotEmpty
                ? 'Explicitly excluded by the brief; exclusion takes precedence'
                : included.isNotEmpty
                ? 'Explicitly included by the brief'
                : all.isNotEmpty
                ? 'Included by the all-others instruction'
                : 'Not explicitly included',
            evidence: [
              ...excluded,
              ...included,
              ...all.map((c) => c.source),
              ...clarified.map((s) => 'Clarification only: $s'),
            ],
          );
        })
        .toList(growable: false);
  }

  static bool _matches(String text, String term) {
    // Explicit regular plurals retain legacy matches without matching "empower"
    // as power or "profile" as any partial token. No stemming/inference.
    const plurals = {
      'footing': 'footings',
      'foundation': 'foundations',
      'slab': 'slabs',
      'beam': 'beams',
      'column': 'columns',
      'truss': 'trusses',
      'partition': 'partitions',
      'roof': 'roofs',
      'gutter': 'gutters',
      'door': 'doors',
      'window': 'windows',
      'finish': 'finishes',
      'ceiling': 'ceilings',
      'tile': 'tiles',
      'water line': 'water lines',
      'sewer': 'sewers',
      'sprinkler': 'sprinklers',
      'fire alarm': 'fire alarms',
      'curb': 'curbs',
      'fence': 'fences',
    };
    final forms = [term, if (plurals.containsKey(term)) plurals[term]!];
    final pattern = forms
        .map((s) => s.split(' ').map(RegExp.escape).join(r'\s+'))
        .join('|');
    return RegExp(
      '(?<![a-z0-9_])(?:$pattern)(?![a-z0-9_])',
      caseSensitive: false,
    ).hasMatch(text);
  }
}

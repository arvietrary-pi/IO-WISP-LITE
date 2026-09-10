enum ScopeDecision {
  included('Included'),
  rejected('Rejected'),
  held('Hold / clarify'),
  review('Review');

  const ScopeDecision(this.label);
  final String label;
}

class ScopePackage {
  const ScopePackage(this.id, this.label, this.terms);
  final String id, label;
  final List<String> terms;
}

/// The V0.0.5 catalog (HTML SCOPE_PACKAGES), shared by all native layers.
const scopePackages = <ScopePackage>[
  ScopePackage('preliminaries', 'Preliminaries / mobilization', [
    'preliminaries',
    'preliminary works',
    'prelims',
    'prelim',
    'mobilization',
    'temporary facilities',
    'general requirements',
    'supervision',
    'permits',
  ]),
  ScopePackage('demolition', 'Demolition / removal', [
    'demolition',
    'removal',
    'strip out',
    'disposal',
    'hauling',
  ]),
  ScopePackage('earthworks', 'Earthworks / site preparation', [
    'earthworks',
    'excavation',
    'backfill',
    'grading',
    'site preparation',
  ]),
  ScopePackage('concrete', 'Concrete / foundations', [
    'concrete',
    'footing',
    'foundation',
    'slab',
    'formwork',
  ]),
  ScopePackage('reinforcement', 'Reinforcement', [
    'reinforcement',
    'rebar',
    'reinforcing steel',
  ]),
  ScopePackage('structural', 'Structural framing', [
    'structural framing',
    'structural steel',
    'beam',
    'column',
    'truss',
  ]),
  ScopePackage('masonry', 'Masonry / partitions', [
    'masonry',
    'chb',
    'blockwork',
    'partition',
  ]),
  ScopePackage('roofing', 'Roofing / waterproofing', [
    'roof',
    'roofing',
    'waterproofing',
    'flashing',
    'gutter',
  ]),
  ScopePackage('openings', 'Doors / windows / glazing', [
    'door',
    'window',
    'glazing',
    'hardware',
  ]),
  ScopePackage('finishes', 'Architectural finishes', [
    'finish',
    'flooring',
    'ceiling',
    'painting',
    'tile',
  ]),
  ScopePackage('plumbing', 'Plumbing / sanitary', [
    'plumbing',
    'sanitary',
    'water line',
    'sewer',
  ]),
  ScopePackage('electrical', 'Electrical / lighting', [
    'electrical',
    'lighting',
    'power',
    'wiring',
  ]),
  ScopePackage('mechanical', 'Mechanical / HVAC', [
    'mechanical',
    'hvac',
    'air conditioning',
    'ventilation',
  ]),
  ScopePackage('fire', 'Fire / life safety', [
    'fire protection',
    'sprinkler',
    'fire alarm',
    'life safety',
  ]),
  ScopePackage('external', 'External works / drainage', [
    'external works',
    'drainage',
    'paving',
    'curb',
    'fence',
    'landscape',
  ]),
  ScopePackage('testing', 'Testing / commissioning', [
    'testing',
    'test and commissioning',
    't&c',
    'commissioning',
    'inspection',
    'handover',
  ]),
];

class ScopeResult {
  ScopeResult({
    required this.packageId,
    required this.detected,
    required this.reason,
    required List<String> evidence,
    this.manual,
    this.manualReason,
  }) : evidence = List.unmodifiable(evidence);
  final String packageId, reason;
  final ScopeDecision detected;
  final List<String> evidence;
  final ScopeDecision? manual;
  final String? manualReason;
  ScopeDecision get effective => manual ?? detected;
  ScopeResult overrideWith(ScopeDecision? decision, String? note) =>
      ScopeResult(
        packageId: packageId,
        detected: detected,
        reason: reason,
        evidence: evidence,
        manual: decision,
        manualReason: decision == null ? null : note,
      );
}

class ScopeRevision {
  ScopeRevision({
    required this.id,
    required this.projectId,
    required this.order,
    required this.raw,
    required this.strict,
    required this.appliedAt,
    required this.action,
    required this.interpreterVersion,
    required List<ScopeResult> results,
    this.parentId,
    this.restoredFrom,
  }) : results = List.unmodifiable(results);
  final String id, projectId, raw, action, interpreterVersion;
  final String? parentId, restoredFrom;
  final int order;
  final bool strict;
  final DateTime appliedAt;
  final List<ScopeResult> results;
}

abstract interface class ScopeRepository {
  ScopeRevision? current(String projectId);
  List<ScopeRevision> history(String projectId);
  ScopeRevision get(String projectId, String revisionId);

  /// Atomically append a complete revision if parentId is still current.
  void append(ScopeRevision revision);
}

void validateScopeResults(List<ScopeResult> results) {
  final expected = scopePackages.map((p) => p.id).toSet();
  if (results.length != expected.length ||
      results.map((r) => r.packageId).toSet().length != expected.length ||
      results.any(
        (r) =>
            !expected.contains(r.packageId) ||
            r.reason.isEmpty ||
            (r.manual == null
                ? r.manualReason != null
                : (r.manualReason?.trim().isEmpty ?? true)),
      )) {
    throw const FormatException(
      'Scope results must contain all 16 packages and valid evidence/override reasons.',
    );
  }
}

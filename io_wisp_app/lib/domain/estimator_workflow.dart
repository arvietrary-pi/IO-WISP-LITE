import 'scope.dart';

const checklistTemplateVersion = 'checklist/1';

class ChecklistTemplateItem {
  const ChecklistTemplateItem(
    this.key,
    this.sectionKey,
    this.sectionTitle,
    this.itemOrder,
    this.title,
    this.prompt,
  );

  final String key, sectionKey, sectionTitle, title, prompt;
  final int itemOrder;
}

/// The 49-item V0.0.5 estimator checklist with stable native keys.
const estimatorChecklistCatalog = <ChecklistTemplateItem>[
  ChecklistTemplateItem(
    'chk_set_project_identity',
    'sec_set_control',
    'Set control',
    1,
    'Project identity recorded',
    'Name, location, client, estimator, issue/tender date, and currency are recorded.',
  ),
  ChecklistTemplateItem(
    'chk_set_complete_set',
    'sec_set_control',
    'Set control',
    2,
    'Complete set received',
    'Drawing package, specifications, addenda, and referenced reports are available.',
  ),
  ChecklistTemplateItem(
    'chk_set_latest_revision',
    'sec_set_control',
    'Set control',
    3,
    'Latest revision identified',
    'Issue number/date and superseded information are identified.',
  ),
  ChecklistTemplateItem(
    'chk_set_scope_boundaries',
    'sec_set_control',
    'Set control',
    4,
    'Scope boundaries recorded',
    'Inclusions, exclusions, alternates, provisional sums, and owner-supplied items are noted.',
  ),
  ChecklistTemplateItem(
    'chk_set_pricing_basis',
    'sec_set_control',
    'Set control',
    5,
    'Pricing basis recorded',
    'Tax, escalation, estimate validity, labor basis, and rate date are stated.',
  ),
  ChecklistTemplateItem(
    'chk_set_document_register',
    'sec_set_control',
    'Set control',
    6,
    'Document register checked',
    'Page count, sheet numbers, drawing schedule, and missing documents are reviewed.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_scale_units',
    'sec_drawing_review',
    'Drawing review',
    7,
    'Scale and units checked',
    'Scale, units, north/orientation, and any not-to-scale notes are verified.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_site_constraints',
    'sec_drawing_review',
    'Drawing review',
    8,
    'Site constraints reviewed',
    'Boundary, access, setbacks, levels, existing conditions, and working space are reviewed.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_plans_reconciled',
    'sec_drawing_review',
    'Drawing review',
    9,
    'Plans reconciled',
    'Floor plans agree with areas, room schedules, elevations, and sections.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_heights_levels',
    'sec_drawing_review',
    'Drawing review',
    10,
    'Heights and levels confirmed',
    'Elevations, sections, roof lines, ceiling heights, and level changes are checked.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_details_schedules',
    'sec_drawing_review',
    'Drawing review',
    11,
    'Details and schedules checked',
    'Details, legends, door/window schedules, finish schedules, and notes are reviewed.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_structural',
    'sec_drawing_review',
    'Drawing review',
    12,
    'Structural information reviewed',
    'Foundation, slab, framing, reinforcement, structural notes, and details are included.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_mep_fire',
    'sec_drawing_review',
    'Drawing review',
    13,
    'MEP and fire interfaces reviewed',
    'Services, penetrations, equipment, fire/life safety, and coordination requirements are included.',
  ),
  ChecklistTemplateItem(
    'chk_drawings_demolition',
    'sec_drawing_review',
    'Drawing review',
    14,
    'Existing/demolition work reviewed',
    'Demolition, protection, temporary works, and make-good requirements are captured.',
  ),
  ChecklistTemplateItem(
    'chk_scope_preliminaries',
    'sec_scope_capture',
    'Scope capture',
    15,
    'Preliminaries and mobilization',
    'Permits, supervision, temporary facilities, protection, mobilization, and demobilization.',
  ),
  ChecklistTemplateItem(
    'chk_scope_sitework',
    'sec_scope_capture',
    'Scope capture',
    16,
    'Sitework and demolition',
    'Clearing, demolition, excavation, fill, hauling, disposal, and site preparation.',
  ),
  ChecklistTemplateItem(
    'chk_scope_substructure',
    'sec_scope_capture',
    'Scope capture',
    17,
    'Substructure',
    'Foundations, footings, piles, slabs, retaining elements, waterproofing, and below-grade works.',
  ),
  ChecklistTemplateItem(
    'chk_scope_structure',
    'sec_scope_capture',
    'Scope capture',
    18,
    'Structure and framing',
    'Concrete, reinforcement, steel, masonry, timber, framing, beams, columns, and supports.',
  ),
  ChecklistTemplateItem(
    'chk_scope_envelope_roof',
    'sec_scope_capture',
    'Scope capture',
    19,
    'Envelope and roof',
    'Roofing, waterproofing, cladding, insulation, doors, windows, and sealants.',
  ),
  ChecklistTemplateItem(
    'chk_scope_interiors',
    'sec_scope_capture',
    'Scope capture',
    20,
    'Interiors and finishes',
    'Partitions, ceilings, flooring, painting, joinery, fixtures, and equipment.',
  ),
  ChecklistTemplateItem(
    'chk_scope_external',
    'sec_scope_capture',
    'Scope capture',
    21,
    'External works',
    'Paving, fences, drainage, utilities, landscape, roads, curbs, and reinstatement.',
  ),
  ChecklistTemplateItem(
    'chk_scope_services',
    'sec_scope_capture',
    'Scope capture',
    22,
    'Services and commissioning',
    'Mechanical, electrical, plumbing/hydraulic, fire, testing, commissioning, and handover.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_source_reference',
    'sec_takeoff_quality',
    'Takeoff quality',
    23,
    'Source reference on each line',
    'Each quantity points to a sheet, page, detail, schedule, specification, or field record.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_dimensions',
    'sec_takeoff_quality',
    'Takeoff quality',
    24,
    'Dimensions cross-checked',
    'Dimensions, scale, areas, perimeters, levels, and counts are checked.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_openings',
    'sec_takeoff_quality',
    'Takeoff quality',
    25,
    'Openings and overlaps checked',
    'Voids, openings, overlaps, and duplicate scope are removed or documented.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_waste_laps',
    'sec_takeoff_quality',
    'Takeoff quality',
    26,
    'Waste and laps recorded',
    'Waste, laps, cuts, and overage are shown separately from net quantities.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_units',
    'sec_takeoff_quality',
    'Takeoff quality',
    27,
    'Units are consistent',
    'Units, conversions, and decimal precision are consistent throughout the takeoff.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_exact_allowance',
    'sec_takeoff_quality',
    'Takeoff quality',
    28,
    'Exact vs allowance separated',
    'Measured quantities are not mixed with assumptions, provisional quantities, or allowances.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_conflicts',
    'sec_takeoff_quality',
    'Takeoff quality',
    29,
    'Conflicts logged',
    'Drawing/specification conflicts, unclear notes, and missing details are recorded for RFI.',
  ),
  ChecklistTemplateItem(
    'chk_takeoff_totals',
    'sec_takeoff_quality',
    'Takeoff quality',
    30,
    'Totals reconciled',
    'Quantities are checked against schedules, typical units, areas, and overall project totals.',
  ),
  ChecklistTemplateItem(
    'chk_pricing_material_rates',
    'sec_pricing_boq',
    'Pricing and BOQ',
    31,
    'Material rate basis recorded',
    'Supplier, quote date, brand/specification, delivery, and validity are recorded.',
  ),
  ChecklistTemplateItem(
    'chk_pricing_labor',
    'sec_pricing_boq',
    'Pricing and BOQ',
    32,
    'Labor productivity recorded',
    'Crew composition, productivity, work hours, and wage basis are stated.',
  ),
  ChecklistTemplateItem(
    'chk_pricing_plant_access',
    'sec_pricing_boq',
    'Pricing and BOQ',
    33,
    'Plant and access considered',
    'Equipment, lifting, access, temporary works, haulage, and disposal are included where needed.',
  ),
  ChecklistTemplateItem(
    'chk_pricing_subcontractors',
    'sec_pricing_boq',
    'Pricing and BOQ',
    34,
    'Subcontractor coverage checked',
    'Trade packages, quotes, gaps, and quote comparisons are documented.',
  ),
  ChecklistTemplateItem(
    'chk_pricing_commercial',
    'sec_pricing_boq',
    'Pricing and BOQ',
    35,
    'Commercial additions checked',
    'Waste, taxes, overhead, profit, contingency, insurance, and escalation are addressed.',
  ),
  ChecklistTemplateItem(
    'chk_pricing_alternates',
    'sec_pricing_boq',
    'Pricing and BOQ',
    36,
    'Alternates and exclusions marked',
    'Alternates, provisional sums, exclusions, and owner-supplied items are unmistakable.',
  ),
  ChecklistTemplateItem(
    'chk_pricing_arithmetic',
    'sec_pricing_boq',
    'Pricing and BOQ',
    37,
    'Arithmetic checked',
    'Extensions, subtotals, unit-rate builds, and final totals have been checked.',
  ),
  ChecklistTemplateItem(
    'chk_risk_logistics',
    'sec_risk',
    'Constructability and risk',
    38,
    'Site logistics reviewed',
    'Access, storage, traffic, neighbors, laydown, and working space are considered.',
  ),
  ChecklistTemplateItem(
    'chk_risk_sequence',
    'sec_risk',
    'Constructability and risk',
    39,
    'Sequence and temporary support reviewed',
    'Construction sequence, temporary support, dewatering, and protection are considered.',
  ),
  ChecklistTemplateItem(
    'chk_risk_long_lead',
    'sec_risk',
    'Constructability and risk',
    40,
    'Long-lead items identified',
    'Procurement lead times, approvals, samples, and substitutions are identified.',
  ),
  ChecklistTemplateItem(
    'chk_risk_safety_permits',
    'sec_risk',
    'Constructability and risk',
    41,
    'Safety and permits identified',
    'Permits, inspections, code obligations, testing, and safety controls are recorded.',
  ),
  ChecklistTemplateItem(
    'chk_risk_ground_weather',
    'sec_risk',
    'Constructability and risk',
    42,
    'Ground/weather risk recorded',
    'Ground conditions, weather exposure, water, and seasonal risks are addressed.',
  ),
  ChecklistTemplateItem(
    'chk_risk_rfis_unknowns',
    'sec_risk',
    'Constructability and risk',
    43,
    'RFIs and unknowns assigned',
    'Open questions have an owner, required response, and effect on cost or schedule.',
  ),
  ChecklistTemplateItem(
    'chk_risk_qa_testing',
    'sec_risk',
    'Constructability and risk',
    44,
    'QA/QC and testing included',
    'Inspection, testing, commissioning, records, and corrective work are considered.',
  ),
  ChecklistTemplateItem(
    'chk_issue_scope_alignment',
    'sec_final_issue',
    'Final issue',
    45,
    'Estimate agrees with scope',
    'Takeoff, BOQ, estimate, assumptions, exclusions, and clarifications are aligned.',
  ),
  ChecklistTemplateItem(
    'chk_issue_flags_visible',
    'sec_final_issue',
    'Final issue',
    46,
    'Unresolved flags are visible',
    'Review items and limitations are carried into the final package.',
  ),
  ChecklistTemplateItem(
    'chk_issue_file_control',
    'sec_final_issue',
    'Final issue',
    47,
    'Files and revisions are controlled',
    'File names, revision/date, source set, and issue record are complete.',
  ),
  ChecklistTemplateItem(
    'chk_issue_package',
    'sec_final_issue',
    'Final issue',
    48,
    'Final package assembled',
    'TOC, takeoff, BOQ, pricing basis, assumptions, exclusions, RFIs, and risk notes are included.',
  ),
  ChecklistTemplateItem(
    'chk_issue_independent_review',
    'sec_final_issue',
    'Final issue',
    49,
    'Independent review completed',
    'A second pass or independent check has been completed for key quantities and totals.',
  ),
];

class ChecklistEntry {
  const ChecklistEntry({
    required this.id,
    required this.projectId,
    required this.templateKey,
    required this.isDone,
    required this.note,
    required this.updatedAt,
    this.evidencePage,
  });

  final String id, projectId, templateKey, note;
  final bool isDone;
  final int? evidencePage;
  final DateTime updatedAt;

  ChecklistTemplateItem get template =>
      estimatorChecklistCatalog.firstWhere((item) => item.key == templateKey);
}

class EstimateContent {
  const EstimateContent({
    required this.projectId,
    required this.scope,
    required this.basis,
    required this.assumptions,
    required this.exclusions,
    required this.rfis,
    required this.risks,
    required this.rates,
    required this.changes,
    required this.updatedAt,
  });

  final String projectId,
      scope,
      basis,
      assumptions,
      exclusions,
      rfis,
      risks,
      rates,
      changes;
  final DateTime updatedAt;

  List<String> get values => [
    scope,
    basis,
    assumptions,
    exclusions,
    rfis,
    risks,
    rates,
    changes,
  ];
  EstimateContent copyWith({
    String? scope,
    String? basis,
    String? assumptions,
    String? exclusions,
    String? rfis,
    String? risks,
    String? rates,
    String? changes,
    DateTime? updatedAt,
  }) => EstimateContent(
    projectId: projectId,
    scope: scope ?? this.scope,
    basis: basis ?? this.basis,
    assumptions: assumptions ?? this.assumptions,
    exclusions: exclusions ?? this.exclusions,
    rfis: rfis ?? this.rfis,
    risks: risks ?? this.risks,
    rates: rates ?? this.rates,
    changes: changes ?? this.changes,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class EstimateContentRevision {
  const EstimateContentRevision({
    required this.id,
    required this.content,
    required this.appliedAt,
    required this.source,
  });
  final String id, source;
  final EstimateContent content;
  final DateTime appliedAt;
}

const estimateContentFields = <(String, String, String)>[
  (
    'scope',
    'Scope summary',
    'What is being priced and which work packages are included.',
  ),
  (
    'basis',
    'Drawing / specification basis',
    'Drawing set, specifications, reports, addenda, and site information used.',
  ),
  (
    'assumptions',
    'Assumptions and allowances',
    'Dimensions, productivity, waste, provisional quantities, design development, or access.',
  ),
  (
    'exclusions',
    'Exclusions / owner-supplied items',
    'Work, materials, taxes, permits, design, testing, or owner-supplied items not included.',
  ),
  (
    'rfis',
    'Clarifications / RFIs',
    'Question, source reference, responsible party, due date, response, and cost/schedule impact.',
  ),
  (
    'risks',
    'Risks and constructability',
    'Access, ground, weather, sequencing, temporary works, long-lead items, safety, and coordination risks.',
  ),
  (
    'rates',
    'Pricing basis',
    'Rate source/date, labor productivity, equipment, delivery, tax, overhead, profit, and contingency.',
  ),
  (
    'changes',
    'Revision / change log',
    'Date, revision, changed sheets/scope, affected quantities, pricing impact, and reviewer.',
  ),
];

enum RoadmapStatus { notStarted, inProgress, complete, deferred, notApplicable }

class RoadmapTemplateItem {
  const RoadmapTemplateItem(
    this.key,
    this.stepOrder,
    this.phase,
    this.title,
    this.purpose,
    this.outputs,
  );
  final String key, phase, title, purpose, outputs;
  final int stepOrder;
}

const roadmapBaseCatalog = <RoadmapTemplateItem>[
  RoadmapTemplateItem(
    'scope_review',
    100,
    'Scope review',
    'Confirm project and estimate basis',
    'Confirm scope boundaries, estimate basis, and unresolved decisions.',
    'Applied Scope Brief and estimate basis',
  ),
  RoadmapTemplateItem(
    'drawing_log',
    200,
    'Document review',
    'Build and verify the drawing log',
    'Review every physical page, drawing identifier, revision, and document-control flag.',
    'Verified Document Register',
  ),
  RoadmapTemplateItem(
    'quantity_takeoff',
    300,
    'Quantity takeoff',
    'Prepare traceable quantity takeoff',
    'Measure or count scope items and retain physical-page and detail references.',
    'Takeoff and source references',
  ),
  RoadmapTemplateItem(
    'rfis_clarifications',
    400,
    'Clarifications',
    'Resolve RFIs and scope clarifications',
    'Record missing information, responsibility, due dates, and cost effects.',
    'RFI and clarification log',
  ),
  RoadmapTemplateItem(
    'pricing_recap',
    500,
    'Pricing',
    'Build the pricing recap',
    'Reconcile material, labor, equipment, delivery, and commercial additions.',
    'Pricing recap and rate basis',
  ),
  RoadmapTemplateItem(
    'subcontractor_quotes',
    600,
    'Procurement',
    'Review subcontractor quotes',
    'Compare trade coverage, qualifications, validity, and gaps.',
    'Quote comparison and coverage notes',
  ),
  RoadmapTemplateItem(
    'risk_contingency',
    700,
    'Risk review',
    'Review risk and contingency',
    'Assess constructability, interfaces, unknowns, and contingency basis.',
    'Risk register and contingency basis',
  ),
  RoadmapTemplateItem(
    'final_submission',
    800,
    'Final submission',
    'Assemble and check the estimate package',
    'Reconcile scope, quantities, pricing, assumptions, exclusions, and issue controls.',
    'Auditable issue package',
  ),
];

class RoadmapEntry {
  const RoadmapEntry({
    required this.id,
    required this.projectId,
    required this.itemKey,
    required this.stepOrder,
    required this.phase,
    required this.title,
    required this.purpose,
    required this.outputs,
    required this.status,
    required this.reference,
    required this.notes,
    required this.updatedAt,
  });
  final String id,
      projectId,
      itemKey,
      phase,
      title,
      purpose,
      outputs,
      reference,
      notes;
  final int stepOrder;
  final RoadmapStatus status;
  final DateTime updatedAt;
}

String normalizeDisciplineKey(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty || lower == 'unknown') return '';
  if (lower.contains('architect')) return 'architectural';
  if (lower.contains('structur')) return 'structural';
  if (lower.contains('mechan') || lower.contains('hvac')) return 'mechanical';
  if (lower.contains('electr')) return 'electrical';
  if (lower.contains('plumb') ||
      lower.contains('hydraulic') ||
      lower.contains('sanitary')) {
    return 'plumbing';
  }
  if (lower.contains('civil') ||
      lower.contains('site') ||
      lower.contains('survey')) {
    return 'civil';
  }
  return lower
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

enum TimerReferenceType { wholeEstimate, checklistItem }

class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.projectId,
    required this.referenceType,
    required this.label,
    required this.startedAt,
    required this.durationSeconds,
    required this.note,
    required this.isSoftDeleted,
    required this.createdAt,
    required this.updatedAt,
    this.referenceId,
    this.stoppedAt,
  });
  final String id, projectId, label, note;
  final TimerReferenceType referenceType;
  final String? referenceId;
  final DateTime startedAt, createdAt, updatedAt;
  final DateTime? stoppedAt;
  final int durationSeconds;
  final bool isSoftDeleted;

  bool get isActive => stoppedAt == null && !isSoftDeleted;
  int elapsedSecondsAt(DateTime now) => isActive
      ? (now.toUtc().difference(startedAt.toUtc()).inSeconds).clamp(
          0,
          0x7fffffff,
        )
      : durationSeconds;
}

abstract interface class ScopeContentSynchronizer {
  void syncFromScopeRevision(ScopeRevision revision);
}

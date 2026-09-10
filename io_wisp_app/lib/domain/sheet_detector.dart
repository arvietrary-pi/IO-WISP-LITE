import 'dart:math' as math;

import 'document_register.dart';

class _TitleRule {
  const _TitleRule(this.title, this.discipline, this.words);
  final String title, discipline;
  final List<String> words;
}

class _Topic {
  const _Topic(this.label, this.words);
  final String label;
  final List<String> words;
}

class _Line {
  _Line(this.y, this.x, this.height, this.items);
  double y, x, height;
  final List<PositionalTextItem> items;
}

class _TextLine {
  const _TextLine(this.text, this.x, this.y);
  final String text;
  final double x, y;
}

class SheetDetector {
  const SheetDetector();
  static const version = 'v005-native/1';

  static const titleRules = <_TitleRule>[
    _TitleRule('Cover / Drawing Index', 'General', [
      'cover sheet',
      'title sheet',
      'drawing index',
      'drawing schedule',
      'sheet index',
      'project information',
    ]),
    _TitleRule('General Notes & Legends', 'General', [
      'general notes',
      'legend',
      'legends',
      'abbreviations',
      'symbols',
    ]),
    _TitleRule('Yield / Information Data', 'Architectural', [
      'yield information',
      'yield data',
      'unit yield',
      'yield information data',
    ]),
    _TitleRule('Private Open Spaces Diagram', 'Architectural', [
      'private open spaces',
      'private open space',
    ]),
    _TitleRule('Survey / Existing Conditions Plan', 'Civil / Site', [
      'survey plan',
      'site survey',
      'existing conditions',
      'contour plan',
      'feature survey',
    ]),
    _TitleRule('Site Plan', 'Civil / Site', [
      'site plan',
      'site layout',
      'site analysis',
      'site circulation',
    ]),
    _TitleRule('Demolition Plan', 'Architectural', [
      'demolition plan',
      'demolition',
      'remove existing',
    ]),
    _TitleRule('Fire Egress / Life Safety Plan', 'Fire / Life Safety', [
      'fire egress',
      'life safety',
      'fire exit',
      'egress plan',
      'fire protection',
    ]),
    _TitleRule('Grading / Earthworks Plan', 'Civil / Site', [
      'grading plan',
      'earthworks',
      'cut and fill',
      'earthwork',
    ]),
    _TitleRule('Drainage / Stormwater Plan', 'Civil / Site', [
      'stormwater',
      'storm water',
      'drainage plan',
      'surface water',
    ]),
    _TitleRule('Utilities Plan', 'Civil / Site', [
      'utilities plan',
      'utility plan',
      'sewer plan',
      'water supply',
      'underground services',
    ]),
    _TitleRule('Floor Plan', 'Architectural', [
      'floor plan',
      'floor plans',
      'unit plan',
      'apartment plan',
      'room layout',
    ]),
    _TitleRule('Roof Plan', 'Architectural', [
      'roof plan',
      'roof layout',
      'roof framing',
    ]),
    _TitleRule('Reflected Ceiling Plan', 'Architectural', [
      'reflected ceiling',
      'ceiling plan',
      'ceiling plans',
    ]),
    _TitleRule('Elevations', 'Architectural', ['elevations', 'elevation']),
    _TitleRule('Sections', 'Architectural', ['sections', 'section']),
    _TitleRule('Architectural Details', 'Architectural', [
      'construction details',
      'architectural details',
      'details',
    ]),
    _TitleRule('Doors / Windows / Hardware Schedules', 'Architectural', [
      'door schedule',
      'window schedule',
      'hardware schedule',
      'doors and windows',
    ]),
    _TitleRule('Room Finishes / Fitout Plan', 'Architectural', [
      'room finishes',
      'finishes plan',
      'fitouts',
      'fitout',
      'finish schedule',
    ]),
    _TitleRule('Furniture & Equipment Plan', 'Architectural', [
      'furniture',
      'equipment plan',
      'furniture and equipment',
    ]),
    _TitleRule('Foundation / Footing Plan', 'Structural', [
      'foundation plan',
      'footing plan',
      'footings',
      'foundation layout',
    ]),
    _TitleRule('Structural Framing Plan', 'Structural', [
      'framing plan',
      'structural framing',
      'floor framing',
      'roof framing plan',
    ]),
    _TitleRule('Structural Slab / Reinforcement Plan', 'Structural', [
      'slab plan',
      'reinforcement plan',
      'reinforcement',
      'rebar plan',
    ]),
    _TitleRule('Structural Details', 'Structural', [
      'structural details',
      'beam details',
      'column details',
      'connection details',
    ]),
    _TitleRule('Mechanical / HVAC Plan', 'Mechanical', [
      'mechanical plan',
      'hvac',
      'air conditioning',
      'ductwork',
    ]),
    _TitleRule('Electrical / Lighting Plan', 'Electrical', [
      'electrical plan',
      'lighting plan',
      'power plan',
      'electrical layout',
    ]),
    _TitleRule('Plumbing / Hydraulic Plan', 'Plumbing / Hydraulic', [
      'plumbing plan',
      'hydraulics',
      'hydraulic plan',
      'sanitary plan',
      'water services',
    ]),
    _TitleRule('Communications / Security Plan', 'Electrical', [
      'communications',
      'data plan',
      'security plan',
      'cctv',
      'access control',
    ]),
    _TitleRule('Landscape / External Works Plan', 'Landscape / External', [
      'landscape plan',
      'landscaping',
      'external works',
      'hardscape',
      'planting plan',
    ]),
    _TitleRule('Specifications / Technical Notes', 'General', [
      'specification',
      'technical notes',
      'ncc report',
      'standards',
    ]),
  ];

  static const topics = <_Topic>[
    _Topic('dimensions and setting out', [
      'dimension',
      'dimensions',
      'setting out',
      'setout',
      'grid line',
      'gridline',
    ]),
    _Topic('levels and elevations', [
      'level',
      'levels',
      'elevation',
      'elevations',
      'datum',
      'finished floor',
    ]),
    _Topic('materials and specifications', [
      'material',
      'materials',
      'specification',
      'specifications',
      'finish',
      'finishes',
    ]),
    _Topic('construction notes and details', [
      'general note',
      'construction note',
      'detail',
      'details',
      'typical',
    ]),
    _Topic('doors, windows, and openings', [
      'door',
      'doors',
      'window',
      'windows',
      'opening',
      'openings',
    ]),
    _Topic('roof slopes and drainage', [
      'roof',
      'slope',
      'fall',
      'gutter',
      'downpipe',
      'drainage',
    ]),
    _Topic('structure and reinforcement', [
      'reinforcement',
      'rebar',
      'beam',
      'column',
      'footing',
      'foundation',
      'slab',
    ]),
    _Topic('services and equipment', [
      'electrical',
      'lighting',
      'plumbing',
      'hydraulic',
      'mechanical',
      'hvac',
      'equipment',
    ]),
    _Topic('site access and external works', [
      'site access',
      'boundary',
      'setback',
      'paving',
      'landscape',
      'external works',
    ]),
    _Topic('demolition and existing work', [
      'demolition',
      'remove existing',
      'existing condition',
      'make good',
    ]),
  ];

  static String clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<String> extractSheetNumbers(String text) {
    final raw = text.toUpperCase();
    final pattern = RegExp(
      r'\b[A-Z]{1,3}(?:[-/ ]?\d{1,3})(?:[.\-]\d{1,3}){0,2}[A-Z]?\b',
    );
    final values = <String>[];
    for (final match in pattern.allMatches(raw)) {
      final value = match.group(0)!.replaceAll(' ', '').replaceAll('/', '-');
      if (!RegExp('[A-Z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
        continue;
      }
      if (RegExp(r'^(AS|ISO|NCC)\d').hasMatch(value)) {
        continue;
      }
      if (!values.contains(value)) {
        values.add(value);
      }
    }
    return values;
  }

  static int candidateScore(String candidate, [int position = 0]) {
    final value = candidate.toUpperCase();
    final prefix = RegExp(r'^([A-Z]{1,3})').firstMatch(value)?.group(1) ?? '';
    final digits = RegExp(r'\d').allMatches(value).length;
    const recognized = {
      'A',
      'AR',
      'G',
      'GN',
      'S',
      'ST',
      'C',
      'CV',
      'E',
      'EL',
      'M',
      'ME',
      'P',
      'PL',
      'H',
      'F',
      'FP',
      'FS',
      'L',
    };
    const suspicious = {
      'AND',
      'TO',
      'OF',
      'LOT',
      'BED',
      'COL',
      'HR',
      'GR',
      'PB',
      'EP',
      'PC',
      'FW',
      'RJ',
      'TOW',
      'RL',
      'LB',
      'N',
    };
    var score = math.max(0, 4 - position);
    if (RegExp(r'[.\-]').hasMatch(value)) score += 12;
    if (recognized.contains(prefix)) score += 6;
    if (digits >= 3) score += 3;
    if (RegExp(r'^[A-Z]{1,3}-?\d{2,4}(?:[.\-]\d{1,3})?[A-Z]?$')
        .hasMatch(value)) {
      score += 10;
    }
    if (suspicious.contains(prefix)) score -= 14;
    return score;
  }

  DetectedRegisterEntry detect(PositionalTextPage page) {
    final items =
        page.items
            .where((item) => clean(item.text).isNotEmpty)
            .map(
              (item) => PositionalTextItem(
                text: clean(item.text),
                x: item.x,
                y: item.y,
                width: item.width,
                height: math.max(5, item.height),
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.y.compareTo(b.y) != 0
                ? a.y.compareTo(b.y)
                : a.x.compareTo(b.x),
          );
    final clustered = <_Line>[];
    for (final item in items) {
      _Line? line;
      for (
        var index = clustered.length - 1;
        index >= math.max(0, clustered.length - 8);
        index--
      ) {
        final candidate = clustered[index];
        final tolerance = math.max(
          2.5,
          math.min(8, math.max(item.height, candidate.height) * .48),
        );
        if ((candidate.y - item.y).abs() <= tolerance) {
          line = candidate;
          break;
        }
      }
      if (line == null) {
        line = _Line(item.y, item.x, item.height, []);
        clustered.add(line);
      }
      line.items.add(item);
      line.x = math.min(line.x, item.x);
      line.y = (line.y * (line.items.length - 1) + item.y) / line.items.length;
      line.height = math.max(line.height, item.height);
    }
    clustered.sort(
      (a, b) =>
          a.y.compareTo(b.y) != 0 ? a.y.compareTo(b.y) : a.x.compareTo(b.x),
    );
    final lines = clustered
        .map((line) {
          line.items.sort((a, b) => a.x.compareTo(b.x));
          final text = clean(line.items.map((item) => item.text).join(' '))
              .replaceAll(RegExp(r'\s+([,.;:])'), r'$1');
          return _TextLine(text, line.x, line.y);
        })
        .where((line) => line.text.isNotEmpty)
        .toList();
    final width = math.max(1, page.width);
    final height = math.max(1, page.height);
    final titleLines = lines.where((line) {
      final normalizedX = line.x / width;
      final normalizedY = line.y / height;
      return (normalizedY >= .62 && normalizedX >= .40) || normalizedY >= .82;
    }).toList();
    final raw = clean(lines.map((line) => line.text).join(' '));
    final titleBlock = clean(titleLines.map((line) => line.text).join(' '));
    final titleCandidates = extractSheetNumbers(titleBlock);
    final allCandidates = extractSheetNumbers(raw);
    final pool = [
      ...titleCandidates,
      ...allCandidates.where((value) => !titleCandidates.contains(value)),
    ];
    final hints = <String, double>{};
    for (final line in lines) {
      for (final value in extractSheetNumbers(line.text)) {
        hints[value] = math.max(hints[value] ?? 0, line.y / height);
      }
    }
    final ranked = <({String value, int score, int order})>[];
    for (var index = 0; index < pool.length; index++) {
      final base = candidateScore(pool[index], index);
      final y = hints[pool[index]] ?? 0;
      final spatial = base >= 9
          ? (y >= .9
                ? 30
                : y >= .82
                ? 15
                : 0)
          : 0;
      ranked.add((value: pool[index], score: base + spatial, order: index));
    }
    ranked.sort(
      (a, b) => b.score != a.score
          ? b.score.compareTo(a.score)
          : a.order.compareTo(b.order),
    );
    final candidates = ranked
        .where((item) => item.score >= 9)
        .map((item) => item.value)
        .toList();
    final sheet = ranked.isNotEmpty && ranked.first.score >= 9
        ? ranked.first.value
        : '';
    final titleBlockMatch = _titleMatch(titleBlock);
    final match = titleBlockMatch ?? _titleMatch(raw);
    final title = match?.rule.title ?? '';
    final prefixDiscipline = inferDiscipline(sheet);
    final discipline = match?.rule.discipline == 'General'
        ? 'General'
        : prefixDiscipline != 'Unclassified' &&
              prefixDiscipline != 'Architectural'
        ? prefixDiscipline
        : match?.rule.discipline ?? prefixDiscipline;
    final metadata = _metadata(titleBlock.isNotEmpty ? titleBlock : raw);
    final diagnostics = <PageDiagnostic>[
      if (raw.isEmpty) PageDiagnostic.noReadableText,
      if (sheet.isEmpty) PageDiagnostic.noSheetNumber,
      if (title.isEmpty) PageDiagnostic.noTitleKeyword,
      if (titleBlock.isEmpty && raw.isNotEmpty) PageDiagnostic.noTitleBlock,
      if (candidates.length > 1) PageDiagnostic.multipleSheetCandidates,
    ];
    final strong =
        titleBlock.isNotEmpty && sheet.isNotEmpty && titleBlockMatch != null;
    final confidence = strong
        ? 'high'
        : raw.isNotEmpty && (sheet.isNotEmpty || title.isNotEmpty)
        ? 'medium'
        : 'low';
    final references = extractSheetNumbers(raw)
        .where((value) => candidateScore(value) >= 9)
        .toList();
    return DetectedRegisterEntry(
      physicalPage: page.physicalPage,
      sheetNumber: sheet,
      title: title,
      discipline: discipline,
      revision: metadata.$1,
      scale: metadata.$2,
      drawingDate: metadata.$3,
      summary: _summary(raw, title, discipline),
      evidence: _evidence(
        titleBlock.isNotEmpty ? titleBlock : raw,
        sheet,
        match?.matched ?? '',
      ),
      titleBlockText: titleBlock.length > 1200
          ? titleBlock.substring(0, 1200)
          : titleBlock,
      textSample: raw.length > 5000 ? raw.substring(0, 5000) : raw,
      candidates: List.unmodifiable(candidates),
      references: List.unmodifiable(references),
      diagnostics: List.unmodifiable(diagnostics),
      status: confidence == 'high'
          ? RegisterEntryStatus.ready
          : RegisterEntryStatus.review,
      confidence: confidence,
      textItemCount: items.length,
      lineCount: lines.length,
      hasReadableText: raw.isNotEmpty,
    );
  }

  static ({_TitleRule rule, int score, String matched})? _titleMatch(
    String text,
  ) {
    final raw = clean(text).toLowerCase();
    ({_TitleRule rule, int score, String matched})? best;
    for (final rule in titleRules) {
      var score = 0;
      var matched = '';
      for (final word in rule.words) {
        if (raw.contains(word)) {
          score += word.length > 8 ? 3 : 2;
          if (word.length > matched.length) matched = word;
        }
      }
      if (score > 0 && (best == null || score > best.score)) {
        best = (rule: rule, score: score, matched: matched);
      }
    }
    return best;
  }

  static String inferDiscipline(String sheet, [String title = '']) {
    final value = sheet.toUpperCase().replaceAll(RegExp(r'[-_.]'), ' ');
    final rules = <(RegExp, String)>[
      (RegExp(r'^FP|^FS|^F\b'), 'Fire / Life Safety'),
      (RegExp(r'^PL|^P\b|^H\b'), 'Plumbing / Hydraulic'),
      (RegExp(r'^ME|^M\b'), 'Mechanical'),
      (RegExp(r'^EL|^E\b'), 'Electrical'),
      (RegExp(r'^ST|^S\b'), 'Structural'),
      (RegExp(r'^CV|^C\b'), 'Civil / Site'),
      (RegExp(r'^L\b'), 'Landscape / External'),
      (RegExp(r'^AR|^A\b|^G\b|^GN'), 'Architectural'),
    ];
    for (final rule in rules) {
      if (rule.$1.hasMatch(value)) return rule.$2;
    }
    return _titleMatch(title)?.rule.discipline ?? 'Unclassified';
  }

  static (String, String, String) _metadata(String text) {
    final revision =
        RegExp(
          r'\bREV(?:ISION)?\b\s*[:#.-]?\s*([A-Z0-9]{1,8})\b',
          caseSensitive: false,
        ).firstMatch(text)?.group(1) ??
        '';
    final scale =
        (RegExp(
                  r'\bSCALE(?:S)?\b\s*[:.-]?\s*((?:1\s*[:/]\s*\d{1,5})|NTS|AS\s+NOTED)\b',
                  caseSensitive: false,
                ).firstMatch(text)?.group(1) ??
                '')
            .replaceAll(RegExp(r'\s+'), '');
    final date =
        RegExp(
          r'\b(?:DATE|ISSUED)\b\s*[:.-]?\s*(\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{4}[./-]\d{1,2}[./-]\d{1,2})\b',
          caseSensitive: false,
        ).firstMatch(text)?.group(1) ??
        '';
    return (revision, scale, date);
  }

  static String _summary(String text, String title, String discipline) {
    final raw = clean(text).toLowerCase();
    final found = topics
        .where((topic) => topic.words.any(raw.contains))
        .map((topic) => topic.label)
        .take(4)
        .toList();
    final subject = title.isNotEmpty
        ? title
        : discipline != 'Unclassified'
        ? '$discipline drawing'
        : 'Drawing page';
    if (raw.isEmpty) {
      return 'No readable embedded text was detected; identify this page manually.';
    }
    if (found.isEmpty) {
      return '$subject identified from the embedded PDF text; verify the title block and drawing content.';
    }
    final topicText = found.length == 1
        ? found.first
        : '${found.take(found.length - 1).join(', ')}, and ${found.last}';
    return '$subject covering $topicText.';
  }

  static String _evidence(String text, String sheet, String matched) {
    final raw = clean(text);
    var position = -1;
    for (final term in [sheet, matched].where((value) => value.isNotEmpty)) {
      position = raw.toLowerCase().indexOf(term.toLowerCase());
      if (position >= 0) break;
    }
    if (position < 0) return raw.length <= 190 ? raw : raw.substring(0, 190);
    final start = math.max(0, position - 45);
    final end = math.min(raw.length, position + 150);
    return '${position > 45 ? '…' : ''}${raw.substring(start, end)}${raw.length > end ? '…' : ''}';
  }
}

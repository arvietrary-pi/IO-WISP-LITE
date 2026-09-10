import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/legacy_import.dart';
import '../../domain/project.dart';

class ReadOnlyLegacyJsonReader implements LegacySourceReader {
  const ReadOnlyLegacyJsonReader();
  @override
  Future<LegacySource> read(String selectedPath) async {
    // No write, copy, rename, directory lookup from JSON, or browser access.
    // Bound reads even if a different process grows the selected file.
    final filename = p.windows.basename(selectedPath);
    if (!filename.toLowerCase().endsWith('.json')) {
      return LegacyJsonParser.failure(
        filename,
        'extension',
        'Select a JSON project export.',
      );
    }
    try {
      final file = await File(selectedPath).open(mode: FileMode.read);
      late Uint8List bytes;
      try {
        if (await file.length() > LegacyJsonParser.maxBytes) {
          return LegacyJsonParser.failure(
            filename,
            'size',
            'The source exceeds the 8 MiB limit.',
          );
        }
        bytes = await file.read(LegacyJsonParser.maxBytes + 1);
      } finally {
        await file.close();
      }
      return await Isolate.run(() => LegacyJsonParser.parse(bytes, filename));
    } on FileSystemException {
      return LegacyJsonParser.failure(
        filename,
        'read',
        'The selected source could not be read. Check that it is available and readable.',
      );
    }
  }
}

class LegacyJsonParser {
  static const maxBytes = 8 * 1024 * 1024;
  static const maxDepth = 32;
  static const maxNodes = 100000;
  static const maxFindings = 200;
  static const format = 'IO Wisp Lite V0.0.5 export';

  static LegacySource failure(String name, String code, String message) =>
      LegacySource(
        filename: safeFilename(name),
        fingerprint: '',
        byteCount: 0,
        format: 'Unrecognized',
        candidate: null,
        findings: [ImportFinding(FindingLevel.fatal, code, 'source', message)],
      );

  static String safeFilename(String name) {
    final base = p.windows
        .basename(name)
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '_');
    return base.length > 180 ? '${base.substring(0, 170)}.json' : base;
  }

  static LegacySource parse(Uint8List bytes, String filename) {
    if (bytes.length > maxBytes) {
      return failure(filename, 'size', 'The source exceeds the 8 MiB limit.');
    }
    final findings = <ImportFinding>[];
    void add(FindingLevel level, String code, String field, String message) {
      if (findings.length >= maxFindings) {
        throw const FormatException(
          'Too many validation findings (limit 200).',
        );
      }
      findings.add(ImportFinding(level, code, field, message));
    }

    final fingerprint = sha256.convert(bytes).toString();
    ImportCandidate? candidate;
    var detected = 'Unrecognized';
    try {
      var text = utf8.decode(bytes, allowMalformed: false);
      if (text.startsWith('\ufeff')) {
        text = text.substring(1);
        add(
          FindingLevel.information,
          'utf8-bom',
          'source',
          'UTF-8 byte-order marker removed for parsing. Source bytes remain unchanged.',
        );
      }
      _scan(text);
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final identities = <String>{};
        for (final entry in decoded) {
          if (entry is Map && entry['project'] is Map) {
            final project = entry['project'] as Map;
            for (final key in ['id', 'name']) {
              final value = project[key];
              if (value is String &&
                  value.trim().isNotEmpty &&
                  !identities.add(
                    '$key:${ProjectNameRules.normalize(value)}',
                  )) {
                add(
                  FindingLevel.fatal,
                  'duplicate-in-source',
                  'source',
                  'Repeated project identity or name inside this unsupported batch.',
                );
              }
            }
          }
        }
        add(
          FindingLevel.fatal,
          'batch-unsupported',
          'source',
          'Multiple-project arrays are not a verified export format. Select one V0.0.5 project export at a time.',
        );
      } else if (decoded is! Map<String, dynamic>) {
        add(
          FindingLevel.fatal,
          'structure',
          'source',
          'Expected a V0.0.5 project export object.',
        );
      } else {
        final root = decoded;
        if (root['io_assistant'] != 'IO Wisp Lite' ||
            root['app_version'] != 'V0.0.5') {
          add(
            FindingLevel.fatal,
            'format',
            'source',
            'Only exports marked io_assistant = IO Wisp Lite and app_version = V0.0.5 are supported. Raw browser records, drawing-only JSON and other versions are not imported.',
          );
        } else {
          detected = format;
        }
        if (root.containsKey('api_used') && root['api_used'] is! bool) {
          add(FindingLevel.fatal, 'type', 'api_used', 'Expected a boolean.');
        } else if (root['api_used'] == true) {
          add(
            FindingLevel.warning,
            'api-marker',
            'api_used',
            'The source has api_used=true, unlike the verified Lite exporter. No content is executed.',
          );
        }
        const rootKeys = {
          'io_assistant',
          'app_version',
          'api_used',
          'project',
          'document',
          'table_of_contents',
          'checklist',
          'roadmap',
          'content',
        };
        _unknown(root, rootKeys, '', add);
        final project = root['project'];
        if (project is! Map<String, dynamic>) {
          add(
            FindingLevel.fatal,
            'project-required',
            'project',
            'A project object is required.',
          );
        } else {
          const strings = {
            'id',
            'name',
            'location',
            'revision',
            'estimator',
            'createdAt',
            'updatedAt',
            'folderName',
            'folderCreatedAt',
            'sourceFile',
          };
          const arrays = {
            'sheets',
            'checklist',
            'roadmap',
            'timeEntries',
            'files',
          };
          const objects = {'content', 'scopeBrief'};
          _unknown(
            project,
            {...strings, ...arrays, ...objects, 'pages'},
            'project.',
            add,
          );
          for (final key in strings) {
            if (project.containsKey(key) && project[key] is! String) {
              add(
                FindingLevel.fatal,
                'type',
                'project.$key',
                'Expected a string.',
              );
            }
          }
          for (final key in arrays) {
            if (project.containsKey(key) && project[key] is! List) {
              add(
                FindingLevel.fatal,
                'type',
                'project.$key',
                'Expected an array.',
              );
            }
          }
          for (final key in objects) {
            if (project.containsKey(key) && project[key] is! Map) {
              add(
                FindingLevel.fatal,
                'type',
                'project.$key',
                'Expected an object.',
              );
            }
          }
          if (project.containsKey('pages') &&
              (project['pages'] is! int || (project['pages'] as int) < 0)) {
            add(
              FindingLevel.fatal,
              'type',
              'project.pages',
              'Expected a nonnegative integer.',
            );
          }
          String field(String key, {int limit = 300}) {
            final raw = project[key];
            if (raw is! String) return '';
            if (raw.length > limit ||
                RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(raw)) {
              add(
                FindingLevel.fatal,
                'text-limit',
                'project.$key',
                'Text contains control characters or exceeds the $limit character limit.',
              );
            }
            return raw;
          }

          final mappings = <FieldMapping>[];
          String mapped(String key, String destination) {
            final raw = field(key);
            final value = key == 'name'
                ? ProjectNameRules.displayValue(raw)
                : raw.trim();
            mappings.add(
              FieldMapping('project.$key', destination, value, value != raw),
            );
            if (raw != value) {
              add(
                FindingLevel.information,
                'normalized',
                'project.$key',
                'Whitespace normalized in the imported value.',
              );
            }
            if (!project.containsKey(key) && key != 'name') {
              add(
                FindingLevel.information,
                'default-empty',
                'project.$key',
                'Optional field is absent; left empty.',
              );
            }
            return value;
          }

          final name = mapped('name', 'Project name');
          if (name.isEmpty) {
            add(
              FindingLevel.fatal,
              'name-required',
              'project.name',
              'A nonempty project name is required; document.title is not substituted.',
            );
          }
          final location = mapped('location', 'Location / client');
          final revision = mapped('revision', 'Set / revision');
          final estimator = mapped('estimator', 'Estimator');
          for (final key in ['name', 'location']) {
            final value = project[key];
            if (value is String &&
                value.isNotEmpty &&
                !ImportNameRules.safeSegment(value)) {
              add(
                FindingLevel.warning,
                'safe-folder-normalization',
                'project.$key',
                'Unsafe or reserved filename characters are replaced only in the new folder name. Display text remains reviewable.',
              );
            }
          }
          final legacyId = field('id', limit: 128).trim();
          if (legacyId.isNotEmpty &&
              !RegExp(r'^[a-zA-Z0-9_.:-]+$').hasMatch(legacyId)) {
            add(
              FindingLevel.fatal,
              'legacy-id',
              'project.id',
              'Legacy identity must be a short identifier without spaces, paths or control characters.',
            );
          }
          final dates = <String, DateTime?>{};
          for (final key in ['createdAt', 'updatedAt', 'folderCreatedAt']) {
            final value = project[key];
            dates[key] = value is String && value.isNotEmpty
                ? strictDate(value)
                : null;
            if (value is String && value.isNotEmpty && dates[key] == null) {
              add(
                FindingLevel.fatal,
                'date',
                'project.$key',
                'Expected a real ISO-8601 timestamp with an explicit timezone. Invalid calendar dates are rejected.',
              );
            }
          }
          if (dates['createdAt'] != null &&
              dates['updatedAt'] != null &&
              dates['updatedAt']!.isBefore(dates['createdAt']!)) {
            add(
              FindingLevel.fatal,
              'date-order',
              'project.updatedAt',
              'Updated timestamp precedes the created timestamp.',
            );
          }
          for (final key in ['createdAt', 'updatedAt']) {
            if (key == 'updatedAt' &&
                dates['createdAt'] == null &&
                dates['updatedAt'] != null) {
              add(
                FindingLevel.warning,
                'missing-created-date',
                'project.updatedAt',
                'The creation timestamp is absent. The source updated timestamp was validated but is not migrated; both new timestamps use import time.',
              );
              dates['updatedAt'] = null;
            }
            mappings.add(
              FieldMapping(
                'project.$key',
                key == 'createdAt' ? 'Created at' : 'Updated at',
                dates[key]?.toIso8601String() ??
                    'Import time (or source created time for updatedAt)',
                true,
              ),
            );
          }
          add(
            FindingLevel.information,
            'new-uuid',
            'project.id',
            'A new Flutter UUID will be generated. Legacy identity, when present, is stored only as provenance.',
          );
          for (final key in [...arrays, ...objects, 'pages', 'sourceFile']) {
            if (project.containsKey(key)) {
              final value = project[key];
              final count = value is List ? ' (${value.length} entries)' : '';
              add(
                FindingLevel.deferred,
                'later-phase',
                'project.$key',
                'Not migrated$count. Retain your source JSON for a later migration phase.',
              );
            }
          }
          for (final key in ['folderName', 'folderCreatedAt']) {
            if (project.containsKey(key)) {
              add(
                FindingLevel.information,
                'folder-ignored',
                'project.$key',
                'Legacy folder metadata is ignored; a new empty folder is created under the configured root.',
              );
            }
          }
          _nested(project, 'project', add);
          final document = root['document'];
          if (document != null && document is! Map) {
            add(FindingLevel.fatal, 'type', 'document', 'Expected an object.');
          } else if (document is Map<String, dynamic>) {
            _unknown(document, {'title', 'page_count'}, 'document.', add);
            if (document.containsKey('title') && document['title'] is! String) {
              add(
                FindingLevel.fatal,
                'type',
                'document.title',
                'Expected a string.',
              );
            }
            if (document.containsKey('page_count') &&
                (document['page_count'] is! int ||
                    document['page_count'] < 0)) {
              add(
                FindingLevel.fatal,
                'type',
                'document.page_count',
                'Expected a nonnegative integer.',
              );
            }
            if (document['title'] is String &&
                document['title'] != project['name']) {
              add(
                FindingLevel.warning,
                'mirror-conflict',
                'document.title',
                'Duplicated title differs from project.name. project.name is the proposed name.',
              );
            }
          }
          for (final key in [
            'document',
            'table_of_contents',
            'checklist',
            'roadmap',
            'content',
          ]) {
            if (!root.containsKey(key)) continue;
            final value = root[key];
            final wantsObject = key == 'content' || key == 'document';
            if (wantsObject ? value is! Map : value is! List) {
              add(
                FindingLevel.fatal,
                'type',
                key,
                wantsObject ? 'Expected an object.' : 'Expected an array.',
              );
            }
            add(
              FindingLevel.deferred,
              'export-mirror',
              key,
              'Export metadata or duplicated later-phase data; not migrated.',
            );
            if (key != 'document') {
              _nested(
                {key == 'table_of_contents' ? 'sheets' : key: value},
                'export',
                add,
              );
            }
          }
          candidate = ImportCandidate(
            draft: ProjectDraft(
              name: name,
              locationClient: location,
              revision: revision,
              estimator: estimator,
            ),
            legacyId: legacyId.isEmpty ? null : legacyId,
            createdAt: dates['createdAt'],
            updatedAt: dates['updatedAt'],
            mappings: mappings,
          );
        }
      }
    } on FormatException catch (error) {
      findings.add(
        ImportFinding(
          FindingLevel.fatal,
          'parse',
          'source',
          // Never echo a decoder excerpt: it may contain secrets or private data.
          error.source == null && error.message.startsWith('Limit:')
              ? error.message
              : 'Malformed, ambiguous, oversized or excessively nested JSON. Check the source export.',
        ),
      );
    }
    return LegacySource(
      filename: safeFilename(filename),
      fingerprint: fingerprint,
      byteCount: bytes.length,
      format: detected,
      candidate: candidate,
      findings: findings,
    );
  }

  static DateTime? strictDate(String text) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(text);
    if (match == null) return null;
    final n = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
    final date = DateTime.utc(n[0], n[1], n[2]);
    if (n[0] < 1 ||
        date.year != n[0] ||
        date.month != n[1] ||
        date.day != n[2] ||
        n[3] > 23 ||
        n[4] > 59 ||
        n[5] > 59) {
      return null;
    }
    final zone = match[7]!;
    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 14 ||
            int.parse(zone.substring(4)) > 59 ||
            (int.parse(zone.substring(1, 3)) == 14 &&
                int.parse(zone.substring(4)) != 0))) {
      return null;
    }
    return DateTime.tryParse(text)?.toUtc();
  }

  static void _unknown(
    Map<String, dynamic> data,
    Set<String> known,
    String prefix,
    void Function(FindingLevel, String, String, String) add,
  ) {
    for (final key in data.keys.where((k) => !known.contains(k))) {
      final safeKey = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]{0,60}$').hasMatch(key)
          ? key
          : '[unrecognized key]';
      add(
        FindingLevel.warning,
        'unsupported-field',
        '$prefix$safeKey',
        'Unknown field is not stored. Its value is not used.',
      );
      if (key == 'projects' && prefix.isEmpty) {
        add(
          FindingLevel.fatal,
          'batch-unsupported',
          'projects',
          'A multiple-project container is unsupported. Export each project separately.',
        );
      }
      if (RegExp(
        r'path|directory|handle',
        caseSensitive: false,
      ).hasMatch(key)) {
        add(
          FindingLevel.warning,
          'untrusted-location',
          '$prefix$safeKey',
          'Untrusted path or browser handle is ignored. It is never a destination or a file to open.',
        );
      }
    }
  }

  // Validate later-phase containers and typed legacy fields without migrating
  // or retaining their content. Unknown values are never copied to provenance.
  static const _fields = <String, String>{
    'id': 's',
    'page': 'n',
    'sheet': 's',
    'title': 's',
    'label': 's',
    'discipline': 's',
    'confidence': 's',
    'evidence': 's',
    'status': 's',
    'notes': 's',
    'candidates': 'a',
    'summary': 's',
    'revision': 's',
    'scale': 's',
    'drawingDate': 's',
    'sourceFile': 's',
    'extractionStatus': 's',
    'textItemCount': 'n',
    'lineCount': 'n',
    'titleBlockText': 's',
    'textSample': 's',
    'section': 's',
    'description': 's',
    'prompt': 's',
    'done': 'b',
    'note': 's',
    'key': 's',
    'step': 'n',
    'phase': 's',
    'purpose': 's',
    'outputs': 's',
    'reference': 's',
    'scope': 's',
    'refId': 's',
    'startedAt': 'd',
    'endedAt': 'd',
    'durationSeconds': 'n',
    'name': 's',
    'kind': 's',
    'savedAt': 'd',
    'raw': 's',
    'lastParsedRaw': 's',
    'included': 's',
    'excluded': 's',
    'clarifications': 's',
    'strict': 'b',
    'gate': 'a',
    'decision': 's',
    'reason': 's',
    'manual': 'b',
    'basis': 's',
    'assumptions': 's',
    'exclusions': 's',
    'rfis': 's',
    'risks': 's',
    'rates': 's',
    'changes': 's',
  };

  static void _nested(
    Map<String, dynamic> project,
    String prefix,
    void Function(FindingLevel, String, String, String) add,
  ) {
    final seen = <String>{};
    void walk(dynamic value, String field, String key) {
      if (value is Map<String, dynamic>) {
        _unknown(value, _fields.keys.toSet(), '$field.', (
          level,
          code,
          path,
          msg,
        ) {
          // Group repeated row findings; no enormous preview for a plan set.
          final group = path.replaceAll(RegExp(r'\[\d+\]'), '[]');
          if (seen.add('$code:$group')) add(level, code, group, msg);
        });
        for (final entry in value.entries) {
          final type = _fields[entry.key];
          if (type == null) continue;
          final v = entry.value;
          final valid = switch (type) {
            's' => v is String,
            'b' => v is bool,
            'n' => v is num && v.isFinite && v >= 0,
            'a' => v is List,
            'd' =>
              v == null || v == '' || (v is String && strictDate(v) != null),
            _ => true,
          };
          final path = '$field.${entry.key}';
          if (!valid && seen.add('type:$path')) {
            add(
              FindingLevel.warning,
              'deferred-invalid-field',
              path,
              'Later-phase field has an invalid type/date; it is not migrated.',
            );
          }
          walk(v, path, entry.key);
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          if (value[i] is! Map &&
              key != 'candidates' &&
              seen.add('row:$field')) {
            add(
              FindingLevel.warning,
              'deferred-invalid-row',
              field,
              'Later-phase array contains a non-object row; it is not migrated.',
            );
          }
          walk(value[i], '$field[$i]', key);
        }
      } else if (value is String &&
          (key == 'sourceFile' || key == 'folderName' || key == 'name')) {
        if (value.isNotEmpty &&
            (!ImportNameRules.safeSegment(value) ||
                RegExp(r'(^|[/\\])\.\.([/\\]|$)').hasMatch(value))) {
          add(
            FindingLevel.warning,
            'unsafe-legacy-path',
            field,
            'Unsafe, absolute, reserved or traversal-like legacy path is ignored. No referenced file or folder will be accessed.',
          );
        }
      }
    }

    for (final entry in project.entries) {
      if ([
        'sheets',
        'checklist',
        'roadmap',
        'timeEntries',
        'files',
        'scopeBrief',
        'content',
        'sourceFile',
        'folderName',
      ].contains(entry.key)) {
        walk(entry.value, '$prefix.${entry.key}', entry.key);
      }
    }
  }

  static void _scan(String text) {
    final stack = <Set<String>?>[];
    var nodes = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 34) {
        final start = i++;
        while (i < text.length) {
          if (text.codeUnitAt(i) == 92) {
            i += 2;
            continue;
          }
          if (text.codeUnitAt(i) == 34) break;
          i++;
        }
        if (i >= text.length) throw const FormatException('Unclosed string.');
        var next = i + 1;
        while (next < text.length && text.codeUnitAt(next) <= 32) {
          next++;
        }
        if (next < text.length &&
            text.codeUnitAt(next) == 58 &&
            stack.isNotEmpty &&
            stack.last != null) {
          final key = jsonDecode(text.substring(start, i + 1)) as String;
          if (!stack.last!.add(key)) {
            throw const FormatException('Duplicate object key.');
          }
        }
        nodes++;
      } else if (c == 123 || c == 91) {
        stack.add(c == 123 ? <String>{} : null);
        if (stack.length > maxDepth) {
          throw const FormatException('Limit: JSON nesting exceeds 32 levels.');
        }
        nodes++;
      } else if (c == 125 || c == 93) {
        if (stack.isEmpty) throw const FormatException('Unbalanced JSON.');
        stack.removeLast();
      } else if (c == 44) {
        nodes++;
      }
      if (nodes > maxNodes) {
        throw const FormatException(
          'Limit: JSON complexity exceeds 100000 tokens.',
        );
      }
    }
  }
}

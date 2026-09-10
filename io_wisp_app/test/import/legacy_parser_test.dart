import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/data/import/legacy_json_reader.dart';
import 'package:io_wisp_app/domain/legacy_import.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/legacy_v005.json').readAsStringSync())
        as Map<String, dynamic>;
LegacySource parse(dynamic data) => LegacyJsonParser.parse(
  Uint8List.fromList(utf8.encode(jsonEncode(data))),
  'example.json',
);

void main() {
  test('missing creation date normalizes both timestamps to import time with a warning', () {
    final data = fixture();
    (data['project'] as Map).remove('createdAt');
    final source = parse(data);
    expect(source.blocked, false);
    expect(source.candidate!.createdAt, isNull);
    expect(source.candidate!.updatedAt, isNull);
    expect(source.findings.any((f) => f.code == 'missing-created-date'), true);
  });
  test(
    'extended Windows device names are sanitized independently of display text',
    () {
      for (final name in ['CON.foo.bar', 'LPT1.txt.more', 'COM¹']) {
        expect(ImportNameRules.safeSegment(name), false);
        expect(ImportNameRules.folderPart(name), startsWith('_'));
      }
    },
  );
  test('confirmed full V0.0.5 export maps only identity and dates', () {
    final source = parse(fixture());
    expect(source.blocked, false);
    expect(source.candidate!.draft.name, 'Synthetic Workshop');
    expect(source.candidate!.draft.locationClient, 'Example Client');
    expect(source.candidate!.legacyId, 'project-synthetic001');
    expect(source.candidate!.createdAt, DateTime.utc(2026, 8, 1, 1, 2, 3));
    expect(
      source.findings.where((f) => f.level == FindingLevel.warning),
      isEmpty,
    );
    expect(
      source.findings
          .where((f) => f.level == FindingLevel.deferred)
          .map((f) => f.field),
      containsAll([
        'project.scopeBrief',
        'project.files',
        'project.sheets',
        'project.timeEntries',
        'table_of_contents',
      ]),
    );
  });
  for (final text in [
    '{',
    '{"project":1,"project":2}',
    '{"a":1,"\\u0061":2}',
    '{"x":"unterminated}',
    'null',
    '42',
    '"text"',
  ]) {
    test('rejects malformed, ambiguous or non-object JSON $text', () {
      expect(
        LegacyJsonParser.parse(
          Uint8List.fromList(utf8.encode(text)),
          'test.json',
        ).blocked,
        true,
      );
    });
  }
  for (final change in <void Function(Map<String, dynamic>)>[
    (v) => v.remove('app_version'),
    (v) => v['app_version'] = 'V0.0.4',
    (v) => v['io_assistant'] = 'Other',
    (v) => v['project'] = [],
    (v) => (v['project'] as Map).remove('name'),
    (v) => v['project']['name'] = ' \n ',
    (v) => v['project']['name'] = 2,
    (v) => v['project']['location'] = null,
    (v) => v['project']['pages'] = -1,
    (v) => v['project']['files'] = {},
    (v) => v['project']['scopeBrief'] = [],
    (v) => v['api_used'] = 'false',
    (v) => v['document']['title'] = 1,
    (v) => v['project']['id'] = '../path',
    (v) => v['project']['name'] = List.filled(301, 'x').join(),
  ]) {
    test('invalid fields are fatal ${change.hashCode}', () {
      final v = fixture();
      change(v);
      expect(parse(v).blocked, true);
    });
  }
  for (final date in [
    '2026-02-30T00:00:00Z',
    '2026-13-01T00:00:00Z',
    '2026-01-01',
    '2026-01-01T00:00:00',
    '2026-01-01T24:00:00Z',
    '2026-01-01T00:00:00+14:30',
  ]) {
    test('rejects invalid timestamp $date', () {
      final v = fixture();
      v['project']['createdAt'] = date;
      expect(parse(v).blocked, true);
    });
  }
  test('normalizes whitespace and timezone without mutating fixture', () {
    final v = fixture();
    v['project']['name'] = '  Synthetic   Workshop ';
    v['project']['revision'] = ' A ';
    v['project']['createdAt'] = '2026-08-01T09:02:03+08:00';
    final source = parse(v);
    expect(source.blocked, false);
    expect(source.candidate!.draft.name, 'Synthetic Workshop');
    expect(source.candidate!.draft.revision, 'A');
    expect(v['project']['revision'], ' A ');
    expect(source.candidate!.createdAt, DateTime.utc(2026, 8, 1, 1, 2, 3));
  });
  test('optional fields may be absent; title never substitutes a name', () {
    final v = {
      'io_assistant': 'IO Wisp Lite',
      'app_version': 'V0.0.5',
      'project': {'name': 'Minimal'},
    };
    expect(parse(v).blocked, false);
    expect(parse(v).candidate!.draft.locationClient, '');
    expect(parse({'name': 'Raw record', 'sheets': []}).blocked, true);
  });
  test('unknown fields disclosed without retaining their values', () {
    final v = fixture();
    v['secret'] = 'DO_NOT_STORE';
    v['project']['extra'] = {'token': 'PRIVATE'};
    v['project']['sheets'][0]['unknown'] = 'PRIVATE';
    final source = parse(v);
    expect(source.blocked, false);
    expect(
      source.findings.where((f) => f.code == 'unsupported-field'),
      hasLength(3),
    );
    expect(
      source.findings.map((f) => f.message).join(),
      isNot(contains('PRIVATE')),
    );
  });
  for (final value in [
    r'..\..\outside',
    r'C:\outside\plan.pdf',
    r'\\server\share',
    r'CON',
    'NUL.txt',
  ]) {
    test('legacy path ignored and warned: $value', () {
      final v = fixture();
      v['project']['folderName'] = value;
      v['project']['files'][0]['name'] = value;
      final source = parse(v);
      expect(source.blocked, false);
      expect(
        source.findings.where((f) => f.code == 'unsafe-legacy-path'),
        hasLength(2),
      );
    });
  }
  test('arrays rejected and repeated source candidates detected', () {
    final source = parse([fixture(), fixture()]);
    expect(source.blocked, true);
    expect(source.findings.any((f) => f.code == 'duplicate-in-source'), true);
    expect(parse([fixture()]).blocked, true);
  });
  test('size, depth and complexity are bounded before decode', () {
    expect(
      LegacyJsonParser.parse(
        Uint8List(LegacyJsonParser.maxBytes + 1),
        'large.json',
      ).blocked,
      true,
    );
    final nested =
        '${List.filled(33, '[').join()}0${List.filled(33, ']').join()}';
    expect(
      LegacyJsonParser.parse(
        Uint8List.fromList(utf8.encode(nested)),
        'nested.json',
      ).findings.single.message,
      contains('32'),
    );
    final many = '[${List.filled(100002, '0').join(',')}]';
    expect(
      LegacyJsonParser.parse(
        Uint8List.fromList(utf8.encode(many)),
        'many.json',
      ).findings.single.message,
      contains('100000'),
    );
  });
  test('read-only loading and SHA256 leave source bytes and modification time unchanged', () async {
    final temp = await Directory.systemTemp.createTemp('wisp-import-reader-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/source.json');
    final bytes = File('test/fixtures/legacy_v005.json').readAsBytesSync();
    file.writeAsBytesSync(bytes);
    final before = file.statSync();
    final source = await const ReadOnlyLegacyJsonReader().read(file.path);
    expect(source.blocked, false);
    expect(source.fingerprint, sha256.convert(bytes).toString());
    expect(file.readAsBytesSync(), bytes);
    expect(file.statSync().modified, before.modified);
    final second = await const ReadOnlyLegacyJsonReader().read(file.path);
    expect(second.fingerprint, source.fingerprint);
  });
}

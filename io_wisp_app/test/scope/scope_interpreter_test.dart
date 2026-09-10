import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:io_wisp_app/domain/scope.dart';
import 'package:io_wisp_app/domain/scope_interpreter.dart';

void main() {
  const interpreter = ScopeInterpreter();
  final fixtures = jsonDecode(
    File('test/fixtures/scope_cases.json').readAsStringSync(),
  ) as List;
  for (final f in fixtures.cast<Map<String, dynamic>>()) {
    test('fixture: ${f['name']}', () {
      final results = interpreter.interpret(
        f['raw'] as String,
        strict: f['strict'] as bool,
      );
      validateScopeResults(results);
      for (final r in results) {
        expect(
          r.detected.name,
          (f['decisions'] as Map)[r.packageId] ?? f['default'],
          reason: r.packageId,
        );
        expect(r.manual, isNull);
      }
      final again = interpreter.interpret(
        f['raw'] as String,
        strict: f['strict'] as bool,
      );
      expect(
        again.map((r) => [r.detected.name, r.reason, r.evidence]),
        results.map((r) => [r.detected.name, r.reason, r.evidence]),
      );
    });
  }
  for (final p in scopePackages) {
    test('catalog aliases match whole terms: ${p.id}', () {
      for (final term in p.terms) {
        final r = interpreter
            .interpret('Include $term', strict: true)
            .firstWhere((r) => r.packageId == p.id);
        expect(r.detected, ScopeDecision.included, reason: term);
        expect(r.evidence.join(), contains(term));
      }
    });
  }
  test('catalog exactly matches protected legacy source', () {
    final html = File('../releases/v0.0.5/IO_Wisp_Lite_V0.0.5.html')
        .readAsStringSync();
    final source = RegExp(r'const SCOPE_PACKAGES = (\[[\s\S]*?\n      \]);')
        .firstMatch(html)!
        .group(1)!;
    final legacy = jsonDecode(source.replaceAll("'", '"'));
    expect(scopePackages.map((p) => [p.id, p.label, p.terms]).toList(), legacy);
  });
  test(
    'invalid control characters fail',
    () => expect(
      () => interpreter.interpret('Include\u0000concrete', strict: true),
      throwsFormatException,
    ),
  );
  test(
    'oversized input fails',
    () => expect(
      () => interpreter.interpret('a' * 64001, strict: true),
      throwsFormatException,
    ),
  );
  test('exclusion and inclusion evidence are both retained', () {
    final r = interpreter
        .interpret('Include concrete. Exclude concrete.', strict: true)
        .firstWhere((r) => r.packageId == 'concrete');
    expect(r.detected, ScopeDecision.rejected);
    expect(r.evidence, hasLength(2));
  });
}

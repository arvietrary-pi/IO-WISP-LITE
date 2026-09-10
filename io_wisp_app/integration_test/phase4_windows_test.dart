import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/scope/scope_test_support.dart';
import '../test/scope/scope_ui_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Phase 4 Scope Brief with disposable SQLite and failure injection',
    (tester) async {
      final c = ScopeTestContext();
      final checkpoints = <String>[];
      debugPrint('PHASE4_DISPOSABLE_PATH=${c.temp.path}');
      try {
        await scopeUiScenario(
          tester,
          c,
          checkpoint: (s) {
            checkpoints.add(s);
            debugPrint('P4: $s');
          },
        );
        final snapshot = {
          'disposablePath': c.temp.path,
          'checkpoints': checkpoints,
          'schema': c.db.userVersion,
          for (final table in [
            'projects',
            'scope_revisions',
            'scope_results',
            'scope_current',
          ])
            table: c.db.database
                .select('SELECT * FROM $table')
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
          'integrity': c.db.database
              .select('PRAGMA integrity_check')
              .single
              .values
              .single,
        };
        File('${c.temp.path}/native-scope-evidence.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(snapshot),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        c.close(keep: const bool.fromEnvironment('WISP_KEEP_EVIDENCE'));
      }
    },
  );
}

import 'package:flutter_test/flutter_test.dart';

import 'package:io_wisp_app/domain/project.dart';

void main() {
  group('ProjectNameRules', () {
    test('rejects empty and whitespace-only names', () {
      expect(ProjectNameRules.validationError(''), isNotNull);
      expect(ProjectNameRules.validationError('   \n\t'), isNotNull);
    });

    test('normalizes duplicate comparison without changing display value', () {
      expect(ProjectNameRules.displayValue('  A  Project  '), 'A Project');
      expect(ProjectNameRules.normalize('  A  Project  '), 'a project');
    });
  });

  group('FolderNamePolicy', () {
    test('sanitizes Windows characters and traversal input', () {
      final folder = FolderNamePolicy.forProject(
        name: r'..\..\A/B:C*?',
        locationClient: r'Client/..\escape',
        date: DateTime(2026, 9, 3),
      );

      expect(FolderNamePolicy.isSafeFolderName(folder), isTrue);
      expect(folder.contains('\\'), isFalse);
      expect(folder.contains('/'), isFalse);
      expect(folder.contains(':'), isFalse);
      expect(folder, contains('2026-09-03'));
    });

    test('protects Windows reserved names', () {
      final folder = FolderNamePolicy.sanitizeSegment('CON');

      expect(folder, '_CON');
      expect(FolderNamePolicy.isSafeFolderName(folder), isTrue);
      expect(FolderNamePolicy.isSafeFolderName('CON'), isFalse);
      expect(FolderNamePolicy.isSafeFolderName('report.'), isFalse);
    });

    test('absolute-path input cannot become a safe child reference', () {
      final folder = FolderNamePolicy.sanitizeSegment(
        r'C:\Users\Public\escape',
      );

      expect(FolderNamePolicy.isSafeFolderName(folder), isTrue);
      expect(folder.contains('\\'), isFalse);
      expect(folder.startsWith('C:'), isFalse);
    });
  });
}

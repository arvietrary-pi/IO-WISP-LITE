import 'package:uuid/uuid.dart';

import '../../domain/managed_file.dart';
import '../../domain/pdf_document.dart';
import '../database/app_database.dart';

class SqlitePdfRepository {
  SqlitePdfRepository(this.db);
  final AppDatabase db;
  PdfIndex? find(String project, String file) {
    final rows = db.database.select(
      'SELECT * FROM pdf_documents WHERE project_id=? AND managed_file_id=? AND complete=1',
      [project, file],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    final pages = db.database.select(
      'SELECT * FROM pdf_pages WHERE project_id=? AND document_id=? ORDER BY physical_page',
      [project, r['id']],
    );
    if (pages.length != r['page_count']) {
      throw const PdfFailure(
        PdfFailureKind.persistence,
        'Stored PDF index is incomplete.',
      );
    }
    return PdfIndex(
      r['id'] as String,
      project,
      file,
      r['fingerprint'] as String,
      r['index_version'] as String,
      pages
          .map(
            (p) => PhysicalPage(
              p['physical_page'] as int,
              (p['width'] as num).toDouble(),
              (p['height'] as num).toDouble(),
              p['rotation'] as int,
            ),
          )
          .toList(),
    );
  }

  PdfIndex save(ManagedFile file, List<PhysicalPage> pages, String version) {
    validatePages(pages);
    return db.transaction(() {
      final prior = find(file.projectId, file.id);
      if (prior != null) {
        if (prior.fingerprint != file.fingerprint.sha256 ||
            prior.indexVersion != version ||
            prior.pages.length != pages.length ||
            List.generate(
              pages.length,
              (i) =>
                  prior.pages[i].number == pages[i].number &&
                  prior.pages[i].width == pages[i].width &&
                  prior.pages[i].height == pages[i].height &&
                  prior.pages[i].rotation == pages[i].rotation,
            ).contains(false)) {
          throw const PdfFailure(
            PdfFailureKind.persistence,
            'Stored PDF index differs from the source. The previous index is retained for review.',
          );
        }
        return prior;
      }
      final id = const Uuid().v4();
      db.database.execute(
        'INSERT INTO pdf_documents(id,project_id,managed_file_id,fingerprint,page_count,index_version,indexed_at) VALUES(?,?,?,?,?,?,?)',
        [
          id,
          file.projectId,
          file.id,
          file.fingerprint.sha256,
          pages.length,
          version,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      for (final page in pages) {
        db.database.execute('INSERT INTO pdf_pages VALUES(?,?,?,?,?,?)', [
          file.projectId,
          id,
          page.number,
          page.width,
          page.height,
          page.rotation,
        ]);
      }
      db.database.execute('UPDATE pdf_documents SET complete=1 WHERE id=?', [
        id,
      ]);
      return find(file.projectId, file.id)!;
    });
  }
}

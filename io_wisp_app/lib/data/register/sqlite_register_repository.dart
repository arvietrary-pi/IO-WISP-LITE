import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/document_register.dart';
import '../database/app_database.dart';

class RegisterPersistenceException implements Exception {
  const RegisterPersistenceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SqliteRegisterRepository {
  SqliteRegisterRepository(this.db);
  final AppDatabase db;

  DocumentRegister? find(String projectId, String managedFileId) {
    final rows = db.database.select(
      'SELECT * FROM document_registers WHERE project_id=? AND managed_file_id=?',
      [projectId, managedFileId],
    );
    return rows.isEmpty ? null : _read(rows.single);
  }

  List<DocumentRegister> listProject(String projectId) => db.database
      .select(
        'SELECT * FROM document_registers WHERE project_id=? ORDER BY analyzed_at, source_filename',
        [projectId],
      )
      .map(_read)
      .toList(growable: false);

  DocumentRegister saveDetection({
    required String projectId,
    required String managedFileId,
    required String sourceFilename,
    required String fingerprint,
    required String detectorVersion,
    required List<DetectedRegisterEntry> entries,
    DateTime? analyzedAt,
  }) {
    if (entries.isEmpty ||
        entries.asMap().entries.any(
          (pair) => pair.value.physicalPage != pair.key + 1,
        )) {
      throw const RegisterPersistenceException(
        'Detection must contain every physical page in sequential order.',
      );
    }
    final time = (analyzedAt ?? DateTime.now().toUtc()).toUtc();
    return db.transaction(() {
      final existing = db.database.select(
        'SELECT * FROM document_registers WHERE project_id=? AND managed_file_id=?',
        [projectId, managedFileId],
      );
      late String id;
      if (existing.isEmpty) {
        id = const Uuid().v4();
        db.database.execute(
          '''
          INSERT INTO document_registers(
            id,project_id,managed_file_id,source_filename,fingerprint,
            detector_version,analyzed_at,page_count
          ) VALUES(?,?,?,?,?,?,?,?)
        ''',
          [
            id,
            projectId,
            managedFileId,
            sourceFilename,
            fingerprint,
            detectorVersion,
            time.toIso8601String(),
            entries.length,
          ],
        );
      } else {
        final row = existing.single;
        id = row['id'] as String;
        if (row['fingerprint'] != fingerprint ||
            row['page_count'] != entries.length ||
            row['source_filename'] != sourceFilename) {
          throw const RegisterPersistenceException(
            'The source identity or physical page count changed. Import it as a separate revision.',
          );
        }
        db.database.execute(
          '''
          UPDATE document_registers
          SET detector_version=?, analyzed_at=? WHERE id=?
        ''',
          [detectorVersion, time.toIso8601String(), id],
        );
      }
      for (final entry in entries) {
        _upsertDetected(id, entry);
      }
      final stored =
          db.database.select(
                'SELECT count(*) AS count FROM document_register_entries WHERE register_id=?',
                [id],
              ).single['count']
              as int;
      if (stored != entries.length) {
        throw const RegisterPersistenceException(
          'The stored Document Register is incomplete.',
        );
      }
      return _read(
        db.database.select('SELECT * FROM document_registers WHERE id=?', [
          id,
        ]).single,
      );
    });
  }

  void _upsertDetected(String registerId, DetectedRegisterEntry entry) {
    final values = <Object?>[
      registerId,
      entry.physicalPage,
      entry.sheetNumber,
      entry.title,
      entry.discipline,
      entry.revision,
      entry.scale,
      entry.drawingDate,
      entry.summary,
      entry.evidence,
      entry.titleBlockText,
      entry.textSample,
      jsonEncode(entry.candidates),
      jsonEncode(entry.references),
      jsonEncode(entry.diagnostics.map((value) => value.name).toList()),
      entry.status.name,
      entry.confidence,
      entry.textItemCount,
      entry.lineCount,
      entry.hasReadableText ? 1 : 0,
    ];
    db.database.execute('''
      INSERT INTO document_register_entries(
        register_id,physical_page,detected_sheet_number,detected_title,
        detected_discipline,detected_revision,detected_scale,
        detected_drawing_date,detected_summary,detected_evidence,
        detected_title_block_text,detected_text_sample,
        detected_candidates_json,detected_references_json,
        detected_diagnostics_json,detected_status,detected_confidence,
        text_item_count,line_count,has_readable_text
      ) VALUES(${List.filled(20, '?').join(',')})
      ON CONFLICT(register_id,physical_page) DO UPDATE SET
        detected_sheet_number=excluded.detected_sheet_number,
        detected_title=excluded.detected_title,
        detected_discipline=excluded.detected_discipline,
        detected_revision=excluded.detected_revision,
        detected_scale=excluded.detected_scale,
        detected_drawing_date=excluded.detected_drawing_date,
        detected_summary=excluded.detected_summary,
        detected_evidence=excluded.detected_evidence,
        detected_title_block_text=excluded.detected_title_block_text,
        detected_text_sample=excluded.detected_text_sample,
        detected_candidates_json=excluded.detected_candidates_json,
        detected_references_json=excluded.detected_references_json,
        detected_diagnostics_json=excluded.detected_diagnostics_json,
        detected_status=excluded.detected_status,
        detected_confidence=excluded.detected_confidence,
        text_item_count=excluded.text_item_count,
        line_count=excluded.line_count,
        has_readable_text=excluded.has_readable_text
    ''', values);
  }

  DocumentRegister updateOverrides(
    String projectId,
    String managedFileId,
    int physicalPage,
    RegisterEntryOverrides overrides,
  ) => db.transaction(() {
    final register = _require(projectId, managedFileId);
    db.database.execute(
      '''
      UPDATE document_register_entries SET
        manual_sheet_number=?, manual_title=?, manual_discipline=?,
        manual_revision=?, manual_scale=?, manual_drawing_date=?,
        estimator_notes=?, document_state=?
      WHERE register_id=? AND physical_page=?
    ''',
      [
        overrides.sheetNumber,
        overrides.title,
        overrides.discipline,
        overrides.revision,
        overrides.scale,
        overrides.drawingDate,
        overrides.notes,
        overrides.documentState.name,
        register.id,
        physicalPage,
      ],
    );
    if (db.database.updatedRows != 1) {
      throw const RegisterPersistenceException(
        'Document Register page was not found.',
      );
    }
    return _readHeader(register.id);
  });

  DocumentRegister setReviewState(
    String projectId,
    String managedFileId,
    int physicalPage,
    RegisterReviewState state, {
    String? signedOffBy,
    DateTime? signedOffAt,
  }) => db.transaction(() {
    if (state == RegisterReviewState.signedOff &&
        (signedOffBy == null || signedOffBy.trim().isEmpty)) {
      throw const RegisterPersistenceException(
        'Estimator name is required for sign-off.',
      );
    }
    final register = _require(projectId, managedFileId);
    db.database.execute(
      '''
      UPDATE document_register_entries SET review_state=?,signed_off_at=?,signed_off_by=?
      WHERE register_id=? AND physical_page=?
    ''',
      [
        state.name,
        state == RegisterReviewState.signedOff
            ? (signedOffAt ?? DateTime.now().toUtc()).toUtc().toIso8601String()
            : null,
        state == RegisterReviewState.signedOff ? signedOffBy!.trim() : null,
        register.id,
        physicalPage,
      ],
    );
    if (db.database.updatedRows != 1) {
      throw const RegisterPersistenceException(
        'Document Register page was not found.',
      );
    }
    return _readHeader(register.id);
  });

  DocumentRegister _require(String projectId, String managedFileId) =>
      find(projectId, managedFileId) ??
      (throw const RegisterPersistenceException(
        'Analyze this PDF before editing its Document Register.',
      ));

  DocumentRegister _readHeader(String id) => _read(
    db.database.select('SELECT * FROM document_registers WHERE id=?', [
      id,
    ]).single,
  );

  DocumentRegister _read(Map<String, Object?> header) {
    final id = header['id'] as String;
    final rows = db.database.select(
      'SELECT * FROM document_register_entries WHERE register_id=? ORDER BY physical_page',
      [id],
    );
    if (rows.length != header['page_count']) {
      throw const RegisterPersistenceException(
        'Stored Document Register page rows are incomplete.',
      );
    }
    return DocumentRegister(
      id: id,
      projectId: header['project_id'] as String,
      managedFileId: header['managed_file_id'] as String,
      sourceFilename: header['source_filename'] as String,
      fingerprint: header['fingerprint'] as String,
      detectorVersion: header['detector_version'] as String,
      analyzedAt: DateTime.parse(header['analyzed_at'] as String).toUtc(),
      entries: rows.map((row) => _entry(id, row)).toList(growable: false),
    );
  }

  DocumentRegisterEntry _entry(String registerId, Map<String, Object?> row) {
    List<String> strings(String key) =>
        (jsonDecode(row[key] as String) as List).cast<String>();
    final candidates = strings('detected_candidates_json');
    return DocumentRegisterEntry(
      registerId: registerId,
      detected: DetectedRegisterEntry(
        physicalPage: row['physical_page'] as int,
        sheetNumber: row['detected_sheet_number'] as String,
        title: row['detected_title'] as String,
        discipline: row['detected_discipline'] as String,
        revision: row['detected_revision'] as String,
        scale: row['detected_scale'] as String,
        drawingDate: row['detected_drawing_date'] as String,
        summary: row['detected_summary'] as String,
        evidence: row['detected_evidence'] as String,
        titleBlockText: row['detected_title_block_text'] as String,
        textSample: row['detected_text_sample'] as String,
        candidates: candidates,
        references: strings('detected_references_json'),
        diagnostics: strings('detected_diagnostics_json')
            .map((value) => PageDiagnostic.values.byName(value))
            .toList(growable: false),
        status: RegisterEntryStatus.values.byName(
          row['detected_status'] as String,
        ),
        confidence: row['detected_confidence'] as String,
        textItemCount: row['text_item_count'] as int,
        lineCount: row['line_count'] as int,
        hasReadableText: row['has_readable_text'] == 1,
      ),
      manualSheetNumber: row['manual_sheet_number'] as String?,
      manualTitle: row['manual_title'] as String?,
      manualDiscipline: row['manual_discipline'] as String?,
      manualRevision: row['manual_revision'] as String?,
      manualScale: row['manual_scale'] as String?,
      manualDrawingDate: row['manual_drawing_date'] as String?,
      notes: row['estimator_notes'] as String,
      reviewState: RegisterReviewState.values.byName(
        row['review_state'] as String,
      ),
      signedOffAt: row['signed_off_at'] == null
          ? null
          : DateTime.parse(row['signed_off_at'] as String).toUtc(),
      signedOffBy: row['signed_off_by'] as String?,
      documentState: DocumentState.values.byName(
        row['document_state'] as String,
      ),
    );
  }
}

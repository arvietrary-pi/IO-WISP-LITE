import 'dart:convert';
import 'dart:typed_data';

import '../data/pdf/sqlite_pdf_repository.dart';
import '../data/storage/sqlite_managed_file_repository.dart';
import '../domain/managed_file.dart';
import '../domain/pdf_document.dart';

class ManagedPdfService implements PdfDocumentService {
  ManagedPdfService(this.files, this.store, this.indexes, this.renderer);
  final SqliteManagedFileRepository files;
  final ProjectFileStore store;
  final SqlitePdfRepository indexes;
  final PdfRenderer renderer;
  @override
  Future<PdfSession> open(
    String projectId,
    String managedFileId,
    RenderCancellation cancel,
  ) async {
    ProjectFileLease? lease;
    ManagedReadSource? source;
    PdfRenderDocument? document;
    try {
      cancel.check();
      if (managedFileId.isEmpty) {
        throw const PdfFailure(
          PdfFailureKind.noSource,
          'No PDF source selected. Return to Project files.',
        );
      }
      final record = files.database.database.select(
        'SELECT project_id FROM managed_files WHERE id=?',
        [managedFileId],
      );
      if (record.isEmpty) {
        throw const PdfFailure(
          PdfFailureKind.missingRecord,
          'The managed file record is missing.',
        );
      }
      if (record.single['project_id'] != projectId) {
        throw const PdfFailure(
          PdfFailureKind.projectMismatch,
          'This source does not belong to the selected project.',
        );
      }
      final file = files.get(projectId, managedFileId);
      if (file.state == ManagedFileState.missing) {
        throw const PdfFailure(
          PdfFailureKind.missingFile,
          'The managed PDF is missing. Restore the exact original copy and refresh its status.',
        );
      }
      if (file.state == ManagedFileState.recoveryNeeded) {
        throw const PdfFailure(
          PdfFailureKind.unusableSource,
          'Source requires recovery review; it may have changed. Refresh and review Project files.',
        );
      }
      if (file.state != ManagedFileState.ready) {
        throw const PdfFailure(
          PdfFailureKind.unusableSource,
          'The source is not in a usable ready state.',
        );
      }
      if (file.relativePath != 'sources/${file.leaf}') {
        throw const PdfFailure(
          PdfFailureKind.storage,
          'Managed source reference is invalid.',
        );
      }
      lease = store.openProject(files.project(projectId), files.projects);
      if (lease is! ManagedReadLease) {
        throw const PdfFailure(
          PdfFailureKind.unsupported,
          'This storage adapter cannot provide protected PDF reads.',
        );
      }
      source = lease.openReadOnlyManaged(file.relativePath);
      if (source == null) {
        throw const PdfFailure(
          PdfFailureKind.missingFile,
          'The managed PDF file is missing. No alternative file was opened.',
        );
      }
      final fingerprint = await source.fingerprint();
      cancel.check();
      if (!fingerprint.matches(file.fingerprint)) {
        throw const PdfFailure(
          PdfFailureKind.changedSource,
          'Managed source changed: SHA-256 or size differs from import provenance. Restore the exact copy or import the revision separately.',
        );
      }
      final header = Uint8List(
        fingerprint.byteCount < 1024 ? fingerprint.byteCount : 1024,
      );
      final read = source.readAt(header, 0, header.length);
      if (!latin1.decode(header.sublist(0, read)).contains('%PDF-')) {
        throw const PdfFailure(
          PdfFailureKind.notPdf,
          'The managed file is not PDF content.',
        );
      }
      document = await renderer.open(
        source,
        fingerprint.byteCount,
        '$projectId/$managedFileId/${fingerprint.sha256}',
      );
      cancel.check();
      validatePages(document.pages);
      lease.verify();
      // Revalidate provenance/state after asynchronous opening; no stale import state can commit.
      final current = files.get(projectId, managedFileId);
      if (current.state != ManagedFileState.ready ||
          current.relativePath != file.relativePath ||
          !current.fingerprint.matches(file.fingerprint)) {
        throw const PdfFailure(
          PdfFailureKind.changedSource,
          'Managed source record changed while opening.',
        );
      }
      PdfIndex index;
      try {
        index = indexes.save(file, document.pages, renderer.indexVersion);
      } catch (_) {
        throw const PdfFailure(
          PdfFailureKind.persistence,
          'PDF index could not be saved or verified. The previous valid index is retained.',
        );
      }
      final heldSource = source;
      final heldLease = lease;
      return PdfSession(file, index, document, () {
        heldSource.close();
        heldLease.close();
      });
    } catch (e) {
      try {
        await document?.dispose();
      } finally {
        source?.close();
        lease?.close();
      }
      if (e is PdfFailure) rethrow;
      throw const PdfFailure(
        PdfFailureKind.storage,
        'Protected source could not be read. Check the project folder and file access, then retry.',
      );
    }
  }
}

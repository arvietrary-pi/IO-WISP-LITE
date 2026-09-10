import 'dart:typed_data';

import 'managed_file.dart';
import 'document_register.dart';

enum PdfFailureKind {
  noSource,
  missingRecord,
  projectMismatch,
  unusableSource,
  missingFile,
  changedSource,
  notPdf,
  corrupt,
  unsupported,
  zeroPages,
  render,
  resource,
  cancelled,
  persistence,
  storage,
}

class PdfFailure implements Exception {
  const PdfFailure(this.kind, this.message);
  final PdfFailureKind kind;
  final String message;
  @override
  String toString() => message;
}

class PhysicalPage {
  const PhysicalPage(this.number, this.width, this.height, this.rotation);
  final int number, rotation;

  /// Rotated dimensions in PDF points (1/72 inch), never drawing identifiers.
  final double width, height;
}

void validatePages(List<PhysicalPage> pages) {
  if (pages.isEmpty) {
    throw const PdfFailure(
      PdfFailureKind.zeroPages,
      'The PDF has no usable physical pages.',
    );
  }
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    if (p.number != i + 1 ||
        !p.width.isFinite ||
        !p.height.isFinite ||
        p.width <= 0 ||
        p.height <= 0 ||
        ![0, 90, 180, 270].contains(p.rotation)) {
      throw const PdfFailure(
        PdfFailureKind.corrupt,
        'The PDF has invalid physical-page geometry.',
      );
    }
  }
}

class PdfIndex {
  PdfIndex(
    this.id,
    this.projectId,
    this.managedFileId,
    this.fingerprint,
    this.indexVersion,
    List<PhysicalPage> pages,
  ) : pages = List.unmodifiable(pages) {
    validatePages(pages);
  }
  final String id, projectId, managedFileId, fingerprint, indexVersion;
  final List<PhysicalPage> pages;
}

class PageRequest {
  const PageRequest(this.page, this.warning);
  final int page;
  final String? warning;
  static PageRequest parse(String input, int count) {
    if (count < 1 || !RegExp(r'^[+-]?\d+$').hasMatch(input.trim())) {
      throw const PdfFailure(
        PdfFailureKind.render,
        'Enter a whole physical PDF page number.',
      );
    }
    final value = BigInt.parse(input.trim());
    final page = value < BigInt.one
        ? 1
        : value > BigInt.from(count)
        ? count
        : value.toInt();
    return PageRequest(
      page,
      value == BigInt.from(page)
          ? null
          : 'Requested page is outside 1–$count. Showing physical PDF page $page.',
    );
  }
}

class RenderCancellation {
  bool cancelled = false;
  void Function()? onCancel;
  void cancel() {
    cancelled = true;
    onCancel?.call();
  }

  void check() {
    if (cancelled) {
      throw const PdfFailure(
        PdfFailureKind.cancelled,
        'PDF operation cancelled.',
      );
    }
  }
}

/// One owned BGRA raster. Consumers must dispose it, including stale results.
abstract interface class PageRaster {
  int get width;
  int get height;
  Uint8List get pixels;
  String? get diagnostic;
  void dispose();
}

abstract interface class PdfRenderDocument {
  List<PhysicalPage> get pages;
  Future<PositionalTextPage> extractText(int physicalPage);
  Future<PageRaster> render(
    int physicalPage,
    double scale,
    RenderCancellation cancel,
  );
  Future<void> dispose();
}

abstract interface class PdfRenderer {
  String get indexVersion;
  Future<PdfRenderDocument> open(
    ManagedReadSource source,
    int size,
    String identity,
  );
}

abstract interface class PdfDocumentService {
  Future<PdfSession> open(
    String projectId,
    String managedFileId,
    RenderCancellation cancel,
  );
}

class PdfSession {
  PdfSession(this.file, this.index, this.document, this.release);
  final ManagedFile file;
  final PdfIndex index;
  final PdfRenderDocument document;
  final void Function() release;
  Future<void>? _closing;
  Future<void> dispose() => _closing ??= _dispose();
  Future<void> _dispose() async {
    try {
      await document.dispose();
    } finally {
      release();
    }
  }
}

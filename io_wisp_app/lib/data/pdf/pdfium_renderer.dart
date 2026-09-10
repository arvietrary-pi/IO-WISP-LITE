import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart' as engine;

import '../../domain/managed_file.dart';
import '../../domain/document_register.dart';
import '../../domain/pdf_document.dart';

Future<void> _nativeTail = Future.value();
Future<T> _native<T>(Future<T> Function() operation) {
  final result = _nativeTail.then((_) => operation());
  _nativeTail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  return result;
}

class PdfiumRenderer implements PdfRenderer {
  @override
  String get indexVersion => 'pdfium-geometry/1;pdfrx_engine/0.5.0';
  @override
  Future<PdfRenderDocument> open(
    ManagedReadSource source,
    int size,
    String identity,
  ) => _native(() => _open(source, size, identity));

  Future<PdfRenderDocument> _open(
    ManagedReadSource source,
    int size,
    String identity,
  ) async {
    engine.PdfDocument? document;
    try {
      // The native asset is bundled at build time. No URI, cache or download API.
      await engine.PdfrxEntryFunctions.instance.init();
      document = await engine.PdfDocument.openCustom(
        read: source.readAt,
        fileSize: size,
        sourceName: identity,
        // Fill one native encoded buffer through bounded protected reads.
        // Avoid the upstream Windows custom-callback condition-variable race.
        maxSizeToCacheOnMemory: size,
      );
      final pages = document.pages
          .map(
            (p) => PhysicalPage(
              p.pageNumber,
              p.width,
              p.height,
              p.rotation.index * 90,
            ),
          )
          .toList();
      validatePages(pages);
      return _Document(document, pages);
    } catch (e) {
      await document?.dispose();
      if (e is PdfFailure) rethrow;
      if (e is OutOfMemoryError) {
        throw const PdfFailure(
          PdfFailureKind.resource,
          'Insufficient memory to open this PDF. Close other documents and retry.',
        );
      }
      if (e is engine.PdfPasswordException) {
        throw const PdfFailure(
          PdfFailureKind.unsupported,
          'The PDF could not be opened: it may be corrupt, password-protected, or use unsupported encryption. This Windows renderer cannot distinguish these failures. Password entry is not supported.',
        );
      }
      if (e is engine.PdfException) {
        throw const PdfFailure(
          PdfFailureKind.corrupt,
          'The PDF renderer could not open this corrupt or unsupported document.',
        );
      }
      throw const PdfFailure(
        PdfFailureKind.unsupported,
        'The bundled PDF renderer could not initialize or open this source.',
      );
    }
  }
}

class _Document implements PdfRenderDocument {
  _Document(this.native, List<PhysicalPage> pages)
    : pages = List.unmodifiable(pages);
  final engine.PdfDocument native;
  @override
  final List<PhysicalPage> pages;
  bool _closed = false;
  Future<void>? _closing;
  final Set<Future<PageRaster>> _pending = {};

  @override
  Future<PositionalTextPage> extractText(int physicalPage) =>
      _native(() => _extractText(physicalPage));

  Future<PositionalTextPage> _extractText(int physicalPage) async {
    if (_closed) {
      throw const PdfFailure(
        PdfFailureKind.cancelled,
        'PDF session is closed.',
      );
    }
    if (physicalPage < 1 || physicalPage > pages.length) {
      throw const PdfFailure(
        PdfFailureKind.render,
        'Physical PDF page is out of range.',
      );
    }
    try {
      final page = native.pages[physicalPage - 1];
      final text = await page.loadStructuredText();
      final items = <PositionalTextItem>[];
      for (final fragment in text.fragments) {
        final value = fragment.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (value.isEmpty || fragment.bounds.isEmpty) continue;
        items.add(orientPdfTextRect(page, fragment.bounds, value));
      }
      return PositionalTextPage(
        physicalPage: physicalPage,
        width: page.width,
        height: page.height,
        rotation: page.rotation.index * 90,
        items: List.unmodifiable(items),
      );
    } catch (error) {
      if (error is PdfFailure) rethrow;
      throw const PdfFailure(
        PdfFailureKind.unsupported,
        'Embedded positional text could not be extracted from this physical page.',
      );
    }
  }

  @override
  Future<PageRaster> render(
    int physicalPage,
    double scale,
    RenderCancellation cancel,
  ) {
    late Future<PageRaster> task;
    task = _render(
      physicalPage,
      scale,
      cancel,
    ).whenComplete(() => _pending.remove(task));
    _pending.add(task);
    return task;
  }

  Future<PageRaster> _render(
    int number,
    double scale,
    RenderCancellation cancel,
  ) async {
    cancel.check();
    if (_closed) {
      throw const PdfFailure(
        PdfFailureKind.cancelled,
        'PDF session is closed.',
      );
    }
    if (number < 1 || number > pages.length) {
      throw const PdfFailure(
        PdfFailureKind.render,
        'Physical PDF page is out of range.',
      );
    }
    if (!scale.isFinite || scale < .2 || scale > 3) {
      throw const PdfFailure(
        PdfFailureKind.resource,
        'Zoom must be between 20% and 300%.',
      );
    }
    final page = native.pages[number - 1];
    final width = page.width * scale;
    final height = page.height * scale;
    // Raster budget only: scale down large pages, never reject the source. At
    // 4 bytes/pixel this bounds each native raster to 16 MiB plus display copy.
    final factor = math.min(
      1.0,
      math.min(
        math.sqrt(4194304 / (width * height)),
        4096 / math.max(width, height),
      ),
    );
    final w = math.max(1, (width * factor).floor());
    final h = math.max(1, (height * factor).floor());
    final token = page.createCancellationToken();
    cancel.onCancel = token.cancel;
    if (cancel.cancelled) token.cancel();
    engine.PdfImage? image;
    try {
      image = await _native(
        () => page.render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
          cancellationToken: token,
        ),
      );
      cancel.check();
      if (_closed) {
        throw const PdfFailure(
          PdfFailureKind.cancelled,
          'PDF session is closed.',
        );
      }
      if (image == null) {
        throw const PdfFailure(
          PdfFailureKind.render,
          'Physical page rendering failed. Retry this page or select another page.',
        );
      }
      final result = _Raster(
        image,
        factor < .999
            ? 'Display resolution reduced to $w × $h pixels to bound memory. Zoom and source geometry are unchanged.'
            : null,
      );
      image = null;
      return result;
    } catch (e) {
      if (e is PdfFailure) rethrow;
      if (e is OutOfMemoryError) {
        throw const PdfFailure(
          PdfFailureKind.resource,
          'Insufficient memory to render this page. Try a lower zoom.',
        );
      }
      throw const PdfFailure(
        PdfFailureKind.render,
        'Physical page rendering failed. Retry at a lower zoom.',
      );
    } finally {
      image?.dispose();
      cancel.onCancel = null;
    }
  }

  @override
  Future<void> dispose() => _closing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    await Future.wait(
      _pending.toList().map((f) async {
        try {
          await f;
        } catch (_) {}
      }),
    );
    await _native(native.dispose);
  }
}

/// Converts PDFium's pre-rotation, bottom-left rectangles into the oriented
/// top-left point space used by the V0.0.5 deterministic detector.
PositionalTextItem orientPdfTextRect(
  engine.PdfPage page,
  engine.PdfRect rect,
  String text,
) {
  final rotation = page.rotation.index;
  final rawWidth = rotation.isOdd ? page.height : page.width;
  final rawHeight = rotation.isOdd ? page.width : page.height;
  late double left, top, width, height;
  switch (rotation) {
    case 0:
      left = rect.left;
      top = rawHeight - rect.top;
      width = rect.width;
      height = rect.height;
    case 1:
      left = rawHeight - rect.top;
      top = rect.left;
      width = rect.height;
      height = rect.width;
    case 2:
      left = rawWidth - rect.right;
      top = rect.bottom;
      width = rect.width;
      height = rect.height;
    case 3:
      left = rect.bottom;
      top = rawWidth - rect.right;
      width = rect.height;
      height = rect.width;
    default:
      throw StateError('Unsupported PDF rotation.');
  }
  return PositionalTextItem(
    text: text,
    x: left.clamp(0, page.width),
    y: (top + height).clamp(0, page.height),
    width: width,
    height: height,
  );
}

class _Raster implements PageRaster {
  _Raster(this.native, this.diagnostic);
  final engine.PdfImage native;
  bool disposed = false;
  @override
  final String? diagnostic;
  @override
  int get width => native.width;
  @override
  int get height => native.height;
  @override
  Uint8List get pixels => native.pixels;
  @override
  void dispose() {
    if (!disposed) {
      disposed = true;
      native.dispose();
    }
  }
}

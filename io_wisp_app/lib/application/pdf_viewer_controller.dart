import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/pdf_document.dart';

class PdfViewerController extends ChangeNotifier {
  PdfViewerController(this.service);
  final PdfDocumentService service;
  PdfSession? session;
  ui.Image? image;
  int page = 1;
  double zoom = 1, viewportWidth = 0;
  bool fit = false, loading = false, disposed = false;
  String? error, warning, diagnostic;
  PdfFailureKind? failureKind;
  int _generation = 0;
  RenderCancellation? _opening, _rendering;
  bool _pumping = false, _pending = false;
  String _project = '', _file = '';
  int get count => session?.index.pages.length ?? 0;
  bool get previousEnabled => count > 0 && page > 1;
  bool get nextEnabled => count > 0 && page < count;
  double get displayWidth =>
      count == 0 ? 0 : session!.index.pages[page - 1].width * zoom;
  double get displayHeight =>
      count == 0 ? 0 : session!.index.pages[page - 1].height * zoom;
  void _emit() {
    if (!disposed) notifyListeners();
  }

  void _clearImage() {
    image?.dispose();
    image = null;
    diagnostic = null;
  }

  Future<void> open(String project, String file) async {
    if (disposed) return;
    _project = project;
    _file = file;
    final generation = ++_generation;
    _opening?.cancel();
    _rendering?.cancel();
    final cancel = _opening = RenderCancellation();
    final old = session;
    session = null;
    _pending = false;
    _clearImage();
    page = 1;
    zoom = 1;
    fit = false;
    error = warning = null;
    failureKind = null;
    loading = true;
    _emit();
    try {
      await old?.dispose();
      cancel.check();
      final next = await service.open(project, file, cancel);
      if (disposed || generation != _generation) {
        await next.dispose();
        return;
      }
      session = next;
      _request();
    } catch (e) {
      if (disposed || generation != _generation) return;
      loading = false;
      error = '$e';
      failureKind = e is PdfFailure ? e.kind : PdfFailureKind.render;
      _emit();
    }
  }

  Future<void> retry() =>
      session == null ? open(_project, _file) : _retryRender();
  Future<void> _retryRender() async {
    _request();
  }

  void first() => go('1');
  void previous() {
    if (previousEnabled) go('${page - 1}');
  }

  void next() {
    if (nextEnabled) go('${page + 1}');
  }

  void go(String value) {
    if (session == null || disposed) return;
    try {
      final request = PageRequest.parse(value, count);
      page = request.page;
      warning = request.warning;
      if (fit) _fitScale();
      _request();
    } on PdfFailure catch (e) {
      warning = e.message;
      _emit();
    }
  }

  void zoomBy(double delta) {
    if (session == null || disposed) return;
    fit = false;
    zoom = ((zoom + delta) * 100).round().clamp(20, 300) / 100;
    warning = null;
    _request();
  }

  void fitWidth() {
    if (session == null || disposed) return;
    fit = true;
    _fitScale();
    _request();
  }

  void viewport(double width) {
    if (disposed ||
        !width.isFinite ||
        width <= 0 ||
        (width - viewportWidth).abs() < .5) {
      return;
    }
    viewportWidth = width;
    if (fit && session != null) {
      _fitScale();
      _request();
    }
  }

  void _fitScale() {
    final requested = viewportWidth / session!.index.pages[page - 1].width;
    zoom = requested.clamp(.2, 3);
    warning = requested < .2 || requested > 3
        ? 'Fit width reached the 20–300% zoom boundary.'
        : null;
  }

  void _request() {
    if (disposed || session == null) return;
    ++_generation;
    _rendering?.cancel();
    _clearImage();
    error = null;
    failureKind = null;
    loading = true;
    _pending = true;
    _emit();
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_pending && !disposed && session != null) {
        _pending = false;
        final generation = _generation;
        final current = session!;
        final cancel = _rendering = RenderCancellation();
        PageRaster? raster;
        ui.Image? decoded;
        try {
          raster = await current.document.render(page, zoom, cancel);
          if (disposed || generation != _generation) continue;
          final completed = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            raster.pixels,
            raster.width,
            raster.height,
            ui.PixelFormat.bgra8888,
            completed.complete,
          );
          decoded = await completed.future;
          if (disposed || generation != _generation) continue;
          image = decoded;
          decoded = null;
          diagnostic = raster.diagnostic;
          loading = false;
          _emit();
        } catch (e) {
          if (!disposed && generation == _generation) {
            _clearImage();
            loading = false;
            error = '$e';
            failureKind = e is PdfFailure ? e.kind : PdfFailureKind.render;
            _emit();
          }
        } finally {
          decoded?.dispose();
          raster?.dispose();
        }
      }
    } finally {
      _pumping = false;
    }
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    ++_generation;
    _opening?.cancel();
    _rendering?.cancel();
    _clearImage();
    final old = session;
    session = null;
    if (old != null) unawaited(old.dispose());
    super.dispose();
  }
}

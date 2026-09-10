import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/pdf_viewer_controller.dart';
import '../../domain/pdf_document.dart';

class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.managedFileId,
    required this.filename,
    required this.service,
    this.initialPhysicalPage = 1,
  });
  final String projectId, projectName, managedFileId, filename;
  final PdfDocumentService service;
  final int initialPhysicalPage;
  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late PdfViewerController controller;
  final entry = TextEditingController();
  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    controller = PdfViewerController(widget.service)..addListener(_changed);
    unawaited(_openInitial());
  }

  Future<void> _openInitial() async {
    await controller.open(widget.projectId, widget.managedFileId);
    if (widget.initialPhysicalPage != 1 && controller.count > 0) {
      controller.go('${widget.initialPhysicalPage}');
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {
        entry.text = '${controller.page}';
      });
    }
  }

  @override
  void didUpdateWidget(covariant PdfViewerPage old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId ||
        old.managedFileId != widget.managedFileId ||
        old.service != widget.service) {
      controller.removeListener(_changed);
      controller.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final usable = c.count > 0;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.projectName} — ${widget.filename}')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  usable
                      ? 'Physical PDF page ${c.page} of ${c.count}'
                      : 'No physical PDF page loaded',
                  key: const ValueKey('pdfPageLabel'),
                ),
                OutlinedButton(
                  key: const ValueKey('pdfFirst'),
                  onPressed: c.previousEnabled ? c.first : null,
                  child: const Text('First'),
                ),
                OutlinedButton(
                  key: const ValueKey('pdfPrevious'),
                  onPressed: c.previousEnabled ? c.previous : null,
                  child: const Text('Previous'),
                ),
                OutlinedButton(
                  key: const ValueKey('pdfNext'),
                  onPressed: c.nextEnabled ? c.next : null,
                  child: const Text('Next'),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    key: const ValueKey('pdfPageEntry'),
                    controller: entry,
                    enabled: usable,
                    decoration: const InputDecoration(labelText: 'Page'),
                    onSubmitted: c.go,
                  ),
                ),
                OutlinedButton(
                  key: const ValueKey('pdfGo'),
                  onPressed: usable ? () => c.go(entry.text) : null,
                  child: const Text('Go'),
                ),
                IconButton(
                  key: const ValueKey('pdfZoomOut'),
                  tooltip: 'Zoom out',
                  onPressed: usable && c.zoom > .2
                      ? () => c.zoomBy(-.15)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('${(c.zoom * 100).round()}%'),
                IconButton(
                  key: const ValueKey('pdfZoomIn'),
                  tooltip: 'Zoom in',
                  onPressed: usable && c.zoom < 3 ? () => c.zoomBy(.15) : null,
                  icon: const Icon(Icons.add),
                ),
                OutlinedButton(
                  key: const ValueKey('pdfFitWidth'),
                  onPressed: usable ? c.fitWidth : null,
                  child: const Text('Fit width'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Physical PDF pages are separate from drawing/sheet numbers.',
            ),
          ),
          if (c.loading)
            const LinearProgressIndicator(key: ValueKey('pdfLoading')),
          if (c.warning != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(c.warning!)),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.error!, key: const ValueKey('pdfError')),
                  TextButton(
                    key: const ValueKey('pdfRetry'),
                    onPressed: c.retry,
                    child: const Text('Retry'),
                  ),
                  const Text(
                    'Return to Project files to review the managed source or import a separate revision.',
                  ),
                ],
              ),
            ),
          if (c.diagnostic != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(c.diagnostic!),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    c.viewport(
                      (constraints.maxWidth - 32).clamp(1, double.infinity),
                    );
                  }
                });
                return ColoredBox(
                  color: const Color(0xffdce2e5),
                  child: c.image == null
                      ? Center(
                          child: Text(
                            c.loading
                                ? 'Loading physical PDF page…'
                                : 'No page raster displayed.',
                          ),
                        )
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: RawImage(
                                key: const ValueKey('pdfRaster'),
                                image: c.image,
                                width: c.displayWidth,
                                height: c.displayHeight,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

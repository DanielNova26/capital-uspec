// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

final Set<String> _registeredPdfViewTypes = <String>{};

Widget buildGdPdfPreview({
  required String url,
  required Future<Uint8List> pdfFuture,
  required String fileName,
  String? refreshKey,
}) {
  return _WebPdfPreview(
    url: url,
    fileName: fileName,
    pdfFuture: pdfFuture,
    refreshKey: refreshKey,
  );
}

class _WebPdfPreview extends StatefulWidget {
  final String url;
  final String fileName;
  final Future<Uint8List> pdfFuture;
  final String? refreshKey;

  const _WebPdfPreview({
    required this.url,
    required this.fileName,
    required this.pdfFuture,
    this.refreshKey,
  });

  @override
  State<_WebPdfPreview> createState() => _WebPdfPreviewState();
}

class _WebPdfPreviewState extends State<_WebPdfPreview> {
  bool _downloading = false;
  Uint8List? _cachedBytes;

  @override
  void didUpdateWidget(covariant _WebPdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.fileName != widget.fileName) {
      _cachedBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayUrl = _appendCacheBust(widget.url, widget.refreshKey);
    final viewType =
        'gd-pdf-preview-${displayUrl.hashCode}-${widget.fileName.hashCode}';
    if (_registeredPdfViewTypes.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        return html.IFrameElement()
          ..src = displayUrl
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%';
      });
    }

    return Stack(
      children: [
        HtmlElementView(key: ValueKey(viewType), viewType: viewType),
        Positioned(
          bottom: 16,
          right: 16,
          child: PointerInterceptor(
            child: _downloading
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FloatingActionButton.small(
                    heroTag: 'dl-${widget.fileName}',
                    tooltip: 'Descargar: ${widget.fileName}',
                    backgroundColor: Colors.black54,
                    onPressed: _download,
                    child: const Icon(Icons.download, color: Colors.white),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = _cachedBytes ?? await widget.pdfFuture;
      final blob = html.Blob([bytes], 'application/pdf');
      final objectUrl = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: objectUrl)
        ..setAttribute('download', widget.fileName)
        ..click();
      html.Url.revokeObjectUrl(objectUrl);
    } catch (_) {
      html.window.open(widget.url, '_blank');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}

String _appendCacheBust(String url, String? refreshKey) {
  final token = (refreshKey ?? '').trim();
  if (token.isEmpty) return url;
  final separator = url.contains('?') ? '&' : '?';
  return '$url${separator}v=$token';
}

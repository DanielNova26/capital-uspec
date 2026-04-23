import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final Set<String> _registeredPdfViewTypes = <String>{};

Widget buildGdPdfPreview({
  required String url,
  required Future<Uint8List> pdfFuture,
  required String fileName,
  String? refreshKey,
}) {
  final _ = pdfFuture;
  return _WebPdfPreview(url: url, fileName: fileName, refreshKey: refreshKey);
}

class _WebPdfPreview extends StatelessWidget {
  final String url;
  final String fileName;
  final String? refreshKey;

  const _WebPdfPreview({
    required this.url,
    required this.fileName,
    this.refreshKey,
  });

  @override
  Widget build(BuildContext context) {
    final displayUrl = _appendCacheBust(url, refreshKey);
    final viewType =
        'gd-pdf-preview-${displayUrl.hashCode}-${fileName.hashCode}';
    if (_registeredPdfViewTypes.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = displayUrl
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%';
        return iframe;
      });
    }

    return HtmlElementView(key: ValueKey(viewType), viewType: viewType);
  }
}

String _appendCacheBust(String url, String? refreshKey) {
  final token = (refreshKey ?? '').trim();
  if (token.isEmpty) return url;
  final separator = url.contains('?') ? '&' : '?';
  return '$url${separator}v=$token';
}

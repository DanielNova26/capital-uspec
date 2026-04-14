import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final Set<String> _registeredPdfViewTypes = <String>{};

Widget buildGdPdfPreview({
  required String url,
  required Future<Uint8List> pdfFuture,
  required String fileName,
}) {
  final _ = pdfFuture;
  return _WebPdfPreview(url: url, fileName: fileName);
}

class _WebPdfPreview extends StatelessWidget {
  final String url;
  final String fileName;

  const _WebPdfPreview({required this.url, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final viewType = 'gd-pdf-preview-${url.hashCode}-${fileName.hashCode}';
    if (_registeredPdfViewTypes.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = url
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%';
        return iframe;
      });
    }

    return HtmlElementView(viewType: viewType);
  }
}

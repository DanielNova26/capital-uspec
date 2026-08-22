// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher_string.dart';

/// Visor inline de PDF en Flutter Web.
///
/// Descarga los bytes del PDF y los convierte en un Blob URL para evitar
/// el problema de `Content-Disposition: attachment` que tienen algunas URLs
/// de Firebase Storage. Renderiza el PDF en un <iframe> usando el visor
/// nativo del navegador, sin dependencias externas adicionales.
class WebPdfView extends StatefulWidget {
  final String url;
  const WebPdfView({super.key, required this.url});

  @override
  State<WebPdfView> createState() => _WebPdfViewState();
}

class _WebPdfViewState extends State<WebPdfView> {
  // Identificador único por instancia + URL para evitar conflictos de registro
  late final String _viewId;
  bool _ready = false;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'pdf-iframe-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200) {
        if (mounted) setState(() => _errored = true);
        return;
      }
      // Crear Blob URL: el navegador siempre renderiza blobs inline,
      // ignorando cabeceras Content-Disposition del servidor original.
      final blob = html.Blob([response.bodyBytes], 'application/pdf');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);

      // Registrar la view factory ANTES de que se construya HtmlElementView
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
        return html.IFrameElement()
          ..src = blobUrl
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none';
      });

      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _errored = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) return _Fallback(url: widget.url);
    if (!_ready) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 12),
            Text(
              'Cargando PDF…',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }
    return HtmlElementView(viewType: _viewId);
  }
}

class _Fallback extends StatelessWidget {
  final String url;
  const _Fallback({required this.url});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf_rounded, size: 64, color: Colors.red.shade400),
          const SizedBox(height: 12),
          const Text(
            'No se pudo cargar el PDF',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ábrelo en una nueva pestaña para revisarlo.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => launchUrlString(url, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Abrir PDF'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          ),
        ],
      ),
    );
  }
}

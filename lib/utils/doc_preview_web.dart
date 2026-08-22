// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

final Set<String> _registeredPdfTypes = {};

void showWebPdfDialog(BuildContext context, String url, String title) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PdfBlobDialog(url: url, title: title),
  );
}

/// Descarga los bytes del PDF desde la URL (Firebase Storage u otra),
/// crea un Blob URL local (sin Content-Disposition) y lo muestra en un iframe.
class _PdfBlobDialog extends StatefulWidget {
  final String url;
  final String title;
  const _PdfBlobDialog({required this.url, required this.title});

  @override
  State<_PdfBlobDialog> createState() => _PdfBlobDialogState();
}

class _PdfBlobDialogState extends State<_PdfBlobDialog> {
  String? _blobUrl;
  String? _viewType;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200) {
        throw Exception('No se pudo cargar el PDF (${response.statusCode})');
      }
      final blob = html.Blob([response.bodyBytes], 'application/pdf');
      final objectUrl = html.Url.createObjectUrlFromBlob(blob);

      final vt = 'hv-pdf-${objectUrl.hashCode.abs()}';
      if (_registeredPdfTypes.add(vt)) {
        ui_web.platformViewRegistry.registerViewFactory(vt, (int _) {
          return html.IFrameElement()
            ..src = objectUrl
            ..style.border = '0'
            ..style.width = '100%'
            ..style.height = '100%';
        });
      }

      if (mounted) {
        setState(() {
          _blobUrl = objectUrl;
          _viewType = vt;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void dispose() {
    // Liberar el Blob URL del navegador
    if (_blobUrl != null) html.Url.revokeObjectUrl(_blobUrl!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const thPrimary = Color(0xFFC28942);
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: size.width > 900 ? 860 : double.infinity,
        height: size.height * 0.88,
        child: Column(
          children: [
            // Cabecera
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf, color: thPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Contenido
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Cargando PDF…'),
                        ],
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    )
                  : HtmlElementView(
                      key: ValueKey(_viewType),
                      viewType: _viewType!,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

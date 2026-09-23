// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../theme/app_typography.dart';
import 'office_preview.dart';

/// Web: iframe con el visor de Microsoft; si el usuario lo pide, con el de
/// Google. El iframe no avisa cuando el visor falla (es otro origen), así que
/// se deja a mano el cambio de visor y el botón de descarga.
class OfficePreview extends StatefulWidget {
  final String url;
  final String nombreArchivo;
  const OfficePreview({super.key, required this.url, this.nombreArchivo = ''});

  @override
  State<OfficePreview> createState() => _OfficePreviewState();
}

class _OfficePreviewState extends State<OfficePreview> {
  bool _google = false;
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _registrar();
  }

  @override
  void didUpdateWidget(covariant OfficePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _google = false;
      _registrar();
    }
  }

  void _registrar() {
    final src = _google
        ? urlVisorGoogle(widget.url)
        : urlVisorOffice(widget.url);
    _viewId =
        'office-iframe-${src.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      return html.IFrameElement()
        ..src = src
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFFF1F5F9),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.nombreArchivo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _google = !_google;
                  _registrar();
                }),
                child: Text(
                  _google ? 'Usar visor de Microsoft' : 'Usar visor de Google',
                  style: const TextStyle(fontFamily: kArial, fontSize: 11),
                ),
              ),
              IconButton(
                tooltip: 'Descargar archivo',
                visualDensity: VisualDensity.compact,
                onPressed: () => launchUrlString(
                  widget.url,
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: HtmlElementView(key: ValueKey(_viewId), viewType: _viewId),
        ),
      ],
    );
  }
}

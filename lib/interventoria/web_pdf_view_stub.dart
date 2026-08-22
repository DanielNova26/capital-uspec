import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Implementación móvil: no hay iframe nativo, se abre el PDF en visor externo.
class WebPdfView extends StatelessWidget {
  final String url;
  const WebPdfView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf_rounded, size: 64, color: Colors.red.shade400),
          const SizedBox(height: 16),
          const Text(
            'PDF del interventor',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Toca el botón para abrir el PDF\nen el visor de tu dispositivo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),
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

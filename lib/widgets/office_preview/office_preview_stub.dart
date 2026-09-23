import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../theme/app_typography.dart';
import 'office_preview.dart';

/// Móvil: no hay iframe. Se abre el visor en línea en el navegador o se
/// descarga el archivo.
class OfficePreview extends StatelessWidget {
  final String url;
  final String nombreArchivo;
  const OfficePreview({super.key, required this.url, this.nombreArchivo = ''});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_rounded,
              size: 56,
              color: Color(0xFF2563A6),
            ),
            const SizedBox(height: 12),
            Text(
              nombreArchivo.isEmpty ? 'Documento' : nombreArchivo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => launchUrlString(
                urlVisorOffice(url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('Ver en línea'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  launchUrlString(url, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Descargar'),
            ),
          ],
        ),
      ),
    );
  }
}

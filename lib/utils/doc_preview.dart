import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'doc_preview_stub.dart'
    if (dart.library.html) 'doc_preview_web.dart';

/// Muestra un PDF en un diálogo con iframe (web) o abre externamente (móvil).
Future<void> previewDocument(
  BuildContext context,
  String url,
  String title,
) async {
  if (url.isEmpty) return;
  if (kIsWeb) {
    showWebPdfDialog(context, url, title);
  } else {
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }
}

/// Muestra una imagen en pantalla completa dentro de un diálogo.
void previewImage(BuildContext context, String url) {
  if (url.isEmpty) return;
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              radius: 18,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

void showWebPdfDialog(BuildContext context, String url, String title) {
  // En móvil: descarga y muestra con PdfPreview (paquete printing)
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _MobilePdfDialog(url: url, title: title),
  );
}

class _MobilePdfDialog extends StatelessWidget {
  final String url;
  final String title;
  const _MobilePdfDialog({required this.url, required this.title});

  Future<Uint8List> _load() async {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) throw Exception('Error ${r.statusCode}');
    return r.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: PdfPreview(
              build: (_) => _load(),
              allowPrinting: false,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: title,
            ),
          ),
        ],
      ),
    );
  }
}

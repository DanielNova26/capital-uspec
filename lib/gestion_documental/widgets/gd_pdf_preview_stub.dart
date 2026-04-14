import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

Widget buildGdPdfPreview({
  required String url,
  required Future<Uint8List> pdfFuture,
  required String fileName,
}) {
  return FutureBuilder<Uint8List>(
    future: pdfFuture,
    builder: (context, pdfSnap) {
      if (pdfSnap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (pdfSnap.hasError) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 48,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No se pudo renderizar la vista previa',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  pdfSnap.error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final bytes = pdfSnap.data;
      if (bytes == null || bytes.isEmpty) {
        return const Center(
          child: Text(
            'El PDF no contiene datos para vista previa.',
          ),
        );
      }

      return PdfPreview(
        build: (_) async => bytes,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: fileName,
      );
    },
  );
}

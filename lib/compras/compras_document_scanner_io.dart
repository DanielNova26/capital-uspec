import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

bool get documentScannerAvailable => Platform.isAndroid;

Future<Uint8List?> scanDocumentPdf() async {
  if (!Platform.isAndroid) return null;

  final scanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: const {DocumentFormat.pdf},
      mode: ScannerMode.full,
      pageLimit: 20,
      isGalleryImport: true,
    ),
  );
  try {
    final result = await scanner.scanDocument();
    final path = result.pdf?.uri.trim() ?? '';
    if (path.isEmpty) return null;
    return File(path).readAsBytes();
  } on PlatformException catch (error) {
    final message = (error.message ?? '').toLowerCase();
    if (message.contains('cancel')) return null;
    rethrow;
  } finally {
    await scanner.close();
  }
}

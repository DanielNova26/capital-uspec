import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Android: ML Kit. iOS/iPadOS: VisionKit, el escáner de Apple, expuesto por
/// `ios/Runner/AppDelegate.swift` (ML Kit no tiene escáner para iOS). Los dos
/// detectan bordes, recortan y admiten varias páginas, y devuelven un PDF.
///
/// Se decide con `defaultTargetPlatform` (y no `Platform`) para poder probar la
/// rama de iOS; en la app es exactamente el sistema en el que corre.
bool get documentScannerAvailable =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

const MethodChannel _escanerIos = MethodChannel('todo/escaner_documentos');

Future<Uint8List?> scanDocumentPdf() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) return _scanDocumentPdfIos();
  if (defaultTargetPlatform != TargetPlatform.android) return null;

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

/// Devuelve null si la persona cancela. Un error (sin cámara, simulador) sube
/// como [PlatformException] y la pantalla ofrece "Cámara rápida".
Future<Uint8List?> _scanDocumentPdfIos() {
  return _escanerIos.invokeMethod<Uint8List>('escanearPdf');
}

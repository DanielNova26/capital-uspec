// "Escanear documento" existía solo en Android (ML Kit no tiene escáner para
// iOS). En iPhone y iPad ahora lo hace VisionKit por el canal
// `todo/escaner_documentos` que abre `ios/Runner/AppDelegate.swift`.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_document_scanner_io.dart';

const _canal = MethodChannel('todo/escaner_documentos');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    mensajero.setMockMethodCallHandler(_canal, null);
  });

  test('el botón existe en Android y en iOS, no en escritorio', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(documentScannerAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(documentScannerAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(documentScannerAvailable, isFalse);
  });

  test('en iOS devuelve el PDF que arma el escáner nativo', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final pdf = Uint8List.fromList('%PDF-1.7 prueba'.codeUnits);
    final llamadas = <String>[];
    mensajero.setMockMethodCallHandler(_canal, (llamada) async {
      llamadas.add(llamada.method);
      return pdf;
    });

    expect(await scanDocumentPdf(), pdf);
    expect(llamadas, ['escanearPdf']);
  });

  test('en iOS, cancelar no es un error: devuelve null', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    mensajero.setMockMethodCallHandler(_canal, (_) async => null);

    expect(await scanDocumentPdf(), isNull);
  });

  test('en iOS, un fallo del escáner llega a la pantalla', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    mensajero.setMockMethodCallHandler(_canal, (_) async {
      throw PlatformException(code: 'no_disponible');
    });

    expect(scanDocumentPdf(), throwsA(isA<PlatformException>()));
  });

  test('en escritorio no intenta escanear', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(await scanDocumentPdf(), isNull);
  });
}

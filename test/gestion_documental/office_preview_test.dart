import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/widgets/office_preview/office_preview.dart';

void main() {
  for (final plataforma in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'descarga validada en $plataforma a $ancho con texto ampliado',
        (tester) async {
          tester.view.physicalSize = Size(ancho, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var descargas = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: plataforma),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(ancho, 900),
                  textScaler: const TextScaler.linear(1.6),
                ),
                child: Scaffold(
                  body: OfficePreview(
                    url: 'https://example.test/archivo.docx',
                    nombreArchivo:
                        'PROGRAMA DE PROVEEDORES Y MATERIAS PRIMAS.docx',
                    onDownload: () => descargas++,
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Descargar'));
          expect(descargas, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('Word y Excel tienen visor; otros formatos no', () {
    expect(tieneVistaPreviaOffice('informe.DOCX'), isTrue);
    expect(tieneVistaPreviaOffice('datos.xlsx'), isTrue);
    expect(tieneVistaPreviaOffice('acta.pdf'), isFalse);
  });

  test('la URL del archivo queda codificada para el visor', () {
    const url = 'https://storage.example/doc.xlsx?token=a&b=c';
    expect(urlVisorOffice(url), contains(Uri.encodeComponent(url)));
    expect(urlVisorGoogle(url), contains(Uri.encodeComponent(url)));
  });
}

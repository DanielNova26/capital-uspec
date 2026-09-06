import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/carnet_marca.dart';
import 'package:todo/talento_humano/carnet_pdf.dart';
import 'package:todo/talento_humano/carnet_preview.dart';

const _marca = CarnetMarca(
  empresaId: 'alfa',
  empresaNombre: 'ALFA Unión Temporal',
  colorPrimario: kCarnetAzulPorDefecto,
  colorSecundario: kCarnetDoradoPorDefecto,
);

/// Sin `fotoUrl` a propósito: en un test no hay red, y lo que se quiere revisar
/// aquí es la composición, no la foto.
const _persona = CarnetPersona(
  userId: '1020304050',
  nombres: 'María Fernanda',
  apellidos: 'Rodríguez Cárdenas',
  cargo: 'Auxiliar de Servicios Generales',
  cedula: '1.020.304.050',
  rh: 'O+',
);

void main() {
  testWidgets('la vista previa se arma sin desbordes y deja un PNG a la vista', (
    tester,
  ) async {
    // Sin cargar la fuente real, el test pinta cajas en vez de letras y el PNG
    // no sirve para revisar nada.
    final fuente = FontLoader('Arial')
      ..addFont(rootBundle.load('assets/arial.ttf'));
    await fuente.load();

    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final clave = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: Center(
            child: RepaintBoundary(
              key: clave,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final formato in CarnetFormato.values) ...[
                      CarnetPreview(
                        persona: _persona,
                        marca: _marca,
                        formato: formato,
                        ancho: 300,
                      ),
                      const SizedBox(width: 28),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Un desborde de layout en Flutter no falla el test por sí solo: hay que
    // preguntarle a la consola de errores. Sin esto, un carnet cuyo contenido
    // no cabe en el alto de la tarjeta pasaría inadvertido hasta que alguien
    // lo imprimiera. Es exactamente el fallo que tenía la primera versión.
    expect(tester.takeException(), isNull);

    // La captura del PNG va en `runAsync` porque `toImage` necesita que el
    // rasterizador del motor corra de verdad, y el reloj falso de flutter_test
    // no lo mueve: sin esto la prueba se queda colgada.
    await tester.runAsync(() async {
      final limite =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await limite.toImage(pixelRatio: 2.5);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final salida = Directory('build/carnet_muestra')
        ..createSync(recursive: true);
      File(
        '${salida.path}/vista_previa.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });

    expect(
      File('build/carnet_muestra/vista_previa.png').lengthSync(),
      greaterThan(0),
    );
  });
}

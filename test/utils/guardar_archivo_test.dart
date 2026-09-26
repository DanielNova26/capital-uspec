// En iPad la hoja de compartir es un popover y necesita un punto de origen:
// sin él, share_plus lanza error y Printing la pega a la esquina.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/utils/guardar_archivo.dart';

void main() {
  testWidgets('desde un botón, la hoja sale del botón', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Rect origen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => origen = origenCompartir(context),
                child: const Text('Compartir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Compartir'));

    expect(origen, tester.getRect(find.byType(TextButton)));
  });

  testWidgets('desde la pantalla entera, la hoja sale del centro', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late BuildContext pantalla;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pantalla = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    final origen = origenCompartir(pantalla);
    expect(origen.center, const Offset(590, 410));
    expect(origen.isEmpty, isFalse);
  });
}

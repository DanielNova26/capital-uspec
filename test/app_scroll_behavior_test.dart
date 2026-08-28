// La barra de scroll horizontal es una ayuda de puntero. En un teléfono el
// dedo ya desliza la fila y la barra queda pintada encima de las tarjetas,
// así que allí no debe existir. En escritorio (y web de escritorio) sí.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/theme/app_scroll_behavior.dart';

Widget _appConFilaHorizontal(TargetPlatform plataforma) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  theme: ThemeData(platform: plataforma),
  home: Scaffold(
    body: SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 40,
        itemBuilder: (_, i) => SizedBox(width: 120, child: Text('celda $i')),
      ),
    ),
  ),
);

Widget _appConBarraHorizontal(TargetPlatform plataforma) => MaterialApp(
  theme: ThemeData(platform: plataforma),
  home: Scaffold(
    body: BarraHorizontal(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(40, (i) => SizedBox(width: 120, child: Text('celda $i'))),
        ),
      ),
    ),
  ),
);

void main() {
  group('usaBarraHorizontal', () {
    testWidgets('es falso en Android e iOS', (tester) async {
      for (final plataforma in [TargetPlatform.android, TargetPlatform.iOS]) {
        late bool resultado;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: plataforma),
            home: Builder(
              builder: (context) {
                resultado = usaBarraHorizontal(context);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(resultado, isFalse, reason: '$plataforma no debe llevar barra');
      }
    });

    testWidgets('es verdadero en escritorio', (tester) async {
      for (final plataforma in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        late bool resultado;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: plataforma),
            home: Builder(
              builder: (context) {
                resultado = usaBarraHorizontal(context);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(resultado, isTrue, reason: '$plataforma sí debe llevar barra');
      }
    });
  });

  group('AppScrollBehavior', () {
    testWidgets('no dibuja barra horizontal en móvil', (tester) async {
      await tester.pumpWidget(_appConFilaHorizontal(TargetPlatform.android));
      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets('sí dibuja barra horizontal en escritorio', (tester) async {
      await tester.pumpWidget(_appConFilaHorizontal(TargetPlatform.windows));
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('el eje vertical conserva el comportamiento de la plataforma', (
      tester,
    ) async {
      // El cambio es solo para el eje horizontal: una lista vertical en
      // escritorio debe seguir llevando su barra de siempre.
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: ListView.builder(
              itemCount: 60,
              itemBuilder: (_, i) => SizedBox(height: 40, child: Text('fila $i')),
            ),
          ),
        ),
      );
      expect(find.byType(Scrollbar), findsOneWidget);
    });
  });

  group('BarraHorizontal', () {
    testWidgets('en móvil devuelve el hijo sin envolver', (tester) async {
      await tester.pumpWidget(_appConBarraHorizontal(TargetPlatform.android));
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('en escritorio envuelve en Scrollbar', (tester) async {
      await tester.pumpWidget(_appConBarraHorizontal(TargetPlatform.windows));
      expect(find.byType(Scrollbar), findsOneWidget);
    });
  });
}

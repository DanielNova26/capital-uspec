// "La barra de desplazamiento inferior no me permite moverme" (Análisis,
// 28 sep 2026). La matriz llevaba dos barras horizontales encimadas: la que
// pone AppScrollBehavior en todo scroll horizontal de escritorio y otra
// puesta a mano con BarraHorizontal, esta sin controlador. Ahora la matriz y
// el gráfico apagan la del tema y dejan una sola, con controlador propio.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/theme/app_scroll_behavior.dart';

const _alto = 300.0;

Widget _app(Widget body) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  theme: ThemeData(
    platform: TargetPlatform.windows,
    scrollbarTheme: kAppScrollbarTheme,
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 800, height: _alto, child: body),
    ),
  ),
);

/// Como quedó la matriz: una sola barra, con el controlador del scroll.
class _MatrizConUnaBarra extends StatefulWidget {
  const _MatrizConUnaBarra();

  @override
  State<_MatrizConUnaBarra> createState() => _MatrizConUnaBarraState();
}

class _MatrizConUnaBarraState extends State<_MatrizConUnaBarra> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BarraHorizontal(
    controller: controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: const SizedBox(width: 3000, height: _alto),
    ),
  );
}

/// Como estaban la matriz de Subsanaciones y las del Maestro: BarraHorizontal
/// sin controlador, encima de la barra del tema.
Widget _tablaSinControlador() => BarraHorizontal(
  child: SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: const SizedBox(width: 3000, height: _alto),
  ),
);

Future<double> _arrastrarBarra(WidgetTester tester) async {
  // El pulgar arranca a la izquierda, pegado al borde inferior.
  final gesture = await tester.startGesture(
    const Offset(60, _alto - 4),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.moveTo(const Offset(400, _alto - 4));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  return tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;
}

void main() {
  testWidgets('la matriz de Análisis tiene una sola barra horizontal', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _MatrizConUnaBarra()));
    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('arrastrar la barra de abajo mueve la matriz', (tester) async {
    await tester.pumpWidget(_app(const _MatrizConUnaBarra()));
    await tester.pumpAndSettle();
    expect(await _arrastrarBarra(tester), greaterThan(0));
  });

  testWidgets(
    'sin controlador queda solo la barra del tema, y se arrastra sin errores',
    (tester) async {
      // Antes: tres barras y "The Scrollbar's ScrollController has no
      // ScrollPosition attached" al soltar el arrastre.
      await tester.pumpWidget(_app(_tablaSinControlador()));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(await _arrastrarBarra(tester), greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('en el teléfono no hay barra y el dedo sigue deslizando', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        theme: ThemeData(platform: TargetPlatform.android),
        home: const Scaffold(body: _MatrizConUnaBarra()),
      ),
    );
    expect(find.byType(Scrollbar), findsNothing);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels,
      greaterThan(0),
    );
  });
}

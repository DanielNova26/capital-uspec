import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_maestro_subsanaciones.dart';

void main() {
  Future<void> montarMaestro(WidgetTester tester, {required Size size}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InterventoriaMaestroSubsanaciones()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('web muestra la biblioteca como tabla maestra', (tester) async {
    await montarMaestro(tester, size: const Size(1440, 900));

    expect(find.text('Biblioteca de subsanaciones'), findsOneWidget);
    expect(find.text('Subsanación / aspecto del acta'), findsOneWidget);
    expect(find.text('Asignado a'), findsWidgets);
    expect(find.text('1.1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil usa fichas y permite buscar por responsable', (
    tester,
  ) async {
    await montarMaestro(tester, size: const Size(390, 844));

    expect(
      find.textContaining('El acta lo asigna a', findRichText: true),
      findsWidgets,
    );
    expect(find.text('Subsanación / aspecto del acta'), findsNothing);

    await tester.enterText(
      find.byType(TextField).first,
      'Coordinador de mantenimiento',
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('numerales coinciden con los filtros'),
      findsOne,
    );
    expect(find.text('Coordinador de mantenimiento'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/widgets/acciones_de_fila.dart';

Future<void> _pump(WidgetTester tester, double ancho, List<String> log) async {
  tester.view.physicalSize = Size(ancho, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Row(
            children: [
              const Expanded(child: Text('Nombre de la fila')),
              ...accionesDeFila(context, [
                IconButton(
                  icon: const Icon(Icons.group_outlined),
                  tooltip: 'Ver personal',
                  onPressed: () => log.add('ver'),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar',
                  onPressed: () => log.add('editar'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Eliminar',
                  onPressed: () => log.add('eliminar'),
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('en ancho amplio los tres botones van en línea', (tester) async {
    await _pump(tester, 900, []);
    expect(find.byType(IconButton), findsNWidgets(3));
    expect(find.byType(PopupMenuButton<int>), findsNothing);
  });

  testWidgets('en el teléfono pasan a un menú con las mismas acciones', (
    tester,
  ) async {
    final log = <String>[];
    await _pump(tester, 390, log);
    // El menú usa su propio IconButton: no deben verse los tres de la fila.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byType(PopupMenuButton<int>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    expect(find.text('Ver personal'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(log, ['editar']);
  });
}

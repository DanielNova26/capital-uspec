import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_catalog_import_screen.dart';

void main() {
  testWidgets('Compras ofrece sus cargas Excel y conserva Marcas en el módulo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ComprasCatalogImportScreen(
          empresaId: 'empresa-1',
          userId: 'comprador-1',
        ),
      ),
    );

    expect(find.text('Cargar catálogo de Compras'), findsOneWidget);
    expect(find.text('Proveedores'), findsOneWidget);
    expect(find.text('Productos'), findsOneWidget);
    expect(find.textContaining('Las marcas se crean y editan'), findsOneWidget);
    for (final button in tester.widgetList<FilledButton>(
      find.widgetWithText(FilledButton, 'Importar'),
    )) {
      expect(button.onPressed, isNull);
    }
  });
}

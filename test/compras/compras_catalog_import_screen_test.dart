import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_catalog_import_screen.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets('plantillas a $width px, texto 1.6, $platform', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const ComprasCatalogImportScreen(
              empresaId: 'A',
              userId: 'comprador',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.text('Descargar plantilla'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'Compras ofrece sus cargas Excel y conserva Marcas en el módulo',
    (tester) async {
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
      expect(
        find.textContaining('Las marcas se crean y editan'),
        findsOneWidget,
      );
      for (final button in tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, 'Importar'),
      )) {
        expect(button.onPressed, isNull);
      }
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/widgets/gd_plantilla_excel_dialog.dart';

void main() {
  for (final plataforma in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    final anchos = plataforma == TargetPlatform.windows
        ? [390.0, 768.0, 1024.0, 1366.0]
        : [390.0];
    for (final ancho in anchos) {
      testWidgets('elige cuatro hojas en ${plataforma.name} a $ancho px', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(ancho, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        int? cantidad;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: plataforma),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.8),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    cantidad = await gdElegirCantidadHojas(context);
                  },
                  child: const Text('Plantilla Excel'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Plantilla Excel'));
        await tester.pumpAndSettle();
        final campo = find.byType(TextFormField);
        final descargar = find.widgetWithText(FilledButton, 'Descargar');
        await tester.ensureVisible(campo);
        expect(find.text('1'), findsOneWidget);
        await tester.enterText(campo, '0');
        await tester.tap(descargar);
        await tester.pumpAndSettle();
        expect(find.text('Elige entre 1 y 100 hojas.'), findsOneWidget);
        expect(cantidad, isNull);
        await tester.enterText(campo, '4');
        await tester.tap(descargar);
        await tester.pumpAndSettle();
        expect(cantidad, 4);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

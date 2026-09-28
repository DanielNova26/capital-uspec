import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_formato_editor.dart';
import 'package:todo/visitas/visitas_formato_sst.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

/// El editor solo le pide al servicio los cargos del departamento.
class _SvcFalso implements VisitasService {
  @override
  Future<List<String>> cargosDeArea(
    String empresaId, {
    required String areaId,
    String areaNombre = '',
  }) async => const ['Nutricionista', 'Profesional de calidad'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const nuevo = VisitaFormato(
    empresaId: 'e',
    areaId: 'calidad',
    areaNombre: 'Calidad',
    nombre: 'Visita de calidad',
    items: [
      VisitaFormatoItem(
        id: 'a',
        orden: 1,
        seccion: 'Cocina',
        texto: '¿Pisos limpios?',
      ),
      VisitaFormatoItem(
        id: 'b',
        orden: 2,
        seccion: 'Cocina',
        texto: 'Estado general',
        tipo: kItemTipoOpcion,
        opciones: ['Bueno', 'Malo'],
      ),
    ],
  );

  Future<void> abrir(
    WidgetTester tester,
    VisitaFormato f, {
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: VisitaFormatoEditorScreen(
          svc: _SvcFalso(),
          formato: f,
          userId: 'u',
          areas: const {'calidad': 'Calidad'},
          areaFija: 'calidad',
          avisosImportacion: const ['Hoja "Hoja1": 2 pregunta(s).'],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // El listado principal: el primer Scrollable (los TextField tienen el suyo).
  Finder principal() => find.byType(Scrollable).first;

  Future<void> verHasta(WidgetTester tester, Finder f) =>
      tester.scrollUntilVisible(f, 250, scrollable: principal());

  testWidgets('en el teléfono: tarjetas, agregar pregunta y vista tabla', (
    tester,
  ) async {
    await abrir(tester, nuevo);
    expect(
      find.text('Adaptado desde Excel: revísalo antes de guardar'),
      findsOneWidget,
    );
    await verHasta(tester, find.text('Preguntas (2)'));
    await verHasta(tester, find.text('COCINA'));
    expect(find.text('Así lo verá el profesional'), findsWidgets);

    final agregar = find.widgetWithText(FilledButton, 'Pregunta');
    await verHasta(tester, agregar);
    await tester.tap(agregar);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Preguntas (3)'),
      -250,
      scrollable: principal(),
    );

    await tester.tap(find.text('Tabla (Excel)'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en escritorio el formato SST abre con sus hojas y tablas', (
    tester,
  ) async {
    await abrir(tester, formatoSstOficial('e'), tamano: const Size(1400, 900));
    await verHasta(tester, find.text('Preguntas (109)'));
    // 20 por página.
    await verHasta(tester, find.text('1-20 de 109 preguntas').first);
    await verHasta(tester, find.text('Extintores'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('crear una tabla con filas fijas y escala Cumple', (
    tester,
  ) async {
    await abrir(tester, nuevo, tamano: const Size(1200, 900));
    final tabla = find.widgetWithText(OutlinedButton, 'Tabla');
    await verHasta(tester, tabla);
    await tester.tap(tabla);
    await tester.pumpAndSettle();
    expect(find.text('Nueva tabla'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de la tabla'),
      'Áreas',
    );
    // Sin columnas para calificar no guarda.
    await tester.tap(find.text('Guardar tabla'));
    await tester.pump();
    expect(
      find.text('Agrega al menos una columna para calificar.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

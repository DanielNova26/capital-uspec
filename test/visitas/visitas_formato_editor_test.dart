import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_formato_editor.dart';
import 'package:todo/visitas/visitas_formato_sst.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';
import 'package:todo/utils/excel_download.dart';

/// El editor solo le pide al servicio los cargos del departamento.
class _SvcFalso implements VisitasService {
  VisitaFormato? guardado;

  @override
  Future<String> guardarFormato(
    VisitaFormato f, {
    required String actorId,
  }) async {
    guardado = f;
    return f.id.isEmpty ? 'nuevo' : f.id;
  }

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
    _SvcFalso? svc,
    Future<void> Function({
      required String nombreArchivo,
      required Uint8List bytes,
    })?
    descargarExcel,
    double escala = 1,
    TargetPlatform? plataforma,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: plataforma == null ? null : ThemeData(platform: plataforma),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: VisitaFormatoEditorScreen(
          svc: svc ?? _SvcFalso(),
          formato: f,
          userId: 'u',
          areas: const {'calidad': 'Calidad'},
          areaFija: 'calidad',
          avisosImportacion: const ['Hoja "Hoja1": 2 pregunta(s).'],
          descargarExcel: descargarExcel ?? descargarExcelCompras,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final plataforma in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'descarga borrador sin guardarlo $plataforma $ancho texto 1.8',
        (tester) async {
          final svc = _SvcFalso();
          Uint8List? archivo;
          await abrir(
            tester,
            nuevo,
            svc: svc,
            tamano: Size(ancho, 1000),
            escala: 1.8,
            plataforma: plataforma,
            descargarExcel: ({required nombreArchivo, required bytes}) async {
              archivo = bytes;
            },
          );
          final campo = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.labelText == 'Nombre del formato',
          );
          await tester.ensureVisible(campo);
          await tester.enterText(campo, 'Formulario actualizado sin guardar');
          final boton = find.text('Descargar formulario Excel');
          await tester.scrollUntilVisible(
            boton,
            -250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(boton);
          await tester.pumpAndSettle();
          await tester.tap(boton);
          await tester.pumpAndSettle();
          expect(archivo, isNotNull);
          final libro = xl.Excel.decodeBytes(archivo!);
          expect(
            libro['Formato'].rows[1][1]!.value.toString(),
            'Formulario actualizado sin guardar',
          );
          expect(libro['Preguntas'].maxRows, 3);
          expect(svc.guardado, isNull);
          expect(find.byType(VisitaFormatoEditorScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // El listado principal: el primer Scrollable (los TextField tienen el suyo).
  Finder principal() => find.byType(Scrollable).first;

  Future<void> verHasta(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 250, scrollable: principal());
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
    for (final existente in [false, true]) {
      testWidgets('selección múltiple crea/edita=$existente a $ancho', (
        tester,
      ) async {
        final svc = _SvcFalso();
        final f = nuevo.copyWith(
          id: existente ? 'existente' : '',
          items: [
            nuevo.items.last.copyWith(
              tipo: existente ? kItemTipoSeleccionMultiple : kItemTipoOpcion,
            ),
          ],
        );
        await abrir(tester, f, tamano: Size(ancho, 1000), svc: svc);
        await verHasta(tester, find.text('Preguntas (1)'));
        if (!existente) {
          await tester.ensureVisible(find.text('Lista de opciones').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Lista de opciones').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Selección múltiple').last);
          await tester.pumpAndSettle();
        }
        final opciones = find.widgetWithText(
          TextField,
          'Opciones, separadas por punto y coma',
        );
        await verHasta(tester, opciones);
        await tester.enterText(opciones, 'Horno; Estufa; Nevera');
        await tester.pump();
        expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(3));
        await tester.tap(find.text('Guardar').first);
        await tester.pumpAndSettle();
        expect(svc.guardado?.items.single.tipo, kItemTipoSeleccionMultiple);
        expect(svc.guardado?.items.single.opciones, [
          'Horno',
          'Estufa',
          'Nevera',
        ]);
        expect(svc.guardado?.id, f.id);
        expect(tester.takeException(), isNull);
      });
    }
  }

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

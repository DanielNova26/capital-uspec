import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:todo/services/company_branding_service.dart';
import 'package:todo/visitas/visitas_consolidado.dart';
import 'package:todo/visitas/visitas_models.dart';
import 'package:todo/visitas/visitas_service.dart';

VisitaFormato _formato(String empresa, {bool historico = false}) =>
    VisitaFormato(
      id: 'f',
      empresaId: empresa,
      areaId: 'calidad',
      areaNombre: 'Calidad',
      nombre: historico ? 'Formato original' : 'Formato actualizado',
      items: [
        VisitaFormatoItem(
          id: historico ? 'original' : 'nuevo',
          orden: 1,
          texto: historico ? 'Pregunta original' : 'Pregunta nueva',
        ),
      ],
    );

class _Branding extends Fake implements CompanyBrandingService {
  final espera = Completer<Uint8List?>();
  final empresas = <String?>[];
  @override
  Future<Uint8List?> loadLogoBytes(String? empresaId, {String? fallbackAsset}) {
    empresas.add(empresaId);
    return espera.future;
  }
}

class _Servicio extends Fake implements VisitasService {
  final fotos = <String>[];
  @override
  Future<Map<String, String>> areasDeEmpresa(String empresaId) async => {
    'calidad': 'Calidad',
  };
  @override
  Stream<List<VisitaFormato>> streamFormatos(
    String empresaId, {
    String? areaId,
  }) => Stream.value([_formato(empresaId)]);
  @override
  Stream<List<VisitaProfesional>> streamVisitas(
    String empresaId, {
    String? profesionalId,
    String? areaId,
    String? coordinadorId,
  }) => Stream.value([
    for (var n = 1; n <= 4; n++)
      VisitaProfesional(
        id: '$empresaId-$n',
        empresaId: empresaId,
        numero: n,
        formatoId: n == 3 ? 'perdido' : 'f',
        formatoNombre: 'Inspección',
        formatoAsignado: n == 1 ? _formato(empresaId, historico: true) : null,
        areaId: 'calidad',
        areaNombre: 'Calidad',
        centroId: 'c',
        centroNombre: 'Sede $n',
        profesionalId: 'p',
        profesionalNombre: 'Profesional',
        asignadoPorId: 'jefe',
        asignadoPorNombre: 'Jefe',
        fechaProgramada: DateTime.now(),
        estado: n == 4 ? kVisitaCancelada : kVisitaTerminada,
        respuestas: const {
          'original': VisitaRespuesta(
            resultado: kItemNoCumple,
            evidencias: [
              VisitaEvidencia(
                url: '',
                path: 'foto-original',
                nombre: 'foto.jpg',
              ),
            ],
          ),
        },
      ),
  ]);
  @override
  Future<Uint8List?> bytesEvidencia(VisitaEvidencia e) async {
    fotos.add(e.path);
    return Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 40)));
  }
}

Widget _app(
  _Servicio svc,
  _Branding branding,
  Future<void> Function(Uint8List, String) entregar, {
  String empresa = 'A',
}) => MaterialApp(
  home: Scaffold(
    body: VisitasConsolidadoTab(
      svc: svc,
      empresaId: empresa,
      userId: 'jefe',
      todasLasAreas: true,
      nombreEmpresa: () async => empresa,
      branding: branding,
      entregarInforme: entregar,
    ),
  ),
);

Future<void> _mostrar(WidgetTester tester, String id) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('pdf-visita-$id')),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(ValueKey('pdf-visita-$id')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(ValueKey('pdf-visita-$id')));
  await tester.pumpAndSettle();
  expect(find.byKey(ValueKey('pdf-visita-$id')).hitTestable(), findsOneWidget);
}

void main() {
  testWidgets(
    'descarga el PDF de la visita elegida con su formato original y fotos',
    (tester) async {
      final svc = _Servicio();
      final branding = _Branding()..espera.complete(null);
      final entregado = Completer<(Uint8List, String)>();
      await tester.pumpWidget(
        _app(svc, branding, (bytes, nombre) async {
          entregado.complete((bytes, nombre));
        }),
      );
      await tester.pumpAndSettle();
      await _mostrar(tester, 'A-1');
      await tester.tap(find.byKey(const ValueKey('pdf-visita-A-1')));
      for (var i = 0; i < 100 && !entregado.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(
        entregado.isCompleted,
        isTrue,
        reason: 'La acción debe entregar el PDF generado.',
      );
      await tester.pumpAndSettle();
      final (bytes, nombre) = await entregado.future;
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(nombre, startsWith('Visita_00001_Calidad_Sede_1_'));
      expect(branding.empresas, ['A']);
      // The live catalogue has no 'original' item. Its photo is only included
      // when the report uses the snapshot assigned to this visit.
      expect(svc.fotos, ['foto-original']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permite formato histórico de catálogo, bloquea acta sin formato y cancelada',
    (tester) async {
      await tester.pumpWidget(_app(_Servicio(), _Branding(), (_, _) async {}));
      await tester.pumpAndSettle();
      for (final n in [2, 3, 4]) {
        await _mostrar(tester, 'A-$n');
        final boton = tester.widget<OutlinedButton>(
          find.byKey(ValueKey('pdf-visita-A-$n')),
        );
        expect(boton.onPressed, n == 2 ? isNotNull : isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cambiar de empresa interrumpe la entrega de un informe en preparación',
    (tester) async {
      final svc = _Servicio();
      final branding = _Branding();
      var entregas = 0;
      Future<void> entregar(Uint8List _, String _) async {
        entregas++;
      }

      await tester.pumpWidget(_app(svc, branding, entregar));
      await tester.pumpAndSettle();
      await _mostrar(tester, 'A-1');
      await tester.tap(find.byKey(const ValueKey('pdf-visita-A-1')));
      await tester.pump();
      expect(branding.empresas, ['A']);
      await tester.pumpWidget(_app(svc, branding, entregar, empresa: 'B'));
      await tester.pump();
      branding.espera.complete(null);
      await tester.pumpAndSettle();
      expect(entregas, 0);
      expect(svc.fotos, isEmpty);
      expect(find.byKey(const ValueKey('pdf-visita-A-1')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'las fechas admiten teclado, conservan rango válido y cancelar no modifica',
    (tester) async {
      await tester.pumpWidget(_app(_Servicio(), _Branding(), (_, _) async {}));
      await tester.pumpAndSettle();
      final hoy = DateTime.now();
      final posterior = DateTime(hoy.year, hoy.month + 1, 2);
      final anterior = DateTime(hoy.year, hoy.month, 3);
      String dd(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      Future<void> escribir(String campo, DateTime fecha, String accion) async {
        final boton = find.byKey(ValueKey('fecha-$campo'));
        await tester.ensureVisible(boton);
        await tester.tap(boton);
        await tester.pumpAndSettle();
        final contexto = tester.element(find.byType(DatePickerDialog));
        final locale = MaterialLocalizations.of(contexto);
        await tester.tap(find.byTooltip(locale.inputDateModeButtonLabel));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          locale.formatCompactDate(fecha),
        );
        await tester.tap(find.text(accion));
        await tester.pumpAndSettle();
      }

      await escribir('desde', posterior, 'Aplicar');
      expect(find.text('Desde: ${dd(posterior)}'), findsOneWidget);
      expect(find.text('Hasta: ${dd(posterior)}'), findsOneWidget);
      await escribir('hasta', anterior, 'Aplicar');
      expect(find.text('Desde: ${dd(anterior)}'), findsOneWidget);
      expect(find.text('Hasta: ${dd(anterior)}'), findsOneWidget);
      await escribir('desde', posterior, 'Cancelar');
      expect(find.text('Desde: ${dd(anterior)}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

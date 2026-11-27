import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_reasignacion.dart';

class _Service extends InterventoriaReasignacionService {
  final llamadas = <Map<String, dynamic>>[];
  bool fallar = false;
  Map<String, dynamic> catalogo = {
    'grupos': [
      {'id': 'g7', 'nombre': 'Grupo 7'},
      {'id': 'g6', 'nombre': 'Grupo 6'},
    ],
    'areas': [
      {'id': 'q', 'nombre': 'Calidad'},
      {'id': 'op', 'nombre': 'Operaciones'},
    ],
    'personas': [
      {
        'id': 'jarod',
        'nombre': 'Jarod Nieto',
        'cargo': 'Coordinador',
        'areaId': 'q',
        'grupos': ['g7'],
      },
      {
        'id': 'alterno',
        'nombre': 'Alterno',
        'cargo': 'Ingeniero',
        'areaId': 'op',
        'grupos': ['g6'],
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> llamar(Map<String, dynamic> datos) async {
    llamadas.add({...datos});
    if (datos['accion'] == 'catalogo') return catalogo;
    if (fallar)
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Reintenta sin perder los datos.',
      );
    return {'ok': true};
  }
}

void main() {
  for (final plataforma in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
      testWidgets(
        'proponer y enviar en $plataforma a $ancho con texto 200% y teclado',
        (tester) async {
          tester.view.physicalSize = Size(ancho, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final svc = _Service();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: plataforma),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(ancho, 1100),
                  textScaler: TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 240),
                ),
                child: Scaffold(
                  body: FormularioReasignacionInterventoria(
                    empresaId: 'e',
                    taskId: 't',
                    service: svc,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Jarod Nieto'));
          await tester.tap(find.text('Jarod Nieto'));
          await tester.enterText(
            find.widgetWithText(TextField, 'Por qué no te corresponde'),
            'La sede corresponde al grupo siete.',
          );
          final boton = find.text('Enviar a Interventoría');
          await tester.ensureVisible(boton);
          await tester.tap(boton);
          await tester.pumpAndSettle();
          final envio = svc.llamadas.last;
          expect(envio['accion'], 'solicitar');
          expect(envio['destinoId'], 'jarod');
          expect(envio['empresaId'], 'e');
          expect(envio['motivo'], 'La sede corresponde al grupo siete.');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'grupo y área filtran la propuesta; cambiar filtros limpia la selección',
    (tester) async {
      final svc = _Service();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormularioReasignacionInterventoria(
              empresaId: 'e',
              taskId: 't',
              service: svc,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos los grupos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grupo 7').last);
      await tester.pumpAndSettle();
      expect(find.text('Jarod Nieto'), findsOneWidget);
      expect(find.text('Alterno'), findsNothing);
      await tester.tap(find.text('Todas las áreas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Operaciones').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No hay personas habilitadas'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'fallo conserva motivo y destinatario y reintenta con el mismo identificador',
    (tester) async {
      final svc = _Service()..fallar = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormularioReasignacionInterventoria(
              empresaId: 'e',
              taskId: 't',
              service: svc,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jarod Nieto'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Por qué no te corresponde'),
        'Motivo suficiente.',
      );
      await tester.ensureVisible(find.text('Enviar a Interventoría'));
      await tester.tap(find.text('Enviar a Interventoría'));
      await tester.pumpAndSettle();
      expect(find.text('Reintenta sin perder los datos.'), findsOneWidget);
      final primera = svc.llamadas.last;
      svc.fallar = false;
      await tester.ensureVisible(find.text('Enviar a Interventoría'));
      await tester.tap(find.text('Enviar a Interventoría'));
      await tester.pumpAndSettle();
      expect(svc.llamadas.last['solicitudId'], primera['solicitudId']);
      expect(svc.llamadas.last['motivo'], 'Motivo suficiente.');
      expect(svc.llamadas.last['destinoId'], 'jarod');
    },
  );
  testWidgets('revisor puede rechazar con motivo sin elegir otra persona', (
    tester,
  ) async {
    final svc = _Service();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormularioReasignacionInterventoria(
            empresaId: 'e',
            taskId: 't',
            service: svc,
            solicitud: const {
              'solicitudId': 's',
              'destinoId': 'jarod',
              'grupoId': 'g7',
              'areaId': 'q',
              'motivo': 'No corresponde',
              'solicitante': 'Marcela',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'La asignación es correcta por el numeral.',
    );
    await tester.ensureVisible(find.text('Rechazar con motivo'));
    await tester.tap(find.text('Rechazar con motivo'));
    await tester.pumpAndSettle();
    expect(svc.llamadas.last['accion'], 'resolver');
    expect(svc.llamadas.last['aprobar'], isFalse);
    expect(svc.llamadas.last['solicitudId'], 's');
    expect(svc.llamadas.last['destinoId'], '');
  });
  testWidgets('el panel descarta la respuesta atrasada de otra empresa', (
    tester,
  ) async {
    final svc = _PanelService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SolicitudesReasignacionInterventoriaPanel(
            empresaId: 'A',
            service: svc,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SolicitudesReasignacionInterventoriaPanel(
            empresaId: 'B',
            service: svc,
          ),
        ),
      ),
    );
    svc.b.complete({'items': [], 'cursor': null});
    await tester.pumpAndSettle();
    svc.a.complete({
      'items': [
        {'titulo': 'Tarea de otra empresa'},
      ],
      'cursor': null,
    });
    await tester.pumpAndSettle();
    expect(find.text('Tarea de otra empresa'), findsNothing);
    expect(find.text('No hay solicitudes pendientes.'), findsOneWidget);
  });
}

class _PanelService extends InterventoriaReasignacionService {
  final a = Completer<Map<String, dynamic>>(),
      b = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> llamar(Map<String, dynamic> datos) =>
      datos['empresaId'] == 'A' ? a.future : b.future;
}

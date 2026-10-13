import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_planes_screen.dart';
import 'package:todo/interventoria/interventoria_planes_service.dart';
import 'package:todo/interventoria/interventoria_planes_widgets.dart';

PlanData _item(String id, String numeral, {String acta = '25133385'}) => {
  'id': id,
  'planId': 'p',
  'tareaId': 't$id',
  'numeroTarea': 7,
  'establecimiento': 'Tuluá',
  'idVisitaK2': acta,
  'fechaActa': '2026-10-01T10:00:00Z',
  'numeral': numeral,
  'responsableNombre': 'Ana',
  'descripcion': 'Corregir el rotulado $numeral.',
  'respuestaVersion': 0,
  'soportesVersion': 0,
  'evidencias': <dynamic>[],
};

final _plan = <String, dynamic>{
  'id': 'p',
  'numero': 'ABC 123',
  'csc': 'ABC 123',
  'fechaNotificacion': '2026-10-05',
  'limiteRespuesta': '2026-10-10',
  'limiteSoportes': '2026-10-25',
  'estadoGestion': 'en_gestion',
  'cantidad': 4,
  'avance': {
    'total': 4,
    'presentados': 1,
    'porRevisar': 2,
    'devueltos': 0,
    'sinIniciar': 1,
  },
  'establecimientos': ['Tuluá'],
};

void main() {
  test('el avance se cuenta igual que en el listado', () {
    final avance = planAvanceDe([
      {
        ..._item('1', '1'),
        'respuestaVersion': 1,
        'soportesVersion': 1,
        'respuestaPresentado': {},
        'soportesPresentado': {},
      },
      {
        ..._item('2', '2'),
        'respuestaVersion': 1,
        'respuestaRevision': {'estado': 'por_revisar'},
      },
      {
        ..._item('3', '3'),
        'soportesVersion': 1,
        'soportesRevision': {'estado': 'devuelto'},
      },
      _item('4', '4'),
    ]);
    expect(avance, {
      'total': 4,
      'presentados': 1,
      'porRevisar': 1,
      'devueltos': 1,
      'sinIniciar': 1,
    });
  });

  test('los hallazgos se ordenan por establecimiento, acta y numeral', () {
    final f = PlanFiltros();
    final rows = [
      {..._item('a', '2'), 'idVisitaK2': 'B-2'},
      {..._item('b', '1'), 'idVisitaK2': 'B-2'},
      {..._item('c', '9'), 'idVisitaK2': 'A-1'},
      {..._item('d', '3'), 'establecimiento': 'Armenia', 'idVisitaK2': 'Z-9'},
    ];
    expect(f.aplicar(rows).map((r) => r['id']), ['d', 'c', 'b', 'a']);
  });

  testWidgets('el listado muestra estado, avance y plazos de cada plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InterventoriaPlanesPanel(
            empresaId: 'A',
            request: (_) async => {
              'planes': [_plan],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ABC 123'), findsOneWidget);
    expect(find.text('En gestión'), findsOneWidget);
    expect(
      find.textContaining('1 de 4 presentados en K2 · 2 por revisar'),
      findsOneWidget,
    );
  });

  testWidgets('el hallazgo se trabaja dentro del plan, sin pestaña aparte', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final enviados = <PlanData>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanDetalle(
            planId: 'p',
            request: (input) async {
              if (input['accion'] == 'detalle') {
                return {
                  'plan': _plan,
                  'items': [_item('1', '3.5'), _item('2', '3.6')],
                  'historial': [],
                };
              }
              enviados.add(input);
              return {};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expediente y descuentos'), findsNothing);
    expect(find.textContaining('Acta 25133385'), findsOneWidget);
    expect(find.text('Guardar y enviar a revisión'), findsNothing);

    await tester.tap(find.text('Numeral 3.5'));
    await tester.pumpAndSettle();
    final compromiso = find.widgetWithText(TextField, 'Compromiso de mejora');
    await tester.ensureVisible(compromiso);
    await tester.enterText(compromiso, 'Reemplazar los rótulos y capacitar.');
    await tester.pump();
    final guardar = find.text('Guardar y enviar a revisión');
    await tester.ensureVisible(guardar);
    await tester.tap(guardar);
    await tester.pumpAndSettle();
    expect(enviados.single['accion'], 'responder');
    expect(enviados.single['itemId'], '1');
    expect(
      enviados.single['compromiso'],
      'Reemplazar los rótulos y capacitar.',
    );
    expect(tester.takeException(), isNull);
  });
}

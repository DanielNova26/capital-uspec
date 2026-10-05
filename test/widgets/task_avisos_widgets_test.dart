import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_flujo.dart';
import 'package:todo/widgets/task_modern_card.dart';
import 'package:todo/widgets/task_numero_aviso.dart';

// 4 oct 2026, documento "Tareas": número en los avisos y, en la tarjeta,
// a quién se reasigna y quién aprueba la reasignación en espera.

void main() {
  testWidgets('número de tarea en rojo en el aviso', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TaskNumeroAvisoChip(taskId: 't1', numero: 2088)),
      ),
    );
    expect(find.text('Tarea No. 2088'), findsOneWidget);
    final texto = tester.widget<Text>(find.text('Tarea No. 2088'));
    expect(texto.style?.color, kTaskNumeroAvisoColor);
  });

  test('la descripción no repite el número que ya se muestra aparte', () {
    expect(
      sinPrefijoNumeroTarea('Tarea No. 2088 · Informe · Prueba'),
      'Informe · Prueba',
    );
    expect(sinPrefijoNumeroTarea('Informe · Prueba'), 'Informe · Prueba');
  });

  testWidgets('tarjeta con reasignación en espera: destino y aprobador', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskModernCard(
            compact: true,
            onTap: () {},
            data: {
              'titulo': 'Visita Talento Humano · Pasto: Ítem 33',
              'estado': 'en_progreso',
              'asignado_uid': 'yesika',
              'asignado_nombre': 'Yesika Cardenas',
              'creador_id': 'zuly',
              'creador_nombre': 'Zuly Cervantes',
              'aprobador_uid': 'zuly',
              'aprobador_nombre': 'Zuly Cervantes',
              'numero': 2096,
              'solicitud_reasignacion_estado': 'pendiente',
              'solicitud_reasignacion_to_uid': 'lina',
              'solicitud_reasignacion_to_nombre': 'Lina Vargas',
            },
          ),
        ),
      ),
    );
    expect(find.text('Reasignada a: Lina Vargas'), findsOneWidget);
    expect(find.text('Aprueba: Zuly Cervantes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin reasignación en espera no se pinta la nota', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskModernCard(
            onTap: () {},
            data: const {
              'titulo': 'Informe',
              'estado': 'en_progreso',
              'asignado_uid': 'yesika',
              'asignado_nombre': 'Yesika Cardenas',
            },
          ),
        ),
      ),
    );
    expect(find.byType(TaskReasignacionEsperaNota), findsNothing);
    expect(taskReasignacionEnEspera(const {}), isNull);
  });
}

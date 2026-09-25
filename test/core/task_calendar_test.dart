import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_calendar.dart';

/// 25 sep 2026: "en el calendario solo los por recibir y por entregar".
void main() {
  const daniel = '1001';
  const aprobador = '2002';
  const responsable = '3003';

  test('la tarea asignada a mí es POR ENTREGAR', () {
    final t = {'asignado_uid': responsable, 'jefe_uid': aprobador};
    expect(
      papelTareaCalendario(t, responsable),
      PapelTareaCalendario.porEntregar,
    );
  });

  test('la que apruebo es POR RECIBIR', () {
    final t = {
      'asignado_uid': responsable,
      'aprobador_uid': aprobador,
      'jefe_uid': aprobador,
      'creador_id': daniel,
    };
    expect(papelTareaCalendario(t, aprobador), PapelTareaCalendario.porRecibir);
  });

  test('las tareas anteriores al contrato v2 se reciben por jefe_uid', () {
    final t = {'asignado_uid': responsable, 'jefe_uid': aprobador};
    expect(papelTareaCalendario(t, aprobador), PapelTareaCalendario.porRecibir);
  });

  test('haberla creado no la pone en el calendario', () {
    // Hallazgo de Interventoría: la creó quien completó el acta, la recibe
    // el aprobador de la matriz.
    final t = {
      'asignado_uid': responsable,
      'aprobador_uid': aprobador,
      'jefe_uid': aprobador,
      'creador_id': daniel,
      'origen': 'interventoria',
    };
    expect(papelTareaCalendario(t, daniel), isNull);
  });

  test('en una tarea manual sin jefe el creador la recibe', () {
    // create_task_screen deja al creador como aprobador cuando no hay jefe.
    final t = {
      'asignado_uid': responsable,
      'aprobador_uid': daniel,
      'jefe_uid': null,
      'creador_id': daniel,
    };
    expect(papelTareaCalendario(t, daniel), PapelTareaCalendario.porRecibir);
  });

  test('si me la asigné y la apruebo, la entrego', () {
    final t = {'asignado_uid': daniel, 'aprobador_uid': daniel};
    expect(papelTareaCalendario(t, daniel), PapelTareaCalendario.porEntregar);
  });

  test('sin usuario no hay papel', () {
    expect(papelTareaCalendario({'asignado_uid': ''}, ''), isNull);
  });
}

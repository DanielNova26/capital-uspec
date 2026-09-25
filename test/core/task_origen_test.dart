import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_origen.dart';

/// 25 sep 2026: "no deben quedar en Tareas que asigné, porque él no las
/// asigna puntualmente, las asigna la interventoría; él solo le dio al botón".
void main() {
  const daniel = '1001';

  test('las nuevas quedan a nombre de Interventoría', () {
    final t = {
      'creador_id': kCreadorInterventoria,
      'ejecutadoPorId': daniel,
      'sourceModule': 'interventoria',
      'asignacionAutomatica': true,
    };
    expect(esAsignacionAutomaticaDeModulo(t), isTrue);
    expect(laAsignoEstaPersona(t, daniel), isFalse);
  });

  test('las viejas a nombre de quien dio clic tampoco son suyas', () {
    final t = {
      'creador_id': daniel,
      'sourceModule': 'interventoria',
      'asignacionAutomatica': true,
    };
    expect(esAsignacionAutomaticaDeModulo(t), isTrue);
    expect(laAsignoEstaPersona(t, daniel), isFalse);
  });

  test('la que eligió a mano en el tablero sí la asignó él', () {
    final t = {
      'creador_id': daniel,
      'sourceModule': 'interventoria',
      'asignacionAutomatica': false,
    };
    expect(laAsignoEstaPersona(t, daniel), isTrue);
  });

  test('una tarea manual sigue siendo de quien la creó', () {
    final t = {'creador_id': daniel, 'sourceModule': 'tareas'};
    expect(esAsignacionAutomaticaDeModulo(t), isFalse);
    expect(laAsignoEstaPersona(t, daniel), isTrue);
    expect(laAsignoEstaPersona(t, 'otro'), isFalse);
  });

  test('reconoce el origen en tareas sin sourceModule', () {
    final t = {
      'creador_id': daniel,
      'origen': 'interventoria',
      'asignacionAutomatica': true,
    };
    expect(esAsignacionAutomaticaDeModulo(t), isTrue);
  });
}

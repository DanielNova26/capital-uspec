import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_revision_maestro.dart';
import 'package:todo/interventoria/interventoria_service.dart';

/// Reasignar por grupos (14 oct 2026): solo se mueven las tareas automáticas
/// sin iniciar; lo demás se conserva.
void main() {
  const nuevo = InterventoriaPersona(
    id: 'nuevo',
    nombre: 'Nora Nueva',
    cargo: 'Coordinador',
    cargoMatriz: 'Coordinador',
    delCentro: true,
  );
  const corporativo = InterventoriaPersona(
    id: 'corp',
    nombre: 'Carlos Corp',
    cargo: 'Coordinador',
    cargoMatriz: 'Coordinador',
    delCentro: false,
  );

  Map<String, dynamic> tarea({
    String asignado = 'viejo',
    String estado = 'pendiente',
    String creador = 'interventoria',
    bool reasignado = false,
    String aprobador = 'apr',
  }) => {
    'asignado_uid': asignado,
    'estado': estado,
    'creador_id': creador,
    'sourceModule': 'interventoria',
    'asignacionAutomatica': true,
    'reasignado': reasignado,
    'aprobador_uid': aprobador,
  };

  DecisionReasignacionGrupo decidir(
    Map<String, dynamic> t,
    InterventoriaPersona? r, {
    Set<String> activos = const {'viejo', 'nuevo', 'corp'},
  }) => decidirReasignacionPorGrupo(
    tarea: t,
    responsable: r,
    aprobador: null,
    activosIds: activos,
  );

  test('reasigna la tarea pendiente a quien cubre el establecimiento', () {
    expect(decidir(tarea(), nuevo), DecisionReasignacionGrupo.reasignar);
  });

  test('sin cambio si ya la tiene quien corresponde', () {
    expect(
      decidir(tarea(asignado: 'nuevo'), nuevo),
      DecisionReasignacionGrupo.sinCambio,
    );
  });

  test('no pisa lo que una persona decidió', () {
    expect(
      decidir(tarea(reasignado: true), nuevo),
      DecisionReasignacionGrupo.manual,
    );
    final manual = tarea(creador: '123')..['asignacionAutomatica'] = false;
    expect(decidir(manual, nuevo), DecisionReasignacionGrupo.manual);
  });

  test('conserva las tareas ya iniciadas', () {
    expect(
      decidir(tarea(estado: 'en_progreso'), nuevo),
      DecisionReasignacionGrupo.enCurso,
    );
  });

  test('sin responsable en el maestro no hace nada', () {
    expect(decidir(tarea(), null), DecisionReasignacionGrupo.sinResponsable);
  });

  test('no salta a un cargo corporativo si quien la tiene sigue activo', () {
    expect(
      decidir(tarea(), corporativo),
      DecisionReasignacionGrupo.sinCobertura,
    );
  });

  test('sí pasa a un corporativo si quien la tiene ya no está activo', () {
    expect(
      decidir(tarea(), corporativo, activos: const {'corp'}),
      DecisionReasignacionGrupo.reasignar,
    );
  });
}

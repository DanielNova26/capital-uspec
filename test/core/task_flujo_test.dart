import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_flujo.dart';
import 'package:todo/core/task_origen.dart';

Map<String, dynamic> _tarea([Map<String, dynamic> extra = const {}]) => {
  'titulo': 'Informe',
  'empresaId': 'e1',
  'estado': 'en_progreso',
  'asignado_uid': 'yimmy',
  'creador_id': 'oscar',
  'creador_nombre': 'Oscar Cano',
  'jefe_uid': 'zuly',
  'jefe_nombre': 'Zuly Cervantes',
  'aprobador_uid': 'zuly',
  'aprobador_nombre': 'Zuly Cervantes',
  ...extra,
};

void main() {
  group('aprobador efectivo', () {
    test('es el aprobador guardado', () {
      expect(taskAprobadorId(_tarea()), 'zuly');
      expect(taskAprobadorNombre(_tarea()), 'Zuly Cervantes');
    });

    test(
      'nunca el propio responsable: decide quien la asignó (tarea 2090)',
      () {
        // Reasignada a Zuly antes de octubre: el aprobador seguía siendo ella.
        final t = _tarea({'asignado_uid': 'zuly'});
        expect(taskAprobadorId(t), 'oscar');
        expect(taskAprobadorNombre(t), 'Oscar Cano');
      },
    );

    test('sin aprobador ni jefe (Visitas) aprueba quien asignó', () {
      final t = _tarea({'aprobador_uid': '', 'jefe_uid': null});
      expect(taskAprobadorId(t), 'oscar');
    });

    test('el creador automático de Interventoría no aprueba', () {
      final t = _tarea({
        'aprobador_uid': '',
        'jefe_uid': '',
        'creador_id': kCreadorInterventoria,
      });
      expect(taskAprobadorId(t), '');
    });
  });

  group('Tareas por aprobar', () {
    test('solo lo que espera una decisión de la persona', () {
      expect(taskEsperaDecisionDe(_tarea(), {'zuly'}), isFalse);
      final porAprobar = _tarea({
        'estado': 'por_aprobar',
        'solicitud_finalizacion_estado': 'pendiente',
      });
      expect(taskEsperaDecisionDe(porAprobar, {'zuly'}), isTrue);
      expect(taskEsperaDecisionDe(porAprobar, {'oscar'}), isFalse);
      final reasignacion = _tarea({
        'solicitud_reasignacion_estado': 'pendiente',
      });
      expect(taskEsperaDecisionDe(reasignacion, {'zuly'}), isTrue);
      expect(
        taskEsperaDecisionDe(_tarea({'estado': 'finalizado'}), {'zuly'}),
        isFalse,
      );
    });

    test('la reasignada que terminó su nuevo responsable le sale a quien '
        'la asignó', () {
      final t = _tarea({
        'asignado_uid': 'zuly',
        'estado': 'por_aprobar',
        'solicitud_finalizacion_estado': 'pendiente',
        'reasignada_desde_uid': 'yimmy',
      });
      expect(taskEsperaDecisionDe(t, {'oscar'}), isTrue);
      expect(taskEsperaDecisionDe(t, {'zuly'}), isFalse);
    });
  });

  test('avisos de seguimiento: emisor y aprobador, sin quien actúa', () {
    expect(taskDestinatariosSeguimiento(_tarea(), excluir: 'yimmy'), {
      'oscar',
      'zuly',
    });
    expect(taskDestinatariosSeguimiento(_tarea(), excluir: 'zuly'), {'oscar'});
    final interventoria = _tarea({'creador_id': kCreadorInterventoria});
    expect(taskDestinatariosSeguimiento(interventoria, excluir: 'yimmy'), {
      'zuly',
    });
  });

  test('número de tarea en los avisos', () {
    expect(taskNumeroAviso(_tarea()), '');
    expect(taskNumeroAviso(_tarea({'numero': 2088})), 'Tarea No. 2088');
    expect(
      conNumeroDeTarea(_tarea({'numero': 2088}), 'Informe · Prueba'),
      'Tarea No. 2088 · Informe · Prueba',
    );
    expect(conNumeroDeTarea(_tarea(), 'Informe'), 'Informe');
  });

  test('reasignación en espera: destino y quién aprueba', () {
    expect(taskReasignacionEnEspera(_tarea()), isNull);
    final espera = taskReasignacionEnEspera(
      _tarea({
        'solicitud_reasignacion_estado': 'pendiente',
        'solicitud_reasignacion_to_uid': 'lina',
        'solicitud_reasignacion_to_nombre': 'Lina Vargas',
      }),
    )!;
    expect(espera.destinoNombre, 'Lina Vargas');
    expect(espera.aprobadorId, 'zuly');
    expect(espera.aprobadorNombre, 'Zuly Cervantes');
  });

  group('aprobador tras aprobar una reasignación', () {
    test('pasa al jefe inmediato del nuevo responsable', () {
      final campos = taskAprobadorTrasReasignar(
        tarea: _tarea(),
        nuevoResponsableId: 'zuly',
        jefeId: 'oscar',
        jefeNombre: 'Oscar Cano',
      );
      expect(campos['aprobador_uid'], 'oscar');
      expect(campos['aprobador_nombre'], 'Oscar Cano');
      expect(campos['jefe_uid'], 'oscar');
    });

    test('sin jefe (o si es él mismo) decide quien la asignó', () {
      final sinJefe = taskAprobadorTrasReasignar(
        tarea: _tarea(),
        nuevoResponsableId: 'lina',
      );
      expect(sinJefe['aprobador_uid'], 'oscar');
      expect(sinJefe['jefe_uid'], '');
      final propio = taskAprobadorTrasReasignar(
        tarea: _tarea(),
        nuevoResponsableId: 'lina',
        jefeId: 'lina',
      );
      expect(propio['aprobador_uid'], 'oscar');
    });

    test('reasignada a quien la asignó: conserva el aprobador anterior', () {
      final campos = taskAprobadorTrasReasignar(
        tarea: _tarea(),
        nuevoResponsableId: 'oscar',
      );
      expect(campos['aprobador_uid'], 'zuly');
    });
  });

  group('destino de un aviso', () {
    TaskDestinoAviso destino(
      Map<String, dynamic> t,
      String yo, [
      String tipo = '',
    ]) => decidirDestinoAvisoTarea(tarea: t, misIds: {yo}, tipo: tipo).destino;

    test('la tarea nueva lleva al responsable a Mis tareas', () {
      expect(
        destino(_tarea(), 'yimmy', 'task_assigned'),
        TaskDestinoAviso.misTareas,
      );
    });

    test(
      'la solicitud de reasignación lleva a quien aprueba a Por aprobar',
      () {
        final t = _tarea({'solicitud_reasignacion_estado': 'pendiente'});
        expect(
          destino(t, 'zuly', 'task_solicitud_reasignacion'),
          TaskDestinoAviso.porAprobar,
        );
        // Quien la asignó también recibe el aviso: la ve en Tareas que asigné.
        expect(
          destino(t, 'oscar', 'task_solicitud_reasignacion'),
          TaskDestinoAviso.tareasQueAsigne,
        );
      },
    );

    test('quien la entregó la encuentra en Antes asignadas', () {
      final t = _tarea({
        'asignado_uid': 'lina',
        'reasignada_desde_uid': 'yimmy',
        'participantes_uid': ['yimmy', 'lina'],
      });
      final d = decidirDestinoAvisoTarea(
        tarea: t,
        misIds: {'yimmy'},
        tipo: 'task_reasignacion_aprobada',
      );
      expect(d.destino, TaskDestinoAviso.historial);
      expect(d.pestanaHistorial, 2);
    });

    test('cerrada: historial con el proceso del aviso', () {
      final t = _tarea({'estado': 'finalizado', 'approved': true});
      final d = decidirDestinoAvisoTarea(
        tarea: t,
        misIds: {'yimmy'},
        tipo: 'task_avance',
      );
      expect(d.destino, TaskDestinoAviso.historial);
      expect(d.pestanaHistorial, 0);
      expect(d.proceso, 'Avances');
      expect(
        decidirDestinoAvisoTarea(tarea: t, misIds: {'oscar'}).pestanaHistorial,
        1,
      );
    });

    test('el aviso informativo al jefe abre la tarea en Por aprobar', () {
      expect(
        destino(_tarea(), 'zuly', 'task_assigned_report'),
        TaskDestinoAviso.porAprobar,
      );
    });
  });

  test('el contrato acepta Timestamp en las fechas de la tarea', () {
    final t = _tarea({'fecha_limite': Timestamp.fromDate(DateTime(2020))});
    // Vencida, pero sin solicitud: no espera decisión de nadie.
    expect(taskEsperaDecisionDe(t, {'zuly'}), isFalse);
  });
}

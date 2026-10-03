import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_estado_visible.dart';
import 'package:todo/core/task_origen.dart';

void main() {
  final ayer = Timestamp.fromDate(
    DateTime.now().subtract(const Duration(days: 1)),
  );
  final manana = Timestamp.fromDate(
    DateTime.now().add(const Duration(days: 1)),
  );

  group('estado visible (3 oct 2026: uniforme sin importar el módulo)', () {
    test('creada desde cualquier módulo se ve PENDIENTE', () {
      for (final tarea in [
        {'estado': 'en_progreso', 'sourceModule': 'compras'},
        {'estado': 'en_progreso', 'origen': 'visita'},
        {'estado': 'pendiente', 'sourceModule': 'interventoria'},
        {'estado': 'en_progreso', 'sourceModule': 'gestion_documental'},
        {'estado': 'en_progreso', 'sourceModule': 'tareas'},
      ]) {
        expect(
          taskEstadoVisible({...tarea, 'fecha_limite': manana}),
          TaskEstadoVisible.pendiente,
          reason: '$tarea',
        );
      }
    });

    test('reasignada, por aprobar, retrasada y terminada', () {
      expect(
        taskEstadoVisible({
          'estado': 'en_progreso',
          'reasignada_desde_uid': 'p1',
          'fecha_limite': manana,
        }),
        TaskEstadoVisible.reasignada,
      );
      expect(
        taskEstadoVisible({
          'estado': 'en_progreso',
          'solicitud_reasignacion_estado': 'aprobada',
          'fecha_limite': manana,
        }),
        TaskEstadoVisible.reasignada,
      );
      expect(
        taskEstadoVisible({
          'estado': 'en_progreso',
          'solicitud_finalizacion_estado': 'pendiente',
        }),
        TaskEstadoVisible.porAprobar,
      );
      expect(
        taskEstadoVisible({'estado': 'en_progreso', 'fecha_limite': ayer}),
        TaskEstadoVisible.retrasada,
      );
      expect(
        taskEstadoVisible({'estado': 'finalizado', 'fecha_limite': ayer}),
        TaskEstadoVisible.terminada,
      );
    });

    test('la reasignada vencida se ve RETRASADA', () {
      expect(
        taskEstadoVisible({
          'estado': 'en_progreso',
          'reasignada_desde_uid': 'p1',
          'fecha_limite': ayer,
        }),
        TaskEstadoVisible.retrasada,
      );
    });

    test('la devuelta vuelve a PENDIENTE y se marca como devuelta', () {
      final devuelta = {'estado': 'devuelta', 'fecha_limite': manana};
      expect(taskEstadoVisible(devuelta), TaskEstadoVisible.pendiente);
      expect(taskFueDevuelta(devuelta), isTrue);
    });

    test('colores pedidos: gris, violeta, amarillo, rojo y verde', () {
      expect(TaskEstadoVisible.pendiente.etiqueta, 'PENDIENTE');
      expect(TaskEstadoVisible.porAprobar.etiqueta, 'POR_APROBAR');
      // Un tono distinto por estado.
      final fondos = {for (final e in TaskEstadoVisible.values) e.fondo};
      expect(fondos.length, TaskEstadoVisible.values.length);
      expect(
        taskEstadoVisiblePorClave('por_aprobar'),
        TaskEstadoVisible.porAprobar,
      );
    });
  });

  group('módulo de origen', () {
    test('un id por módulo', () {
      expect(taskModuloOrigen({'sourceModule': 'tareas'}), 'tareas');
      expect(taskModuloOrigen({'origen': 'visita'}), 'visitas');
      expect(taskModuloOrigen({'module': 'compras_bodega'}), 'compras');
      expect(
        taskModuloOrigen({
          'source': {'moduleId': 'gestion_documental'},
        }),
        'gestion_documental',
      );
      expect(
        taskModuloOrigen({'sourceModule': 'interventoria'}),
        'interventoria',
      );
      expect(taskModuloOrigen(const {}), 'tareas');
    });

    test('nombres legibles', () {
      expect(taskModuloOrigenNombre('tareas'), 'Manual');
      expect(
        taskModuloOrigenNombre('gestion_documental'),
        'Gestión de Correspondencia',
      );
      expect(taskModuloOrigenNombre('otro_modulo'), 'Otro modulo');
    });

    test('expediente de correspondencia', () {
      expect(
        taskExpedienteCorrespondencia({
          'sourceType': 'correspondencia_correo',
          'correspondenciaId': 'exp1',
        }),
        'exp1',
      );
      expect(
        taskExpedienteCorrespondencia({
          'source': {'moduleId': 'gestion_documental', 'entityId': 'exp2'},
        }),
        'exp2',
      );
      expect(
        taskExpedienteCorrespondencia({
          'sourceModule': 'interventoria',
          'source': {'entityId': 'hallazgo'},
        }),
        '',
      );
    });
  });

  group('número, fechas y asignador', () {
    test('número interno', () {
      expect(taskNumeroTexto({'numero': 154}), 'N.º 154');
      expect(taskNumeroTexto({'numero': '7'}), 'N.º 7');
      expect(taskNumeroTexto(const {}), '');
      expect(taskNumero({'numero': 0}), isNull);
    });

    test('días abierta desde la asignación', () {
      final hace5 = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(taskDiasAbierta({'estado': 'en_progreso', 'createdAt': hace5}), 5);
      // Reasignada: cuenta desde que la recibió la persona actual.
      final hace2 = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(
        taskDiasAbierta({
          'estado': 'en_progreso',
          'createdAt': hace5,
          'reasignada_en': hace2,
        }),
        2,
      );
    });

    test('la matriz de Interventoría se muestra como el módulo', () {
      final auto = taskAsignador({
        'creador_id': kCreadorInterventoria,
        'creador_nombre': 'x',
      });
      expect(auto.id, isEmpty);
      expect(auto.nombre, kNombreCreadorInterventoria);
      final persona = taskAsignador({
        'creador_id': '123',
        'creador_nombre': 'Ana',
      });
      expect(persona.id, '123');
      expect(persona.nombre, 'Ana');
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_module_closeout_service.dart';

void main() {
  group('cierre administrativo por módulo', () {
    test('reconoce tareas de Interventoría y Facturación', () {
      expect(
        adminCloseoutModuleFromTask({
          'source': {'moduleId': 'interventoria'},
        }),
        'interventoria',
      );
      expect(
        adminCloseoutModuleFromTask({'origen': 'facturacion_observacion'}),
        'facturacion',
      );
      expect(adminCloseoutModuleFromTask({'sourceModule': 'compras'}), isEmpty);
    });

    test('tareas a mano: sin marca de ningún módulo', () {
      expect(
        adminCloseoutModuleFromTask({
          'origen': 'manual',
          'sourceModule': 'tareas',
        }),
        'tareas',
      );
      expect(adminCloseoutModuleFromTask({}), 'tareas');
      expect(adminCloseoutModuleFromTask({'origen': 'excel'}), 'tareas');
      // Las de un módulo no son de Tareas.
      expect(
        adminCloseoutModuleFromTask({'origen': 'visita', 'visitaId': 'v1'}),
        isEmpty,
      );
      expect(
        adminCloseoutModuleFromTask({
          'source': {'moduleId': 'gestion_documental'},
        }),
        isEmpty,
      );
      expect(
        adminCloseoutModuleFromTask({'creador_id': 'interventoria_automatica'}),
        'interventoria',
      );
    });

    test('solo considera abiertas las tareas no finalizadas', () {
      expect(adminCloseoutTaskIsOpen({'estado': 'en_progreso'}), isTrue);
      expect(adminCloseoutTaskIsOpen({'estado': 'por_aprobar'}), isTrue);
      expect(adminCloseoutTaskIsOpen({'estado': 'finalizado'}), isFalse);
      expect(adminCloseoutTaskIsOpen({'status': 'completada'}), isFalse);
    });

    test('aplica el corte antes o desde el inicio del día', () {
      final cutoff = DateTime(2026, 9, 1);
      final august = DateTime(2026, 8, 31, 23, 59, 59);
      final september = DateTime(2026, 9, 1, 0, 0);

      expect(
        adminCloseoutDateMatches(august, cutoff, AdminCloseoutRange.before),
        isTrue,
      );
      expect(
        adminCloseoutDateMatches(september, cutoff, AdminCloseoutRange.before),
        isFalse,
      );
      expect(
        adminCloseoutDateMatches(september, cutoff, AdminCloseoutRange.from),
        isTrue,
      );
    });

    test('lee fechas históricas y actuales de las tareas', () {
      final date = DateTime(2026, 8, 20, 12);
      expect(
        adminCloseoutTaskCreatedAt({
          'fecha_creacion': Timestamp.fromDate(date),
        }),
        date,
      );
      expect(
        adminCloseoutTaskCreatedAt({'createdAt': date.toIso8601String()}),
        date,
      );
    });

    test('identifica notificaciones directas y ligadas a una tarea', () {
      expect(
        adminCloseoutModuleFromNotification({'type': 'fac_observacion'}),
        'facturacion',
      );
      expect(
        adminCloseoutModuleFromNotification({'type': 'nota_registrador'}),
        'interventoria',
      );
      expect(
        adminCloseoutModuleFromNotification(
          {'type': 'task_assigned', 'taskId': 'task-1'},
          matchingTaskIds: {'task-1'},
        ),
        '__matched_task__',
      );
    });

    test('no vuelve a procesar notificaciones ya leídas', () {
      expect(adminCloseoutNotificationIsUnread({'read': false}), isTrue);
      expect(adminCloseoutNotificationIsUnread({'read': true}), isFalse);
      expect(adminCloseoutNotificationIsUnread({'leido': true}), isFalse);
    });
  });
}

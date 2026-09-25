import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Avisos agrupados de la asignación automática de Interventoría.
///
/// 25 sep 2026. Cada hallazgo asignado creaba una tarea y cada tarea mandaba
/// dos notificaciones con sonido: al responsable y al aprobador. Un acta con
/// veinte hallazgos eran cuarenta timbres, y la reparación del rezago (cientos
/// de hallazgos de todas las sedes) le llegó "a todo el mundo de una".
///
/// Ahora, cuando se asigna en lote (completar un acta, generar las
/// asignaciones pendientes desde el maestro), las tareas nacen sin aviso
/// propio (`notificarCreacion: false`, lo respeta `onTaskCreated`) y al final
/// sale UN aviso por persona:
/// - al responsable, con sonido: tiene trabajo que hacer;
/// - al aprobador, en silencio: no tiene que hacer nada hasta que el
///   responsable termine; entonces le llega "por aprobar", y ese sí suena.

/// Tarea creada para un hallazgo, con lo necesario para agrupar su aviso.
class InterventoriaTareaCreada {
  final String taskId;
  final String hallazgoId;
  final String empresaId;
  final String centroCostoNombre;
  final String responsableId;
  final String responsableNombre;
  final String aprobadorId;
  final String aprobadorNombre;

  const InterventoriaTareaCreada({
    required this.taskId,
    required this.hallazgoId,
    required this.empresaId,
    required this.centroCostoNombre,
    required this.responsableId,
    required this.responsableNombre,
    required this.aprobadorId,
    required this.aprobadorNombre,
  });
}

/// Un aviso para una persona, que resume todas sus tareas del lote.
class InterventoriaAvisoAsignacion {
  final String destinatarioId;

  /// true: el aviso es para quien aprueba (va en silencio). false: para quien
  /// subsana (suena).
  final bool paraAprobar;
  final String titulo;
  final String descripcion;

  /// Primera tarea del grupo: la notificación necesita una tarea para abrir
  /// la bandeja correcta (Mis tareas o Por aprobar).
  final String taskId;
  final List<String> taskIds;
  final String empresaId;

  const InterventoriaAvisoAsignacion({
    required this.destinatarioId,
    required this.paraAprobar,
    required this.titulo,
    required this.descripcion,
    required this.taskId,
    required this.taskIds,
    required this.empresaId,
  });

  bool get silenciosa => paraAprobar;

  int get cantidad => taskIds.length;

  /// Mismo lote, misma persona → mismo aviso. Si el lote se reintenta
  /// después de un error no llega dos veces; si luego se asignan hallazgos
  /// nuevos, las tareas son otras y el aviso también.
  String get claveIdempotencia {
    final ids = [...taskIds]..sort();
    final huella = sha1.convert(utf8.encode(ids.join('|'))).toString();
    return 'interventoria_asignacion:${paraAprobar ? 'aprueba' : 'subsana'}:'
        '$huella';
  }
}

/// "Sede A (3), Sede B (1) y 2 más".
String resumenSedesAviso(Iterable<String> sedes, {int maximo = 4}) {
  final conteo = <String, int>{};
  for (final sede in sedes) {
    final nombre = sede.trim().isEmpty ? 'Sin sede' : sede.trim();
    conteo[nombre] = (conteo[nombre] ?? 0) + 1;
  }
  final orden = conteo.entries.toList()
    ..sort((a, b) {
      final porCantidad = b.value.compareTo(a.value);
      if (porCantidad != 0) return porCantidad;
      return a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });
  final visibles = orden
      .take(maximo)
      .map((e) => '${e.key} (${e.value})')
      .toList();
  final resto = orden.length - visibles.length;
  if (resto <= 0) return visibles.join(', ');
  return '${visibles.join(', ')} y $resto más';
}

/// Arma un aviso por responsable y uno por aprobador.
///
/// Quien es a la vez responsable y aprobador de una tarea solo recibe el
/// aviso de responsable por ella: es el que le pide hacer algo.
List<InterventoriaAvisoAsignacion> avisosDeAsignacion(
  Iterable<InterventoriaTareaCreada> creadas,
) {
  final porResponsable = <String, List<InterventoriaTareaCreada>>{};
  final porAprobador = <String, List<InterventoriaTareaCreada>>{};
  final vistas = <String>{};
  for (final tarea in creadas) {
    if (tarea.taskId.trim().isEmpty || !vistas.add(tarea.taskId)) continue;
    final responsable = tarea.responsableId.trim();
    final aprobador = tarea.aprobadorId.trim();
    if (responsable.isNotEmpty) {
      porResponsable.putIfAbsent(responsable, () => []).add(tarea);
    }
    if (aprobador.isNotEmpty && aprobador != responsable) {
      porAprobador.putIfAbsent(aprobador, () => []).add(tarea);
    }
  }

  final avisos = <InterventoriaAvisoAsignacion>[];
  porResponsable.forEach((id, tareas) {
    final n = tareas.length;
    final sedes = resumenSedesAviso(tareas.map((t) => t.centroCostoNombre));
    avisos.add(
      InterventoriaAvisoAsignacion(
        destinatarioId: id,
        paraAprobar: false,
        titulo: n == 1
            ? 'Nuevo hallazgo de Interventoría asignado'
            : '$n hallazgos de Interventoría asignados',
        descripcion: n == 1
            ? 'Te corresponde subsanar un hallazgo de $sedes. '
                  'Revísalo en Mis tareas.'
            : 'Te corresponde subsanarlos: $sedes. Revísalos en Mis tareas.',
        taskId: tareas.first.taskId,
        taskIds: [for (final t in tareas) t.taskId],
        empresaId: tareas.first.empresaId,
      ),
    );
  });
  porAprobador.forEach((id, tareas) {
    final n = tareas.length;
    final sedes = resumenSedesAviso(tareas.map((t) => t.centroCostoNombre));
    avisos.add(
      InterventoriaAvisoAsignacion(
        destinatarioId: id,
        paraAprobar: true,
        titulo: n == 1
            ? 'Aprobarás un hallazgo de Interventoría'
            : 'Aprobarás $n hallazgos de Interventoría',
        descripcion:
            '$sedes. No tienes que hacer nada todavía: te avisaremos cuando '
            '${n == 1 ? 'el responsable lo termine' : 'cada responsable termine'}'
            ' y esté listo para aprobar.',
        taskId: tareas.first.taskId,
        taskIds: [for (final t in tareas) t.taskId],
        empresaId: tareas.first.empresaId,
      ),
    );
  });
  return avisos;
}

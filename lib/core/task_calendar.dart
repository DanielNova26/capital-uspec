/// Qué tareas salen en el calendario del inicio y con qué etiqueta.
///
/// 25 sep 2026. El calendario pintaba todas las tareas que uno había creado
/// como "POR RECIBIR". Con la asignación automática de Interventoría el creador
/// es quien abrió el módulo o completó el acta (Daniel, Kary), no quien recibe
/// el trabajo: les aparecían cientos de hallazgos "por recibir" que en realidad
/// recibe el aprobador de la matriz. Instrucción: "en el calendario solo los
/// por recibir y por entregar".
///
/// - POR ENTREGAR: la tarea está asignada a mí.
/// - POR RECIBIR: yo la apruebo (`aprobador_uid`, o `jefe_uid` en las tareas
///   anteriores al contrato v2) y no está asignada a mí.
/// - Haberla creado, por sí solo, ya no la pone en el calendario. En una tarea
///   manual sin jefe el creador sigue viéndola, porque el contrato lo deja como
///   aprobador (`TaskContract.normalizeForCreate`).
library;

enum PapelTareaCalendario { porEntregar, porRecibir }

String _texto(Object? valor) => (valor ?? '').toString().trim();

/// Papel de [userId] en la tarea, o `null` si no le toca ni entregarla ni
/// recibirla (y por lo tanto no va en su calendario).
PapelTareaCalendario? papelTareaCalendario(
  Map<String, dynamic> tarea,
  String userId,
) {
  final yo = userId.trim();
  if (yo.isEmpty) return null;
  final asignado = [
    tarea['asignado_uid'],
    tarea['assignedTo'],
  ].map(_texto).firstWhere((v) => v.isNotEmpty, orElse: () => '');
  if (asignado == yo) return PapelTareaCalendario.porEntregar;
  final recibe = {
    _texto(tarea['aprobador_uid']),
    _texto(tarea['approverId']),
    _texto(tarea['jefe_uid']),
    _texto(tarea['bossId']),
  }..remove('');
  if (recibe.contains(yo)) return PapelTareaCalendario.porRecibir;
  return null;
}

/// Quién asignó de verdad una tarea (25 sep 2026).
///
/// Las tareas que Interventoría crea con su matriz no las asigna la persona
/// que dio clic ("Generar asignaciones", completar el acta, "Asignar por el
/// maestro"): las asigna el módulo. Instrucción: "no deben quedar en Tareas
/// que asigné, porque él no las asigna puntualmente, las asigna la
/// interventoría; él solo le dio al botón".
///
/// Desde ahora nacen con [kCreadorInterventoria] como creador, y quien dio
/// clic queda en `ejecutadoPorId` para la trazabilidad. Las creadas antes
/// siguen a nombre de la persona, pero llevan `asignacionAutomatica: true`
/// y [esAsignacionAutomaticaDeModulo] las reconoce igual.
library;

/// Creador de las tareas que asigna la matriz de Interventoría.
const String kCreadorInterventoria = 'interventoria_automatica';

/// Nombre con el que se muestra ese creador ("Asigna: Interventoría").
const String kNombreCreadorInterventoria = 'Interventoría';

String _texto(Object? valor) => (valor ?? '').toString().trim();

/// La tarea la asignó un módulo con su regla, no una persona.
///
/// Una asignación hecha a mano en Interventoría (persona elegida en el
/// tablero, área elegida a mano) guarda `asignacionAutomatica: false` y sí
/// es de quien la hizo.
bool esAsignacionAutomaticaDeModulo(Map<String, dynamic> tarea) {
  final creador = _texto(tarea['creador_id'] ?? tarea['creatorId']);
  if (creador == kCreadorInterventoria) return true;
  final modulo = _texto(tarea['sourceModule'] ?? tarea['origen']).toLowerCase();
  return modulo == 'interventoria' && tarea['asignacionAutomatica'] == true;
}

/// Para "Tareas que asigné" y su historial: lo que la persona asignó.
bool laAsignoEstaPersona(Map<String, dynamic> tarea, String userId) {
  final creador = _texto(tarea['creador_id'] ?? tarea['creatorId']);
  return creador.isNotEmpty &&
      creador == userId.trim() &&
      !esAsignacionAutomaticaDeModulo(tarea);
}

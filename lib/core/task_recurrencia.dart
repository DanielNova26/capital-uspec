// lib/core/task_recurrencia.dart
//
// Tareas repetitivas (documento "Tareas - septiembre 05 de 2026": "permitir
// crear tarea repetitiva: diaria, semanal, mensual, cada lunes, cada
// jueves…"). Es lógica pura, sin Firebase, compartida por Web y móvil; el
// servidor tiene el mismo cálculo en `functions/src/tareas_recurrentes.ts`.
//
// La tarea que se crea hoy es una tarea normal. Además se guarda una
// plantilla en `TBL_TAREAS_RECURRENTES`; cada día el servidor crea la tarea
// de las plantillas que tocan, con el mismo responsable y los mismos datos.

/// Colección con las plantillas de tareas repetitivas.
const String kCollTareasRecurrentes = 'TBL_TAREAS_RECURRENTES';

enum TaskFrecuencia { ninguna, diaria, semanal, mensual }

const List<String> kNombresDiaSemana = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

class TaskRecurrencia {
  final TaskFrecuencia frecuencia;

  /// Días de la semana (1 = lunes … 7 = domingo) de la repetición semanal.
  final Set<int> diasSemana;

  /// Día del mes (1–31) de la repetición mensual. En los meses más cortos
  /// se usa el último día del mes.
  final int diaMes;

  const TaskRecurrencia({
    this.frecuencia = TaskFrecuencia.ninguna,
    this.diasSemana = const {},
    this.diaMes = 1,
  });

  static const TaskRecurrencia ninguna = TaskRecurrencia();

  bool get repite => frecuencia != TaskFrecuencia.ninguna;

  /// Falta algún dato para poder repetirla (semanal sin día elegido).
  bool get incompleta =>
      frecuencia == TaskFrecuencia.semanal && diasSemana.isEmpty;

  /// ¿La tarea de la plantilla toca ese día? Solo mira la fecha.
  bool tocaEn(DateTime dia) {
    final d = DateTime(dia.year, dia.month, dia.day);
    switch (frecuencia) {
      case TaskFrecuencia.ninguna:
        return false;
      case TaskFrecuencia.diaria:
        return true;
      case TaskFrecuencia.semanal:
        return diasSemana.contains(d.weekday);
      case TaskFrecuencia.mensual:
        final ultimo = DateTime(d.year, d.month + 1, 0).day;
        final objetivo = diaMes > ultimo ? ultimo : diaMes;
        return d.day == objetivo;
    }
  }

  /// Primer día posterior a [desde] en que toca (nunca el mismo día: la
  /// tarea de hoy ya se creó al guardar). Nulo si no se repite.
  DateTime? siguienteDespuesDe(DateTime desde) {
    if (!repite || incompleta) return null;
    var d = DateTime(desde.year, desde.month, desde.day);
    for (var i = 0; i < 400; i++) {
      d = DateTime(d.year, d.month, d.day + 1);
      if (tocaEn(d)) return d;
    }
    return null;
  }

  /// "Todos los días", "Cada lunes y jueves", "El día 15 de cada mes".
  String get descripcion {
    switch (frecuencia) {
      case TaskFrecuencia.ninguna:
        return 'No se repite';
      case TaskFrecuencia.diaria:
        return 'Todos los días';
      case TaskFrecuencia.semanal:
        final dias = (diasSemana.toList()..sort())
            .where((d) => d >= 1 && d <= 7)
            .map((d) => kNombresDiaSemana[d - 1].toLowerCase())
            .toList();
        if (dias.isEmpty) return 'Cada semana';
        if (dias.length == 1) return 'Cada ${dias.first}';
        return 'Cada ${dias.sublist(0, dias.length - 1).join(', ')} y '
            '${dias.last}';
      case TaskFrecuencia.mensual:
        return 'El día $diaMes de cada mes';
    }
  }

  Map<String, dynamic> toMap() => {
    'frecuencia': frecuencia.name,
    'diasSemana': (diasSemana.toList()..sort()),
    'diaMes': diaMes,
  };

  static TaskRecurrencia fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return ninguna;
    final nombre = (raw['frecuencia'] ?? '').toString().trim().toLowerCase();
    final frecuencia = TaskFrecuencia.values.firstWhere(
      (f) => f.name == nombre,
      orElse: () => TaskFrecuencia.ninguna,
    );
    final dias = raw['diasSemana'] is Iterable
        ? (raw['diasSemana'] as Iterable)
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((d) => d >= 1 && d <= 7)
              .toSet()
        : <int>{};
    final dia = int.tryParse((raw['diaMes'] ?? '').toString()) ?? 1;
    return TaskRecurrencia(
      frecuencia: frecuencia,
      diasSemana: dias,
      diaMes: dia < 1 ? 1 : (dia > 31 ? 31 : dia),
    );
  }
}

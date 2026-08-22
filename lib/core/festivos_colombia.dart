/// Días festivos de Colombia y conteo de días hábiles.
///
/// En las reuniones se definió que los plazos del sistema se cuentan en días
/// hábiles "excluyendo fines de semana y festivos". Sin esta tabla, una fecha
/// límite calculada en Semana Santa o en un puente se vence antes de tiempo.
///
/// Los festivos no se guardan en Firestore a propósito: son deterministas
/// (calendario gregoriano + Ley Emiliani), así que calcularlos evita depender
/// de que alguien cargue la tabla cada año.
library;

/// Domingo de Pascua del año dado (algoritmo gregoriano anónimo).
DateTime domingoDePascua(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final mes = (h + l - 7 * m + 114) ~/ 31;
  final dia = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, mes, dia);
}

/// Traslada al lunes siguiente, como manda la Ley Emiliani.
DateTime _aLunes(DateTime fecha) {
  if (fecha.weekday == DateTime.monday) return fecha;
  return fecha.add(Duration(days: (8 - fecha.weekday) % 7));
}

final Map<int, Set<int>> _cache = {};

/// Festivos colombianos del año, como días del año normalizados a medianoche.
Set<DateTime> festivosColombia(int year) {
  final pascua = domingoDePascua(year);
  DateTime desdePascua(int dias) => pascua.add(Duration(days: dias));

  return {
    // Fechas fijas
    DateTime(year, 1, 1), // Año Nuevo
    DateTime(year, 5, 1), // Día del Trabajo
    DateTime(year, 7, 20), // Independencia
    DateTime(year, 8, 7), // Batalla de Boyacá
    DateTime(year, 12, 8), // Inmaculada Concepción
    DateTime(year, 12, 25), // Navidad
    // Trasladables al lunes (Ley Emiliani)
    _aLunes(DateTime(year, 1, 6)), // Reyes Magos
    _aLunes(DateTime(year, 3, 19)), // San José
    _aLunes(DateTime(year, 6, 29)), // San Pedro y San Pablo
    _aLunes(DateTime(year, 8, 15)), // Asunción de la Virgen
    _aLunes(DateTime(year, 10, 12)), // Día de la Raza
    _aLunes(DateTime(year, 11, 1)), // Todos los Santos
    _aLunes(DateTime(year, 11, 11)), // Independencia de Cartagena
    // Basados en Semana Santa
    desdePascua(-3), // Jueves Santo
    desdePascua(-2), // Viernes Santo
    desdePascua(43), // Ascensión (jueves +39, trasladado a lunes)
    desdePascua(64), // Corpus Christi (jueves +60, trasladado a lunes)
    desdePascua(71), // Sagrado Corazón (viernes +68, trasladado a lunes)
  };
}

Set<int> _festivosComoDias(int year) => _cache.putIfAbsent(
  year,
  () => festivosColombia(
    year,
  ).map((f) => DateTime(f.year, f.month, f.day).millisecondsSinceEpoch).toSet(),
);

/// true si la fecha es festivo en Colombia.
bool esFestivo(DateTime fecha) => _festivosComoDias(
  fecha.year,
).contains(DateTime(fecha.year, fecha.month, fecha.day).millisecondsSinceEpoch);

/// true si NO es día hábil: sábado, domingo o festivo.
bool esNoHabil(DateTime fecha) =>
    fecha.weekday == DateTime.saturday ||
    fecha.weekday == DateTime.sunday ||
    esFestivo(fecha);

/// Suma [dias] días hábiles a [desde], saltando fines de semana y festivos.
///
/// El resultado vence al cierre del día (23:59), que es como se leen los
/// plazos en la operación: "tienes hasta el viernes".
DateTime sumarDiasHabilesColombia(DateTime desde, int dias) {
  var fecha = DateTime(desde.year, desde.month, desde.day);
  var restantes = dias;
  while (restantes > 0) {
    fecha = fecha.add(const Duration(days: 1));
    if (!esNoHabil(fecha)) restantes--;
  }
  return DateTime(fecha.year, fecha.month, fecha.day, 23, 59);
}

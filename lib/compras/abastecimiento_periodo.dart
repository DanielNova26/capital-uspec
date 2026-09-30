// Período de consumo de Abastecimiento (30 sep 2026).
//
// Antes era fijo de viernes a jueves. Ahora cada empresa lo configura en
// Admin › Maestros por módulo › Compras, en TBL_COMPRAS_CONFIG/{empresaId}
// (campo `abastecimientoPeriodo`), y lo copia a otras empresas la función de
// maestros como el resto de esa configuración. Sin configuración rige el
// ciclo histórico de 7 días que inicia el viernes.
//
// Espejo en functions/src/compras_abastecimiento_reports.ts
// (`periodoConsumoDe`): la app y el reporte de las 5:00 p. m. deben calcular
// el mismo período o el PDF saldría con otras entregas.

const String kComprasConfigCollection = 'TBL_COMPRAS_CONFIG';

/// Campo de TBL_COMPRAS_CONFIG/{empresaId} con la configuración.
const String kCampoPeriodoConsumo = 'abastecimientoPeriodo';

/// Duración máxima de un ciclo por días.
const int kPeriodoConsumoMaxDias = 62;

enum PeriodoConsumoModo {
  /// Ciclos de [PeriodoConsumoConfig.duracionDias] días contados desde
  /// [PeriodoConsumoConfig.inicioReferencia] (semanal, quincenal, 10 días…).
  ciclo,

  /// Mes calendario: del día 1 al último día del mes.
  mensual,
}

DateTime _soloFecha(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Días entre dos fechas sin que el horario de verano sume o reste horas.
int _diasEntre(DateTime desde, DateTime hasta) => DateTime.utc(
  hasta.year,
  hasta.month,
  hasta.day,
).difference(DateTime.utc(desde.year, desde.month, desde.day)).inDays;

DateTime _sumarDias(DateTime fecha, int dias) =>
    DateTime(fecha.year, fecha.month, fecha.day + dias);

String _dosDigitos(int value) => value.toString().padLeft(2, '0');

/// `yyyy-MM-dd`, igual que lo guarda Firestore y lo lee el servidor.
String fechaClavePeriodo(DateTime fecha) =>
    '${fecha.year}-${_dosDigitos(fecha.month)}-${_dosDigitos(fecha.day)}';

DateTime? _parseFechaClave(Object? raw) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})$',
  ).firstMatch((raw ?? '').toString().trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  // Rechaza fechas que Dart corrige solo (2026-02-30 → 2026-03-02).
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

const _diasSemana = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];
const _diasSemanaCortos = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

class PeriodoConsumo {
  final DateTime desde;
  final DateTime hasta;

  PeriodoConsumo(DateTime desde, DateTime hasta)
    : desde = _soloFecha(desde),
      hasta = _soloFecha(hasta);

  int get dias => _diasEntre(desde, hasta) + 1;

  bool contiene(DateTime fecha) {
    final day = _soloFecha(fecha);
    return !day.isBefore(desde) && !day.isAfter(hasta);
  }

  @override
  bool operator ==(Object other) =>
      other is PeriodoConsumo && other.desde == desde && other.hasta == hasta;

  @override
  int get hashCode => Object.hash(desde, hasta);

  @override
  String toString() =>
      '${fechaClavePeriodo(desde)} a ${fechaClavePeriodo(hasta)}';
}

class PeriodoConsumoConfig {
  final PeriodoConsumoModo modo;

  /// Primer día de un período cualquiera del ciclo. Solo aplica a
  /// [PeriodoConsumoModo.ciclo]; los demás períodos se cuentan desde aquí,
  /// hacia adelante y hacia atrás.
  final DateTime inicioReferencia;
  final int duracionDias;

  PeriodoConsumoConfig({
    required this.modo,
    required DateTime inicioReferencia,
    required this.duracionDias,
  }) : inicioReferencia = _soloFecha(inicioReferencia);

  /// La regla histórica: 7 días de viernes a jueves (2 ene 2026 fue viernes).
  static final PeriodoConsumoConfig porDefecto = PeriodoConsumoConfig(
    modo: PeriodoConsumoModo.ciclo,
    inicioReferencia: DateTime(2026, 1, 2),
    duracionDias: 7,
  );

  /// Lee el campo guardado. Cualquier valor incompleto o fuera de rango
  /// vuelve a la regla histórica para no dejar Abastecimiento sin período.
  factory PeriodoConsumoConfig.fromMap(Object? raw) {
    if (raw is! Map) return porDefecto;
    final modoRaw = (raw['modo'] ?? '').toString().trim().toLowerCase();
    if (modoRaw == 'mensual') {
      return PeriodoConsumoConfig(
        modo: PeriodoConsumoModo.mensual,
        inicioReferencia: porDefecto.inicioReferencia,
        duracionDias: 0,
      );
    }
    if (modoRaw != 'ciclo') return porDefecto;
    final inicio = _parseFechaClave(raw['inicioReferencia']);
    final dias = raw['duracionDias'];
    if (inicio == null ||
        dias is! num ||
        dias != dias.roundToDouble() ||
        dias < 1 ||
        dias > kPeriodoConsumoMaxDias) {
      return porDefecto;
    }
    return PeriodoConsumoConfig(
      modo: PeriodoConsumoModo.ciclo,
      inicioReferencia: inicio,
      duracionDias: dias.toInt(),
    );
  }

  /// Lo que se guarda en `TBL_COMPRAS_CONFIG/{empresaId}.abastecimientoPeriodo`.
  Map<String, dynamic> toMap() => modo == PeriodoConsumoModo.mensual
      ? const {'modo': 'mensual'}
      : {
          'modo': 'ciclo',
          'inicioReferencia': fechaClavePeriodo(inicioReferencia),
          'duracionDias': duracionDias,
        };

  /// El período al que pertenece [fecha].
  PeriodoConsumo periodoDe(DateTime fecha) {
    final day = _soloFecha(fecha);
    if (modo == PeriodoConsumoModo.mensual) {
      return PeriodoConsumo(
        DateTime(day.year, day.month, 1),
        DateTime(day.year, day.month + 1, 0),
      );
    }
    final offset = _diasEntre(inicioReferencia, day);
    // División hacia abajo también para fechas anteriores a la referencia.
    final ciclos = (offset / duracionDias).floor();
    final desde = _sumarDias(inicioReferencia, ciclos * duracionDias);
    return PeriodoConsumo(desde, _sumarDias(desde, duracionDias - 1));
  }

  /// El período vigente y los siguientes, para programar una carga.
  List<PeriodoConsumo> programables(DateTime referencia, {int cantidad = 4}) {
    final result = <PeriodoConsumo>[];
    var actual = periodoDe(referencia);
    for (var i = 0; i < cantidad; i++) {
      result.add(actual);
      actual = periodoDe(_sumarDias(actual.hasta, 1));
    }
    return List.unmodifiable(result);
  }

  /// Solo se aceptan períodos que la configuración vigente genera.
  bool esPeriodoValido(DateTime desde, DateTime hasta) =>
      periodoDe(desde) == PeriodoConsumo(desde, hasta);

  bool esInicioDePeriodo(DateTime fecha) =>
      periodoDe(fecha).desde == _soloFecha(fecha);

  /// Para filtros y títulos: "vie–jue", "14 días", "mes calendario".
  String get etiquetaCorta {
    if (modo == PeriodoConsumoModo.mensual) return 'mes calendario';
    if (duracionDias == 7) {
      final inicio = inicioReferencia.weekday - 1;
      final fin = (inicio + 6) % 7;
      return '${_diasSemanaCortos[inicio]}–${_diasSemanaCortos[fin]}';
    }
    return duracionDias == 1 ? 'diario' : '$duracionDias días';
  }

  /// Explicación completa para Admin y los diálogos de carga.
  String get descripcion {
    if (modo == PeriodoConsumoModo.mensual) {
      return 'Mes calendario: del día 1 al último día de cada mes.';
    }
    if (duracionDias == 7) {
      final inicio = inicioReferencia.weekday - 1;
      final fin = (inicio + 6) % 7;
      return 'Semanal: de ${_diasSemana[inicio]} a ${_diasSemana[fin]}.';
    }
    if (duracionDias == 1) return 'Diario: un período por día.';
    return 'Ciclos de $duracionDias días; uno de ellos inicia el '
        '${_dosDigitos(inicioReferencia.day)}/'
        '${_dosDigitos(inicioReferencia.month)}/${inicioReferencia.year}.';
  }

  @override
  bool operator ==(Object other) =>
      other is PeriodoConsumoConfig &&
      other.modo == modo &&
      (modo == PeriodoConsumoModo.mensual ||
          (other.duracionDias == duracionDias &&
              // Dos referencias del mismo ciclo describen la misma regla.
              periodoDe(other.inicioReferencia).desde ==
                  other.inicioReferencia));

  @override
  int get hashCode => modo == PeriodoConsumoModo.mensual
      ? modo.hashCode
      : Object.hash(modo, duracionDias, periodoDe(DateTime(2026, 1, 1)).desde);
}

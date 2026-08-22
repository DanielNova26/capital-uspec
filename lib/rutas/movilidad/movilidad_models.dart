// lib/rutas/movilidad/movilidad_models.dart
//
// ESTUDIO DE MOVILIDAD (submódulo de Rutas).
// Modelo de datos de las mediciones automáticas de tiempos de desplazamiento
// Centro de Operaciones → establecimientos. Sigue el patrón del proyecto:
//   - fromMap(id, m) / toMap()
//   - todo scoped por empresaId
//   - createdAt como Timestamp de cliente (nunca serverTimestamp en createdAt)
//   - updatedAt con serverTimestamp() en toMap()
//
// Equivalencia con el requerimiento original (nombres en inglés):
//   route_measurements    → TBL_RUTAS_MOV_MEDICIONES
//   measurement_schedules → TBL_RUTAS_MOV_HORARIOS
//   configuración         → TBL_RUTAS_MOV_CONFIG (docId = empresaId)
//   corridas / candado    → TBL_RUTAS_MOV_RUNS
// Las mediciones las escribe SOLO el backend (Cloud Functions); la app es
// panel de consulta, administración y exportes.

import 'package:cloud_firestore/cloud_firestore.dart';

// ══════════════════════════════════════════════════════════════════════════════
// COLECCIONES
// ══════════════════════════════════════════════════════════════════════════════

const String kMovColConfig = 'TBL_RUTAS_MOV_CONFIG';
const String kMovColHorarios = 'TBL_RUTAS_MOV_HORARIOS';
const String kMovColMediciones = 'TBL_RUTAS_MOV_MEDICIONES';
const String kMovColRuns = 'TBL_RUTAS_MOV_RUNS';

// ══════════════════════════════════════════════════════════════════════════════
// CENTRO DE OPERACIONES (origen del estudio, según KML/CSV del estudio)
// ══════════════════════════════════════════════════════════════════════════════

const String kMovCentroNombre = 'Centro de Operaciones';
const String kMovCentroDireccion = 'Cra. 69 #79-11, Bogotá';
const double kMovCentroLat = 4.6862937;
const double kMovCentroLng = -74.082623;

/// Umbral de alerta por defecto (min). El estudio exige alertar cuando una
/// ruta "supera o se acerca" a las 2 horas.
const int kMovUmbralAlertaMinDefault = 105;

// ══════════════════════════════════════════════════════════════════════════════
// ESCENARIOS
// ══════════════════════════════════════════════════════════════════════════════

const String kMovEscPicoManana = 'pico_manana';
const String kMovEscValle = 'valle';
const String kMovEscMedioDia = 'medio_dia';
const String kMovEscPicoTarde = 'pico_tarde';
const String kMovEscFinSemana = 'fin_semana';

const List<String> kMovEscenarios = [
  kMovEscPicoManana,
  kMovEscValle,
  kMovEscMedioDia,
  kMovEscPicoTarde,
  kMovEscFinSemana,
];

const Map<String, String> kMovEscenarioLabels = {
  kMovEscPicoManana: 'Hora pico mañana',
  kMovEscValle: 'Hora valle',
  kMovEscMedioDia: 'Medio día',
  kMovEscPicoTarde: 'Hora pico tarde',
  kMovEscFinSemana: 'Fin de semana',
};

String movEscenarioLabel(String key) =>
    kMovEscenarioLabels[key] ?? (key.isEmpty ? '—' : key);

// ══════════════════════════════════════════════════════════════════════════════
// RIESGO (clasificación del requerimiento) Y ESTADO DE TRÁFICO
// ══════════════════════════════════════════════════════════════════════════════

const String kMovRiesgoBajo = 'bajo';
const String kMovRiesgoMedio = 'medio';
const String kMovRiesgoAlto = 'alto_controlado';
const String kMovRiesgoCritico = 'critico';

const List<String> kMovRiesgos = [
  kMovRiesgoBajo,
  kMovRiesgoMedio,
  kMovRiesgoAlto,
  kMovRiesgoCritico,
];

const Map<String, String> kMovRiesgoLabels = {
  kMovRiesgoBajo: 'Bajo',
  kMovRiesgoMedio: 'Medio',
  kMovRiesgoAlto: 'Alto controlado',
  kMovRiesgoCritico: 'Crítico',
};

String movRiesgoLabel(String key) =>
    kMovRiesgoLabels[key] ?? (key.isEmpty ? '—' : key);

/// Clasifica el riesgo con la regla del estudio: 0-60 bajo, 61-90 medio,
/// 91-120 alto controlado, >120 crítico. (Espejo de la Cloud Function.)
String movClasificarRiesgo(double minutos) {
  if (minutos <= 60) return kMovRiesgoBajo;
  if (minutos <= 90) return kMovRiesgoMedio;
  if (minutos <= 120) return kMovRiesgoAlto;
  return kMovRiesgoCritico;
}

const Map<String, String> kMovTraficoLabels = {
  'bajo': 'Bajo',
  'medio': 'Medio',
  'alto': 'Alto',
  'critico': 'Crítico',
};

String movTraficoLabel(String key) =>
    kMovTraficoLabels[key] ?? (key.isEmpty ? '—' : key);

// ══════════════════════════════════════════════════════════════════════════════
// DÍAS
// ══════════════════════════════════════════════════════════════════════════════

/// 1=lunes … 7=domingo (mismo convenio de DateTime.weekday).
const Map<int, String> kMovWeekdayNombres = {
  1: 'Lunes',
  2: 'Martes',
  3: 'Miércoles',
  4: 'Jueves',
  5: 'Viernes',
  6: 'Sábado',
  7: 'Domingo',
};

String movWeekdayNombre(int w) => kMovWeekdayNombres[w] ?? '$w';

/// Días del estudio en el orden pedido: sábado, domingo, lunes y martes.
const List<int> kMovDiasEstudio = [6, 7, 1, 2];

// ══════════════════════════════════════════════════════════════════════════════
// VENTANAS DE ENTREGA DEL SERVICIO
// No son horarios de medición: son el rango en que el alimento DEBE estar
// entregado. Sirven para saber si el vehículo alcanza a cumplir.
// ══════════════════════════════════════════════════════════════════════════════

const String kMovComidaDesayuno = 'desayuno';
const String kMovComidaAlmuerzo = 'almuerzo';
const String kMovComidaCena = 'cena';
const String kMovComidaFuera = 'fuera_de_ventana';

/// Descargue por parada por defecto (min). Definido con la operación.
const int kMovDescargueMinDefault = 20;

class MovVentana {
  final String desde;
  final String hasta;
  const MovVentana(this.desde, this.hasta);
}

const Map<String, MovVentana> kMovVentanasDefault = {
  kMovComidaDesayuno: MovVentana('06:00', '08:00'),
  kMovComidaAlmuerzo: MovVentana('11:30', '13:40'),
  kMovComidaCena: MovVentana('16:00', '18:00'),
};

const Map<String, String> kMovComidaLabels = {
  kMovComidaDesayuno: 'Desayuno',
  kMovComidaAlmuerzo: 'Almuerzo',
  kMovComidaCena: 'Cena',
  kMovComidaFuera: 'Fuera de ventana (control)',
};

Map<String, MovVentana> _ventanasDe(dynamic raw) {
  if (raw is! Map) return kMovVentanasDefault;
  final out = <String, MovVentana>{};
  for (final e in kMovVentanasDefault.entries) {
    final v = raw[e.key];
    out[e.key] = v is Map
        ? MovVentana(
            (v['desde'] ?? e.value.desde).toString(),
            (v['hasta'] ?? e.value.hasta).toString(),
          )
        : e.value;
  }
  return out;
}

String movComidaLabel(String key) =>
    kMovComidaLabels[key] ?? (key.isEmpty ? '—' : key);

/// Horarios sugeridos: se miden las SALIDAS que alimentan cada ventana de
/// entrega, más una corrida de control en hora valle (09:30) que no
/// corresponde a ninguna comida pero sirve de línea base.
/// hora → escenario en día hábil; los fines de semana quedan 'fin_semana'.
const Map<String, String> kMovHorasSugeridas = {
  '06:00': kMovEscPicoManana, // desayuno
  '07:00': kMovEscPicoManana, // desayuno
  '09:30': kMovEscValle, // control, fuera de ventana
  '11:30': kMovEscMedioDia, // almuerzo
  '12:30': kMovEscMedioDia, // almuerzo
  '16:00': kMovEscPicoTarde, // cena
  '17:00': kMovEscPicoTarde, // cena
};

/// Comida a la que corresponde una hora de salida, según las ventanas.
String movComidaDeHora(String hhmm, [Map<String, MovVentana>? ventanas]) {
  int min(String v) {
    final p = v.split(':');
    if (p.length != 2) return -1;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  final m = min(hhmm);
  if (m < 0) return kMovComidaFuera;
  for (final e in (ventanas ?? kMovVentanasDefault).entries) {
    if (m >= min(e.value.desde) && m <= min(e.value.hasta)) return e.key;
  }
  return kMovComidaFuera;
}

// ══════════════════════════════════════════════════════════════════════════════
// FUENTES DE MEDICIÓN
// ══════════════════════════════════════════════════════════════════════════════

const Map<String, String> kMovFuenteLabels = {
  'google': 'Google Routes API (tráfico en tiempo real)',
  'tomtom': 'TomTom Routing API (tráfico en tiempo real)',
};

const Map<String, String> kMovFuenteMedicionLabels = {
  'google_routes': 'Google Routes API',
  'tomtom': 'TomTom API',
};

String movFuenteMedicionLabel(String key) =>
    kMovFuenteMedicionLabels[key] ?? (key.isEmpty ? '—' : key);

/// Nombre corto para las tablas comparativas.
const Map<String, String> kMovFuenteCorta = {
  'google_routes': 'Google',
  'tomtom': 'TomTom',
};

String movFuenteCorta(String key) =>
    kMovFuenteCorta[key] ?? (key.isEmpty ? '—' : key);

/// Clave de configuración (`google`/`tomtom`) a partir de la fuente que quedó
/// grabada en la medición (`google_routes`/`tomtom`).
String movFuenteConfigDe(String fuenteMedicion) =>
    fuenteMedicion == 'tomtom' ? 'tomtom' : 'google';

// ══════════════════════════════════════════════════════════════════════════════
// SEMILLA DE PUNTOS (Tabla_rutas_distancias_corregidas.csv, derivada del KML)
// Coordenadas verificadas/corregidas del estudio. El centro NO va aquí: es el
// origen y vive en TBL_RUTAS_MOV_CONFIG.
// ══════════════════════════════════════════════════════════════════════════════

class MovPuntoSeed {
  final String nombre;
  final String direccion;
  final double lat;
  final double lng;
  final double distanciaKm;
  final String rango;

  const MovPuntoSeed(
    this.nombre,
    this.direccion,
    this.lat,
    this.lng,
    this.distanciaKm,
    this.rango,
  );
}

const List<MovPuntoSeed> kMovPuntosSeed = [
  MovPuntoSeed('USME', 'Cl. 95A Sur #14-28, Bogotá', 4.5021031, -74.116919,
      20.83, 'Más de 20 km'),
  MovPuntoSeed('RAFAEL URIBE', 'Calle 27 Sur #24C-51, Bogotá', 4.5855622,
      -74.1106709, 11.62, '10–15 km'),
  MovPuntoSeed('ENGATIVÁ', 'Carrera 78A #70-54, Bogotá', 4.6900743,
      -74.1026591, 2.26, '0–5 km'),
  MovPuntoSeed(
      'SUBA', 'Carrera 92 #146C-49, Bogotá', 4.741444, -74.084968, 6.14,
      '5–10 km'),
  MovPuntoSeed('URI PUENTE ARANDA', 'Carrera 40 #10A-08, Bogotá', 4.61818,
      -74.10267, 7.89, '5–10 km'),
  MovPuntoSeed('SIJIN', 'Carrera 40 #10A-08, Bogotá', 4.6180602, -74.1026188,
      7.9, '5–10 km'),
  MovPuntoSeed('TEUSAQUILLO', 'Carrera 13 #39-86, Bogotá', 4.6273753,
      -74.0665466, 6.79, '5–10 km'),
  MovPuntoSeed('SANTA FE', 'Carrera 5 #29-11, Bogotá', 4.615598, -74.0666486,
      8.06, '5–10 km'),
  MovPuntoSeed('CANDELARIA', 'Carrera 7 #6A-12, Bogotá', 4.59141, -74.0789,
      10.56, '10–15 km'),
  MovPuntoSeed('SAN CRISTÓBAL', 'Avenida 1 de Mayo, San Cristóbal, Bogotá',
      4.5717922, -74.0905107, 12.76, '10–15 km'),
  MovPuntoSeed('TUNJUELITO', 'Transversal 33 #48C-21 Sur, Bogotá', 4.585573,
      -74.133404, 12.53, '10–15 km'),
  MovPuntoSeed('CIUDAD BOLÍVAR', 'Diagonal 70 Sur, Bogotá', 4.5788539,
      -74.1663245, 15.13, '15–20 km'),
  MovPuntoSeed('KENNEDY', 'Calle 41D Sur #78N-05, Bogotá', 4.61973,
      -74.159099, 11.25, '10–15 km'),
  MovPuntoSeed(
      'BOSA', 'Calle 66 Sur #78-2, Bogotá', 4.6001615, -74.1871891, 15.03,
      '15–20 km'),
  MovPuntoSeed('CTI', 'Carrera 28A #18A-67, Bogotá', 4.616774, -74.0878141,
      7.75, '5–10 km'),
  MovPuntoSeed('FISCALÍA', 'Carrera 28 #18-64, Bogotá', 4.61552, -74.087306,
      7.89, '5–10 km'),
  MovPuntoSeed('BÚNKER', 'Diagonal 22B #52-01, Bogotá', 4.6388889,
      -74.0997222, 5.6, '5–10 km'),
  MovPuntoSeed('MÁRTIRES', 'Carrera 24 #12-32, Bogotá', 4.609142, -74.088818,
      8.61, '5–10 km'),
  MovPuntoSeed('DIJIN', 'Carrera 24 #12-32, Bogotá', 4.609142, -74.088818,
      8.61, '5–10 km'),
  MovPuntoSeed('ANTONIO NARIÑO', 'Carrera 24 #18-90 Sur, Bogotá', 4.5868177,
      -74.0978753, 11.19, '10–15 km'),
  MovPuntoSeed(
      'TERMINAL',
      'Estación de Policía Terminal, Módulo 5, Terminal Salitre, Bogotá',
      4.652707,
      -74.1136331,
      5.08,
      '5–10 km'),
  MovPuntoSeed('UNIDAD TÁCTICA ARBOG', 'Carrera 69 #49A-99, Bogotá',
      4.6633548, -74.101609, 3.31, '0–5 km'),
  MovPuntoSeed('FONTIBÓN', 'Carrera 98 #16B-50, Bogotá', 4.6683128,
      -74.1483088, 7.55, '5–10 km'),
  MovPuntoSeed('AEROPUERTO', 'Avenida Calle 26 #116-87, Bogotá', 4.6900781,
      -74.1311629, 5.4, '5–10 km'),
  MovPuntoSeed('USAQUÉN', 'Calle 165 #8A-43, Bogotá', 4.741481, -74.0267498,
      8.72, '5–10 km'),
  MovPuntoSeed('BARRIOS UNIDOS', 'Calle 72 #62-81, Bogotá', 4.67382,
      -74.08182, 1.39, '0–5 km'),
];

// ══════════════════════════════════════════════════════════════════════════════
// INCIDENTES VIALES (obras, cierres, congestión) — fuente: TomTom Traffic
// ══════════════════════════════════════════════════════════════════════════════

const Map<String, String> kMovIncidenteLabels = {
  'obras': 'Obras en la vía',
  'cierre_via': 'Vía cerrada',
  'carril_cerrado': 'Carril cerrado',
  'congestion': 'Congestión',
  'accidente': 'Accidente',
  'vehiculo_averiado': 'Vehículo averiado',
  'inundacion': 'Inundación',
  'condiciones_peligrosas': 'Condiciones peligrosas',
  'clima': 'Clima adverso',
  'otro': 'Otro',
};

String movIncidenteLabel(String key) =>
    kMovIncidenteLabels[key] ?? (key.isEmpty ? '—' : key);

/// Un incidente concreto detectado SOBRE la ruta medida.
class MovIncidente {
  final String categoria;
  final String descripcion;
  final String desde;
  final String hasta;
  final int? demoraSeg;
  final int? largoM;

  const MovIncidente({
    this.categoria = 'otro',
    this.descripcion = '',
    this.desde = '',
    this.hasta = '',
    this.demoraSeg,
    this.largoM,
  });

  factory MovIncidente.fromMap(Map<String, dynamic> m) => MovIncidente(
        categoria: (m['categoria'] ?? 'otro').toString(),
        descripcion: (m['descripcion'] ?? '').toString(),
        desde: (m['desde'] ?? '').toString(),
        hasta: (m['hasta'] ?? '').toString(),
        demoraSeg: (m['demoraSeg'] as num?)?.toInt(),
        largoM: (m['largoM'] as num?)?.toInt(),
      );

  bool get esObra => categoria == 'obras';

  /// "Obras en la vía · Carrera 28 → Calle 7 · 191 m".
  String get resumen {
    final partes = <String>[movIncidenteLabel(categoria)];
    if (descripcion.isNotEmpty) partes.add(descripcion);
    if (desde.isNotEmpty || hasta.isNotEmpty) {
      partes.add('$desde → $hasta');
    }
    if (largoM != null) partes.add('$largoM m');
    if (demoraSeg != null && demoraSeg! > 0) {
      partes.add('+${(demoraSeg! / 60).round()} min');
    }
    return partes.join(' · ');
  }
}

/// Condiciones de la vía sobre una ruta al momento de la medición.
class MovIncidentesRuta {
  final int total;
  final int obras;
  final int cierres;
  final int congestiones;
  final int accidentes;
  final int demoraIncidentesSeg;
  final List<MovIncidente> detalle;

  const MovIncidentesRuta({
    this.total = 0,
    this.obras = 0,
    this.cierres = 0,
    this.congestiones = 0,
    this.accidentes = 0,
    this.demoraIncidentesSeg = 0,
    this.detalle = const [],
  });

  factory MovIncidentesRuta.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MovIncidentesRuta();
    return MovIncidentesRuta(
      total: (m['total'] as num?)?.toInt() ?? 0,
      obras: (m['obras'] as num?)?.toInt() ?? 0,
      cierres: (m['cierres'] as num?)?.toInt() ?? 0,
      congestiones: (m['congestiones'] as num?)?.toInt() ?? 0,
      accidentes: (m['accidentes'] as num?)?.toInt() ?? 0,
      demoraIncidentesSeg:
          (m['demoraIncidentesSeg'] as num?)?.toInt() ?? 0,
      detalle: ((m['detalle'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => MovIncidente.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  bool get hayAlgo => total > 0;

  /// "2 obras · 1 cierre" para tablas y reportes.
  String get resumenCorto {
    final p = <String>[];
    if (obras > 0) p.add('$obras obra${obras == 1 ? '' : 's'}');
    if (cierres > 0) p.add('$cierres cierre${cierres == 1 ? '' : 's'}');
    if (congestiones > 0) p.add('$congestiones congestión');
    if (accidentes > 0) {
      p.add('$accidentes accidente${accidentes == 1 ? '' : 's'}');
    }
    return p.isEmpty ? '—' : p.join(' · ');
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OBRAS OFICIALES — Planes de Manejo de Tránsito (PMT) de la Secretaría
// Distrital de Movilidad. A diferencia de los incidentes de TomTom, cada obra
// tiene acto administrativo (radicado SDM), contratista y vigencia.
// ══════════════════════════════════════════════════════════════════════════════

const Map<String, String> kMovObraTipoLabels = {
  'obra_infraestructura': 'Obra de infraestructura',
  'obra_servicios_publicos': 'Obra de servicios públicos',
  'evento': 'Evento autorizado',
  'desvio': 'Desvío autorizado',
};

String movObraTipoLabel(String key) =>
    kMovObraTipoLabels[key] ?? (key.isEmpty ? 'Obra' : key);

class MovObraOficial {
  final String tipo;
  final String direccionInicio;
  final String direccionFin;
  final String contratista;
  final String tipoAfectacion;
  final String localidad;
  final String radicadoSdm;
  final String horarioTrabajo;
  final String fechaInicio;
  final String fechaFin;

  const MovObraOficial({
    this.tipo = '',
    this.direccionInicio = '',
    this.direccionFin = '',
    this.contratista = '',
    this.tipoAfectacion = '',
    this.localidad = '',
    this.radicadoSdm = '',
    this.horarioTrabajo = '',
    this.fechaInicio = '',
    this.fechaFin = '',
  });

  factory MovObraOficial.fromMap(Map<String, dynamic> m) => MovObraOficial(
        tipo: (m['tipo'] ?? '').toString(),
        direccionInicio: (m['direccionInicio'] ?? '').toString(),
        direccionFin: (m['direccionFin'] ?? '').toString(),
        contratista: (m['contratista'] ?? '').toString(),
        tipoAfectacion: (m['tipoAfectacion'] ?? '').toString(),
        localidad: (m['localidad'] ?? '').toString(),
        radicadoSdm: (m['radicadoSdm'] ?? '').toString(),
        horarioTrabajo: (m['horarioTrabajo'] ?? '').toString(),
        fechaInicio: (m['fechaInicio'] ?? '').toString(),
        fechaFin: (m['fechaFin'] ?? '').toString(),
      );

  String get tramo => direccionFin.trim().isEmpty
      ? direccionInicio
      : '$direccionInicio → $direccionFin';

  String get vigencia => fechaInicio.isEmpty && fechaFin.isEmpty
      ? ''
      : 'vigente $fechaInicio a $fechaFin';

  /// Línea citable para el informe técnico.
  String get resumen {
    final p = <String>[movObraTipoLabel(tipo)];
    if (tipoAfectacion.isNotEmpty) p.add(tipoAfectacion);
    if (tramo.trim().isNotEmpty) p.add(tramo);
    if (localidad.isNotEmpty) p.add(localidad);
    if (contratista.isNotEmpty) p.add(contratista);
    if (vigencia.isNotEmpty) p.add(vigencia);
    if (radicadoSdm.isNotEmpty) p.add('radicado SDM $radicadoSdm');
    return p.join(' · ');
  }
}

/// Obras oficiales vigentes sobre una ruta al momento de la medición.
class MovObrasRuta {
  final int total;
  final int tramosAfectados;
  final int cierres;
  final List<MovObraOficial> detalle;

  const MovObrasRuta({
    this.total = 0,
    this.tramosAfectados = 0,
    this.cierres = 0,
    this.detalle = const [],
  });

  factory MovObrasRuta.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MovObrasRuta();
    return MovObrasRuta(
      total: (m['total'] as num?)?.toInt() ?? 0,
      tramosAfectados: (m['tramosAfectados'] as num?)?.toInt() ?? 0,
      cierres: (m['cierres'] as num?)?.toInt() ?? 0,
      detalle: ((m['detalle'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => MovObraOficial.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  bool get hayAlgo => total > 0;

  String get resumenCorto {
    if (total == 0) return '—';
    final base = '$total obra${total == 1 ? '' : 's'} PMT';
    return cierres > 0 ? '$base ($cierres con cierre)' : base;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LAS 10 RUTAS DEL ESTUDIO
// La operación NO son 26 viajes independientes desde la planta: son 10 rutas
// encadenadas (el vehículo sale, entrega en la parada 1, sigue a la 2, etc.).
// El orden de esta tabla ES la secuencia real de entrega.
// ══════════════════════════════════════════════════════════════════════════════

const Map<String, List<String>> kMovRutasEstudio = {
  'Ruta 1': ['TERMINAL', 'USME'],
  'Ruta 2': ['URI PUENTE ARANDA', 'SIJIN'],
  'Ruta 3': ['SANTA FE', 'CANDELARIA', 'SAN CRISTÓBAL'],
  'Ruta 4': ['RAFAEL URIBE', 'TUNJUELITO', 'CIUDAD BOLÍVAR'],
  'Ruta 5': ['BÚNKER', 'AEROPUERTO', 'FONTIBÓN'],
  'Ruta 6': ['TEUSAQUILLO', 'CTI', 'FISCALÍA'],
  'Ruta 7': ['KENNEDY', 'BOSA'],
  'Ruta 8': ['UNIDAD TÁCTICA ARBOG', 'MÁRTIRES', 'DIJIN', 'ANTONIO NARIÑO'],
  'Ruta 9': ['BARRIOS UNIDOS', 'USAQUÉN'],
  'Ruta 10': ['ENGATIVÁ', 'SUBA'],
};

/// Total de paradas del estudio (debe coincidir con [kMovPuntosSeed]).
int get kMovTotalParadas =>
    kMovRutasEstudio.values.fold(0, (a, b) => a + b.length);

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

// ══════════════════════════════════════════════════════════════════════════════
// MovConfigDoc — TBL_RUTAS_MOV_CONFIG (docId = empresaId)
// ══════════════════════════════════════════════════════════════════════════════

class MovConfigDoc {
  final String empresaId;

  /// Interruptor maestro de las mediciones automáticas.
  final bool activo;
  final String origenNombre;
  final String origenDireccion;
  final double origenLat;
  final double origenLng;
  final int umbralAlertaMin;

  /// Minutos de descargue/entrega en cada parada. Se suman al tiempo en ruta
  /// de las paradas siguientes.
  final int minutosPorParada;

  /// Ventanas de entrega por comida. Definen si el vehículo llega a tiempo.
  final Map<String, MovVentana> ventanasEntrega;

  /// Cédulas que reciben la notificación cuando una ruta entra en alerta.
  final List<String> alertaCedulas;

  /// Fuente PRINCIPAL: 'google' | 'tomtom'. Es la que manda para las alertas
  /// y para los indicadores del panel.
  final String fuente;

  /// Si es true, cada corrida mide TAMBIÉN con la otra API y guarda una
  /// medición por fuente, para el comparativo entre proveedores.
  final bool compararFuentes;

  /// API keys opcionales por empresa; si están vacías se usan las del backend
  /// (`functions/.env`).
  final String apiKeyGoogle;
  final String apiKeyTomtom;
  final Timestamp? updatedAt;

  const MovConfigDoc({
    required this.empresaId,
    this.activo = true,
    this.origenNombre = kMovCentroNombre,
    this.origenDireccion = kMovCentroDireccion,
    this.origenLat = kMovCentroLat,
    this.origenLng = kMovCentroLng,
    this.umbralAlertaMin = kMovUmbralAlertaMinDefault,
    this.minutosPorParada = kMovDescargueMinDefault,
    this.ventanasEntrega = kMovVentanasDefault,
    this.alertaCedulas = const [],
    this.fuente = 'google',
    this.compararFuentes = false,
    this.apiKeyGoogle = '',
    this.apiKeyTomtom = '',
    this.updatedAt,
  });

  /// Fuente secundaria del comparativo (la contraria a la principal).
  String get fuenteSecundaria => fuente == 'tomtom' ? 'google' : 'tomtom';

  factory MovConfigDoc.defaults(String empresaId) =>
      MovConfigDoc(empresaId: empresaId);

  factory MovConfigDoc.fromMap(String id, Map<String, dynamic> m) =>
      MovConfigDoc(
        empresaId: (m['empresaId'] ?? id).toString(),
        activo: m['activo'] as bool? ?? true,
        origenNombre: (m['origenNombre'] ?? kMovCentroNombre).toString(),
        origenDireccion:
            (m['origenDireccion'] ?? kMovCentroDireccion).toString(),
        origenLat: _asDouble(m['origenLat']) ?? kMovCentroLat,
        origenLng: _asDouble(m['origenLng']) ?? kMovCentroLng,
        umbralAlertaMin: (m['umbralAlertaMin'] as num?)?.toInt() ??
            kMovUmbralAlertaMinDefault,
        minutosPorParada: (m['minutosPorParada'] as num?)?.toInt() ??
            kMovDescargueMinDefault,
        ventanasEntrega: _ventanasDe(m['ventanasEntrega']),
        alertaCedulas: ((m['alertaCedulas'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(),
        fuente: (m['fuente'] ?? 'google').toString(),
        compararFuentes: m['compararFuentes'] as bool? ?? false,
        // 'apiKey' es el nombre legacy de la key de Google.
        apiKeyGoogle: (m['apiKeyGoogle'] ?? m['apiKey'] ?? '').toString(),
        apiKeyTomtom: (m['apiKeyTomtom'] ?? '').toString(),
        updatedAt: m['updatedAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
        'empresaId': empresaId,
        'activo': activo,
        'origenNombre': origenNombre.trim(),
        'origenDireccion': origenDireccion.trim(),
        'origenLat': origenLat,
        'origenLng': origenLng,
        'umbralAlertaMin': umbralAlertaMin,
        'minutosPorParada': minutosPorParada,
        'ventanasEntrega': ventanasEntrega.map(
          (k, v) => MapEntry(k, {'desde': v.desde, 'hasta': v.hasta}),
        ),
        'alertaCedulas': alertaCedulas,
        'fuente': fuente,
        'compararFuentes': compararFuentes,
        'apiKeyGoogle': apiKeyGoogle.trim(),
        'apiKeyTomtom': apiKeyTomtom.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  MovConfigDoc copyWith({
    bool? activo,
    String? origenNombre,
    String? origenDireccion,
    double? origenLat,
    double? origenLng,
    int? umbralAlertaMin,
    int? minutosPorParada,
    Map<String, MovVentana>? ventanasEntrega,
    List<String>? alertaCedulas,
    String? fuente,
    bool? compararFuentes,
    String? apiKeyGoogle,
    String? apiKeyTomtom,
  }) =>
      MovConfigDoc(
        empresaId: empresaId,
        activo: activo ?? this.activo,
        origenNombre: origenNombre ?? this.origenNombre,
        origenDireccion: origenDireccion ?? this.origenDireccion,
        origenLat: origenLat ?? this.origenLat,
        origenLng: origenLng ?? this.origenLng,
        umbralAlertaMin: umbralAlertaMin ?? this.umbralAlertaMin,
        minutosPorParada: minutosPorParada ?? this.minutosPorParada,
        ventanasEntrega: ventanasEntrega ?? this.ventanasEntrega,
        alertaCedulas: alertaCedulas ?? this.alertaCedulas,
        fuente: fuente ?? this.fuente,
        compararFuentes: compararFuentes ?? this.compararFuentes,
        apiKeyGoogle: apiKeyGoogle ?? this.apiKeyGoogle,
        apiKeyTomtom: apiKeyTomtom ?? this.apiKeyTomtom,
        updatedAt: updatedAt,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// MovHorarioDoc — TBL_RUTAS_MOV_HORARIOS (measurement_schedules)
// ══════════════════════════════════════════════════════════════════════════════

class MovHorarioDoc {
  final String id;
  final String empresaId;

  /// 1=lunes … 7=domingo (DateTime.weekday).
  final int weekday;

  /// "HH:mm" hora Bogotá.
  final String hora;
  final String escenario;
  final bool activo;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const MovHorarioDoc({
    this.id = '',
    required this.empresaId,
    required this.weekday,
    required this.hora,
    required this.escenario,
    this.activo = true,
    required this.createdAt,
    this.updatedAt,
  });

  int get minutosDia {
    final p = hora.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  factory MovHorarioDoc.fromMap(String id, Map<String, dynamic> m) =>
      MovHorarioDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        weekday: (m['weekday'] as num?)?.toInt() ?? 1,
        hora: (m['hora'] ?? '').toString(),
        escenario: (m['escenario'] ?? '').toString(),
        activo: m['activo'] as bool? ?? true,
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
        updatedAt: m['updatedAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
        'empresaId': empresaId,
        'weekday': weekday,
        'hora': hora,
        'escenario': escenario,
        'activo': activo,
        'createdAt': createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

// ══════════════════════════════════════════════════════════════════════════════
// MovMedicionDoc — TBL_RUTAS_MOV_MEDICIONES (route_measurements)
// La escribe SOLO el backend. La app la lee (panel, exportes, evidencia).
// ══════════════════════════════════════════════════════════════════════════════

class MovMedicionDoc {
  final String id;
  final String empresaId;
  final String runId;
  final String tipo; // programada | manual

  /// false = intento fallido (se conserva como evidencia; sin métricas).
  final bool ok;
  final String errorMsg;

  final String fecha; // yyyy-MM-dd
  final String hora; // HH:mm
  final Timestamp fechaHora;
  final int weekday;
  final String weekdayNombre;
  final String escenario;

  final String origenNombre;
  final String origenDireccion;
  final double origenLat;
  final double origenLng;

  // ── Ruta encadenada: este registro es un TRAMO, no un viaje directo ──
  final String rutaId;
  final String rutaCodigo;
  final int ordenParada;
  final int totalParadasRuta;
  final bool esPrimerTramo;

  /// De dónde salió este tramo: la planta si es el primero, o la parada
  /// anterior de la misma ruta.
  final String tramoDesdeNombre;
  final double tramoDesdeLat;
  final double tramoDesdeLng;

  final String puntoId;
  final String puntoNombre;
  final String puntoDireccion;
  final double puntoLat;
  final double puntoLng;

  final double distanciaKm;

  /// Tiempo ACTUAL: predicción con tráfico en vivo al momento de la consulta.
  final double duracionTraficoMin;

  /// Tiempo ESPERADO: el que calcula la API con las velocidades nominales de
  /// cada tramo, sin mirar el tráfico del momento. Ojo: NO es "vía vacía".
  final double? duracionSinTraficoMin;

  /// Demora atribuida al tráfico (nunca negativa) — columna formal del
  /// requerimiento del estudio.
  final double? demoraTraficoMin;

  /// Diferencia CON SIGNO entre lo actual y lo esperado.
  /// Positiva = el trayecto va peor que lo calculado (hay congestión).
  /// Negativa = va mejor que lo calculado (vía más fluida que el modelo).
  final double? diferenciaEsperadoMin;

  // ── Acumulado desde la planta hasta esta parada ──────────────────────
  /// Suma de los tramos recorridos de la ruta (sin contar descargues).
  final double duracionAcumuladaMin;
  final double distanciaAcumuladaKm;

  /// Tiempo TOTAL en ruta al llegar: acumulado + descargues anteriores.
  /// Es el valor que manda para la clasificación de riesgo, porque es el
  /// tiempo que lleva el alimento fuera de la planta.
  final double minutosEnRutaAlLlegar;

  /// Minutos de descargue por parada usados en el cálculo.
  final int minutosPorParada;

  // ── Horas reales del tramo y ventana de entrega ──────────────────────
  /// "HH:mm" en que el vehículo SALE hacia esta parada.
  final String horaSalidaTramoTxt;

  /// "HH:mm" en que LLEGA a esta parada (salida + tramo).
  final String horaLlegadaTxt;

  /// Comida a la que pertenece la corrida (desayuno/almuerzo/cena) o
  /// `fuera_de_ventana` si es una corrida de control.
  final String comida;

  /// Cierre de la ventana de entrega, "HH:mm". Vacío si es control.
  final String ventanaHasta;

  /// true = llega a tiempo · false = llega tarde · null = sin ventana.
  final bool? dentroDeVentana;

  /// Minutos de retraso frente al cierre de la ventana (0 si llega a tiempo).
  final int minutosFueraVentana;

  /// Riesgo del tramo aislado (referencia). El campo [riesgo] usa el
  /// acumulado, que es el que importa para inocuidad.
  final String riesgoTramo;

  final String rutaPrincipal;
  final String rutaAlterna;
  final String estadoTrafico; // bajo | medio | alto | critico
  final String riesgo; // bajo | medio | alto_controlado | critico
  final bool alerta;
  final String fuente; // google_routes | tomtom

  /// Obras, cierres y congestión detectados SOBRE esta ruta (tiempo real).
  final MovIncidentesRuta incidentes;

  /// Obras AUTORIZADAS por la SDM (PMT) vigentes sobre esta ruta.
  final MovObrasRuta obrasOficiales;

  final Map<String, dynamic> requestParams;
  final String apiRawResponse;
  final String creadoPor;
  final String observaciones;
  final Timestamp createdAt;

  const MovMedicionDoc({
    this.id = '',
    required this.empresaId,
    this.runId = '',
    this.tipo = '',
    this.ok = true,
    this.errorMsg = '',
    required this.fecha,
    required this.hora,
    required this.fechaHora,
    this.weekday = 1,
    this.weekdayNombre = '',
    this.escenario = '',
    this.origenNombre = '',
    this.origenDireccion = '',
    this.origenLat = 0,
    this.origenLng = 0,
    this.rutaId = '',
    this.rutaCodigo = '',
    this.ordenParada = 1,
    this.totalParadasRuta = 1,
    this.esPrimerTramo = true,
    this.tramoDesdeNombre = '',
    this.tramoDesdeLat = 0,
    this.tramoDesdeLng = 0,
    this.puntoId = '',
    this.puntoNombre = '',
    this.puntoDireccion = '',
    this.puntoLat = 0,
    this.puntoLng = 0,
    this.distanciaKm = 0,
    this.duracionTraficoMin = 0,
    this.duracionSinTraficoMin,
    this.demoraTraficoMin,
    this.diferenciaEsperadoMin,
    this.duracionAcumuladaMin = 0,
    this.distanciaAcumuladaKm = 0,
    this.minutosEnRutaAlLlegar = 0,
    this.minutosPorParada = 0,
    this.horaSalidaTramoTxt = '',
    this.horaLlegadaTxt = '',
    this.comida = '',
    this.ventanaHasta = '',
    this.dentroDeVentana,
    this.minutosFueraVentana = 0,
    this.riesgoTramo = '',
    this.rutaPrincipal = '',
    this.rutaAlterna = '',
    this.estadoTrafico = '',
    this.riesgo = '',
    this.alerta = false,
    this.fuente = '',
    this.incidentes = const MovIncidentesRuta(),
    this.obrasOficiales = const MovObrasRuta(),
    this.requestParams = const {},
    this.apiRawResponse = '',
    this.creadoPor = '',
    this.observaciones = '',
    required this.createdAt,
  });

  factory MovMedicionDoc.fromMap(String id, Map<String, dynamic> m) =>
      MovMedicionDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        runId: (m['runId'] ?? '').toString(),
        tipo: (m['tipo'] ?? '').toString(),
        ok: m['ok'] as bool? ?? true,
        errorMsg: (m['errorMsg'] ?? '').toString(),
        fecha: (m['fecha'] ?? '').toString(),
        hora: (m['hora'] ?? '').toString(),
        fechaHora: m['fechaHora'] as Timestamp? ??
            (m['createdAt'] as Timestamp? ?? Timestamp.now()),
        weekday: (m['weekday'] as num?)?.toInt() ?? 1,
        weekdayNombre: (m['weekdayNombre'] ?? '').toString(),
        escenario: (m['escenario'] ?? '').toString(),
        origenNombre: (m['origenNombre'] ?? '').toString(),
        origenDireccion: (m['origenDireccion'] ?? '').toString(),
        origenLat: _asDouble(m['origenLat']) ?? 0,
        origenLng: _asDouble(m['origenLng']) ?? 0,
        rutaId: (m['rutaId'] ?? '').toString(),
        rutaCodigo: (m['rutaCodigo'] ?? '').toString(),
        ordenParada: (m['ordenParada'] as num?)?.toInt() ?? 1,
        totalParadasRuta: (m['totalParadasRuta'] as num?)?.toInt() ?? 1,
        esPrimerTramo: m['esPrimerTramo'] as bool? ?? true,
        tramoDesdeNombre: (m['tramoDesdeNombre'] ?? '').toString(),
        tramoDesdeLat: _asDouble(m['tramoDesdeLat']) ?? 0,
        tramoDesdeLng: _asDouble(m['tramoDesdeLng']) ?? 0,
        puntoId: (m['puntoId'] ?? '').toString(),
        puntoNombre: (m['puntoNombre'] ?? '').toString(),
        puntoDireccion: (m['puntoDireccion'] ?? '').toString(),
        puntoLat: _asDouble(m['puntoLat']) ?? 0,
        puntoLng: _asDouble(m['puntoLng']) ?? 0,
        distanciaKm: _asDouble(m['distanciaKm']) ?? 0,
        duracionTraficoMin: _asDouble(m['duracionTraficoMin']) ?? 0,
        duracionSinTraficoMin: _asDouble(m['duracionSinTraficoMin']),
        demoraTraficoMin: _asDouble(m['demoraTraficoMin']),
        diferenciaEsperadoMin: _asDouble(m['diferenciaEsperadoMin']),
        duracionAcumuladaMin: _asDouble(m['duracionAcumuladaMin']) ?? 0,
        distanciaAcumuladaKm: _asDouble(m['distanciaAcumuladaKm']) ?? 0,
        // Los registros previos al modelo por rutas no traen acumulado: se
        // cae al tramo, que en ese esquema era el viaje directo completo.
        minutosEnRutaAlLlegar: _asDouble(m['minutosEnRutaAlLlegar']) ??
            _asDouble(m['duracionAcumuladaMin']) ??
            _asDouble(m['duracionTraficoMin']) ??
            0,
        minutosPorParada: (m['minutosPorParada'] as num?)?.toInt() ?? 0,
        horaSalidaTramoTxt: (m['horaSalidaTramoTxt'] ?? '').toString(),
        horaLlegadaTxt: (m['horaLlegadaTxt'] ?? '').toString(),
        comida: (m['comida'] ?? '').toString(),
        ventanaHasta: (m['ventanaHasta'] ?? '').toString(),
        dentroDeVentana: m['dentroDeVentana'] as bool?,
        minutosFueraVentana:
            (m['minutosFueraVentana'] as num?)?.toInt() ?? 0,
        riesgoTramo: (m['riesgoTramo'] ?? '').toString(),
        rutaPrincipal: (m['rutaPrincipal'] ?? '').toString(),
        rutaAlterna: (m['rutaAlterna'] ?? '').toString(),
        estadoTrafico: (m['estadoTrafico'] ?? '').toString(),
        riesgo: (m['riesgo'] ?? '').toString(),
        alerta: m['alerta'] as bool? ?? false,
        fuente: (m['fuente'] ?? '').toString(),
        incidentes: MovIncidentesRuta.fromMap(
          (m['incidentes'] as Map?)?.cast<String, dynamic>(),
        ),
        obrasOficiales: MovObrasRuta.fromMap(
          (m['obrasOficiales'] as Map?)?.cast<String, dynamic>(),
        ),
        requestParams: ((m['requestParams'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v)),
        apiRawResponse: (m['apiRawResponse'] ?? '').toString(),
        creadoPor: (m['creadoPor'] ?? '').toString(),
        observaciones: (m['observaciones'] ?? '').toString(),
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
      );

  /// "1 h 42 min" para tablas y reportes.
  static String formatoMin(double? minutos) {
    if (minutos == null) return '—';
    final total = minutos.round();
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0) return '$m min';
    return '$h h $m min';
  }

  /// "Ruta 3 · parada 2 de 3"
  String get posicionTexto => rutaCodigo.isEmpty
      ? ''
      : '$rutaCodigo · parada $ordenParada de $totalParadasRuta';

  /// Desde dónde salió el tramo (planta o parada anterior).
  String get tramoTexto => tramoDesdeNombre.isEmpty
      ? puntoNombre
      : '$tramoDesdeNombre → $puntoNombre';

  /// "06:00 → 06:38" (sale hacia la parada → llega). Es lo que hace visible
  /// que los tramos van encadenados y no todos a la hora de la franja.
  String get horarioTramoTexto =>
      horaSalidaTramoTxt.isEmpty || horaLlegadaTxt.isEmpty
      ? ''
      : '$horaSalidaTramoTxt → $horaLlegadaTxt';

  bool get llegaTarde => dentroDeVentana == false;

  /// "Llega 06:38 · dentro de la ventana de Desayuno (hasta 08:00)".
  String get ventanaTexto {
    if (dentroDeVentana == null || ventanaHasta.isEmpty) {
      return comida == kMovComidaFuera
          ? 'Corrida de control (no corresponde a una comida)'
          : '—';
    }
    final base = 'Llega $horaLlegadaTxt · ${movComidaLabel(comida)} '
        'cierra $ventanaHasta';
    return dentroDeVentana!
        ? '$base · A TIEMPO'
        : '$base · TARDE por $minutosFueraVentana min';
  }

  /// Tiempo total en ruta al llegar — el que define el riesgo.
  String get acumuladoTexto =>
      ok ? formatoMin(minutosEnRutaAlLlegar) : '—';

  String get duracionTexto => ok ? formatoMin(duracionTraficoMin) : '—';
  String get duracionSinTraficoTexto =>
      ok ? formatoMin(duracionSinTraficoMin) : '—';
  String get demoraTexto => ok ? formatoMin(demoraTraficoMin) : '—';

  /// Diferencia con signo: "+12 min" (peor que lo esperado) o
  /// "−5 min" (mejor que lo esperado). Cae al cálculo en vivo si el documento
  /// es anterior a que se guardara el campo.
  double? get diferenciaCalculada {
    if (diferenciaEsperadoMin != null) return diferenciaEsperadoMin;
    if (duracionSinTraficoMin == null) return null;
    return duracionTraficoMin - duracionSinTraficoMin!;
  }

  String get diferenciaTexto {
    final d = ok ? diferenciaCalculada : null;
    if (d == null) return '—';
    final m = d.round();
    if (m == 0) return 'igual';
    return m > 0 ? '+$m min' : '−${m.abs()} min';
  }

  /// true = el trayecto tardó MÁS de lo calculado (hay congestión real).
  bool get peorQueEsperado => (diferenciaCalculada ?? 0) > 0;
}

// ══════════════════════════════════════════════════════════════════════════════
// MovRunDoc — TBL_RUTAS_MOV_RUNS (corridas: candado + bitácora)
// ══════════════════════════════════════════════════════════════════════════════

class MovRunDoc {
  final String id;
  final String empresaId;
  final String tipo; // programada | manual
  final String estado; // pendiente | ejecutando | ok | parcial | error | omitida
  final String fecha;
  final String hora;
  final int weekday;
  final String escenario;
  final int totalPuntos;
  final int exitosos;
  final int fallidos;
  final int alertas;
  final String errorMsg;
  final String disparadoPor;
  final String fuente;
  final Timestamp? inicioAt;
  final Timestamp? finAt;
  final int duracionMs;
  final Timestamp createdAt;

  const MovRunDoc({
    this.id = '',
    required this.empresaId,
    this.tipo = '',
    this.estado = '',
    this.fecha = '',
    this.hora = '',
    this.weekday = 0,
    this.escenario = '',
    this.totalPuntos = 0,
    this.exitosos = 0,
    this.fallidos = 0,
    this.alertas = 0,
    this.errorMsg = '',
    this.disparadoPor = '',
    this.fuente = '',
    this.inicioAt,
    this.finAt,
    this.duracionMs = 0,
    required this.createdAt,
  });

  factory MovRunDoc.fromMap(String id, Map<String, dynamic> m) => MovRunDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        tipo: (m['tipo'] ?? '').toString(),
        estado: (m['estado'] ?? '').toString(),
        fecha: (m['fecha'] ?? '').toString(),
        hora: (m['hora'] ?? '').toString(),
        weekday: (m['weekday'] as num?)?.toInt() ?? 0,
        escenario: (m['escenario'] ?? '').toString(),
        totalPuntos: (m['totalPuntos'] as num?)?.toInt() ?? 0,
        exitosos: (m['exitosos'] as num?)?.toInt() ?? 0,
        fallidos: (m['fallidos'] as num?)?.toInt() ?? 0,
        alertas: (m['alertas'] as num?)?.toInt() ?? 0,
        errorMsg: (m['errorMsg'] ?? '').toString(),
        disparadoPor: (m['disparadoPor'] ?? '').toString(),
        fuente: (m['fuente'] ?? '').toString(),
        inicioAt: m['inicioAt'] as Timestamp?,
        finAt: m['finAt'] as Timestamp?,
        duracionMs: (m['duracionMs'] as num?)?.toInt() ?? 0,
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
      );
}

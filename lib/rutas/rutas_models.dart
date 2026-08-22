// lib/rutas/rutas_models.dart
//
// Modelo de datos del módulo RUTAS (logística de distribución + evidencia
// fotográfica georreferenciada). Sigue el patrón del proyecto:
//   - fromMap(id, m) / toMap() / copyWith()
//   - todo scoped por empresaId
//   - createdAt como Timestamp de cliente (nunca serverTimestamp en createdAt)
//   - updatedAt con serverTimestamp() en toMap()

import 'package:cloud_firestore/cloud_firestore.dart';

// ══════════════════════════════════════════════════════════════════════════════
// CONSTANTES
// ══════════════════════════════════════════════════════════════════════════════

/// AppId canónico del módulo (registrar en TBL_APPS como {empresaId}_rutasdashboard).
const String kRutasAppId = 'rutasdashboard';

/// Roles del módulo Rutas.
/// - conductor: solo toma y sube la foto de SU ruta del día (móvil).
/// - calidad: revisa, aprueba/rechaza, informes y ZIP (web).
/// - admin: rutas, direcciones, asignación de personal, ventanas y ciclo (web).
/// - admin_calidad: une administración y revisión de calidad en un solo perfil.
/// - desarrollador: perfil de pruebas; permite entrar como admin/calidad/conductor.
/// El rol global 'desarrollador' también ve y puede todo (bypass en AccessGuard).
const String kRutasRolConductor = 'conductor';
const String kRutasRolCalidad = 'calidad';
const String kRutasRolAdmin = 'admin';
const String kRutasRolAdminCalidad = 'admin_calidad';
const String kRutasRolDesarrollador = 'desarrollador';

const List<String> kRutasRoles = [
  kRutasRolConductor,
  kRutasRolCalidad,
  kRutasRolAdmin,
  kRutasRolAdminCalidad,
  kRutasRolDesarrollador,
];

const Map<String, String> kRutasRolLabels = {
  kRutasRolConductor: 'Conductor (toma evidencia)',
  kRutasRolCalidad: 'Calidad (revisa y aprueba)',
  kRutasRolAdmin: 'Administrador (rutas y personal)',
  kRutasRolAdminCalidad: 'Administrador + Calidad',
  kRutasRolDesarrollador: 'Desarrollador (prueba todos los perfiles)',
};

/// Tiempos de comida, en el ORDEN de secuencia obligatoria por establecimiento.
const String kComidaDesayuno = 'Desayuno';
const String kComidaAlmuerzo = 'Almuerzo';
const String kComidaCena = 'Cena + Refrigerio';

const List<String> kComidasOrden = [
  kComidaDesayuno,
  kComidaAlmuerzo,
  kComidaCena,
];

/// Estados de revisión de una evidencia.
const String kEvidPendiente = 'pendiente';
const String kEvidAprobada = 'aprobada';
const String kEvidRechazada = 'rechazada';

const List<String> kEvidEstados = [
  kEvidPendiente,
  kEvidAprobada,
  kEvidRechazada,
];

const Map<String, String> kEvidEstadoLabels = {
  kEvidPendiente: 'Pendiente',
  kEvidAprobada: 'Aprobada',
  kEvidRechazada: 'Rechazada',
};

/// Cantidad de menús del ciclo rotativo.
const int kMenuCount = 21;

/// Radio (m) por defecto para considerar que la captura ocurrió "en el establecimiento".
const int kRadioValidacionMetrosDefault = 150;

/// Origen operativo por defecto. No es un establecimiento ni un destino de ruta.
const String kRutaOrigenNombreDefault = 'Centro de operaciones';
const String kRutaOrigenDireccionDefault = 'Cra. 69 #79-11, Bogota';
const double kRutaOrigenLatDefault = 4.63322;
const double kRutaOrigenLngDefault = -74.19212;

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaStop — establecimiento/destino incrustado en RutaDoc.stops[]
// ══════════════════════════════════════════════════════════════════════════════

class RutaStop {
  final String nombre;
  final String direccionRaw;
  final String direccionLimpia;

  /// Geocodificación PERSISTIDA (se calcula una sola vez, no en cada arranque).
  final double? lat;
  final double? lng;
  final int orden;
  final double? distanciaCentroKm;
  final String rangoDistancia;

  const RutaStop({
    required this.nombre,
    this.direccionRaw = '',
    this.direccionLimpia = '',
    this.lat,
    this.lng,
    this.orden = 0,
    this.distanciaCentroKm,
    this.rangoDistancia = '',
  });

  bool get geocodificada => lat != null && lng != null;

  String get direccionVisible =>
      direccionLimpia.trim().isNotEmpty ? direccionLimpia : direccionRaw;

  factory RutaStop.fromMap(Map<String, dynamic> m) => RutaStop(
    // 'raw'/'name' son los nombres del modelo legacy de FYC; se aceptan al leer.
    nombre: (m['nombre'] ?? m['name'] ?? '').toString(),
    direccionRaw: (m['direccionRaw'] ?? m['raw'] ?? '').toString(),
    direccionLimpia: (m['direccionLimpia'] ?? '').toString(),
    lat: (m['lat'] as num?)?.toDouble(),
    lng: (m['lng'] as num?)?.toDouble(),
    orden: (m['orden'] as num?)?.toInt() ?? 0,
    distanciaCentroKm: _asDouble(
      m['distanciaCentroKm'] ??
          m['distanciaKm'] ??
          m['distanciaLineaRectaKm'] ??
          m['distanceKm'],
    ),
    rangoDistancia: (m['rangoDistancia'] ?? m['rango'] ?? '').toString(),
  );

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'direccionRaw': direccionRaw,
    'direccionLimpia': direccionLimpia,
    'lat': lat,
    'lng': lng,
    'orden': orden,
    'distanciaCentroKm': distanciaCentroKm,
    'rangoDistancia': rangoDistancia,
  };

  RutaStop copyWith({
    String? nombre,
    String? direccionRaw,
    String? direccionLimpia,
    double? lat,
    double? lng,
    int? orden,
    double? distanciaCentroKm,
    String? rangoDistancia,
    bool clearGeo = false,
  }) => RutaStop(
    nombre: nombre ?? this.nombre,
    direccionRaw: direccionRaw ?? this.direccionRaw,
    direccionLimpia: direccionLimpia ?? this.direccionLimpia,
    lat: clearGeo ? null : (lat ?? this.lat),
    lng: clearGeo ? null : (lng ?? this.lng),
    orden: orden ?? this.orden,
    distanciaCentroKm: distanciaCentroKm ?? this.distanciaCentroKm,
    rangoDistancia: rangoDistancia ?? this.rangoDistancia,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaEstablecimientoDoc — colección TBL_RUTAS_ESTABLECIMIENTOS
// Maestro de destinos que luego se combinan en TBL_RUTAS.
// ══════════════════════════════════════════════════════════════════════════════

class RutaEstablecimientoDoc {
  final String id;
  final String empresaId;
  final String nombre;
  final String direccionRaw;
  final String direccionLimpia;
  final double? lat;
  final double? lng;
  final double? distanciaCentroKm;
  final String rangoDistancia;
  final bool activo;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const RutaEstablecimientoDoc({
    this.id = '',
    required this.empresaId,
    required this.nombre,
    this.direccionRaw = '',
    this.direccionLimpia = '',
    this.lat,
    this.lng,
    this.distanciaCentroKm,
    this.rangoDistancia = '',
    this.activo = true,
    required this.createdAt,
    this.updatedAt,
  });

  bool get geocodificada => lat != null && lng != null;

  String get direccionVisible =>
      direccionLimpia.trim().isNotEmpty ? direccionLimpia : direccionRaw;

  RutaStop toStop({int orden = 0}) => RutaStop(
    nombre: nombre,
    direccionRaw: direccionRaw,
    direccionLimpia: direccionLimpia,
    lat: lat,
    lng: lng,
    orden: orden,
    distanciaCentroKm: distanciaCentroKm,
    rangoDistancia: rangoDistancia,
  );

  factory RutaEstablecimientoDoc.fromStop({
    String id = '',
    required String empresaId,
    required RutaStop stop,
    bool activo = true,
    Timestamp? createdAt,
  }) => RutaEstablecimientoDoc(
    id: id,
    empresaId: empresaId,
    nombre: stop.nombre,
    direccionRaw: stop.direccionRaw,
    direccionLimpia: stop.direccionLimpia,
    lat: stop.lat,
    lng: stop.lng,
    distanciaCentroKm: stop.distanciaCentroKm,
    rangoDistancia: stop.rangoDistancia,
    activo: activo,
    createdAt: createdAt ?? Timestamp.now(),
  );

  factory RutaEstablecimientoDoc.fromMap(String id, Map<String, dynamic> m) =>
      RutaEstablecimientoDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        nombre: (m['nombre'] ?? m['name'] ?? '').toString(),
        direccionRaw: (m['direccionRaw'] ?? m['raw'] ?? '').toString(),
        direccionLimpia: (m['direccionLimpia'] ?? '').toString(),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        distanciaCentroKm: _asDouble(
          m['distanciaCentroKm'] ??
              m['distanciaKm'] ??
              m['distanciaLineaRectaKm'] ??
              m['distanceKm'],
        ),
        rangoDistancia: (m['rangoDistancia'] ?? m['rango'] ?? '').toString(),
        activo: m['activo'] as bool? ?? true,
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
        updatedAt: m['updatedAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'nombre': nombre,
    'direccionRaw': direccionRaw,
    'direccionLimpia': direccionLimpia,
    'lat': lat,
    'lng': lng,
    'distanciaCentroKm': distanciaCentroKm,
    'rangoDistancia': rangoDistancia,
    'activo': activo,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  RutaEstablecimientoDoc copyWith({
    String? id,
    String? empresaId,
    String? nombre,
    String? direccionRaw,
    String? direccionLimpia,
    double? lat,
    double? lng,
    double? distanciaCentroKm,
    String? rangoDistancia,
    bool? activo,
    Timestamp? createdAt,
    Timestamp? updatedAt,
    bool clearGeo = false,
  }) => RutaEstablecimientoDoc(
    id: id ?? this.id,
    empresaId: empresaId ?? this.empresaId,
    nombre: nombre ?? this.nombre,
    direccionRaw: direccionRaw ?? this.direccionRaw,
    direccionLimpia: direccionLimpia ?? this.direccionLimpia,
    lat: clearGeo ? null : (lat ?? this.lat),
    lng: clearGeo ? null : (lng ?? this.lng),
    distanciaCentroKm: distanciaCentroKm ?? this.distanciaCentroKm,
    rangoDistancia: rangoDistancia ?? this.rangoDistancia,
    activo: activo ?? this.activo,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaDoc — colección TBL_RUTAS (rutas = solo direcciones; sin conductor fijo)
// ══════════════════════════════════════════════════════════════════════════════

class RutaDoc {
  final String id;
  final String empresaId;
  final String codigo; // p.ej. "Ruta 1"
  final List<RutaStop> stops;
  final bool activa;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const RutaDoc({
    this.id = '',
    required this.empresaId,
    required this.codigo,
    this.stops = const [],
    this.activa = true,
    required this.createdAt,
    this.updatedAt,
  });

  /// Número de ruta extraído del código (para ordenar). 9999 si no hay dígitos.
  int get numero =>
      int.tryParse(codigo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;

  factory RutaDoc.fromMap(String id, Map<String, dynamic> m) => RutaDoc(
    id: id,
    empresaId: (m['empresaId'] ?? '').toString(),
    codigo: (m['codigo'] ?? m['title'] ?? '').toString(),
    stops: ((m['stops'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => RutaStop.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
    activa: m['activa'] as bool? ?? true,
    createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
    updatedAt: m['updatedAt'] as Timestamp?,
  );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'codigo': codigo,
    'stops': stops.map((s) => s.toMap()).toList(),
    'activa': activa,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  RutaDoc copyWith({
    String? id,
    String? empresaId,
    String? codigo,
    List<RutaStop>? stops,
    bool? activa,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) => RutaDoc(
    id: id ?? this.id,
    empresaId: empresaId ?? this.empresaId,
    codigo: codigo ?? this.codigo,
    stops: stops ?? this.stops,
    activa: activa ?? this.activa,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaUbicacionDoc — última ubicación conocida del conductor para centro de control
// ══════════════════════════════════════════════════════════════════════════════

class RutaUbicacionDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String rutaId;
  final String rutaCodigo;
  final String conductorCedula;
  final String conductorNombre;
  final String vehiculo;
  final String paradaNombre;
  final double lat;
  final double lng;
  final double? precisionMetros;
  final String direccion;
  final Timestamp updatedAt;

  const RutaUbicacionDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    this.rutaId = '',
    this.rutaCodigo = '',
    this.conductorCedula = '',
    this.conductorNombre = '',
    this.vehiculo = '',
    this.paradaNombre = '',
    required this.lat,
    required this.lng,
    this.precisionMetros,
    this.direccion = '',
    required this.updatedAt,
  });

  factory RutaUbicacionDoc.fromMap(String id, Map<String, dynamic> m) =>
      RutaUbicacionDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        userId: (m['userId'] ?? '').toString(),
        rutaId: (m['rutaId'] ?? '').toString(),
        rutaCodigo: (m['rutaCodigo'] ?? '').toString(),
        conductorCedula: (m['conductorCedula'] ?? '').toString(),
        conductorNombre: (m['conductorNombre'] ?? '').toString(),
        vehiculo: (m['vehiculo'] ?? '').toString(),
        paradaNombre: (m['paradaNombre'] ?? '').toString(),
        lat: _asDouble(m['lat']) ?? 0,
        lng: _asDouble(m['lng']) ?? 0,
        precisionMetros: _asDouble(m['precisionMetros']),
        direccion: (m['direccion'] ?? '').toString(),
        updatedAt: m['updatedAt'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'userId': userId,
    'rutaId': rutaId,
    'rutaCodigo': rutaCodigo,
    'conductorCedula': conductorCedula,
    'conductorNombre': conductorNombre,
    'vehiculo': vehiculo,
    'paradaNombre': paradaNombre,
    'lat': lat,
    'lng': lng,
    'precisionMetros': precisionMetros,
    'direccion': direccion,
    'updatedAt': updatedAt,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaAsignacionDoc — colección TBL_RUTAS_ASIGNACIONES
// Quién maneja qué ruta y desde cuándo. Cada cambio = histórico (cierra la
// anterior con vigenteHasta y abre una nueva). Conductor/ayudante son USUARIOS.
// ══════════════════════════════════════════════════════════════════════════════

class RutaAsignacionDoc {
  final String id;
  final String empresaId;
  final String rutaId;
  final String rutaCodigo;
  final String conductorCedula;
  final String conductorNombre;
  final String ayudanteCedula;
  final String ayudanteNombre;
  final String ayudante2Cedula;
  final String ayudante2Nombre;
  final String vehiculo;

  /// true = asignación vigente (vigenteHasta == null).
  final bool activa;
  final Timestamp vigenteDesde;
  final Timestamp? vigenteHasta;
  final String asignadoPor;
  final Timestamp createdAt;

  const RutaAsignacionDoc({
    this.id = '',
    required this.empresaId,
    required this.rutaId,
    this.rutaCodigo = '',
    this.conductorCedula = '',
    this.conductorNombre = '',
    this.ayudanteCedula = '',
    this.ayudanteNombre = '',
    this.ayudante2Cedula = '',
    this.ayudante2Nombre = '',
    this.vehiculo = '',
    this.activa = true,
    required this.vigenteDesde,
    this.vigenteHasta,
    this.asignadoPor = '',
    required this.createdAt,
  });

  factory RutaAsignacionDoc.fromMap(String id, Map<String, dynamic> m) =>
      RutaAsignacionDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        rutaId: (m['rutaId'] ?? '').toString(),
        rutaCodigo: (m['rutaCodigo'] ?? '').toString(),
        conductorCedula: (m['conductorCedula'] ?? '').toString(),
        conductorNombre: (m['conductorNombre'] ?? '').toString(),
        ayudanteCedula: (m['ayudanteCedula'] ?? '').toString(),
        ayudanteNombre: (m['ayudanteNombre'] ?? '').toString(),
        ayudante2Cedula: (m['ayudante2Cedula'] ?? '').toString(),
        ayudante2Nombre: (m['ayudante2Nombre'] ?? '').toString(),
        vehiculo: (m['vehiculo'] ?? '').toString(),
        activa: m['activa'] as bool? ?? (m['vigenteHasta'] == null),
        vigenteDesde: m['vigenteDesde'] as Timestamp? ?? Timestamp.now(),
        vigenteHasta: m['vigenteHasta'] as Timestamp?,
        asignadoPor: (m['asignadoPor'] ?? '').toString(),
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'rutaId': rutaId,
    'rutaCodigo': rutaCodigo,
    'conductorCedula': conductorCedula,
    'conductorNombre': conductorNombre,
    'ayudanteCedula': ayudanteCedula,
    'ayudanteNombre': ayudanteNombre,
    'ayudante2Cedula': ayudante2Cedula,
    'ayudante2Nombre': ayudante2Nombre,
    'vehiculo': vehiculo,
    'activa': activa,
    'vigenteDesde': vigenteDesde,
    'vigenteHasta': vigenteHasta,
    'asignadoPor': asignadoPor,
    'createdAt': createdAt,
  };

  RutaAsignacionDoc copyWith({
    String? id,
    String? empresaId,
    String? rutaId,
    String? rutaCodigo,
    String? conductorCedula,
    String? conductorNombre,
    String? ayudanteCedula,
    String? ayudanteNombre,
    String? ayudante2Cedula,
    String? ayudante2Nombre,
    String? vehiculo,
    bool? activa,
    Timestamp? vigenteDesde,
    Timestamp? vigenteHasta,
    String? asignadoPor,
    Timestamp? createdAt,
  }) => RutaAsignacionDoc(
    id: id ?? this.id,
    empresaId: empresaId ?? this.empresaId,
    rutaId: rutaId ?? this.rutaId,
    rutaCodigo: rutaCodigo ?? this.rutaCodigo,
    conductorCedula: conductorCedula ?? this.conductorCedula,
    conductorNombre: conductorNombre ?? this.conductorNombre,
    ayudanteCedula: ayudanteCedula ?? this.ayudanteCedula,
    ayudanteNombre: ayudanteNombre ?? this.ayudanteNombre,
    ayudante2Cedula: ayudante2Cedula ?? this.ayudante2Cedula,
    ayudante2Nombre: ayudante2Nombre ?? this.ayudante2Nombre,
    vehiculo: vehiculo ?? this.vehiculo,
    activa: activa ?? this.activa,
    vigenteDesde: vigenteDesde ?? this.vigenteDesde,
    vigenteHasta: vigenteHasta ?? this.vigenteHasta,
    asignadoPor: asignadoPor ?? this.asignadoPor,
    createdAt: createdAt ?? this.createdAt,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// VentanaComida — rango horario "HH:mm" en que aplica un tiempo de comida
// ══════════════════════════════════════════════════════════════════════════════

class VentanaComida {
  final String desde; // "HH:mm"
  final String hasta; // "HH:mm"

  const VentanaComida({required this.desde, required this.hasta});

  factory VentanaComida.fromMap(Map<String, dynamic> m) => VentanaComida(
    desde: (m['desde'] ?? '00:00').toString(),
    hasta: (m['hasta'] ?? '23:59').toString(),
  );

  Map<String, dynamic> toMap() => {'desde': desde, 'hasta': hasta};
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaConfigDoc — colección TBL_RUTAS_CONFIG (docId = empresaId)
// Configuración por empresa: fecha base del ciclo de menú, ventanas de comida
// y radio de validación de distancia. Lo administra el rol admin.
// ══════════════════════════════════════════════════════════════════════════════

class RutaConfigDoc {
  final String empresaId;

  /// Fecha del "Menú 1". El ciclo de 21 días rota a partir de aquí.
  final Timestamp cicloFechaBase;

  /// comida -> ventana horaria. Claves: kComidaDesayuno/Almuerzo/Cena.
  final Map<String, VentanaComida> ventanas;
  final int radioValidacionMetros;
  final String origenNombre;
  final String origenDireccion;
  final double origenLat;
  final double origenLng;
  final Timestamp? updatedAt;

  const RutaConfigDoc({
    required this.empresaId,
    required this.cicloFechaBase,
    required this.ventanas,
    this.radioValidacionMetros = kRadioValidacionMetrosDefault,
    this.origenNombre = kRutaOrigenNombreDefault,
    this.origenDireccion = kRutaOrigenDireccionDefault,
    this.origenLat = kRutaOrigenLatDefault,
    this.origenLng = kRutaOrigenLngDefault,
    this.updatedAt,
  });

  VentanaComida ventanaDe(String comida) =>
      ventanas[comida] ?? const VentanaComida(desde: '00:00', hasta: '23:59');

  /// Configuración por defecto cuando la empresa aún no tiene doc en Firestore.
  factory RutaConfigDoc.defaults(String empresaId) => RutaConfigDoc(
    empresaId: empresaId,
    cicloFechaBase: Timestamp.fromDate(DateTime(2025, 1, 1)),
    ventanas: const {
      kComidaDesayuno: VentanaComida(desde: '04:00', hasta: '10:00'),
      kComidaAlmuerzo: VentanaComida(desde: '10:00', hasta: '15:00'),
      kComidaCena: VentanaComida(desde: '15:00', hasta: '23:59'),
    },
    radioValidacionMetros: kRadioValidacionMetrosDefault,
    origenNombre: kRutaOrigenNombreDefault,
    origenDireccion: kRutaOrigenDireccionDefault,
    origenLat: kRutaOrigenLatDefault,
    origenLng: kRutaOrigenLngDefault,
  );

  factory RutaConfigDoc.fromMap(String id, Map<String, dynamic> m) {
    final rawVentanas = (m['ventanas'] as Map?)?.cast<String, dynamic>() ?? {};
    final ventanas = <String, VentanaComida>{};
    for (final comida in kComidasOrden) {
      final raw = rawVentanas[comida];
      if (raw is Map) {
        ventanas[comida] = VentanaComida.fromMap(
          Map<String, dynamic>.from(raw),
        );
      } else {
        ventanas[comida] = RutaConfigDoc.defaults(id).ventanaDe(comida);
      }
    }
    return RutaConfigDoc(
      empresaId: (m['empresaId'] ?? id).toString(),
      cicloFechaBase:
          m['cicloFechaBase'] as Timestamp? ??
          Timestamp.fromDate(DateTime(2025, 1, 1)),
      ventanas: ventanas,
      radioValidacionMetros:
          (m['radioValidacionMetros'] as num?)?.toInt() ??
          kRadioValidacionMetrosDefault,
      origenNombre: (m['origenNombre'] ?? kRutaOrigenNombreDefault).toString(),
      origenDireccion: (m['origenDireccion'] ?? kRutaOrigenDireccionDefault)
          .toString(),
      origenLat: _asDouble(m['origenLat']) ?? kRutaOrigenLatDefault,
      origenLng: _asDouble(m['origenLng']) ?? kRutaOrigenLngDefault,
      updatedAt: m['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'cicloFechaBase': cicloFechaBase,
    'ventanas': ventanas.map((k, v) => MapEntry(k, v.toMap())),
    'radioValidacionMetros': radioValidacionMetros,
    'origenNombre': origenNombre.trim(),
    'origenDireccion': origenDireccion.trim(),
    'origenLat': origenLat,
    'origenLng': origenLng,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  RutaConfigDoc copyWith({
    String? empresaId,
    Timestamp? cicloFechaBase,
    Map<String, VentanaComida>? ventanas,
    int? radioValidacionMetros,
    String? origenNombre,
    String? origenDireccion,
    double? origenLat,
    double? origenLng,
    Timestamp? updatedAt,
  }) => RutaConfigDoc(
    empresaId: empresaId ?? this.empresaId,
    cicloFechaBase: cicloFechaBase ?? this.cicloFechaBase,
    ventanas: ventanas ?? this.ventanas,
    radioValidacionMetros: radioValidacionMetros ?? this.radioValidacionMetros,
    origenNombre: origenNombre ?? this.origenNombre,
    origenDireccion: origenDireccion ?? this.origenDireccion,
    origenLat: origenLat ?? this.origenLat,
    origenLng: origenLng ?? this.origenLng,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaEvidenciaDoc — colección TBL_RUTAS_EVIDENCIAS
// Una evidencia por (ruta, fecha, parada, comida). DocId determinístico para que
// re-tomar reemplace y para imponer la secuencia desayuno→almuerzo→cena.
// ══════════════════════════════════════════════════════════════════════════════

class RutaEvidenciaDoc {
  final String id;
  final String empresaId;
  final String rutaId;
  final String rutaCodigo;

  /// "yyyy-MM-dd" (clave de día) + componentes para filtros server-side.
  final String fecha;
  final String year;
  final String month;
  final String day;

  final String comida;
  final int menuNumero;

  // Establecimiento/destino (copiado de la ruta al momento de la evidencia).
  final String paradaNombre;
  final String paradaDireccion;
  final double? paradaLat;
  final double? paradaLng;

  // Personal (copiado de la asignación vigente).
  final String conductorCedula;
  final String conductorNombre;
  final String ayudanteCedula;
  final String ayudanteNombre;
  final String ayudante2Cedula;
  final String ayudante2Nombre;
  final String vehiculo;

  // Geo de la CAPTURA (tomada al momento de la foto, no al abrir la app).
  final double? capturaLat;
  final double? capturaLng;
  final String capturaTexto;

  /// Distancia (m) entre la captura y el establecimiento. -1 si no se pudo calcular.
  final double distanciaMetros;

  // Archivos.
  final String storagePath;
  final String? downloadURL;
  final String? thumbPath;
  final String? thumbURL;

  // Revisión de calidad.
  final String estado; // pendiente | aprobada | rechazada
  final String revisadoPor;
  final Timestamp? revisadoEn;
  final String motivoRechazo;

  final String createdBy;
  final Timestamp createdAt;

  const RutaEvidenciaDoc({
    this.id = '',
    required this.empresaId,
    required this.rutaId,
    this.rutaCodigo = '',
    required this.fecha,
    this.year = '',
    this.month = '',
    this.day = '',
    required this.comida,
    this.menuNumero = 0,
    required this.paradaNombre,
    this.paradaDireccion = '',
    this.paradaLat,
    this.paradaLng,
    this.conductorCedula = '',
    this.conductorNombre = '',
    this.ayudanteCedula = '',
    this.ayudanteNombre = '',
    this.ayudante2Cedula = '',
    this.ayudante2Nombre = '',
    this.vehiculo = '',
    this.capturaLat,
    this.capturaLng,
    this.capturaTexto = '',
    this.distanciaMetros = -1,
    required this.storagePath,
    this.downloadURL,
    this.thumbPath,
    this.thumbURL,
    this.estado = kEvidPendiente,
    this.revisadoPor = '',
    this.revisadoEn,
    this.motivoRechazo = '',
    this.createdBy = '',
    required this.createdAt,
  });

  bool get pendiente => estado == kEvidPendiente;
  bool get aprobada => estado == kEvidAprobada;
  bool get rechazada => estado == kEvidRechazada;

  /// Distancia válida = se pudo medir y está dentro del radio configurado.
  bool dentroDeRadio(int radioMetros) =>
      distanciaMetros >= 0 && distanciaMetros <= radioMetros;

  factory RutaEvidenciaDoc.fromMap(String id, Map<String, dynamic> m) =>
      RutaEvidenciaDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        rutaId: (m['rutaId'] ?? '').toString(),
        rutaCodigo: (m['rutaCodigo'] ?? '').toString(),
        fecha: (m['fecha'] ?? '').toString(),
        year: (m['year'] ?? '').toString(),
        month: (m['month'] ?? '').toString(),
        day: (m['day'] ?? '').toString(),
        comida: (m['comida'] ?? '').toString(),
        menuNumero: (m['menuNumero'] as num?)?.toInt() ?? 0,
        paradaNombre: (m['paradaNombre'] ?? '').toString(),
        paradaDireccion: (m['paradaDireccion'] ?? '').toString(),
        paradaLat: (m['paradaLat'] as num?)?.toDouble(),
        paradaLng: (m['paradaLng'] as num?)?.toDouble(),
        conductorCedula: (m['conductorCedula'] ?? '').toString(),
        conductorNombre: (m['conductorNombre'] ?? '').toString(),
        ayudanteCedula: (m['ayudanteCedula'] ?? '').toString(),
        ayudanteNombre: (m['ayudanteNombre'] ?? '').toString(),
        ayudante2Cedula: (m['ayudante2Cedula'] ?? '').toString(),
        ayudante2Nombre: (m['ayudante2Nombre'] ?? '').toString(),
        vehiculo: (m['vehiculo'] ?? '').toString(),
        capturaLat: (m['capturaLat'] as num?)?.toDouble(),
        capturaLng: (m['capturaLng'] as num?)?.toDouble(),
        capturaTexto: (m['capturaTexto'] ?? '').toString(),
        distanciaMetros: (m['distanciaMetros'] as num?)?.toDouble() ?? -1,
        storagePath: (m['storagePath'] ?? '').toString(),
        downloadURL: m['downloadURL'] as String?,
        thumbPath: m['thumbPath'] as String?,
        thumbURL: m['thumbURL'] as String?,
        estado: (m['estado'] ?? kEvidPendiente).toString(),
        revisadoPor: (m['revisadoPor'] ?? '').toString(),
        revisadoEn: m['revisadoEn'] as Timestamp?,
        motivoRechazo: (m['motivoRechazo'] ?? '').toString(),
        createdBy: (m['createdBy'] ?? '').toString(),
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'rutaId': rutaId,
    'rutaCodigo': rutaCodigo,
    'fecha': fecha,
    'year': year,
    'month': month,
    'day': day,
    'comida': comida,
    'menuNumero': menuNumero,
    'paradaNombre': paradaNombre,
    'paradaDireccion': paradaDireccion,
    'paradaLat': paradaLat,
    'paradaLng': paradaLng,
    'conductorCedula': conductorCedula,
    'conductorNombre': conductorNombre,
    'ayudanteCedula': ayudanteCedula,
    'ayudanteNombre': ayudanteNombre,
    'ayudante2Cedula': ayudante2Cedula,
    'ayudante2Nombre': ayudante2Nombre,
    'vehiculo': vehiculo,
    'capturaLat': capturaLat,
    'capturaLng': capturaLng,
    'capturaTexto': capturaTexto,
    'distanciaMetros': distanciaMetros,
    'storagePath': storagePath,
    'downloadURL': downloadURL,
    'thumbPath': thumbPath,
    'thumbURL': thumbURL,
    'estado': estado,
    'revisadoPor': revisadoPor,
    'revisadoEn': revisadoEn,
    'motivoRechazo': motivoRechazo,
    'createdBy': createdBy,
    'createdAt': createdAt,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaResumenDiarioDoc — colección TBL_RUTAS_RESUMEN_DIARIO (solo lectura)
// Lo calcula una Cloud Function para informes baratos (sin fotos).
// ══════════════════════════════════════════════════════════════════════════════

class RutaResumenDiarioDoc {
  final String id;
  final String empresaId;
  final String fecha; // yyyy-MM-dd
  final String rutaId;
  final String rutaCodigo;
  final int puntosTotales;
  final int puntosCompletos;
  final int aprobadas;
  final int rechazadas;
  final int pendientes;
  final Timestamp? primeraEntrega;
  final Timestamp? ultimaEntrega;
  final int duracionMin;
  final double distanciaPromedio;

  const RutaResumenDiarioDoc({
    this.id = '',
    required this.empresaId,
    required this.fecha,
    required this.rutaId,
    this.rutaCodigo = '',
    this.puntosTotales = 0,
    this.puntosCompletos = 0,
    this.aprobadas = 0,
    this.rechazadas = 0,
    this.pendientes = 0,
    this.primeraEntrega,
    this.ultimaEntrega,
    this.duracionMin = 0,
    this.distanciaPromedio = 0,
  });

  factory RutaResumenDiarioDoc.fromMap(String id, Map<String, dynamic> m) =>
      RutaResumenDiarioDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        fecha: (m['fecha'] ?? '').toString(),
        rutaId: (m['rutaId'] ?? '').toString(),
        rutaCodigo: (m['rutaCodigo'] ?? '').toString(),
        puntosTotales: (m['puntosTotales'] as num?)?.toInt() ?? 0,
        puntosCompletos: (m['puntosCompletos'] as num?)?.toInt() ?? 0,
        aprobadas: (m['aprobadas'] as num?)?.toInt() ?? 0,
        rechazadas: (m['rechazadas'] as num?)?.toInt() ?? 0,
        pendientes: (m['pendientes'] as num?)?.toInt() ?? 0,
        primeraEntrega: m['primeraEntrega'] as Timestamp?,
        ultimaEntrega: m['ultimaEntrega'] as Timestamp?,
        duracionMin: (m['duracionMin'] as num?)?.toInt() ?? 0,
        distanciaPromedio: (m['distanciaPromedio'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'fecha': fecha,
    'rutaId': rutaId,
    'rutaCodigo': rutaCodigo,
    'puntosTotales': puntosTotales,
    'puntosCompletos': puntosCompletos,
    'aprobadas': aprobadas,
    'rechazadas': rechazadas,
    'pendientes': pendientes,
    'primeraEntrega': primeraEntrega,
    'ultimaEntrega': ultimaEntrega,
    'duracionMin': duracionMin,
    'distanciaPromedio': distanciaPromedio,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaVehiculoDoc — colección TBL_RUTAS_PLACAS (maestro de placas por empresa)
// ══════════════════════════════════════════════════════════════════════════════

class RutaVehiculoDoc {
  final String id;
  final String empresaId;
  final String placa;
  final String descripcion;
  final bool activo;
  final Timestamp createdAt;
  final Timestamp? updatedAt;
  final Timestamp? inactivatedAt;

  const RutaVehiculoDoc({
    this.id = '',
    required this.empresaId,
    required this.placa,
    this.descripcion = '',
    this.activo = true,
    required this.createdAt,
    this.updatedAt,
    this.inactivatedAt,
  });

  factory RutaVehiculoDoc.fromMap(String id, Map<String, dynamic> m) =>
      RutaVehiculoDoc(
        id: id,
        empresaId: (m['empresaId'] ?? '').toString(),
        placa: (m['placa'] ?? '').toString(),
        descripcion: (m['descripcion'] ?? '').toString(),
        activo: m['activo'] as bool? ?? true,
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
        updatedAt: m['updatedAt'] as Timestamp?,
        inactivatedAt: m['inactivatedAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'placa': placa.trim().toUpperCase(),
    'descripcion': descripcion.trim(),
    'activo': activo,
    'createdAt': createdAt,
    'inactivatedAt': inactivatedAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  RutaVehiculoDoc copyWith({
    String? id,
    String? empresaId,
    String? placa,
    String? descripcion,
    bool? activo,
    Timestamp? createdAt,
    Timestamp? updatedAt,
    Timestamp? inactivatedAt,
  }) => RutaVehiculoDoc(
    id: id ?? this.id,
    empresaId: empresaId ?? this.empresaId,
    placa: placa ?? this.placa,
    descripcion: descripcion ?? this.descripcion,
    activo: activo ?? this.activo,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    inactivatedAt: inactivatedAt ?? this.inactivatedAt,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RutaRolDoc — colección TBL_RUTAS_ROLES (docId = {empresaId}_{userId})
// ══════════════════════════════════════════════════════════════════════════════

class RutaRolDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String cedula;
  final String nombre;
  final String rol; // conductor | calidad | admin
  final Timestamp createdAt;

  const RutaRolDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    this.cedula = '',
    this.nombre = '',
    required this.rol,
    required this.createdAt,
  });

  factory RutaRolDoc.fromMap(String id, Map<String, dynamic> m) => RutaRolDoc(
    id: id,
    empresaId: (m['empresaId'] ?? '').toString(),
    userId: (m['userId'] ?? '').toString(),
    cedula: (m['cedula'] ?? '').toString(),
    nombre: (m['nombre'] ?? '').toString(),
    rol: (m['rol'] ?? '').toString(),
    createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
  );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'userId': userId,
    'cedula': cedula,
    'nombre': nombre,
    'rol': rol,
    'createdAt': createdAt,
  };
}

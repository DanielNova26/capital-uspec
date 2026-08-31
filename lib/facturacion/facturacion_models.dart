// lib/facturacion/facturacion_models.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constantes del módulo
// ─────────────────────────────────────────────────────────────────────────────

const String kFacAppId = 'facturaciondashboard';
const String kFacTaskOrigin = 'facturacion_observacion';

const String kRolFacturacion = 'facturacion';
const String kRolEstablecimiento = 'establecimiento';
const String kRolFacVisor = 'visor_fac';

const Set<String> kRolesFacGestion = {kRolFacturacion};
const Set<String> kRolesFacLectura = {kRolFacturacion, kRolFacVisor};

const List<String> kFacRoles = [
  kRolFacturacion,
  kRolEstablecimiento,
  kRolFacVisor,
];

const Map<String, String> kFacRoleLabels = {
  kRolFacturacion: 'Facturación',
  kRolEstablecimiento: 'Establecimiento',
  kRolFacVisor: 'Visor',
};

String normalizeFacRole(String? value) {
  final key = (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  switch (key) {
    case 'facturacion':
    case 'gestor_facturacion':
    case 'administrador_facturacion':
      return kRolFacturacion;
    case 'establecimiento':
    case 'usuario_establecimiento':
      return kRolEstablecimiento;
    case 'visor':
    case 'visor_fac':
    case 'solo_lectura':
    case 'consulta':
      return kRolFacVisor;
    default:
      return key;
  }
}

enum FacAccessMode {
  manager,
  viewer,
  establishment,
  missingEstablishment,
  invalidRole,
}

FacAccessMode resolveFacAccessMode(
  FacUserInfo info, {
  bool developerOverride = false,
}) {
  final role = normalizeFacRole(info.rol);
  // El override de desarrollador solo cubre cuentas sin configuración
  // funcional. Si Admin Dashboard asignó un rol explícito, se respeta para
  // poder operar y probar exactamente el flujo correspondiente.
  if (role.isEmpty) {
    return developerOverride ? FacAccessMode.manager : FacAccessMode.viewer;
  }
  if (role == kRolFacVisor) return FacAccessMode.viewer;
  if (role == kRolFacturacion) return FacAccessMode.manager;
  if (role == kRolEstablecimiento) {
    final estId = info.establecimientoId?.trim() ?? '';
    return estId.isEmpty
        ? FacAccessMode.missingEstablishment
        : FacAccessMode.establishment;
  }
  return FacAccessMode.invalidRole;
}

/// Resuelve el rol desde la misma estructura que administra Admin Dashboard.
/// Si existe un bloque para la empresa activa, ese bloque es autoritativo:
/// un rol vacío no debe heredar accidentalmente el rol global de otra empresa.
FacUserInfo resolveFacUserInfoFromData(
  Map<String, dynamic> data,
  String empresaId,
) {
  final detalle = data['empresasDetalle'];
  final rawScoped = detalle is Map ? detalle[empresaId] : null;
  final scoped = rawScoped is Map
      ? rawScoped.map((key, value) => MapEntry(key.toString(), value))
      : null;
  final hasCompanyScope = scoped != null;

  final role = normalizeFacRole(
    (hasCompanyScope ? scoped['rolFac'] : data['rolFac'])?.toString(),
  );
  final establecimientoId =
      (hasCompanyScope
              ? scoped['establecimientoFacId']
              : data['establecimientoFacId'])
          ?.toString()
          .trim() ??
      '';

  return FacUserInfo(
    rol: role,
    establecimientoId: establecimientoId.isEmpty ? null : establecimientoId,
  );
}

/// Catálogo histórico usado únicamente como semilla y compatibilidad.
/// La fuente operativa es TBL_FAC_OBLIGACIONES, separada por empresa.
const List<String> kFacDocumentos = [
  'Cuadro de Raciones',
  'Servicio del Agua',
  'Servicio del Gas',
  'Servicio de Energía',
  'Inventario',
  'Proyectos Productivos',
  'Contractuales',
  'Documentación HSE',
  'Paz y Salvo',
  'Nominas',
  'Seguridad Social',
];

String facObligacionCodigo(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');

class FacObligacion {
  final String id;
  final String empresaId;
  final String codigo;
  final String nombre;
  final String descripcion;
  final int orden;
  final bool enabled;
  final bool sistema;

  const FacObligacion({
    required this.id,
    required this.empresaId,
    required this.codigo,
    required this.nombre,
    this.descripcion = '',
    required this.orden,
    this.enabled = true,
    this.sistema = false,
  });

  factory FacObligacion.fromMap(String docId, Map<String, dynamic> data) {
    final nombre = (data['nombre'] ?? '').toString().trim();
    return FacObligacion(
      id: docId,
      empresaId: (data['empresaId'] ?? '').toString().trim(),
      codigo: (data['codigo'] ?? facObligacionCodigo(nombre)).toString().trim(),
      nombre: nombre,
      descripcion: (data['descripcion'] ?? '').toString().trim(),
      orden: (data['orden'] as num?)?.toInt() ?? 0,
      enabled: (data['enabled'] as bool?) ?? true,
      sistema: (data['sistema'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'codigo': codigo,
    'nombre': nombre,
    'descripcion': descripcion,
    'orden': orden,
    'enabled': enabled,
    'sistema': sistema,
  };

  FacObligacion copyWith({int? orden, bool? enabled, String? descripcion}) =>
      FacObligacion(
        id: id,
        empresaId: empresaId,
        codigo: codigo,
        nombre: nombre,
        descripcion: descripcion ?? this.descripcion,
        orden: orden ?? this.orden,
        enabled: enabled ?? this.enabled,
        sistema: sistema,
      );

  static List<FacObligacion> legacy(String empresaId) => [
    for (var index = 0; index < kFacDocumentos.length; index++)
      FacObligacion(
        id: '${empresaId}_${facObligacionCodigo(kFacDocumentos[index])}',
        empresaId: empresaId,
        codigo: facObligacionCodigo(kFacDocumentos[index]),
        nombre: kFacDocumentos[index],
        orden: index,
        sistema: true,
      ),
  ];
}

class FacAvanceObligacion {
  final FacObligacion obligacion;
  final int meta;
  final int cargados;
  final int noAplica;

  const FacAvanceObligacion({
    required this.obligacion,
    required this.meta,
    required this.cargados,
    required this.noAplica,
  });

  int get faltantes {
    final value = meta - cargados;
    return value < 0 ? 0 : value;
  }

  double get progreso => meta == 0 ? 1 : cargados / meta;
}

List<FacAvanceObligacion> calcularAvanceObligaciones(
  List<FacObligacion> obligaciones,
  List<FacProgresoEst> establecimientos,
) => [
  for (final obligacion in obligaciones)
    FacAvanceObligacion(
      obligacion: obligacion,
      meta: establecimientos.where((row) {
        return row.establecimiento.ignoredDocs[obligacion.nombre] != true;
      }).length,
      cargados: establecimientos.where((row) {
        final noAplica =
            row.establecimiento.ignoredDocs[obligacion.nombre] == true;
        return !noAplica && row.docSubido[obligacion.nombre] == true;
      }).length,
      noAplica: establecimientos.where((row) {
        return row.establecimiento.ignoredDocs[obligacion.nombre] == true;
      }).length,
    ),
];

/// Convierte el nombre de un documento al prefijo de Storage.
/// "Cuadro de Raciones" → "cuadro_de_raciones_"
String docToStoragePrefix(String doc) =>
    '${doc.replaceAll(' ', '_').toLowerCase()}_';

/// Meses en español (Title Case).
const List<String> kMeses = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

String calcularSiguienteMes(String mesAnio) {
  final parts = mesAnio.split('_');
  if (parts.length != 2) return mesAnio;
  final mesIdx = kMeses.indexWhere(
    (m) => m.toLowerCase() == parts[0].toLowerCase(),
  );
  if (mesIdx < 0) return mesAnio;
  final anio = int.tryParse(parts[1]) ?? DateTime.now().year;
  if (mesIdx == 11) return 'Enero_${anio + 1}';
  return '${kMeses[mesIdx + 1]}_$anio';
}

int? _facMesOrdinal(String value) {
  final parts = value.trim().split('_');
  if (parts.length != 2) return null;
  final mes = kMeses.indexWhere(
    (item) => item.toLowerCase() == parts.first.toLowerCase(),
  );
  final anio = int.tryParse(parts.last);
  if (mes < 0 || anio == null) return null;
  return anio * 12 + mes;
}

bool facMesEsValido(String value) => _facMesOrdinal(value) != null;

/// Se valida al elegir y de nuevo al guardar, por si pasó el plazo entretanto.
void validarFacFechaLimite(DateTime fecha, {DateTime? ahora}) {
  if (!fecha.isAfter(ahora ?? DateTime.now())) {
    throw ArgumentError(
      'La fecha y hora límite deben ser posteriores a la hora actual.',
    );
  }
}

int compareFacMesDesc(String a, String b) {
  final ordinalA = _facMesOrdinal(a);
  final ordinalB = _facMesOrdinal(b);
  if (ordinalA != null && ordinalB != null) {
    return ordinalB.compareTo(ordinalA);
  }
  if (ordinalA != null) return -1;
  if (ordinalB != null) return 1;
  return b.toLowerCase().compareTo(a.toLowerCase());
}

/// Convierte variantes como `junio_2026` y `JUNIO_2026` a una sola clave.
String normalizeFacMesKey(String value) {
  final trimmed = value.trim();
  final parts = trimmed.split('_');
  if (parts.length == 2) {
    final mes = kMeses.indexWhere(
      (item) => item.toLowerCase() == parts.first.toLowerCase(),
    );
    final anio = int.tryParse(parts.last);
    if (mes >= 0 && anio != null) return '${kMeses[mes]}_$anio';
  }
  return trimmed;
}

List<String> normalizeFacMesKeys(Iterable<String> values) {
  final unique = <String, String>{};
  for (final value in values) {
    final normalized = normalizeFacMesKey(value);
    if (normalized.isEmpty) continue;
    unique.putIfAbsent(normalized.toLowerCase(), () => normalized);
  }
  return unique.values.toList()..sort(compareFacMesDesc);
}

/// Etiqueta legible para UI. La clave interna conserva el formato Mes_Año
/// porque también identifica carpetas y registros históricos.
String facMesLabel(String value) {
  final trimmed = normalizeFacMesKey(value);
  final parts = trimmed.split('_');
  if (parts.length == 2) {
    final mes = kMeses.indexWhere(
      (item) => item.toLowerCase() == parts.first.toLowerCase(),
    );
    final anio = int.tryParse(parts.last);
    if (mes >= 0 && anio != null) return '${kMeses[mes]} $anio';
  }
  return trimmed.replaceAll('_', ' ');
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo: establecimiento con su configuración
// ─────────────────────────────────────────────────────────────────────────────

class FacEstablecimiento {
  final String id; // doc ID en TBL_FAC_ESTABLECIMIENTOS
  final String empresaId;
  final String nombre; // nombre display
  final String mes; // "Marzo_2025"
  final DateTime? fechaLimite;
  final Map<String, bool> ignoredDocs; // doc → true si ignorado
  final Map<String, DateTime?> deadlines; // doc → deadline específico

  const FacEstablecimiento({
    required this.id,
    required this.empresaId,
    required this.nombre,
    required this.mes,
    this.fechaLimite,
    this.ignoredDocs = const {},
    this.deadlines = const {},
  });

  DateTime? fechaLimiteDocumento(String doc) => deadlines[doc] ?? fechaLimite;

  factory FacEstablecimiento.fromMap(String docId, Map<String, dynamic> d) {
    final rawIgnored = d['ignoredDocs'] as Map<String, dynamic>? ?? {};
    final ignored = rawIgnored.map(
      (key, value) => MapEntry(key.toString(), value == true),
    );

    final rawDeadlines = d['deadlines'] as Map<String, dynamic>? ?? {};
    final deadlines = <String, DateTime?>{};
    for (final entry in rawDeadlines.entries) {
      final value = entry.value;
      deadlines[entry.key] = value is Timestamp ? value.toDate() : null;
    }

    DateTime? fechaLimite;
    final fl = d['fechaLimite'];
    if (fl is Timestamp) fechaLimite = fl.toDate();

    return FacEstablecimiento(
      id: docId,
      empresaId: (d['empresaId'] ?? '').toString(),
      nombre: (d['nombre'] ?? docId).toString(),
      mes: (d['mes'] ?? 'Sin asignar').toString(),
      fechaLimite: fechaLimite,
      ignoredDocs: ignored,
      deadlines: deadlines,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'nombre': nombre,
    'mes': mes,
    if (fechaLimite != null) 'fechaLimite': Timestamp.fromDate(fechaLimite!),
    'ignoredDocs': ignoredDocs,
    'deadlines': {
      for (final e in deadlines.entries)
        if (e.value != null) e.key: Timestamp.fromDate(e.value!),
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo: archivo subido en Storage
// ─────────────────────────────────────────────────────────────────────────────

class FacArchivo {
  final String nombre;
  final String fullPath;
  final String downloadUrl;

  const FacArchivo({
    required this.nombre,
    required this.fullPath,
    required this.downloadUrl,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo: revisión documental
// ─────────────────────────────────────────────────────────────────────────────

enum FacEstadoRevision { pendiente, aprobado, rechazado }

FacEstadoRevision parseFacEstadoRevision(Object? value) {
  switch ((value ?? '').toString().trim().toLowerCase()) {
    case 'aprobado':
    case 'aprobada':
      return FacEstadoRevision.aprobado;
    case 'rechazado':
    case 'rechazada':
      return FacEstadoRevision.rechazado;
    default:
      return FacEstadoRevision.pendiente;
  }
}

String facEstadoRevisionValue(FacEstadoRevision estado) => switch (estado) {
  FacEstadoRevision.pendiente => 'pendiente',
  FacEstadoRevision.aprobado => 'aprobado',
  FacEstadoRevision.rechazado => 'rechazado',
};

String facEstadoRevisionLabel(FacEstadoRevision estado) => switch (estado) {
  FacEstadoRevision.pendiente => 'Pendiente de revisión',
  FacEstadoRevision.aprobado => 'Aprobado',
  FacEstadoRevision.rechazado => 'Rechazado',
};

class FacRevision {
  final String id;
  final String empresaId;
  final String establecimientoId;
  final String establecimientoNombre;
  final String mes;
  final String docTipo;
  final FacEstadoRevision estado;
  final String motivo;
  final DateTime? fechaLimite;
  final String revisorId;
  final String revisorNombre;
  final String responsableId;
  final String responsableNombre;
  final String? tareaId;
  final int version;
  final String whatsappEstado;
  final DateTime? actualizadoAt;

  const FacRevision({
    required this.id,
    required this.empresaId,
    required this.establecimientoId,
    required this.establecimientoNombre,
    required this.mes,
    required this.docTipo,
    required this.estado,
    this.motivo = '',
    this.fechaLimite,
    this.revisorId = '',
    this.revisorNombre = '',
    this.responsableId = '',
    this.responsableNombre = '',
    this.tareaId,
    this.version = 0,
    this.whatsappEstado = '',
    this.actualizadoAt,
  });

  factory FacRevision.fromMap(String docId, Map<String, dynamic> data) {
    DateTime? date(Object? value) => value is Timestamp ? value.toDate() : null;
    return FacRevision(
      id: docId,
      empresaId: (data['empresaId'] ?? '').toString(),
      establecimientoId: (data['establecimientoId'] ?? '').toString(),
      establecimientoNombre: (data['establecimientoNombre'] ?? '').toString(),
      mes: normalizeFacMesKey((data['mes'] ?? '').toString()),
      docTipo: (data['docTipo'] ?? '').toString(),
      estado: parseFacEstadoRevision(data['estado']),
      motivo: (data['motivo'] ?? '').toString(),
      fechaLimite: date(data['fechaLimite']),
      revisorId: (data['revisorId'] ?? '').toString(),
      revisorNombre: (data['revisorNombre'] ?? '').toString(),
      responsableId: (data['responsableId'] ?? '').toString(),
      responsableNombre: (data['responsableNombre'] ?? '').toString(),
      tareaId: data['tareaId']?.toString(),
      version: (data['version'] as num?)?.toInt() ?? 0,
      whatsappEstado: (data['whatsappEstado'] ?? '').toString(),
      actualizadoAt: date(data['actualizadoAt']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo: estado de documentación por establecimiento (para el dashboard)
// ─────────────────────────────────────────────────────────────────────────────

class FacProgresoEst {
  final FacEstablecimiento establecimiento;
  final int subidos;
  final int requeridos;
  final int ignorados;
  final Map<String, bool> docSubido; // doc → está subido?

  double get progreso => requeridos > 0 ? subidos / requeridos : 1.0;
  bool get completo => requeridos == 0 || subidos >= requeridos;

  const FacProgresoEst({
    required this.establecimiento,
    required this.subidos,
    required this.requeridos,
    required this.ignorados,
    required this.docSubido,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo: solicitud de siguiente mes
// ─────────────────────────────────────────────────────────────────────────────

enum FacEstadoAutorizacion { pendiente, aprobada, denegada }

class FacAutorizacion {
  final String id;
  final String empresaId;
  final String establecimientoId;
  final String establecimientoNombre;
  final String currentMes;
  final String nextMes;
  final FacEstadoAutorizacion estado;
  final DateTime fecha;
  final String solicitanteId;
  final String solicitanteNombre;

  const FacAutorizacion({
    required this.id,
    required this.empresaId,
    required this.establecimientoId,
    required this.establecimientoNombre,
    required this.currentMes,
    required this.nextMes,
    required this.estado,
    required this.fecha,
    required this.solicitanteId,
    required this.solicitanteNombre,
  });

  factory FacAutorizacion.fromMap(String docId, Map<String, dynamic> d) {
    FacEstadoAutorizacion estado;
    switch ((d['estado'] ?? '').toString()) {
      case 'aprobada':
        estado = FacEstadoAutorizacion.aprobada;
        break;
      case 'denegada':
        estado = FacEstadoAutorizacion.denegada;
        break;
      default:
        estado = FacEstadoAutorizacion.pendiente;
    }
    return FacAutorizacion(
      id: docId,
      empresaId: (d['empresaId'] ?? '').toString(),
      establecimientoId: (d['establecimientoId'] ?? '').toString(),
      establecimientoNombre: (d['establecimientoNombre'] ?? '').toString(),
      currentMes: (d['currentMes'] ?? '').toString(),
      nextMes: (d['nextMes'] ?? '').toString(),
      estado: estado,
      fecha: d['fecha'] is Timestamp
          ? (d['fecha'] as Timestamp).toDate()
          : DateTime.now(),
      solicitanteId: (d['solicitanteId'] ?? '').toString(),
      solicitanteNombre: (d['solicitanteNombre'] ?? '').toString(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo: observación
// ─────────────────────────────────────────────────────────────────────────────

class FacObservacion {
  final String id;
  final String empresaId;
  final String establecimientoId;
  final String texto;
  final String mes;

  /// Documento al que aplica la observación; null = observación general.
  final String? docTipo;
  final String autorId;
  final String autorNombre;
  final DateTime fecha;
  final DateTime? fechaLimite;
  final String? tareaId;
  final String tareaEstado;

  const FacObservacion({
    required this.id,
    required this.empresaId,
    required this.establecimientoId,
    required this.texto,
    required this.mes,
    this.docTipo,
    required this.autorId,
    required this.autorNombre,
    required this.fecha,
    this.fechaLimite,
    this.tareaId,
    this.tareaEstado = '',
  });

  factory FacObservacion.fromMap(String docId, Map<String, dynamic> d) =>
      FacObservacion(
        id: docId,
        empresaId: (d['empresaId'] ?? '').toString(),
        establecimientoId: (d['establecimientoId'] ?? '').toString(),
        texto: (d['texto'] ?? '').toString(),
        mes: (d['mes'] ?? '').toString(),
        docTipo: d['docTipo']?.toString(),
        autorId: (d['autorId'] ?? '').toString(),
        autorNombre: (d['autorNombre'] ?? '').toString(),
        fecha: d['fecha'] is Timestamp
            ? (d['fecha'] as Timestamp).toDate()
            : DateTime.now(),
        fechaLimite: d['fechaLimite'] is Timestamp
            ? (d['fechaLimite'] as Timestamp).toDate()
            : null,
        tareaId: d['tareaId']?.toString(),
        tareaEstado: (d['tareaEstado'] ?? '').toString(),
      );
}

class FacDocumentTaskTarget {
  final String taskId;
  final String empresaId;
  final String establecimientoId;
  final String establecimientoNombre;
  final String mes;
  final String docTipo;
  final String asignadoUid;
  final DateTime? fechaLimite;

  const FacDocumentTaskTarget({
    required this.taskId,
    required this.empresaId,
    required this.establecimientoId,
    required this.establecimientoNombre,
    required this.mes,
    required this.docTipo,
    required this.asignadoUid,
    this.fechaLimite,
  });

  static FacDocumentTaskTarget? fromTaskData(
    String taskId,
    Map<String, dynamic> data,
  ) {
    if ((data['origen'] ?? '').toString() != kFacTaskOrigin) return null;
    final empresaId = (data['empresaId'] ?? '').toString().trim();
    final estId = (data['facEstablecimientoId'] ?? '').toString().trim();
    final docTipo = (data['facDocTipo'] ?? '').toString().trim();
    final mes = (data['facMes'] ?? '').toString().trim();
    final assigned = (data['asignado_uid'] ?? '').toString().trim();
    if (taskId.trim().isEmpty ||
        empresaId.isEmpty ||
        estId.isEmpty ||
        docTipo.isEmpty ||
        mes.isEmpty ||
        assigned.isEmpty) {
      return null;
    }
    return FacDocumentTaskTarget(
      taskId: taskId,
      empresaId: empresaId,
      establecimientoId: estId,
      establecimientoNombre: (data['facEstablecimientoNombre'] ?? estId)
          .toString(),
      mes: normalizeFacMesKey(mes),
      docTipo: docTipo,
      asignadoUid: assigned,
      fechaLimite: data['fecha_limite'] is Timestamp
          ? (data['fecha_limite'] as Timestamp).toDate()
          : null,
    );
  }
}

class FacRecipient {
  final String userId;
  final String nombre;
  final String telefono;

  const FacRecipient({
    required this.userId,
    required this.nombre,
    this.telefono = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Resultado de getRolFac
// ─────────────────────────────────────────────────────────────────────────────

class FacUserInfo {
  final String rol;
  final String? establecimientoId;

  const FacUserInfo({required this.rol, this.establecimientoId});
}

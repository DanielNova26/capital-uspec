// lib/visitas/visitas_models.dart
//
// Visitas de profesionales — maqueta funcional (reunión 9 sep 2026).
//
// Lo que se acordó, en palabras de Oscar: el jefe inmediato asigna la visita
// en un cronograma; el profesional llega al establecimiento con su tablet, el
// sistema guarda ubicación y hora, diligencia el formato de SU área (calidad,
// HSE, mantenimiento, nutrición), digita o dicta observaciones, adjunta
// evidencia por ítem y al final sale un informe automático. A fin de mes, las
// visitas de un área se consolidan en un solo informe.
//
// El problema que resuelve: hoy el profesional "legaliza" la visita por
// correo, dice que fue, adjunta las fotos de siempre y nadie puede
// comprobarlo ni leerlo. Por eso ubicación y hora las pone el sistema, no la
// persona, y la evidencia se toma en el momento.
//
// QUÉ ES MAQUETA Y QUÉ NO
//
// Los FORMATOS (qué se revisa en cada visita) todavía no existen: Oscar quedó
// de recogerlos con cada director de área. Por eso el formato es un maestro
// en Firestore y no una lista fija en código: cuando lleguen, se cargan sin
// tocar la app. Los cuatro que vienen sembrados son BORRADORES con ítems de
// ejemplo, marcados como tales, para que la maqueta se pueda recorrer.
//
// Todo lo demás —programar, ejecutar con ubicación, responder, evidenciar,
// cerrar, convertir hallazgos en tareas y consolidar— es definitivo.

import 'package:cloud_firestore/cloud_firestore.dart';

const String kVisitasAppId = 'visitasdashboard';

const String kVisitasCol = 'TBL_VISITAS';
const String kVisitasFormatosCol = 'TBL_VISITAS_FORMATOS';
const String kVisitasRolesCol = 'TBL_VISITAS_ROLES';

// ── Roles ───────────────────────────────────────────────────────────────────
//
// Tres, y no más, hasta que el módulo se use: quien programa (el jefe
// inmediato), quien va (el profesional) y quien solo mira (gerencia, calidad).
// El desarrollador entra como jefe.

const String kVisitasRolJefe = 'jefe';
const String kVisitasRolProfesional = 'profesional';
const String kVisitasRolConsulta = 'consulta';

const Map<String, String> kVisitasRolesLabel = {
  kVisitasRolJefe: 'Jefe inmediato',
  kVisitasRolProfesional: 'Profesional',
  kVisitasRolConsulta: 'Consulta',
};

bool visitasPuedeProgramar(String? rol) => rol == kVisitasRolJefe;
bool visitasPuedeGestionarFormatos(String? rol) => rol == kVisitasRolJefe;
bool visitasPuedeVerConsolidado(String? rol) =>
    rol == kVisitasRolJefe || rol == kVisitasRolConsulta;

/// Solo el profesional asignado ejecuta su visita. Ni el jefe: si el jefe
/// pudiera responder por él, volveríamos a "dicen que fueron".
bool visitasPuedeEjecutar({
  required String? rol,
  required VisitaProfesional visita,
  required String userId,
}) =>
    rol == kVisitasRolProfesional &&
    visita.profesionalId == userId &&
    (visita.estado == kVisitaProgramada || visita.estado == kVisitaEnCurso);

// ── Estados de la visita ────────────────────────────────────────────────────

const String kVisitaProgramada = 'programada';
const String kVisitaEnCurso = 'en_curso';
const String kVisitaTerminada = 'terminada';
const String kVisitaCancelada = 'cancelada';

const Map<String, String> kVisitaEstadosLabel = {
  kVisitaProgramada: 'Programada',
  kVisitaEnCurso: 'En curso',
  kVisitaTerminada: 'Terminada',
  kVisitaCancelada: 'Cancelada',
};

// ── Resultado de un ítem ────────────────────────────────────────────────────

const String kItemCumple = 'cumple';
const String kItemNoCumple = 'no_cumple';
const String kItemNoAplica = 'no_aplica';

const Map<String, String> kItemResultadoLabel = {
  kItemCumple: 'Cumple',
  kItemNoCumple: 'No cumple',
  kItemNoAplica: 'No aplica',
};

// ── Formato de visita (maestro por área) ────────────────────────────────────

const String kFormatoBorrador = 'borrador';
const String kFormatoVigente = 'vigente';
const String kFormatoRetirado = 'retirado';

class VisitaFormatoItem {
  /// Estable. Las respuestas se guardan por este id: renumerar o reescribir
  /// el texto no puede dejar huérfana una respuesta.
  final String id;
  final int orden;
  final String seccion;
  final String texto;

  /// Si es `true`, un "No cumple" en este ítem exige foto. Es la forma de
  /// obligar la evidencia donde importa sin pedirla en todo.
  final bool requiereEvidencia;

  const VisitaFormatoItem({
    required this.id,
    required this.orden,
    this.seccion = '',
    required this.texto,
    this.requiereEvidencia = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'orden': orden,
    'seccion': seccion,
    'texto': texto,
    'requiereEvidencia': requiereEvidencia,
  };

  factory VisitaFormatoItem.fromMap(Map<String, dynamic> d) =>
      VisitaFormatoItem(
        id: (d['id'] ?? '').toString(),
        orden: (d['orden'] as num?)?.toInt() ?? 0,
        seccion: (d['seccion'] ?? '').toString(),
        texto: (d['texto'] ?? '').toString(),
        requiereEvidencia: d['requiereEvidencia'] == true,
      );
}

class VisitaFormato {
  final String id;
  final String empresaId;
  final String areaId;
  final String areaNombre;
  final String nombre;
  final int version;
  final String estado;
  final List<VisitaFormatoItem> items;

  const VisitaFormato({
    this.id = '',
    required this.empresaId,
    required this.areaId,
    required this.areaNombre,
    required this.nombre,
    this.version = 1,
    this.estado = kFormatoBorrador,
    this.items = const [],
  });

  bool get esBorrador => estado == kFormatoBorrador;
  bool get usable => estado != kFormatoRetirado;

  List<VisitaFormatoItem> get itemsOrdenados =>
      [...items]..sort((a, b) => a.orden.compareTo(b.orden));

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'areaId': areaId,
    'areaNombre': areaNombre,
    'nombre': nombre,
    'version': version,
    'estado': estado,
    'items': items.map((i) => i.toMap()).toList(),
  };

  factory VisitaFormato.fromMap(String id, Map<String, dynamic> d) =>
      VisitaFormato(
        id: id,
        empresaId: (d['empresaId'] ?? '').toString(),
        areaId: (d['areaId'] ?? '').toString(),
        areaNombre: (d['areaNombre'] ?? '').toString(),
        nombre: (d['nombre'] ?? '').toString(),
        version: (d['version'] as num?)?.toInt() ?? 1,
        estado: (d['estado'] ?? kFormatoBorrador).toString(),
        items: [
          for (final raw in (d['items'] as List? ?? const []))
            if (raw is Map)
              VisitaFormatoItem.fromMap(Map<String, dynamic>.from(raw)),
        ],
      );

  VisitaFormato copyWith({
    String? nombre,
    String? estado,
    List<VisitaFormatoItem>? items,
    int? version,
  }) => VisitaFormato(
    id: id,
    empresaId: empresaId,
    areaId: areaId,
    areaNombre: areaNombre,
    nombre: nombre ?? this.nombre,
    version: version ?? this.version,
    estado: estado ?? this.estado,
    items: items ?? this.items,
  );
}

/// Un formato solo sirve si tiene ítems con texto y sin ids repetidos. Un id
/// repetido haría que dos preguntas compartieran la misma respuesta.
List<String> validarFormato(VisitaFormato f) {
  final errores = <String>[];
  if (f.nombre.trim().isEmpty) errores.add('El formato necesita un nombre.');
  if (f.areaId.trim().isEmpty)
    errores.add('El formato debe pertenecer a un área.');
  if (f.items.isEmpty) errores.add('El formato no tiene ningún ítem.');
  final ids = <String>{};
  for (final it in f.items) {
    if (it.texto.trim().isEmpty) {
      errores.add('El ítem ${it.orden} no dice qué se revisa.');
    }
    if (it.id.trim().isEmpty) {
      errores.add('El ítem ${it.orden} no tiene id.');
    } else if (!ids.add(it.id)) {
      errores.add('El id "${it.id}" está repetido.');
    }
  }
  return errores;
}

// ── Evidencia y respuesta ───────────────────────────────────────────────────

class VisitaEvidencia {
  final String url;
  final String path;
  final String nombre;
  final Timestamp? tomadaEn;

  const VisitaEvidencia({
    required this.url,
    required this.path,
    required this.nombre,
    this.tomadaEn,
  });

  Map<String, dynamic> toMap() => {
    'url': url,
    'path': path,
    'nombre': nombre,
    'tomadaEn': tomadaEn ?? Timestamp.now(),
  };

  factory VisitaEvidencia.fromMap(Map<String, dynamic> d) => VisitaEvidencia(
    url: (d['url'] ?? '').toString(),
    path: (d['path'] ?? '').toString(),
    nombre: (d['nombre'] ?? '').toString(),
    tomadaEn: d['tomadaEn'] is Timestamp ? d['tomadaEn'] as Timestamp : null,
  );
}

class VisitaRespuesta {
  /// `cumple`, `no_cumple`, `no_aplica` o vacío (sin responder).
  final String resultado;
  final String observacion;
  final List<VisitaEvidencia> evidencias;

  const VisitaRespuesta({
    this.resultado = '',
    this.observacion = '',
    this.evidencias = const [],
  });

  bool get respondida => resultado.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'resultado': resultado,
    'observacion': observacion,
    'evidencias': evidencias.map((e) => e.toMap()).toList(),
  };

  factory VisitaRespuesta.fromMap(Map<String, dynamic> d) => VisitaRespuesta(
    resultado: (d['resultado'] ?? '').toString(),
    observacion: (d['observacion'] ?? '').toString(),
    evidencias: [
      for (final raw in (d['evidencias'] as List? ?? const []))
        if (raw is Map) VisitaEvidencia.fromMap(Map<String, dynamic>.from(raw)),
    ],
  );

  VisitaRespuesta copyWith({
    String? resultado,
    String? observacion,
    List<VisitaEvidencia>? evidencias,
  }) => VisitaRespuesta(
    resultado: resultado ?? this.resultado,
    observacion: observacion ?? this.observacion,
    evidencias: evidencias ?? this.evidencias,
  );
}

/// Dónde y cuándo. Lo pone el dispositivo, nunca la persona.
class VisitaMarca {
  final Timestamp at;
  final double? lat;
  final double? lng;
  final double? precisionMetros;

  const VisitaMarca({
    required this.at,
    this.lat,
    this.lng,
    this.precisionMetros,
  });

  bool get tieneUbicacion => lat != null && lng != null;

  Map<String, dynamic> toMap() => {
    'at': at,
    'lat': lat,
    'lng': lng,
    'precisionMetros': precisionMetros,
  };

  factory VisitaMarca.fromMap(Map<String, dynamic> d) => VisitaMarca(
    at: d['at'] is Timestamp ? d['at'] as Timestamp : Timestamp.now(),
    lat: (d['lat'] as num?)?.toDouble(),
    lng: (d['lng'] as num?)?.toDouble(),
    precisionMetros: (d['precisionMetros'] as num?)?.toDouble(),
  );
}

// ── La visita ───────────────────────────────────────────────────────────────

class VisitaProfesional {
  final String id;
  final String empresaId;
  final String formatoId;
  final String formatoNombre;
  final String areaId;
  final String areaNombre;
  final String centroId;
  final String centroNombre;
  final String subcentroId;
  final String subcentroNombre;
  final String profesionalId;
  final String profesionalNombre;
  final String asignadoPorId;
  final String asignadoPorNombre;
  final DateTime fechaProgramada;
  final String estado;
  final VisitaMarca? inicio;
  final VisitaMarca? fin;
  final Map<String, VisitaRespuesta> respuestas;
  final String observacionGeneral;

  /// Porcentaje de cumplimiento al cerrar. Se guarda, no se recalcula, para
  /// que el consolidado no dependa de que el formato siga igual.
  final int? cumplimiento;
  final List<String> tareasCreadas;

  const VisitaProfesional({
    this.id = '',
    required this.empresaId,
    required this.formatoId,
    required this.formatoNombre,
    required this.areaId,
    required this.areaNombre,
    required this.centroId,
    required this.centroNombre,
    this.subcentroId = '',
    this.subcentroNombre = '',
    required this.profesionalId,
    required this.profesionalNombre,
    required this.asignadoPorId,
    required this.asignadoPorNombre,
    required this.fechaProgramada,
    this.estado = kVisitaProgramada,
    this.inicio,
    this.fin,
    this.respuestas = const {},
    this.observacionGeneral = '',
    this.cumplimiento,
    this.tareasCreadas = const [],
  });

  String get establecimiento =>
      subcentroNombre.isEmpty ? centroNombre : '$centroNombre $subcentroNombre';

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'formatoId': formatoId,
    'formatoNombre': formatoNombre,
    'areaId': areaId,
    'areaNombre': areaNombre,
    'centroId': centroId,
    'centroNombre': centroNombre,
    'subcentroId': subcentroId,
    'subcentroNombre': subcentroNombre,
    'profesionalId': profesionalId,
    'profesionalNombre': profesionalNombre,
    'asignadoPorId': asignadoPorId,
    'asignadoPorNombre': asignadoPorNombre,
    'fechaProgramada': Timestamp.fromDate(fechaProgramada),
    'estado': estado,
    'inicio': inicio?.toMap(),
    'fin': fin?.toMap(),
    'respuestas': {for (final e in respuestas.entries) e.key: e.value.toMap()},
    'observacionGeneral': observacionGeneral,
    'cumplimiento': cumplimiento,
    'tareasCreadas': tareasCreadas,
  };

  factory VisitaProfesional.fromMap(String id, Map<String, dynamic> d) {
    final rawResp = d['respuestas'];
    final respuestas = <String, VisitaRespuesta>{};
    if (rawResp is Map) {
      for (final e in rawResp.entries) {
        if (e.value is Map) {
          respuestas[e.key.toString()] = VisitaRespuesta.fromMap(
            Map<String, dynamic>.from(e.value as Map),
          );
        }
      }
    }
    final fp = d['fechaProgramada'];
    return VisitaProfesional(
      id: id,
      empresaId: (d['empresaId'] ?? '').toString(),
      formatoId: (d['formatoId'] ?? '').toString(),
      formatoNombre: (d['formatoNombre'] ?? '').toString(),
      areaId: (d['areaId'] ?? '').toString(),
      areaNombre: (d['areaNombre'] ?? '').toString(),
      centroId: (d['centroId'] ?? '').toString(),
      centroNombre: (d['centroNombre'] ?? '').toString(),
      subcentroId: (d['subcentroId'] ?? '').toString(),
      subcentroNombre: (d['subcentroNombre'] ?? '').toString(),
      profesionalId: (d['profesionalId'] ?? '').toString(),
      profesionalNombre: (d['profesionalNombre'] ?? '').toString(),
      asignadoPorId: (d['asignadoPorId'] ?? '').toString(),
      asignadoPorNombre: (d['asignadoPorNombre'] ?? '').toString(),
      fechaProgramada: fp is Timestamp
          ? fp.toDate()
          : DateTime.tryParse(fp?.toString() ?? '') ?? DateTime(2000),
      estado: (d['estado'] ?? kVisitaProgramada).toString(),
      inicio: d['inicio'] is Map
          ? VisitaMarca.fromMap(Map<String, dynamic>.from(d['inicio'] as Map))
          : null,
      fin: d['fin'] is Map
          ? VisitaMarca.fromMap(Map<String, dynamic>.from(d['fin'] as Map))
          : null,
      respuestas: respuestas,
      observacionGeneral: (d['observacionGeneral'] ?? '').toString(),
      cumplimiento: (d['cumplimiento'] as num?)?.toInt(),
      tareasCreadas: [
        for (final t in (d['tareasCreadas'] as List? ?? const [])) t.toString(),
      ],
    );
  }
}

// ── Lógica pura ─────────────────────────────────────────────────────────────

class VisitaResumen {
  final int total;
  final int cumple;
  final int noCumple;
  final int noAplica;
  final int sinResponder;

  const VisitaResumen({
    required this.total,
    required this.cumple,
    required this.noCumple,
    required this.noAplica,
    required this.sinResponder,
  });

  int get evaluados => cumple + noCumple;

  /// Cumple sobre lo evaluado. "No aplica" no suma ni resta: un
  /// establecimiento sin refrigerio no tiene por qué perder puntos por él.
  /// Sin nada evaluado devuelve null, no 0: cero sería "todo mal".
  int? get porcentaje =>
      evaluados == 0 ? null : (cumple * 100 / evaluados).round();
}

VisitaResumen resumenDeVisita(
  VisitaFormato formato,
  Map<String, VisitaRespuesta> respuestas,
) {
  var cumple = 0, noCumple = 0, noAplica = 0, sin = 0;
  for (final it in formato.items) {
    switch (respuestas[it.id]?.resultado ?? '') {
      case kItemCumple:
        cumple++;
      case kItemNoCumple:
        noCumple++;
      case kItemNoAplica:
        noAplica++;
      default:
        sin++;
    }
  }
  return VisitaResumen(
    total: formato.items.length,
    cumple: cumple,
    noCumple: noCumple,
    noAplica: noAplica,
    sinResponder: sin,
  );
}

/// Qué falta para poder cerrar la visita. Vacío = se puede cerrar.
///
/// Un "No cumple" sin observación no le sirve a nadie: el informe diría
/// "falló el ítem 7" y el establecimiento no sabría qué corregir. Y donde el
/// formato pide evidencia, la foto no es opcional: es lo que impide que la
/// evidencia sea "la misma de siempre".
List<String> validarCierreVisita(
  VisitaFormato formato,
  VisitaProfesional visita,
) {
  final errores = <String>[];
  if (visita.inicio == null) {
    errores.add('La visita no se ha iniciado en el establecimiento.');
  }
  for (final it in formato.itemsOrdenados) {
    final r = visita.respuestas[it.id];
    if (r == null || !r.respondida) {
      errores.add('Ítem ${it.orden} sin responder: ${it.texto}');
      continue;
    }
    if (r.resultado == kItemNoCumple) {
      if (r.observacion.trim().isEmpty) {
        errores.add('Ítem ${it.orden} no cumple y no dice por qué.');
      }
      if (it.requiereEvidencia && r.evidencias.isEmpty) {
        errores.add('Ítem ${it.orden} no cumple y exige foto.');
      }
    }
  }
  return errores;
}

/// Un hallazgo por cada "No cumple". Es lo que se vuelve tarea al cerrar.
class VisitaHallazgo {
  final VisitaFormatoItem item;
  final VisitaRespuesta respuesta;
  const VisitaHallazgo(this.item, this.respuesta);
}

List<VisitaHallazgo> hallazgosDeVisita(
  VisitaFormato formato,
  Map<String, VisitaRespuesta> respuestas,
) => [
  for (final it in formato.itemsOrdenados)
    if (respuestas[it.id]?.resultado == kItemNoCumple)
      VisitaHallazgo(it, respuestas[it.id]!),
];

String tituloTareaHallazgo(VisitaProfesional v, VisitaHallazgo h) =>
    'Visita ${v.areaNombre} · ${v.establecimiento}: ${h.item.texto}';

String descripcionTareaHallazgo(VisitaProfesional v, VisitaHallazgo h) {
  final b = StringBuffer()
    ..writeln('Hallazgo de la visita de ${v.areaNombre} del ')
    ..writeln(
      '${v.fechaProgramada.day.toString().padLeft(2, '0')}/'
      '${v.fechaProgramada.month.toString().padLeft(2, '0')}/'
      '${v.fechaProgramada.year} a ${v.establecimiento}.',
    )
    ..writeln()
    ..writeln('Ítem ${h.item.orden}: ${h.item.texto}')
    ..writeln('Observación del profesional: ${h.respuesta.observacion}');
  if (h.respuesta.evidencias.isNotEmpty) {
    b.writeln('Evidencias: ${h.respuesta.evidencias.length}');
  }
  b.writeln('Profesional: ${v.profesionalNombre}');
  return b.toString().trim();
}

/// Fecha límite de corrección: cinco días corridos. Es un punto de partida
/// para la maqueta; cuando cada área diga su plazo, se parametriza en el
/// formato.
DateTime fechaLimiteHallazgo(DateTime cierre) =>
    cierre.add(const Duration(days: 5));

/// Solo se puede iniciar el día programado o después. Iniciarla antes
/// dejaría una marca de hora que no corresponde a la programación.
bool visitaSePuedeIniciar(VisitaProfesional v, DateTime ahora) {
  if (v.estado != kVisitaProgramada) return false;
  final dia = DateTime(
    v.fechaProgramada.year,
    v.fechaProgramada.month,
    v.fechaProgramada.day,
  );
  return !ahora.isBefore(dia);
}

/// Una visita programada que ya pasó de fecha y nadie inició.
bool visitaVencida(VisitaProfesional v, DateTime ahora) {
  if (v.estado != kVisitaProgramada) return false;
  final limite = DateTime(
    v.fechaProgramada.year,
    v.fechaProgramada.month,
    v.fechaProgramada.day,
  ).add(const Duration(days: 1));
  return !ahora.isBefore(limite);
}

// ── Consolidado mensual ─────────────────────────────────────────────────────

class ConsolidadoEstablecimiento {
  final String clave;
  final String nombre;
  final int visitas;
  final int? promedio;
  final int hallazgos;

  const ConsolidadoEstablecimiento({
    required this.clave,
    required this.nombre,
    required this.visitas,
    required this.promedio,
    required this.hallazgos,
  });
}

class ConsolidadoItem {
  final String itemId;
  final String texto;
  final int incumplimientos;
  const ConsolidadoItem({
    required this.itemId,
    required this.texto,
    required this.incumplimientos,
  });
}

class ConsolidadoMensual {
  final int visitasTerminadas;
  final int visitasProgramadas;
  final int visitasCanceladas;
  final int? promedioGeneral;
  final int hallazgos;
  final List<ConsolidadoEstablecimiento> porEstablecimiento;

  /// Los ítems que más se incumplen en el mes, de mayor a menor.
  final List<ConsolidadoItem> itemsCriticos;

  const ConsolidadoMensual({
    required this.visitasTerminadas,
    required this.visitasProgramadas,
    required this.visitasCanceladas,
    required this.promedioGeneral,
    required this.hallazgos,
    required this.porEstablecimiento,
    required this.itemsCriticos,
  });

  static const vacio = ConsolidadoMensual(
    visitasTerminadas: 0,
    visitasProgramadas: 0,
    visitasCanceladas: 0,
    promedioGeneral: null,
    hallazgos: 0,
    porEstablecimiento: [],
    itemsCriticos: [],
  );
}

bool visitaEnMes(VisitaProfesional v, int anio, int mes) =>
    v.fechaProgramada.year == anio && v.fechaProgramada.month == mes;

/// Consolida las visitas de un área en un mes. Solo las terminadas cuentan
/// para el promedio y los hallazgos; las programadas y canceladas se cuentan
/// aparte para que el informe diga también lo que NO se hizo.
///
/// [formatos] sirve para ponerle texto a los ítems críticos; si un formato ya
/// no existe, el ítem sale con su id y nada se pierde.
ConsolidadoMensual consolidarMes(
  Iterable<VisitaProfesional> visitas, {
  Map<String, VisitaFormato> formatos = const {},
}) {
  final terminadas = visitas.where((v) => v.estado == kVisitaTerminada);
  final programadas = visitas.where((v) => v.estado == kVisitaProgramada);
  final canceladas = visitas.where((v) => v.estado == kVisitaCancelada);

  final porEst = <String, List<VisitaProfesional>>{};
  for (final v in terminadas) {
    final clave = v.subcentroId.isEmpty
        ? v.centroId
        : '${v.centroId}|${v.subcentroId}';
    porEst.putIfAbsent(clave, () => []).add(v);
  }

  final incumplidos = <String, int>{};
  final textoItem = <String, String>{};
  var hallazgos = 0;
  for (final v in terminadas) {
    final f = formatos[v.formatoId];
    for (final e in v.respuestas.entries) {
      if (e.value.resultado != kItemNoCumple) continue;
      hallazgos++;
      incumplidos[e.key] = (incumplidos[e.key] ?? 0) + 1;
      final it = f?.items.where((i) => i.id == e.key).firstOrNull;
      if (it != null) textoItem[e.key] = it.texto;
    }
  }

  int? promedio(Iterable<VisitaProfesional> vs) {
    final con = vs.where((v) => v.cumplimiento != null).toList();
    if (con.isEmpty) return null;
    return (con.map((v) => v.cumplimiento!).reduce((a, b) => a + b) /
            con.length)
        .round();
  }

  final establecimientos =
      porEst.entries
          .map(
            (e) => ConsolidadoEstablecimiento(
              clave: e.key,
              nombre: e.value.first.establecimiento,
              visitas: e.value.length,
              promedio: promedio(e.value),
              hallazgos: e.value.fold(
                0,
                (acc, v) =>
                    acc +
                    v.respuestas.values
                        .where((r) => r.resultado == kItemNoCumple)
                        .length,
              ),
            ),
          )
          .toList()
        ..sort((a, b) {
          // Los peores primero: es lo que el director quiere ver.
          final pa = a.promedio ?? 101, pb = b.promedio ?? 101;
          if (pa != pb) return pa.compareTo(pb);
          return a.nombre.compareTo(b.nombre);
        });

  final criticos =
      incumplidos.entries
          .map(
            (e) => ConsolidadoItem(
              itemId: e.key,
              texto: textoItem[e.key] ?? e.key,
              incumplimientos: e.value,
            ),
          )
          .toList()
        ..sort((a, b) => b.incumplimientos.compareTo(a.incumplimientos));

  return ConsolidadoMensual(
    visitasTerminadas: terminadas.length,
    visitasProgramadas: programadas.length,
    visitasCanceladas: canceladas.length,
    promedioGeneral: promedio(terminadas),
    hallazgos: hallazgos,
    porEstablecimiento: establecimientos,
    itemsCriticos: criticos,
  );
}

// ── Formatos sembrados (BORRADORES) ─────────────────────────────────────────
//
// Ítems de ejemplo para que la maqueta se pueda recorrer de punta a punta.
// Los definitivos los entregan los directores de área a través de Oscar. Se
// siembran en estado `borrador`, y el nombre lo dice, para que nadie los tome
// por el formato oficial.

List<VisitaFormato> formatosSemilla(String empresaId) {
  VisitaFormatoItem it(
    String id,
    int orden,
    String seccion,
    String texto, {
    bool foto = false,
  }) => VisitaFormatoItem(
    id: id,
    orden: orden,
    seccion: seccion,
    texto: texto,
    requiereEvidencia: foto,
  );

  return [
    VisitaFormato(
      empresaId: empresaId,
      areaId: 'calidad',
      areaNombre: 'Calidad',
      nombre: 'Visita de Calidad (borrador de ejemplo)',
      items: [
        it('cal_01', 1, 'Personal', 'Personal con dotación completa y carné'),
        it('cal_02', 2, 'Personal', 'Certificados de manipulación vigentes'),
        it(
          'cal_03',
          3,
          'Instalaciones',
          'Pisos, paredes y techos limpios',
          foto: true,
        ),
        it('cal_04', 4, 'Instalaciones', 'Control de plagas al día'),
        it('cal_05', 5, 'Materia prima', 'Sin productos vencidos', foto: true),
        it('cal_06', 6, 'Materia prima', 'Sin productos dañados', foto: true),
        it('cal_07', 7, 'Servicio', 'Horario de desayuno cumplido'),
        it('cal_08', 8, 'Servicio', 'Horario de almuerzo cumplido'),
        it('cal_09', 9, 'Servicio', 'Horario de cena cumplido'),
      ],
    ),
    VisitaFormato(
      empresaId: empresaId,
      areaId: 'hse',
      areaNombre: 'HSE',
      nombre: 'Visita HSE (borrador de ejemplo)',
      items: [
        it(
          'hse_01',
          1,
          'Seguridad',
          'Extintores vigentes y señalizados',
          foto: true,
        ),
        it('hse_02', 2, 'Seguridad', 'Elementos de protección personal en uso'),
        it(
          'hse_03',
          3,
          'Seguridad',
          'Rutas de evacuación despejadas',
          foto: true,
        ),
        it('hse_04', 4, 'Salud', 'Botiquín completo'),
        it('hse_05', 5, 'Ambiente', 'Manejo de residuos según el plan'),
      ],
    ),
    VisitaFormato(
      empresaId: empresaId,
      areaId: 'mantenimiento',
      areaNombre: 'Mantenimiento',
      nombre: 'Visita de Mantenimiento (borrador de ejemplo)',
      items: [
        it(
          'man_01',
          1,
          'Equipos',
          'Refrigeradores y congeladores en temperatura',
          foto: true,
        ),
        it('man_02', 2, 'Equipos', 'Estufas y hornos operando'),
        it(
          'man_03',
          3,
          'Redes',
          'Red eléctrica sin empalmes expuestos',
          foto: true,
        ),
        it('man_04', 4, 'Redes', 'Red hidráulica sin fugas', foto: true),
        it('man_05', 5, 'Redes', 'Gas: válvulas y mangueras en buen estado'),
      ],
    ),
    VisitaFormato(
      empresaId: empresaId,
      areaId: 'nutricion',
      areaNombre: 'Nutrición',
      nombre: 'Visita de Nutrición (borrador de ejemplo)',
      items: [
        it('nut_01', 1, 'Minuta', 'Minuta del día publicada y cumplida'),
        it('nut_02', 2, 'Minuta', 'Gramajes según ciclo de menús', foto: true),
        it('nut_03', 3, 'Almacenamiento', 'Rotación PEPS aplicada'),
        it('nut_04', 4, 'Almacenamiento', 'Cadena de frío documentada'),
        it('nut_05', 5, 'Servicio', 'Bebida y refrigerio según contrato'),
      ],
    ),
  ];
}

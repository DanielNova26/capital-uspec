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

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

const String kVisitasAppId = 'visitasdashboard';

const String kVisitasCol = 'TBL_VISITAS';
const String kVisitasFormatosCol = 'TBL_VISITAS_FORMATOS';
const String kVisitasRolesCol = 'TBL_VISITAS_ROLES';

/// Maestro de ubicaciones de los establecimientos (17 sep 2026).
///
/// Vive aparte de TBL_CENTROS_COSTOS a propósito: las coordenadas las carga
/// solo Desarrollo y sirven para comprobar que el profesional está en el
/// sitio. Un centro sin ubicación aquí no se puede visitar: primero se
/// carga el maestro.
const String kVisitasUbicacionesCol = 'TBL_VISITAS_UBICACIONES';

/// Radio por defecto alrededor del establecimiento, en metros. Corto a
/// propósito: la idea es saber que el acta se hace adentro, no en la
/// cuadra. Se puede ajustar por establecimiento en el maestro.
const double kVisitasRadioDefectoMetros = 150;

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

/// Reprogramar: el jefe cualquier visita programada; el profesional solo la
/// suya. Es lo que se pidió el 17 sep 2026: que jefes y quienes visitan
/// puedan mover el calendario. Una visita ya iniciada no se mueve.
bool visitasPuedeReprogramar({
  required String? rol,
  required VisitaProfesional visita,
  required String userId,
}) {
  if (visita.estado != kVisitaProgramada) return false;
  if (rol == kVisitasRolJefe) return true;
  return rol == kVisitasRolProfesional && visita.profesionalId == userId;
}

/// El maestro de ubicaciones es solo de Desarrollo. No es un rol del
/// módulo: es quien puede todo en la app.
bool visitasPuedeGestionarUbicaciones({required bool esDesarrollador}) =>
    esDesarrollador;

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

// ── Tipos de ítem ───────────────────────────────────────────────────────────
//
// El formato SST trajo tres maneras de responder:
//  - `calificacion`: 1 / 0 / NA (cumple, no cumple, no aplica). Es el que
//    ya existía.
//  - `si_no`: solo cumple / no cumple. No hay "no aplica".
//  - `elemento`: sí/no más cantidad y fecha de vencimiento (botiquín).
// Se guardan con los mismos resultados; lo que cambia es qué se ofrece y
// qué se pide además.

const String kItemTipoCalificacion = 'calificacion';
const String kItemTipoSiNo = 'si_no';
const String kItemTipoElemento = 'elemento';

List<String> resultadosPermitidos(String tipo) => tipo == kItemTipoCalificacion
    ? const [kItemCumple, kItemNoCumple, kItemNoAplica]
    : const [kItemCumple, kItemNoCumple];

// ── Estados de una fila de tabla (extintores) ───────────────────────────────
//
// B: Bueno, M: Malo, R: Regular, NC: No cuenta con el elemento. Tal cual el
// formato F-UT-SST-03. M y NC son hallazgo.

const String kFilaBueno = 'B';
const String kFilaMalo = 'M';
const String kFilaRegular = 'R';
const String kFilaNoCuenta = 'NC';

const Map<String, String> kFilaEstadoLabel = {
  kFilaBueno: 'Bueno',
  kFilaMalo: 'Malo',
  kFilaRegular: 'Regular',
  kFilaNoCuenta: 'No cuenta',
};

bool filaEstadoEsHallazgo(String estado) =>
    estado == kFilaMalo || estado == kFilaNoCuenta;

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

  /// `calificacion`, `si_no` o `elemento`. Ver los tipos arriba.
  final String tipo;

  /// Código de la parte del formato a la que pertenece (F-UT-SST-02…).
  /// Vacío en formatos de una sola hoja.
  final String parte;

  /// Solo para `elemento`: la cantidad esperada ("1 Unidad", "Paquete x 20").
  final String unidad;

  const VisitaFormatoItem({
    required this.id,
    required this.orden,
    this.seccion = '',
    required this.texto,
    this.requiereEvidencia = false,
    this.tipo = kItemTipoCalificacion,
    this.parte = '',
    this.unidad = '',
  });

  bool get esElemento => tipo == kItemTipoElemento;

  Map<String, dynamic> toMap() => {
    'id': id,
    'orden': orden,
    'seccion': seccion,
    'texto': texto,
    'requiereEvidencia': requiereEvidencia,
    'tipo': tipo,
    'parte': parte,
    'unidad': unidad,
  };

  factory VisitaFormatoItem.fromMap(Map<String, dynamic> d) =>
      VisitaFormatoItem(
        id: (d['id'] ?? '').toString(),
        orden: (d['orden'] as num?)?.toInt() ?? 0,
        seccion: (d['seccion'] ?? '').toString(),
        texto: (d['texto'] ?? '').toString(),
        requiereEvidencia: d['requiereEvidencia'] == true,
        tipo: _tipoItem((d['tipo'] ?? '').toString()),
        parte: (d['parte'] ?? '').toString(),
        unidad: (d['unidad'] ?? '').toString(),
      );

  VisitaFormatoItem copyWith({
    int? orden,
    String? seccion,
    String? texto,
    bool? requiereEvidencia,
    String? tipo,
    String? parte,
    String? unidad,
  }) => VisitaFormatoItem(
    id: id,
    orden: orden ?? this.orden,
    seccion: seccion ?? this.seccion,
    texto: texto ?? this.texto,
    requiereEvidencia: requiereEvidencia ?? this.requiereEvidencia,
    tipo: tipo ?? this.tipo,
    parte: parte ?? this.parte,
    unidad: unidad ?? this.unidad,
  );
}

/// Un tipo desconocido cae en `calificacion`: es el que siempre existió y
/// el que menos exige.
String _tipoItem(String raw) => switch (raw) {
  kItemTipoSiNo => kItemTipoSiNo,
  kItemTipoElemento => kItemTipoElemento,
  _ => kItemTipoCalificacion,
};

/// Una hoja del formato: F-UT-SST-02, -03, -01. Es lo que va en el
/// encabezado de cada página del PDF.
class VisitaFormatoParte {
  final String codigo;
  final String nombre;
  final String version;
  final String elaboracion;

  const VisitaFormatoParte({
    required this.codigo,
    required this.nombre,
    this.version = '1',
    this.elaboracion = '',
  });

  Map<String, dynamic> toMap() => {
    'codigo': codigo,
    'nombre': nombre,
    'version': version,
    'elaboracion': elaboracion,
  };

  factory VisitaFormatoParte.fromMap(Map<String, dynamic> d) =>
      VisitaFormatoParte(
        codigo: (d['codigo'] ?? '').toString(),
        nombre: (d['nombre'] ?? '').toString(),
        version: (d['version'] ?? '1').toString(),
        elaboracion: (d['elaboracion'] ?? '').toString(),
      );
}

/// Una columna de una tabla del formato.
class VisitaTablaCampo {
  final String id;
  final String label;
  const VisitaTablaCampo(this.id, this.label);

  Map<String, dynamic> toMap() => {'id': id, 'label': label};
  factory VisitaTablaCampo.fromMap(Map<String, dynamic> d) => VisitaTablaCampo(
    (d['id'] ?? '').toString(),
    (d['label'] ?? '').toString(),
  );
}

/// Tabla de filas dinámicas dentro del formato (la de extintores). Cada
/// fila tiene campos de texto (ubicación, tipo, capacidad…) y campos de
/// estado (B / M / R / NC). Cuántas filas hay lo decide el profesional en
/// el sitio: los establecimientos no tienen todos la misma cantidad de
/// extintores.
class VisitaFormatoTabla {
  final String id;
  final String parte;
  final String nombre;

  /// Cómo se llama cada fila ("Extintor").
  final String etiquetaFila;
  final List<VisitaTablaCampo> camposTexto;
  final List<VisitaTablaCampo> camposEstado;

  const VisitaFormatoTabla({
    required this.id,
    this.parte = '',
    required this.nombre,
    this.etiquetaFila = 'Fila',
    this.camposTexto = const [],
    this.camposEstado = const [],
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'parte': parte,
    'nombre': nombre,
    'etiquetaFila': etiquetaFila,
    'camposTexto': camposTexto.map((c) => c.toMap()).toList(),
    'camposEstado': camposEstado.map((c) => c.toMap()).toList(),
  };

  factory VisitaFormatoTabla.fromMap(Map<String, dynamic> d) =>
      VisitaFormatoTabla(
        id: (d['id'] ?? '').toString(),
        parte: (d['parte'] ?? '').toString(),
        nombre: (d['nombre'] ?? '').toString(),
        etiquetaFila: (d['etiquetaFila'] ?? 'Fila').toString(),
        camposTexto: _campos(d['camposTexto']),
        camposEstado: _campos(d['camposEstado']),
      );

  static List<VisitaTablaCampo> _campos(Object? raw) => [
    for (final r in (raw as List? ?? const []))
      if (r is Map) VisitaTablaCampo.fromMap(Map<String, dynamic>.from(r)),
  ];
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

  /// Hojas del formato. Vacío = formato de una sola hoja sin código.
  final List<VisitaFormatoParte> partes;

  /// Tablas de filas dinámicas. Vacío en la mayoría de formatos.
  final List<VisitaFormatoTabla> tablas;

  const VisitaFormato({
    this.id = '',
    required this.empresaId,
    required this.areaId,
    required this.areaNombre,
    required this.nombre,
    this.version = 1,
    this.estado = kFormatoBorrador,
    this.items = const [],
    this.partes = const [],
    this.tablas = const [],
  });

  bool get esBorrador => estado == kFormatoBorrador;
  bool get usable => estado != kFormatoRetirado;

  List<VisitaFormatoItem> get itemsOrdenados =>
      [...items]..sort((a, b) => a.orden.compareTo(b.orden));

  /// Ítems de una parte, ordenados. Con `parte` vacío devuelve los que no
  /// tienen parte, que en un formato de una hoja son todos.
  List<VisitaFormatoItem> itemsDeParte(String parte) =>
      itemsOrdenados.where((i) => i.parte == parte).toList();

  List<VisitaFormatoTabla> tablasDeParte(String parte) =>
      tablas.where((t) => t.parte == parte).toList();

  VisitaFormatoTabla? tabla(String id) =>
      tablas.where((t) => t.id == id).firstOrNull;

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'areaId': areaId,
    'areaNombre': areaNombre,
    'nombre': nombre,
    'version': version,
    'estado': estado,
    'items': items.map((i) => i.toMap()).toList(),
    'partes': partes.map((p) => p.toMap()).toList(),
    'tablas': tablas.map((t) => t.toMap()).toList(),
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
        partes: [
          for (final raw in (d['partes'] as List? ?? const []))
            if (raw is Map)
              VisitaFormatoParte.fromMap(Map<String, dynamic>.from(raw)),
        ],
        tablas: [
          for (final raw in (d['tablas'] as List? ?? const []))
            if (raw is Map)
              VisitaFormatoTabla.fromMap(Map<String, dynamic>.from(raw)),
        ],
      );

  VisitaFormato copyWith({
    String? nombre,
    String? estado,
    List<VisitaFormatoItem>? items,
    int? version,
    List<VisitaFormatoParte>? partes,
    List<VisitaFormatoTabla>? tablas,
  }) => VisitaFormato(
    id: id,
    empresaId: empresaId,
    areaId: areaId,
    areaNombre: areaNombre,
    nombre: nombre ?? this.nombre,
    version: version ?? this.version,
    estado: estado ?? this.estado,
    items: items ?? this.items,
    partes: partes ?? this.partes,
    tablas: tablas ?? this.tablas,
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
  final tablaIds = <String>{};
  for (final t in f.tablas) {
    if (t.id.trim().isEmpty) {
      errores.add('Una tabla no tiene id.');
    } else if (!tablaIds.add(t.id)) {
      errores.add('La tabla "${t.id}" está repetida.');
    }
    if (t.camposEstado.isEmpty) {
      errores.add('La tabla "${t.nombre}" no tiene columnas de estado.');
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

  /// Solo ítems `elemento`: cuánto hay y cuándo vence (texto libre, como
  /// en el formato: "5 unidades", "12/2027").
  final String cantidad;
  final String vencimiento;

  /// Plan de acción propuesto para un "No cumple". Opcional: si no lo
  /// escriben, en el informe va la observación.
  final String accion;

  const VisitaRespuesta({
    this.resultado = '',
    this.observacion = '',
    this.evidencias = const [],
    this.cantidad = '',
    this.vencimiento = '',
    this.accion = '',
  });

  bool get respondida => resultado.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'resultado': resultado,
    'observacion': observacion,
    'evidencias': evidencias.map((e) => e.toMap()).toList(),
    'cantidad': cantidad,
    'vencimiento': vencimiento,
    'accion': accion,
  };

  factory VisitaRespuesta.fromMap(Map<String, dynamic> d) => VisitaRespuesta(
    resultado: (d['resultado'] ?? '').toString(),
    observacion: (d['observacion'] ?? '').toString(),
    evidencias: [
      for (final raw in (d['evidencias'] as List? ?? const []))
        if (raw is Map) VisitaEvidencia.fromMap(Map<String, dynamic>.from(raw)),
    ],
    cantidad: (d['cantidad'] ?? '').toString(),
    vencimiento: (d['vencimiento'] ?? '').toString(),
    accion: (d['accion'] ?? '').toString(),
  );

  VisitaRespuesta copyWith({
    String? resultado,
    String? observacion,
    List<VisitaEvidencia>? evidencias,
    String? cantidad,
    String? vencimiento,
    String? accion,
  }) => VisitaRespuesta(
    resultado: resultado ?? this.resultado,
    observacion: observacion ?? this.observacion,
    evidencias: evidencias ?? this.evidencias,
    cantidad: cantidad ?? this.cantidad,
    vencimiento: vencimiento ?? this.vencimiento,
    accion: accion ?? this.accion,
  );
}

/// Una fila de una tabla dinámica (un extintor). `campos` son los textos
/// (ubicación, tipo…), `estados` los B/M/R/NC por columna.
class VisitaFilaTabla {
  final String id;
  final Map<String, String> campos;
  final Map<String, String> estados;
  final String observacion;
  final List<VisitaEvidencia> evidencias;

  const VisitaFilaTabla({
    required this.id,
    this.campos = const {},
    this.estados = const {},
    this.observacion = '',
    this.evidencias = const [],
  });

  bool get tieneHallazgo => estados.values.any(filaEstadoEsHallazgo);

  /// Nombre corto de la fila para informes y tareas: el primer campo con
  /// texto (la ubicación, en extintores) o el id.
  String titulo(VisitaFormatoTabla t) {
    for (final c in t.camposTexto) {
      final v = (campos[c.id] ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return id;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'campos': campos,
    'estados': estados,
    'observacion': observacion,
    'evidencias': evidencias.map((e) => e.toMap()).toList(),
  };

  factory VisitaFilaTabla.fromMap(Map<String, dynamic> d) => VisitaFilaTabla(
    id: (d['id'] ?? '').toString(),
    campos: _strMap(d['campos']),
    estados: _strMap(d['estados']),
    observacion: (d['observacion'] ?? '').toString(),
    evidencias: [
      for (final raw in (d['evidencias'] as List? ?? const []))
        if (raw is Map) VisitaEvidencia.fromMap(Map<String, dynamic>.from(raw)),
    ],
  );

  VisitaFilaTabla copyWith({
    Map<String, String>? campos,
    Map<String, String>? estados,
    String? observacion,
    List<VisitaEvidencia>? evidencias,
  }) => VisitaFilaTabla(
    id: id,
    campos: campos ?? this.campos,
    estados: estados ?? this.estados,
    observacion: observacion ?? this.observacion,
    evidencias: evidencias ?? this.evidencias,
  );
}

Map<String, String> _strMap(Object? raw) => raw is Map
    ? {for (final e in raw.entries) e.key.toString(): (e.value ?? '').toString()}
    : const {};

/// Firma estampada en la visita. `modo` dice si fue la firma guardada del
/// perfil (`guardada`) o se dibujó en pantalla (`dibujada`). `blob` lleva
/// el PNG dentro del documento: es lo que lee el PDF en web sin pelear
/// con CORS de Storage, igual que la firma interna de Gestión Documental.
class VisitaFirma {
  final String nombre;
  final String cargo;
  final String modo;
  final String url;
  final String path;
  final Uint8List? blob;
  final Timestamp? at;

  const VisitaFirma({
    required this.nombre,
    this.cargo = '',
    required this.modo,
    this.url = '',
    this.path = '',
    this.blob,
    this.at,
  });

  bool get tieneImagen =>
      (blob != null && blob!.isNotEmpty) || url.isNotEmpty || path.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'cargo': cargo,
    'modo': modo,
    'url': url,
    'path': path,
    if (blob != null) 'blob': Blob(blob!),
    'at': at ?? Timestamp.now(),
  };

  factory VisitaFirma.fromMap(Map<String, dynamic> d) {
    final rawBlob = d['blob'];
    return VisitaFirma(
      nombre: (d['nombre'] ?? '').toString(),
      cargo: (d['cargo'] ?? '').toString(),
      modo: (d['modo'] ?? '').toString(),
      url: (d['url'] ?? '').toString(),
      path: (d['path'] ?? '').toString(),
      blob: rawBlob is Blob
          ? rawBlob.bytes
          : rawBlob is Uint8List
          ? rawBlob
          : null,
      at: d['at'] is Timestamp ? d['at'] as Timestamp : null,
    );
  }
}

const String kFirmaModoGuardada = 'guardada';
const String kFirmaModoDibujada = 'dibujada';

/// Quién recibió la visita en el establecimiento. Va en el encabezado del
/// formato ("RESPONSABLE ESTABLECIMIENTO / CARGO") y firma al final.
class VisitaResponsable {
  final String nombre;
  final String cargo;
  const VisitaResponsable({this.nombre = '', this.cargo = ''});

  bool get completo => nombre.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {'nombre': nombre, 'cargo': cargo};
  factory VisitaResponsable.fromMap(Map<String, dynamic> d) =>
      VisitaResponsable(
        nombre: (d['nombre'] ?? '').toString(),
        cargo: (d['cargo'] ?? '').toString(),
      );
}

/// Un cambio de fecha. Se guarda el historial completo: si una visita se
/// movió tres veces, el consolidado lo puede decir.
class VisitaReprogramacion {
  final DateTime de;
  final DateTime a;
  final String motivo;
  final String porId;
  final String porNombre;
  final Timestamp? at;

  const VisitaReprogramacion({
    required this.de,
    required this.a,
    required this.motivo,
    required this.porId,
    required this.porNombre,
    this.at,
  });

  Map<String, dynamic> toMap() => {
    'de': Timestamp.fromDate(de),
    'a': Timestamp.fromDate(a),
    'motivo': motivo,
    'porId': porId,
    'porNombre': porNombre,
    'at': at ?? Timestamp.now(),
  };

  factory VisitaReprogramacion.fromMap(Map<String, dynamic> d) =>
      VisitaReprogramacion(
        de: _fecha(d['de']),
        a: _fecha(d['a']),
        motivo: (d['motivo'] ?? '').toString(),
        porId: (d['porId'] ?? '').toString(),
        porNombre: (d['porNombre'] ?? '').toString(),
        at: d['at'] is Timestamp ? d['at'] as Timestamp : null,
      );
}

DateTime _fecha(Object? raw) => raw is Timestamp
    ? raw.toDate()
    : DateTime.tryParse(raw?.toString() ?? '') ?? DateTime(2000);

/// Dónde y cuándo. Lo pone el dispositivo, nunca la persona.
///
/// `distanciaMetros` es cuánto había hasta la referencia del maestro de
/// ubicaciones en ese momento; `dentroDelRadio` si esa distancia cabía en
/// el radio del establecimiento. Se guardan calculados para que el informe
/// no dependa de que la referencia siga igual.
class VisitaMarca {
  final Timestamp at;
  final double? lat;
  final double? lng;
  final double? precisionMetros;
  final double? distanciaMetros;
  final bool? dentroDelRadio;

  const VisitaMarca({
    required this.at,
    this.lat,
    this.lng,
    this.precisionMetros,
    this.distanciaMetros,
    this.dentroDelRadio,
  });

  bool get tieneUbicacion => lat != null && lng != null;

  Map<String, dynamic> toMap() => {
    'at': at,
    'lat': lat,
    'lng': lng,
    'precisionMetros': precisionMetros,
    'distanciaMetros': distanciaMetros,
    'dentroDelRadio': dentroDelRadio,
  };

  factory VisitaMarca.fromMap(Map<String, dynamic> d) => VisitaMarca(
    at: d['at'] is Timestamp ? d['at'] as Timestamp : Timestamp.now(),
    lat: (d['lat'] as num?)?.toDouble(),
    lng: (d['lng'] as num?)?.toDouble(),
    precisionMetros: (d['precisionMetros'] as num?)?.toDouble(),
    distanciaMetros: (d['distanciaMetros'] as num?)?.toDouble(),
    dentroDelRadio: d['dentroDelRadio'] is bool
        ? d['dentroDelRadio'] as bool
        : null,
  );
}

// ── Maestro de ubicaciones ──────────────────────────────────────────────────

/// Coordenadas de un establecimiento (o de un subcentro, si tiene las
/// suyas). docId: `{empresaId}_{centroId}` o `{empresaId}_{centroId}__{sub}`.
class VisitaUbicacion {
  final String id;
  final String empresaId;
  final String centroId;
  final String centroNombre;
  final String subcentroId;
  final String subcentroNombre;
  final double lat;
  final double lng;
  final double radioMetros;
  final String ciudad;
  final String direccion;
  final String actualizadoPor;

  const VisitaUbicacion({
    this.id = '',
    required this.empresaId,
    required this.centroId,
    required this.centroNombre,
    this.subcentroId = '',
    this.subcentroNombre = '',
    required this.lat,
    required this.lng,
    this.radioMetros = kVisitasRadioDefectoMetros,
    this.ciudad = '',
    this.direccion = '',
    this.actualizadoPor = '',
  });

  static String docId(String empresaId, String centroId, String subcentroId) =>
      subcentroId.isEmpty
      ? '${empresaId}_$centroId'
      : '${empresaId}_${centroId}__$subcentroId';

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'centroId': centroId,
    'centroNombre': centroNombre,
    'subcentroId': subcentroId,
    'subcentroNombre': subcentroNombre,
    'lat': lat,
    'lng': lng,
    'radioMetros': radioMetros,
    'ciudad': ciudad,
    'direccion': direccion,
    'actualizadoPor': actualizadoPor,
  };

  factory VisitaUbicacion.fromMap(String id, Map<String, dynamic> d) =>
      VisitaUbicacion(
        id: id,
        empresaId: (d['empresaId'] ?? '').toString(),
        centroId: (d['centroId'] ?? '').toString(),
        centroNombre: (d['centroNombre'] ?? '').toString(),
        subcentroId: (d['subcentroId'] ?? '').toString(),
        subcentroNombre: (d['subcentroNombre'] ?? '').toString(),
        lat: (d['lat'] as num?)?.toDouble() ?? 0,
        lng: (d['lng'] as num?)?.toDouble() ?? 0,
        radioMetros:
            (d['radioMetros'] as num?)?.toDouble() ??
            kVisitasRadioDefectoMetros,
        ciudad: (d['ciudad'] ?? '').toString(),
        direccion: (d['direccion'] ?? '').toString(),
        actualizadoPor: (d['actualizadoPor'] ?? '').toString(),
      );
}

/// Distancia en metros entre dos puntos (haversine). Pura, para poder
/// probarla sin GPS.
double distanciaMetros(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double g) => g * math.pi / 180;

/// Resultado de comprobar dónde está el profesional antes de iniciar.
class VerificacionUbicacion {
  final bool permitido;
  final String motivo;
  final double? distancia;
  const VerificacionUbicacion({
    required this.permitido,
    this.motivo = '',
    this.distancia,
  });
}

/// La regla del 17 sep 2026: sin GPS no se inicia; sin referencia en el
/// maestro no se inicia; fuera del radio no se inicia. La precisión del
/// GPS se descuenta de la distancia: si el teléfono dice "±40 m" y la
/// referencia está a 170 m con radio 150, la persona bien puede estar
/// adentro. Se bloquea solo cuando ni con esa tolerancia alcanza.
VerificacionUbicacion verificarUbicacionInicio({
  required VisitaUbicacion? referencia,
  required double? lat,
  required double? lng,
  double? precisionMetros,
}) {
  if (lat == null || lng == null) {
    return const VerificacionUbicacion(
      permitido: false,
      motivo:
          'No se pudo obtener la ubicación del dispositivo. Activa el GPS y '
          'dale permiso a la aplicación: sin ubicación la visita no se inicia.',
    );
  }
  if (referencia == null) {
    return const VerificacionUbicacion(
      permitido: false,
      motivo:
          'Este establecimiento no tiene ubicación cargada en el maestro. '
          'Pídele a Desarrollo que la registre antes de la visita.',
    );
  }
  final d = distanciaMetros(lat, lng, referencia.lat, referencia.lng);
  final tolerancia = (precisionMetros ?? 0).clamp(0, 100).toDouble();
  if (d - tolerancia > referencia.radioMetros) {
    return VerificacionUbicacion(
      permitido: false,
      distancia: d,
      motivo:
          'Estás a ${d.round()} m de ${referencia.subcentroNombre.isEmpty ? referencia.centroNombre : '${referencia.centroNombre} ${referencia.subcentroNombre}'} '
          'y el radio permitido es ${referencia.radioMetros.round()} m. '
          'Acércate al establecimiento para iniciar.',
    );
  }
  return VerificacionUbicacion(permitido: true, distancia: d);
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

  /// Filas de las tablas dinámicas, por id de tabla.
  final Map<String, List<VisitaFilaTabla>> tablas;

  /// Encabezado del formato: quién recibió, ciudad, cargo de quien inspecciona.
  final VisitaResponsable responsableEstablecimiento;
  final String ciudad;
  final String cargoProfesional;

  final VisitaFirma? firmaProfesional;
  final VisitaFirma? firmaEstablecimiento;
  final List<VisitaReprogramacion> reprogramaciones;

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
    this.tablas = const {},
    this.responsableEstablecimiento = const VisitaResponsable(),
    this.ciudad = '',
    this.cargoProfesional = '',
    this.firmaProfesional,
    this.firmaEstablecimiento,
    this.reprogramaciones = const [],
  });

  String get establecimiento =>
      subcentroNombre.isEmpty ? centroNombre : '$centroNombre $subcentroNombre';

  List<VisitaFilaTabla> filasDe(String tablaId) => tablas[tablaId] ?? const [];

  bool get firmada => firmaProfesional != null && firmaEstablecimiento != null;

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
    'tablas': {
      for (final e in tablas.entries)
        e.key: e.value.map((f) => f.toMap()).toList(),
    },
    'responsableEstablecimiento': responsableEstablecimiento.toMap(),
    'ciudad': ciudad,
    'cargoProfesional': cargoProfesional,
    'firmaProfesional': firmaProfesional?.toMap(),
    'firmaEstablecimiento': firmaEstablecimiento?.toMap(),
    'reprogramaciones': reprogramaciones.map((r) => r.toMap()).toList(),
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
    final rawTablas = d['tablas'];
    final tablas = <String, List<VisitaFilaTabla>>{};
    if (rawTablas is Map) {
      for (final e in rawTablas.entries) {
        tablas[e.key.toString()] = [
          for (final f in (e.value as List? ?? const []))
            if (f is Map) VisitaFilaTabla.fromMap(Map<String, dynamic>.from(f)),
        ];
      }
    }
    VisitaFirma? firma(Object? raw) => raw is Map
        ? VisitaFirma.fromMap(Map<String, dynamic>.from(raw))
        : null;
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
      tablas: tablas,
      responsableEstablecimiento: d['responsableEstablecimiento'] is Map
          ? VisitaResponsable.fromMap(
              Map<String, dynamic>.from(d['responsableEstablecimiento'] as Map),
            )
          : const VisitaResponsable(),
      ciudad: (d['ciudad'] ?? '').toString(),
      cargoProfesional: (d['cargoProfesional'] ?? '').toString(),
      firmaProfesional: firma(d['firmaProfesional']),
      firmaEstablecimiento: firma(d['firmaEstablecimiento']),
      reprogramaciones: [
        for (final r in (d['reprogramaciones'] as List? ?? const []))
          if (r is Map)
            VisitaReprogramacion.fromMap(Map<String, dynamic>.from(r)),
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
  Map<String, VisitaRespuesta> respuestas, {
  String? parte,
}) {
  var cumple = 0, noCumple = 0, noAplica = 0, sin = 0, total = 0;
  for (final it in formato.items) {
    if (parte != null && it.parte != parte) continue;
    total++;
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
    total: total,
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
  VisitaProfesional visita, {
  bool exigirFirmas = true,
}) {
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
    if (!resultadosPermitidos(it.tipo).contains(r.resultado)) {
      errores.add('Ítem ${it.orden} tiene una respuesta que no admite.');
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
  for (final t in formato.tablas) {
    final filas = visita.filasDe(t.id);
    if (filas.isEmpty) {
      // Un establecimiento sin extintores es un hallazgo, no una tabla vacía:
      // se registra una fila "No cuenta".
      errores.add('${t.nombre}: no hay ninguna fila registrada.');
    }
    for (var i = 0; i < filas.length; i++) {
      final f = filas[i];
      for (final c in t.camposEstado) {
        final e = f.estados[c.id] ?? '';
        if (!kFilaEstadoLabel.containsKey(e)) {
          errores.add('${t.etiquetaFila} ${i + 1}: falta "${c.label}".');
        }
      }
      if (f.tieneHallazgo && f.observacion.trim().isEmpty) {
        errores.add(
          '${t.etiquetaFila} ${i + 1} tiene novedad y no dice cuál.',
        );
      }
    }
  }
  if (!visita.responsableEstablecimiento.completo) {
    errores.add('Falta el nombre del responsable del establecimiento.');
  }
  if (exigirFirmas) {
    if (visita.firmaProfesional == null) {
      errores.add('Falta la firma de quien realiza la inspección.');
    }
    if (visita.firmaEstablecimiento == null) {
      errores.add('Falta la firma del responsable del establecimiento.');
    }
  }
  return errores;
}

/// Un hallazgo por cada "No cumple" y por cada fila de tabla en M o NC.
/// Es lo que se vuelve tarea al cerrar y lo que llena "Mejora y
/// seguimiento" en el informe.
class VisitaHallazgo {
  /// Clave estable: id del ítem, o `tabla:fila` para una fila.
  final String clave;
  final String elemento;
  final String novedad;
  final String accion;
  final List<VisitaEvidencia> evidencias;

  const VisitaHallazgo({
    required this.clave,
    required this.elemento,
    required this.novedad,
    this.accion = '',
    this.evidencias = const [],
  });
}

List<VisitaHallazgo> hallazgosDeVisita(
  VisitaFormato formato,
  Map<String, VisitaRespuesta> respuestas, {
  Map<String, List<VisitaFilaTabla>> tablas = const {},
}) {
  final out = <VisitaHallazgo>[];
  for (final it in formato.itemsOrdenados) {
    final r = respuestas[it.id];
    if (r?.resultado != kItemNoCumple) continue;
    out.add(
      VisitaHallazgo(
        clave: it.id,
        elemento: 'Ítem ${it.orden}: ${it.texto}',
        novedad: r!.observacion,
        accion: r.accion,
        evidencias: r.evidencias,
      ),
    );
  }
  for (final t in formato.tablas) {
    final filas = tablas[t.id] ?? const [];
    for (final f in filas) {
      if (!f.tieneHallazgo) continue;
      final malos = [
        for (final c in t.camposEstado)
          if (filaEstadoEsHallazgo(f.estados[c.id] ?? ''))
            '${c.label}: ${kFilaEstadoLabel[f.estados[c.id]]}',
      ];
      out.add(
        VisitaHallazgo(
          clave: '${t.id}:${f.id}',
          elemento: '${t.etiquetaFila} ${f.titulo(t)}',
          novedad: [
            malos.join(', '),
            f.observacion,
          ].where((s) => s.trim().isNotEmpty).join(' · '),
          evidencias: f.evidencias,
        ),
      );
    }
  }
  return out;
}

String tituloTareaHallazgo(VisitaProfesional v, VisitaHallazgo h) =>
    'Visita ${v.areaNombre} · ${v.establecimiento}: ${h.elemento}';

String descripcionTareaHallazgo(VisitaProfesional v, VisitaHallazgo h) {
  final b = StringBuffer()
    ..writeln('Hallazgo de la visita de ${v.areaNombre} del ')
    ..writeln(
      '${v.fechaProgramada.day.toString().padLeft(2, '0')}/'
      '${v.fechaProgramada.month.toString().padLeft(2, '0')}/'
      '${v.fechaProgramada.year} a ${v.establecimiento}.',
    )
    ..writeln()
    ..writeln(h.elemento)
    ..writeln('Novedad encontrada: ${h.novedad}');
  if (h.accion.trim().isNotEmpty) b.writeln('Acción propuesta: ${h.accion}');
  if (h.evidencias.isNotEmpty) {
    b.writeln('Evidencias: ${h.evidencias.length}');
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
/// Hallazgos de una visita sin necesidad del formato: "No cumple" en los
/// ítems más filas de tabla en M/NC.
int hallazgosDe(VisitaProfesional v) =>
    v.respuestas.values.where((r) => r.resultado == kItemNoCumple).length +
    v.tablas.values.fold(
      0,
      (acc, filas) => acc + filas.where((f) => f.tieneHallazgo).length,
    );

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
    // Las filas de tabla (extintores en M o NC) también son hallazgos; se
    // agrupan por tabla porque cada fila es un equipo distinto.
    for (final e in v.tablas.entries) {
      final n = e.value.where((fila) => fila.tieneHallazgo).length;
      if (n == 0) continue;
      hallazgos += n;
      incumplidos[e.key] = (incumplidos[e.key] ?? 0) + n;
      final t = f?.tabla(e.key);
      if (t != null) textoItem[e.key] = t.nombre;
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
              hallazgos: e.value.fold(0, (acc, v) => acc + hallazgosDe(v)),
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
//
// HSE ya no va aquí: su formato oficial llegó el 17 sep 2026 y vive en
// `visitas_formato_sst.dart` (se siembra vigente desde el servicio).

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

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

import '../core/area_directory.dart' show areaClave;
import '../core/subcentros_costo.dart' show slugSubcentro;

const String kVisitasAppId = 'visitasdashboard';

const String kVisitasCol = 'TBL_VISITAS';
const String kVisitasFormatosCol = 'TBL_VISITAS_FORMATOS';
const String kVisitasRolesCol = 'TBL_VISITAS_ROLES';

/// Grupos de profesionales con sus establecimientos (25 sep 2026): el jefe
/// arma grupos dentro de su área y a cada grupo le asigna los centros de
/// costo que visita. Programar propone primero esos centros.
const String kVisitasGruposCol = 'TBL_VISITAS_GRUPOS';

/// Maestro de ubicaciones de los establecimientos (17 sep 2026).
///
/// Vive aparte de TBL_CENTROS_COSTOS a propósito: las coordenadas las carga
/// solo Desarrollo y sirven para comprobar que el profesional está en el
/// sitio. Un centro sin ubicación aquí no se puede visitar: primero se
/// carga el maestro.
const String kVisitasUbicacionesCol = 'TBL_VISITAS_UBICACIONES';

/// Establecimientos propios de Visitas (5 oct 2026): "ciertos
/// establecimientos que no son necesariamente iguales a los de
/// Interventoría, pero sí hacen falta para las visitas". Se programan igual
/// que un centro de costo, pero no existen en `TBL_CENTROS_COSTOS` (no los
/// ven Interventoría ni Facturación). Se crean en Admin › Maestros por
/// módulo › Visitas; el id del documento es el `centroId` de la visita.
const String kVisitasEstablecimientosCol = 'TBL_VISITAS_ESTABLECIMIENTOS';

/// Radio por defecto alrededor del establecimiento, en metros. Corto a
/// propósito: la idea es saber que el acta se hace adentro, no en la
/// cuadra. Se puede ajustar por establecimiento en el maestro.
const double kVisitasRadioDefectoMetros = 150;

// ── Roles ───────────────────────────────────────────────────────────────────
//
// Quien programa (el jefe inmediato o director del área), quien va (el
// profesional), quien solo mira (gerencia, calidad) y, desde el 25 sep 2026,
// quien recibe la visita y la firma desde su propio módulo (el
// administrador del establecimiento). El desarrollador entra como jefe.

const String kVisitasRolJefe = 'jefe';
const String kVisitasRolProfesional = 'profesional';
const String kVisitasRolConsulta = 'consulta';

/// Administrador del establecimiento que recibe la visita. Firma el acta
/// desde su módulo, con su cuenta y su dispositivo, en vez de firmar en la
/// tablet del profesional: así la firma queda a su nombre y no a nombre de
/// quien le prestó el equipo.
const String kVisitasRolFirmante = 'firmante';

/// Coordinador (8 oct 2026): ve, solo para consulta, las visitas de los
/// profesionales (supervisores) de los grupos que coordina, y de ningún otro
/// grupo. Se nombra coordinador al armar el grupo (Equipo › Grupos y
/// establecimientos); la visita lleva `coordinadorIds` y lo escribe el
/// servidor, así que ver o no ver una visita lo deciden las reglas.
const String kVisitasRolCoordinador = 'coordinador';

/// Gerencia (26 sep 2026): "es el jefe de todos, así que él puede ver
/// absolutamente todo y hacer todos los formatos". Ve y hace en Visitas lo
/// mismo que Desarrollo: todas las áreas, formatos, cronograma, equipo,
/// consolidado y el maestro de ubicaciones. No trabaja dentro de un área.
const String kVisitasRolGerencia = 'gerencia';

const Map<String, String> kVisitasRolesLabel = {
  kVisitasRolJefe: 'Jefe inmediato (director)',
  kVisitasRolProfesional: 'Profesional',
  kVisitasRolConsulta: 'Consulta',
  kVisitasRolFirmante: 'Firmante del establecimiento',
  kVisitasRolCoordinador: 'Coordinador (ve los grupos que coordina)',
  kVisitasRolGerencia: 'Gerencia (ve y administra todo)',
};

/// El rol limita lo que se ve y se programa por área; firmante, consulta y
/// gerencia no trabajan dentro de un área.
bool visitasRolRequiereArea(String? rol) =>
    rol == kVisitasRolJefe || rol == kVisitasRolProfesional;

/// El cargo es de Gerencia: "Gerencia", "Gerencia general", "Gerente…". Un
/// subgerente o un "director de gerencia" no: es el jefe de todos.
/// Mismo criterio que `esCargoGerencia` en `firestore.rules`.
bool esCargoGerenciaVisitas(String cargo) {
  final c = cargo.trim().toLowerCase();
  return c.startsWith('gerente') || c.startsWith('gerencia');
}

/// El rol con que se entra a Visitas (27 sep 2026). Quien tiene cargo de
/// Gerencia (o el rol de la app `gerencia` / `gerente`) entra como Gerencia
/// aunque en Roles y permisos no se le haya asignado: "a don Oscar no le
/// sale nada" era justo eso, que el rol dependía de que alguien lo diera.
/// Si no, el rol guardado; y Desarrollo sin rol entra como jefe.
String? resolverRolVisitas({
  required String? rolGuardado,
  required bool esDesarrollador,
  String cargo = '',
  String rolApp = '',
}) {
  final app = rolApp.trim().toLowerCase();
  if (esCargoGerenciaVisitas(cargo) || app == 'gerencia' || app == 'gerente') {
    return kVisitasRolGerencia;
  }
  if (rolGuardado != null) return rolGuardado;
  return esDesarrollador ? kVisitasRolJefe : null;
}

/// Quien ve y administra todas las áreas: Desarrollo y Gerencia. Es lo que
/// las pantallas llaman "todo acceso" y lo mismo que exigen las reglas.
bool visitasTodoAcceso({required String? rol, required bool esDesarrollador}) =>
    esDesarrollador || rol == kVisitasRolGerencia;

bool _administra(String? rol) =>
    rol == kVisitasRolJefe || rol == kVisitasRolGerencia;

bool visitasPuedeProgramar(String? rol) => _administra(rol);
bool visitasPuedeGestionarFormatos(String? rol) => _administra(rol);

/// El maestro de equipo (roles, grupos y centros) es del jefe de área. Un
/// jefe solo puede dar o quitar el rol Profesional dentro de su área; el
/// director (jefe) lo nombra Desarrollo o Gerencia, igual que exigen las
/// reglas.
bool visitasPuedeGestionarEquipo(String? rol) => _administra(rol);

/// El firmante designado firma mientras la visita está en curso y la firma
/// del establecimiento sigue vacía. Nadie más firma por él.
bool visitasPuedeFirmarComoEstablecimiento({
  required VisitaProfesional visita,
  required String userId,
}) =>
    visita.estado == kVisitaEnCurso &&
    visita.firmanteEstablecimientoId.isNotEmpty &&
    visita.firmanteEstablecimientoId == userId &&
    visita.firmaEstablecimiento == null;

/// El consolidado (28 sep 2026): el director ve el de su departamento y el
/// profesional el de sus propias actas; Gerencia, Desarrollo y Consulta, el
/// del departamento que elijan.
bool visitasPuedeVerConsolidado(String? rol) =>
    _administra(rol) ||
    rol == kVisitasRolConsulta ||
    rol == kVisitasRolProfesional;

/// Aprobar o rechazar un cambio de fecha: quien programa (el jefe del
/// departamento, Gerencia y Desarrollo).
bool visitasPuedeResponderSolicitud(String? rol) => _administra(rol);

/// Reprogramar: solo el jefe, y solo una visita todavía programada.
///
/// El 17 sep 2026 se había dejado que el profesional moviera la suya; el
/// 18 sep Oscar lo cerró: el cronograma lo arma y lo corrige únicamente la
/// dirección, "porque si usted le dice a la gente cómo quiera hacerlo, ellos
/// van a acomodarse" y es el director quien garantiza que se cumple la
/// norma. Una visita ya iniciada no se mueve.
bool visitasPuedeReprogramar({
  required String? rol,
  required VisitaProfesional visita,
  required String userId,
  DateTime? ahora,
}) {
  if (visita.estado != kVisitaProgramada || !_administra(rol)) return false;
  // 1 oct 2026: una visita que no se cumplió no la mueve el jefe por su
  // cuenta; primero el profesional pide la reasignación (queda el registro).
  return !visitaIncumplida(visita, ahora ?? DateTime.now()) ||
      visita.solicitudFecha?.pendiente == true;
}

/// El maestro de ubicaciones es de Desarrollo y Gerencia (26 sep 2026: "solo
/// los podemos agregar el desarrollador y el gerente"). Los profesionales y
/// los jefes de área no lo tocan: es lo que decide si una visita se puede
/// iniciar.
bool visitasPuedeGestionarUbicaciones({
  required bool esDesarrollador,
  String? rol,
}) => esDesarrollador || rol == kVisitasRolGerencia;

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

// Tipos "de formulario" (26 sep 2026: "que parezca prácticamente un formato
// de Google"). Recogen un dato del sitio —el nombre del manipulador, cuántos
// comensales, la fecha del último fumigado— y NO califican: no suman ni
// restan en el cumplimiento y nunca son hallazgo.
const String kItemTipoTexto = 'texto';
const String kItemTipoParrafo = 'parrafo';
const String kItemTipoNumero = 'numero';
const String kItemTipoFecha = 'fecha';
const String kItemTipoOpcion = 'opcion';

/// Cómo se le dice a cada tipo en pantalla y en la plantilla Excel. "Elemento"
/// no le decía nada a nadie (26 sep 2026): el nombre dice qué se responde.
const Map<String, String> kItemTiposLabel = {
  kItemTipoCalificacion: 'Cumple / No cumple / No aplica',
  kItemTipoSiNo: 'Sí / No',
  kItemTipoElemento: 'Sí / No con cantidad y vencimiento',
  kItemTipoOpcion: 'Lista de opciones',
  kItemTipoTexto: 'Respuesta corta',
  kItemTipoParrafo: 'Párrafo',
  kItemTipoNumero: 'Número',
  kItemTipoFecha: 'Fecha',
};

/// Para qué sirve cada tipo, en una línea.
const Map<String, String> kItemTiposAyuda = {
  kItemTipoCalificacion:
      'Se califica 1 (cumple), 0 (no cumple) o NA. Cuenta en el % y un "No '
      'cumple" se vuelve tarea.',
  kItemTipoSiNo:
      'Solo Sí o No, sin "No aplica". Un "No" cuenta como no cumple y se '
      'vuelve tarea.',
  kItemTipoElemento:
      'Para revisar que un elemento esté (gasas del botiquín, guantes…) y '
      'anotar cuántos hay y cuándo vencen. Escribe lo esperado en "Cantidad '
      'esperada".',
  kItemTipoOpcion:
      'El profesional elige una de las opciones que escribas. No califica.',
  kItemTipoTexto: 'Un dato corto: un nombre, una placa. No califica.',
  kItemTipoParrafo: 'Texto largo o descripción. No califica.',
  kItemTipoNumero:
      'Una cantidad o medida: comensales, temperatura. No '
      'califica.',
  kItemTipoFecha: 'Una fecha: último fumigado, vencimiento. No califica.',
};

/// Los tipos que califican: cuentan en el cumplimiento y pueden ser hallazgo.
bool itemCalifica(String tipo) =>
    tipo == kItemTipoCalificacion ||
    tipo == kItemTipoSiNo ||
    tipo == kItemTipoElemento;

List<String> resultadosPermitidos(String tipo) => switch (tipo) {
  kItemTipoCalificacion => const [kItemCumple, kItemNoCumple, kItemNoAplica],
  kItemTipoSiNo || kItemTipoElemento => const [kItemCumple, kItemNoCumple],
  _ => const [],
};

// ── Estados de una fila de tabla ────────────────────────────────────────────
//
// Escala de extintores (F-UT-SST-03): B Bueno, M Malo, R Regular, NC No
// cuenta con el elemento; M y NC son hallazgo. Desde el 26 sep 2026 una tabla
// también puede calificar con Cumple / No cumple / No aplica o con Sí / No.
// Los códigos no se repiten entre escalas para que "¿es hallazgo?" no dependa
// de saber de qué tabla viene la fila.

const String kFilaBueno = 'B';
const String kFilaMalo = 'M';
const String kFilaRegular = 'R';
const String kFilaNoCuenta = 'NC';
const String kFilaCumple = 'CU';
const String kFilaNoCumple = 'NCU';
const String kFilaNoAplica = 'NA';
const String kFilaSi = 'SI';
const String kFilaNo = 'NO';

const Map<String, String> kFilaEstadoLabel = {
  kFilaBueno: 'Bueno',
  kFilaMalo: 'Malo',
  kFilaRegular: 'Regular',
  kFilaNoCuenta: 'No cuenta',
  kFilaCumple: 'Cumple',
  kFilaNoCumple: 'No cumple',
  kFilaNoAplica: 'No aplica',
  kFilaSi: 'Sí',
  kFilaNo: 'No',
};

const String kEscalaBmrnc = 'bmrnc';
const String kEscalaCumple = 'cumple';
const String kEscalaSiNo = 'si_no';

const Map<String, String> kEscalasLabel = {
  kEscalaBmrnc: 'Bueno / Malo / Regular / No cuenta',
  kEscalaCumple: 'Cumple / No cumple / No aplica',
  kEscalaSiNo: 'Sí / No',
};

/// Un estado de la escala: el código guardado, lo que va en el botón y el
/// nombre completo.
typedef EstadoEscala = ({String codigo, String corto, String nombre});

List<EstadoEscala> estadosDeEscala(String escala) => switch (escala) {
  kEscalaCumple => const [
    (codigo: kFilaCumple, corto: 'C', nombre: 'Cumple'),
    (codigo: kFilaNoCumple, corto: 'NC', nombre: 'No cumple'),
    (codigo: kFilaNoAplica, corto: 'NA', nombre: 'No aplica'),
  ],
  kEscalaSiNo => const [
    (codigo: kFilaSi, corto: 'Sí', nombre: 'Sí'),
    (codigo: kFilaNo, corto: 'No', nombre: 'No'),
  ],
  _ => const [
    (codigo: kFilaBueno, corto: 'B', nombre: 'Bueno'),
    (codigo: kFilaMalo, corto: 'M', nombre: 'Malo'),
    (codigo: kFilaRegular, corto: 'R', nombre: 'Regular'),
    (codigo: kFilaNoCuenta, corto: 'NC', nombre: 'No cuenta con el elemento'),
  ],
};

bool estadoValidoEnEscala(String escala, String? estado) =>
    estadosDeEscala(escala).any((e) => e.codigo == estado);

/// Lo que va en la celda del informe: el código corto de su escala.
String estadoCorto(String escala, String? estado) =>
    estadosDeEscala(
      escala,
    ).where((e) => e.codigo == estado).firstOrNull?.corto ??
    (estado ?? '');

/// La leyenda que acompaña la tabla: "B: Bueno · M: Malo…".
String leyendaEscala(String escala) => [
  for (final e in estadosDeEscala(escala)) '${e.corto}: ${e.nombre}',
].join(' · ');

bool filaEstadoEsHallazgo(String estado) =>
    estado == kFilaMalo ||
    estado == kFilaNoCuenta ||
    estado == kFilaNoCumple ||
    estado == kFilaNo;

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

  /// Solo para `opcion`: las opciones entre las que se elige.
  final List<String> opciones;

  /// Si la pregunta se debe contestar para cerrar. Las que califican siempre
  /// son obligatorias; las de formulario pueden quedar opcionales.
  final bool obligatoria;

  /// Texto de ayuda debajo de la pregunta, como la descripción de Google
  /// Forms: qué mirar, cómo medir.
  final String ayuda;

  const VisitaFormatoItem({
    required this.id,
    required this.orden,
    this.seccion = '',
    required this.texto,
    this.requiereEvidencia = false,
    this.tipo = kItemTipoCalificacion,
    this.parte = '',
    this.unidad = '',
    this.opciones = const [],
    this.obligatoria = true,
    this.ayuda = '',
  });

  bool get esElemento => tipo == kItemTipoElemento;
  bool get califica => itemCalifica(tipo);

  /// Los campos nuevos solo se escriben cuando traen algo. Las reglas de
  /// Firestore comparan `formatoAsignado.items` con los ítems guardados del
  /// formato, campo por campo: si un formato viejo (sin estos campos) se
  /// copiara con `opciones: []` o `obligatoria: true`, ya no sería igual y
  /// programar sobre él daría permission-denied.
  Map<String, dynamic> toMap() => {
    'id': id,
    'orden': orden,
    'seccion': seccion,
    'texto': texto,
    'requiereEvidencia': requiereEvidencia,
    'tipo': tipo,
    'parte': parte,
    'unidad': unidad,
    if (opciones.isNotEmpty) 'opciones': opciones,
    if (!obligatoria) 'obligatoria': false,
    if (ayuda.isNotEmpty) 'ayuda': ayuda,
  };

  factory VisitaFormatoItem.fromMap(Map<String, dynamic> d) =>
      VisitaFormatoItem(
        id: (d['id'] ?? '').toString(),
        orden: (d['orden'] as num?)?.toInt() ?? 0,
        seccion: (d['seccion'] ?? '').toString(),
        texto: (d['texto'] ?? '').toString(),
        requiereEvidencia: d['requiereEvidencia'] == true,
        tipo: tipoItemDesde((d['tipo'] ?? '').toString()),
        parte: (d['parte'] ?? '').toString(),
        unidad: (d['unidad'] ?? '').toString(),
        opciones: [
          for (final o in (d['opciones'] as List? ?? const []))
            if (o.toString().trim().isNotEmpty) o.toString().trim(),
        ],
        obligatoria: d['obligatoria'] != false,
        ayuda: (d['ayuda'] ?? '').toString(),
      );

  VisitaFormatoItem copyWith({
    int? orden,
    String? seccion,
    String? texto,
    bool? requiereEvidencia,
    String? tipo,
    String? parte,
    String? unidad,
    List<String>? opciones,
    bool? obligatoria,
    String? ayuda,
  }) => VisitaFormatoItem(
    id: id,
    orden: orden ?? this.orden,
    seccion: seccion ?? this.seccion,
    texto: texto ?? this.texto,
    requiereEvidencia: requiereEvidencia ?? this.requiereEvidencia,
    tipo: tipo ?? this.tipo,
    parte: parte ?? this.parte,
    unidad: unidad ?? this.unidad,
    opciones: opciones ?? this.opciones,
    obligatoria: obligatoria ?? this.obligatoria,
    ayuda: ayuda ?? this.ayuda,
  );
}

/// Un tipo desconocido cae en `calificacion`: es el que siempre existió y
/// el que menos exige.
String tipoItemDesde(String raw) =>
    kItemTiposLabel.containsKey(raw) ? raw : kItemTipoCalificacion;

/// ¿La respuesta de formulario es válida para su tipo? Vacía siempre lo es
/// (si falta, lo dice `obligatoria`).
bool valorValidoParaItem(VisitaFormatoItem it, String valor) {
  final v = valor.trim();
  if (v.isEmpty) return true;
  return switch (it.tipo) {
    kItemTipoNumero => double.tryParse(v.replaceAll(',', '.')) != null,
    kItemTipoOpcion => it.opciones.isEmpty || it.opciones.contains(v),
    _ => true,
  };
}

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

  /// Con qué se califica cada columna de estado (26 sep 2026). Por defecto la
  /// de extintores: Bueno / Malo / Regular / No cuenta.
  final String escala;

  /// Filas que trae el formato, como las filas de una cuadrícula de Google
  /// Forms ("Cocina", "Bodega", "Baños"). Con filas fijas el profesional
  /// califica esas y no agrega otras; sin ellas agrega las que encuentre en
  /// el sitio (un extintor por fila).
  final List<String> filasFijas;

  const VisitaFormatoTabla({
    required this.id,
    this.parte = '',
    required this.nombre,
    this.etiquetaFila = 'Fila',
    this.camposTexto = const [],
    this.camposEstado = const [],
    this.escala = kEscalaBmrnc,
    this.filasFijas = const [],
  });

  bool get conFilasFijas => filasFijas.isNotEmpty;

  /// `escala` y `filasFijas` solo se escriben si no son las de siempre, por
  /// la misma razón que en [VisitaFormatoItem.toMap]: las reglas comparan
  /// las tablas del formato asignado con las guardadas.
  Map<String, dynamic> toMap() => {
    'id': id,
    'parte': parte,
    'nombre': nombre,
    'etiquetaFila': etiquetaFila,
    'camposTexto': camposTexto.map((c) => c.toMap()).toList(),
    'camposEstado': camposEstado.map((c) => c.toMap()).toList(),
    if (escala != kEscalaBmrnc) 'escala': escala,
    if (filasFijas.isNotEmpty) 'filasFijas': filasFijas,
  };

  factory VisitaFormatoTabla.fromMap(Map<String, dynamic> d) =>
      VisitaFormatoTabla(
        id: (d['id'] ?? '').toString(),
        parte: (d['parte'] ?? '').toString(),
        nombre: (d['nombre'] ?? '').toString(),
        etiquetaFila: (d['etiquetaFila'] ?? 'Fila').toString(),
        camposTexto: _campos(d['camposTexto']),
        camposEstado: _campos(d['camposEstado']),
        escala: kEscalasLabel.containsKey(d['escala'])
            ? d['escala'].toString()
            : kEscalaBmrnc,
        filasFijas: [
          for (final f in (d['filasFijas'] as List? ?? const []))
            if (f.toString().trim().isNotEmpty) f.toString().trim(),
        ],
      );

  VisitaFormatoTabla copyWith({
    String? parte,
    String? nombre,
    String? etiquetaFila,
    List<VisitaTablaCampo>? camposTexto,
    List<VisitaTablaCampo>? camposEstado,
    String? escala,
    List<String>? filasFijas,
  }) => VisitaFormatoTabla(
    id: id,
    parte: parte ?? this.parte,
    nombre: nombre ?? this.nombre,
    etiquetaFila: etiquetaFila ?? this.etiquetaFila,
    camposTexto: camposTexto ?? this.camposTexto,
    camposEstado: camposEstado ?? this.camposEstado,
    escala: escala ?? this.escala,
    filasFijas: filasFijas ?? this.filasFijas,
  );

  static List<VisitaTablaCampo> _campos(Object? raw) => [
    for (final r in (raw as List? ?? const []))
      if (r is Map) VisitaTablaCampo.fromMap(Map<String, dynamic>.from(r)),
  ];
}

/// Id de la fila fija número [i] (desde 0). Estable: la visita guarda una
/// copia del formato, así que el orden de sus filas fijas no cambia.
String idFilaFija(int i) => 'fija_${i + 1}';

/// Las filas que se muestran y se validan de una tabla: con filas fijas, una
/// por cada fila del formato (la guardada o una vacía para llenar); sin
/// ellas, las que agregó el profesional.
List<VisitaFilaTabla> filasParaTabla(
  VisitaFormatoTabla t,
  List<VisitaFilaTabla> guardadas,
) {
  if (!t.conFilasFijas) return guardadas;
  final porId = {for (final f in guardadas) f.id: f};
  return [
    for (var i = 0; i < t.filasFijas.length; i++)
      porId[idFilaFija(i)] ?? VisitaFilaTabla(id: idFilaFija(i)),
  ];
}

/// Nombre de una fila en mensajes y en el informe: "Extintor 2" en las
/// dinámicas, el nombre de la fila en las fijas ("Cocina").
String nombreFilaTabla(VisitaFormatoTabla t, VisitaFilaTabla f, int indice) =>
    t.conFilasFijas ? f.titulo(t) : '${t.etiquetaFila} ${indice + 1}';

class VisitaFormato {
  final String id;
  final String empresaId;
  final String areaId;
  final String areaNombre;
  final String nombre;
  final int version;
  final String estado;
  final bool predeterminado;
  final List<VisitaFormatoItem> items;

  /// Hojas del formato. Vacío = formato de una sola hoja sin código.
  final List<VisitaFormatoParte> partes;

  /// Tablas de filas dinámicas. Vacío en la mayoría de formatos.
  final List<VisitaFormatoTabla> tablas;

  /// Cargos a los que aplica dentro del área (25 sep 2026). Vacío = a todos
  /// los del área. Ordena la lista de formatos y propone el correcto al
  /// programar: el de la nutricionista no es el del auxiliar.
  final List<String> cargos;

  /// Encabezado del documento (26 sep 2026: "que todos los informes queden
  /// con el encabezado del SST"). Un formato de una sola hoja no tiene
  /// partes, así que el código, la versión y la fecha de elaboración del
  /// documento van aquí. `sistema` es la primera línea del encabezado
  /// ("SISTEMA DE GESTIÓN DE CALIDAD"); vacío = se arma con el área.
  final String codigo;
  final String versionDocumento;
  final String elaboracion;
  final String sistema;

  const VisitaFormato({
    this.id = '',
    required this.empresaId,
    required this.areaId,
    required this.areaNombre,
    required this.nombre,
    this.version = 1,
    this.estado = kFormatoBorrador,
    this.predeterminado = false,
    this.items = const [],
    this.partes = const [],
    this.tablas = const [],
    this.cargos = const [],
    this.codigo = '',
    this.versionDocumento = '',
    this.elaboracion = '',
    this.sistema = '',
  });

  bool get esBorrador => estado == kFormatoBorrador;
  bool get usable => estado != kFormatoRetirado;

  /// Primera línea del encabezado del informe.
  String get sistemaEncabezado => sistema.trim().isNotEmpty
      ? sistema.trim().toUpperCase()
      : 'SISTEMA DE GESTIÓN · ${areaNombre.trim().toUpperCase()}';

  /// Las hojas del informe: las partes del formato o, si no tiene, una sola
  /// con el encabezado del documento. Así todos los informes salen con el
  /// mismo bloque de código / versión / página / elaboración.
  List<VisitaFormatoParte> get hojasInforme => partes.isNotEmpty
      ? partes
      : [
          VisitaFormatoParte(
            codigo: codigo,
            nombre: nombre.toUpperCase(),
            version: versionDocumento.isNotEmpty
                ? versionDocumento
                : '$version',
            elaboracion: elaboracion,
          ),
        ];

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
    'predeterminado': predeterminado,
    'items': items.map((i) => i.toMap()).toList(),
    'partes': partes.map((p) => p.toMap()).toList(),
    'tablas': tablas.map((t) => t.toMap()).toList(),
    'cargos': cargos,
    'codigo': codigo,
    'versionDocumento': versionDocumento,
    'elaboracion': elaboracion,
    'sistema': sistema,
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
        predeterminado: d['predeterminado'] == true,
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
        cargos: [
          for (final c in (d['cargos'] as List? ?? const []))
            if (c.toString().trim().isNotEmpty) c.toString().trim(),
        ],
        codigo: (d['codigo'] ?? '').toString(),
        versionDocumento: (d['versionDocumento'] ?? '').toString(),
        elaboracion: (d['elaboracion'] ?? '').toString(),
        sistema: (d['sistema'] ?? '').toString(),
      );

  VisitaFormato copyWith({
    String? id,
    String? areaId,
    String? areaNombre,
    String? nombre,
    String? estado,
    bool? predeterminado,
    List<VisitaFormatoItem>? items,
    int? version,
    List<VisitaFormatoParte>? partes,
    List<VisitaFormatoTabla>? tablas,
    List<String>? cargos,
    String? codigo,
    String? versionDocumento,
    String? elaboracion,
    String? sistema,
  }) => VisitaFormato(
    id: id ?? this.id,
    empresaId: empresaId,
    areaId: areaId ?? this.areaId,
    areaNombre: areaNombre ?? this.areaNombre,
    nombre: nombre ?? this.nombre,
    version: version ?? this.version,
    estado: estado ?? this.estado,
    predeterminado: predeterminado ?? this.predeterminado,
    items: items ?? this.items,
    partes: partes ?? this.partes,
    tablas: tablas ?? this.tablas,
    cargos: cargos ?? this.cargos,
    codigo: codigo ?? this.codigo,
    versionDocumento: versionDocumento ?? this.versionDocumento,
    elaboracion: elaboracion ?? this.elaboracion,
    sistema: sistema ?? this.sistema,
  );
}

/// Un formato solo sirve si tiene ítems con texto y sin ids repetidos. Un id
/// repetido haría que dos preguntas compartieran la misma respuesta.
List<String> validarFormato(VisitaFormato f) {
  final errores = <String>[];
  if (f.nombre.trim().isEmpty) errores.add('El formato necesita un nombre.');
  if (f.areaId.trim().isEmpty)
    errores.add('El formato debe pertenecer a un área.');
  // Un formato puede ser solo una tabla (una cuadrícula por áreas), pero
  // algo tiene que preguntar.
  if (f.items.isEmpty && f.tablas.isEmpty) {
    errores.add('El formato no tiene ningún ítem.');
  }
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
    if (it.tipo == kItemTipoOpcion && it.opciones.length < 2) {
      errores.add('El ítem ${it.orden} es de lista y necesita dos opciones.');
    }
  }
  final tablaIds = <String>{};
  for (final t in f.tablas) {
    if (t.id.trim().isEmpty) {
      errores.add('Una tabla no tiene id.');
    } else if (!tablaIds.add(t.id)) {
      errores.add('La tabla "${t.id}" está repetida.');
    }
    if (t.nombre.trim().isEmpty) errores.add('Una tabla no tiene nombre.');
    if (t.camposEstado.isEmpty) {
      errores.add('La tabla "${t.nombre}" no tiene columnas de estado.');
    }
    final columnas = <String>{};
    for (final c in [...t.camposTexto, ...t.camposEstado]) {
      if (c.label.trim().isEmpty) {
        errores.add('La tabla "${t.nombre}" tiene una columna sin nombre.');
      }
      if (!columnas.add(c.id)) {
        errores.add('La tabla "${t.nombre}" repite la columna "${c.label}".');
      }
    }
    if (t.filasFijas.toSet().length != t.filasFijas.length) {
      errores.add('La tabla "${t.nombre}" repite una fila.');
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

  /// Qué muestra la foto. Lo escribe el profesional en las evidencias
  /// adicionales y es el pie del anexo en el informe.
  final String descripcion;

  /// La foto ya lleva la banda con fecha, hora, lugar y GPS (26 sep 2026).
  final bool conMarca;

  const VisitaEvidencia({
    required this.url,
    required this.path,
    required this.nombre,
    this.tomadaEn,
    this.descripcion = '',
    this.conMarca = false,
  });

  Map<String, dynamic> toMap() => {
    'url': url,
    'path': path,
    'nombre': nombre,
    'tomadaEn': tomadaEn ?? Timestamp.now(),
    if (descripcion.isNotEmpty) 'descripcion': descripcion,
    if (conMarca) 'conMarca': true,
  };

  factory VisitaEvidencia.fromMap(Map<String, dynamic> d) => VisitaEvidencia(
    url: (d['url'] ?? '').toString(),
    path: (d['path'] ?? '').toString(),
    nombre: (d['nombre'] ?? '').toString(),
    tomadaEn: d['tomadaEn'] is Timestamp ? d['tomadaEn'] as Timestamp : null,
    descripcion: (d['descripcion'] ?? '').toString(),
    conMarca: d['conMarca'] == true,
  );

  VisitaEvidencia copyWith({String? descripcion}) => VisitaEvidencia(
    url: url,
    path: path,
    nombre: nombre,
    tomadaEn: tomadaEn,
    descripcion: descripcion ?? this.descripcion,
    conMarca: conMarca,
  );
}

class VisitaRespuesta {
  /// `cumple`, `no_cumple`, `no_aplica` o vacío (sin responder).
  final String resultado;

  /// La respuesta de las preguntas de formulario (texto, número, fecha,
  /// opción). Las que califican usan `resultado`.
  final String valor;
  final String observacion;
  final List<VisitaEvidencia> evidencias;

  /// Solo ítems `elemento`: cuánto hay y cuándo vence (texto libre, como
  /// en el formato: "5 unidades", "12/2027").
  final String cantidad;
  final String vencimiento;

  /// Plan de acción propuesto para un "No cumple". Opcional: si no lo
  /// escriben, en el informe va la observación.
  final String accion;

  /// A quién va el plan de acción (25 sep 2026): el área y la persona que
  /// recibe la tarea al cerrar. El establecimiento es el de la visita. Vacío
  /// = la tarea sigue yendo al jefe que programó.
  final String accionAreaId;
  final String accionAreaNombre;
  final String accionResponsableId;
  final String accionResponsableNombre;

  const VisitaRespuesta({
    this.resultado = '',
    this.valor = '',
    this.observacion = '',
    this.evidencias = const [],
    this.cantidad = '',
    this.vencimiento = '',
    this.accion = '',
    this.accionAreaId = '',
    this.accionAreaNombre = '',
    this.accionResponsableId = '',
    this.accionResponsableNombre = '',
  });

  bool get respondida => resultado.isNotEmpty || valor.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    'resultado': resultado,
    if (valor.isNotEmpty) 'valor': valor,
    'observacion': observacion,
    'evidencias': evidencias.map((e) => e.toMap()).toList(),
    'cantidad': cantidad,
    'vencimiento': vencimiento,
    'accion': accion,
    'accionAreaId': accionAreaId,
    'accionAreaNombre': accionAreaNombre,
    'accionResponsableId': accionResponsableId,
    'accionResponsableNombre': accionResponsableNombre,
  };

  factory VisitaRespuesta.fromMap(Map<String, dynamic> d) => VisitaRespuesta(
    resultado: (d['resultado'] ?? '').toString(),
    valor: (d['valor'] ?? '').toString(),
    observacion: (d['observacion'] ?? '').toString(),
    evidencias: [
      for (final raw in (d['evidencias'] as List? ?? const []))
        if (raw is Map) VisitaEvidencia.fromMap(Map<String, dynamic>.from(raw)),
    ],
    cantidad: (d['cantidad'] ?? '').toString(),
    vencimiento: (d['vencimiento'] ?? '').toString(),
    accion: (d['accion'] ?? '').toString(),
    accionAreaId: (d['accionAreaId'] ?? '').toString(),
    accionAreaNombre: (d['accionAreaNombre'] ?? '').toString(),
    accionResponsableId: (d['accionResponsableId'] ?? '').toString(),
    accionResponsableNombre: (d['accionResponsableNombre'] ?? '').toString(),
  );

  VisitaRespuesta copyWith({
    String? resultado,
    String? valor,
    String? observacion,
    List<VisitaEvidencia>? evidencias,
    String? cantidad,
    String? vencimiento,
    String? accion,
    String? accionAreaId,
    String? accionAreaNombre,
    String? accionResponsableId,
    String? accionResponsableNombre,
  }) => VisitaRespuesta(
    resultado: resultado ?? this.resultado,
    valor: valor ?? this.valor,
    observacion: observacion ?? this.observacion,
    evidencias: evidencias ?? this.evidencias,
    cantidad: cantidad ?? this.cantidad,
    vencimiento: vencimiento ?? this.vencimiento,
    accion: accion ?? this.accion,
    accionAreaId: accionAreaId ?? this.accionAreaId,
    accionAreaNombre: accionAreaNombre ?? this.accionAreaNombre,
    accionResponsableId: accionResponsableId ?? this.accionResponsableId,
    accionResponsableNombre:
        accionResponsableNombre ?? this.accionResponsableNombre,
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

  /// Nombre corto de la fila para informes y tareas: el de la fila fija si lo
  /// es; si no, el primer campo con texto (la ubicación, en extintores) o el
  /// id.
  String titulo(VisitaFormatoTabla t) {
    if (t.conFilasFijas) {
      final i = int.tryParse(id.replaceFirst('fija_', ''));
      if (id.startsWith('fija_') &&
          i != null &&
          i >= 1 &&
          i <= t.filasFijas.length) {
        return t.filasFijas[i - 1];
      }
    }
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
    ? {
        for (final e in raw.entries)
          e.key.toString(): (e.value ?? '').toString(),
      }
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

  /// Desde qué equipo y con qué cuenta se firmó (25 sep 2026): "Android",
  /// "Web · Windows"… y el id de la cuenta con sesión abierta. Si el
  /// administrador firma en la tablet del profesional, la cuenta es la del
  /// profesional y el informe lo dice.
  final String dispositivo;
  final String firmadoPorId;

  const VisitaFirma({
    required this.nombre,
    this.cargo = '',
    required this.modo,
    this.url = '',
    this.path = '',
    this.blob,
    this.at,
    this.dispositivo = '',
    this.firmadoPorId = '',
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
    'dispositivo': dispositivo,
    'firmadoPorId': firmadoPorId,
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
      dispositivo: (d['dispositivo'] ?? '').toString(),
      firmadoPorId: (d['firmadoPorId'] ?? '').toString(),
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

  /// Cédula del responsable si se eligió de la lista del personal del
  /// establecimiento; vacío si se escribió a mano (no es usuario de la app).
  /// Con id, puede firmar el acta desde su propio módulo.
  final String userId;
  const VisitaResponsable({
    this.nombre = '',
    this.cargo = '',
    this.userId = '',
  });

  bool get completo => nombre.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'cargo': cargo,
    'userId': userId,
  };
  factory VisitaResponsable.fromMap(Map<String, dynamic> d) =>
      VisitaResponsable(
        nombre: (d['nombre'] ?? '').toString(),
        cargo: (d['cargo'] ?? '').toString(),
        userId: (d['userId'] ?? '').toString(),
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

  /// La visita no se cumplió en la fecha [de] (1 oct 2026): pasó ese día
  /// sin hacerse o sin cerrarse, y se reasignó a pedido del profesional.
  /// Es el registro del incumplimiento.
  final bool incumplida;

  const VisitaReprogramacion({
    required this.de,
    required this.a,
    required this.motivo,
    required this.porId,
    required this.porNombre,
    this.at,
    this.incumplida = false,
  });

  Map<String, dynamic> toMap() => {
    'de': Timestamp.fromDate(de),
    'a': Timestamp.fromDate(a),
    'motivo': motivo,
    'porId': porId,
    'porNombre': porNombre,
    'at': at ?? Timestamp.now(),
    if (incumplida) 'incumplida': true,
  };

  factory VisitaReprogramacion.fromMap(Map<String, dynamic> d) =>
      VisitaReprogramacion(
        de: _fecha(d['de']),
        a: _fecha(d['a']),
        motivo: (d['motivo'] ?? '').toString(),
        porId: (d['porId'] ?? '').toString(),
        porNombre: (d['porNombre'] ?? '').toString(),
        at: d['at'] is Timestamp ? d['at'] as Timestamp : null,
        incumplida: d['incumplida'] == true,
      );
}

// ── Solicitud de cambio de fecha (28 sep 2026) ─────────────────────────────
//
// "Permitir solicitar cambio de fecha a su jefe inmediato". El profesional ya
// no mueve la visita: la pide, con el motivo, y el jefe la aprueba o la
// rechaza. Una sola solicitud a la vez por visita; la última queda guardada
// con su respuesta.

const String kSolicitudPendiente = 'pendiente';
const String kSolicitudAprobada = 'aprobada';
const String kSolicitudRechazada = 'rechazada';

class VisitaSolicitudFecha {
  /// La fecha que pide el profesional (solo el día).
  final DateTime fecha;
  final String motivo;
  final String porId;
  final String porNombre;
  final String estado;
  final Timestamp? at;

  /// Lo que contesta el jefe; al rechazar dice por qué.
  final String respuesta;
  final String respondidaPorId;
  final String respondidaPorNombre;

  /// Se pidió porque la visita no se cumplió ([visitaIncumplida]): es una
  /// solicitud de reasignación, no un simple cambio de fecha.
  final bool reasignacion;

  const VisitaSolicitudFecha({
    required this.fecha,
    required this.motivo,
    required this.porId,
    required this.porNombre,
    this.estado = kSolicitudPendiente,
    this.at,
    this.respuesta = '',
    this.respondidaPorId = '',
    this.respondidaPorNombre = '',
    this.reasignacion = false,
  });

  bool get pendiente => estado == kSolicitudPendiente;

  Map<String, dynamic> toMap() => {
    'fecha': Timestamp.fromDate(fecha),
    'motivo': motivo,
    'porId': porId,
    'porNombre': porNombre,
    'estado': estado,
    'at': at ?? Timestamp.now(),
    'respuesta': respuesta,
    'respondidaPorId': respondidaPorId,
    'respondidaPorNombre': respondidaPorNombre,
    if (reasignacion) 'tipo': 'reasignacion',
  };

  factory VisitaSolicitudFecha.fromMap(Map<String, dynamic> d) =>
      VisitaSolicitudFecha(
        fecha: _fecha(d['fecha']),
        motivo: (d['motivo'] ?? '').toString(),
        porId: (d['porId'] ?? '').toString(),
        porNombre: (d['porNombre'] ?? '').toString(),
        estado: (d['estado'] ?? kSolicitudPendiente).toString(),
        at: d['at'] is Timestamp ? d['at'] as Timestamp : null,
        respuesta: (d['respuesta'] ?? '').toString(),
        respondidaPorId: (d['respondidaPorId'] ?? '').toString(),
        respondidaPorNombre: (d['respondidaPorNombre'] ?? '').toString(),
        reasignacion: d['tipo'] == 'reasignacion',
      );

  VisitaSolicitudFecha respondida({
    required bool aprobada,
    required String porId,
    required String porNombre,
    String respuesta = '',
  }) => VisitaSolicitudFecha(
    fecha: fecha,
    motivo: motivo,
    porId: this.porId,
    porNombre: this.porNombre,
    estado: aprobada ? kSolicitudAprobada : kSolicitudRechazada,
    at: at,
    respuesta: respuesta,
    respondidaPorId: porId,
    respondidaPorNombre: porNombre,
    reasignacion: reasignacion,
  );
}

/// Qué impide pedir el cambio de fecha. Null = se puede.
String? validarSolicitudFecha(
  VisitaProfesional v, {
  required DateTime fecha,
  required String motivo,
  required DateTime hoy,
}) {
  if (v.estado != kVisitaProgramada && v.estado != kVisitaEnCurso) {
    return 'Solo se pide cambio de fecha de una visita programada o en curso.';
  }
  if (v.solicitudFecha?.pendiente == true) {
    return 'Ya hay una solicitud esperando respuesta de tu jefe.';
  }
  if (_soloDia(fecha).isBefore(_soloDia(hoy))) {
    return 'La nueva fecha no puede ser anterior a hoy.';
  }
  if (_soloDia(fecha) == _soloDia(v.fechaProgramada) &&
      v.estado == kVisitaProgramada) {
    return 'Esa ya es la fecha de la visita.';
  }
  if (motivo.trim().isEmpty) return 'Escribe el motivo del cambio.';
  return null;
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

  /// El lugar de Google Maps elegido al buscar (28 sep 2026): con el id se
  /// abre exacto en el mapa; el nombre es el que Google le da.
  final String placeId;
  final String nombreGoogle;

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
    this.placeId = '',
    this.nombreGoogle = '',
  });

  /// Para abrirla en Google Maps (ver el sitio o "cómo llegar").
  String get mapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
      '${placeId.isEmpty ? '' : '&query_place_id=${Uri.encodeQueryComponent(placeId)}'}';

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
    'placeId': placeId,
    'nombreGoogle': nombreGoogle,
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
        placeId: (d['placeId'] ?? '').toString(),
        nombreGoogle: (d['nombreGoogle'] ?? '').toString(),
      );
}

// ── Establecimientos propios de Visitas (5 oct 2026) ───────────────────────

/// Un establecimiento que se visita y no es centro de costo de la empresa
/// (ver [kVisitasEstablecimientosCol]). Se inactiva en vez de borrarse: las
/// visitas y los grupos lo nombran por su id.
class VisitaEstablecimientoPropio {
  /// Id del documento, que es también el `centroId` de sus visitas:
  /// `{empresaId}_est_{nombre}` (ver [idEstablecimientoPropio]).
  final String id;
  final String empresaId;
  final String nombre;
  final String ciudad;
  final bool activo;

  const VisitaEstablecimientoPropio({
    required this.id,
    required this.empresaId,
    required this.nombre,
    this.ciudad = '',
    this.activo = true,
  });

  VisitaEstablecimientoPropio copyWith({
    String? nombre,
    String? ciudad,
    bool? activo,
  }) => VisitaEstablecimientoPropio(
    id: id,
    empresaId: empresaId,
    nombre: nombre ?? this.nombre,
    ciudad: ciudad ?? this.ciudad,
    activo: activo ?? this.activo,
  );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'centroId': id,
    'nombre': nombre.trim(),
    'ciudad': ciudad.trim(),
    'enabled': activo,
  };

  factory VisitaEstablecimientoPropio.fromMap(
    String id,
    Map<String, dynamic> d,
  ) => VisitaEstablecimientoPropio(
    id: id,
    empresaId: (d['empresaId'] ?? '').toString(),
    nombre: (d['nombre'] ?? '').toString(),
    ciudad: (d['ciudad'] ?? '').toString(),
    activo: d['enabled'] != false,
  );
}

/// Id (y `centroId`) de un establecimiento propio: `{empresa}_est_{slug}`.
/// El prefijo de la empresa es el que entiende la copia entre empresas de
/// Admin (`functions/src/maestros.ts`): el establecimiento, su ubicación y
/// las referencias pasan al id del destino. Vacío si el nombre no tiene
/// letras ni números.
String idEstablecimientoPropio(String empresaId, String nombre) {
  final slug = slugSubcentro(nombre);
  return slug.isEmpty ? '' : '${empresaId}_est_$slug';
}

/// La visita (o el grupo) apunta a un establecimiento propio de Visitas y no
/// a un centro de costo.
bool esEstablecimientoPropioVisitas(String empresaId, String centroId) =>
    empresaId.isNotEmpty && centroId.startsWith('${empresaId}_est_');

/// Errores del establecimiento antes de guardarlo. [propios] son los
/// nombres de los demás establecimientos propios (sin él mismo) y [centros]
/// los de los centros de costo: uno igual, sin tildes ni mayúsculas, se
/// rechaza.
List<String> validarEstablecimientoPropio(
  VisitaEstablecimientoPropio e, {
  Iterable<String> propios = const [],
  Iterable<String> centros = const [],
}) {
  final errores = <String>[];
  final nombre = e.nombre.trim();
  if (nombre.length < 2) {
    errores.add('Escribe el nombre del establecimiento.');
  } else if (nombre.length > 120) {
    errores.add('El nombre es muy largo (máximo 120 caracteres).');
  } else if (slugSubcentro(nombre).isEmpty) {
    errores.add('El nombre necesita letras o números.');
  }
  if (e.ciudad.trim().length > 80) {
    errores.add('La ciudad es muy larga (máximo 80 caracteres).');
  }
  final clave = areaClave(nombre);
  if (clave.isNotEmpty) {
    if (centros.any((c) => areaClave(c) == clave)) {
      errores.add(
        '"$nombre" ya es un centro de costo de la empresa: ya se puede '
        'visitar, no hace falta agregarlo aquí.',
      );
    } else if (propios.any((p) => areaClave(p) == clave)) {
      errores.add('Ya existe un establecimiento llamado "$nombre".');
    }
  }
  return errores;
}

/// Un resultado de la búsqueda en Google Maps (`visitasBuscarLugar`, 28 sep
/// 2026): "si busco Buen Pastor, que muestre cuál sale y al elegirlo traiga
/// los datos".
class LugarGoogle {
  final String placeId;
  final String nombre;
  final String direccion;
  final double lat;
  final double lng;
  final String ciudad;
  final String departamento;
  final String mapsUrl;

  const LugarGoogle({
    required this.placeId,
    required this.nombre,
    required this.direccion,
    required this.lat,
    required this.lng,
    this.ciudad = '',
    this.departamento = '',
    this.mapsUrl = '',
  });

  factory LugarGoogle.fromMap(Map<String, dynamic> d) => LugarGoogle(
    placeId: (d['placeId'] ?? '').toString(),
    nombre: (d['nombre'] ?? '').toString(),
    direccion: (d['direccion'] ?? '').toString(),
    lat: (d['lat'] as num?)?.toDouble() ?? 0,
    lng: (d['lng'] as num?)?.toDouble() ?? 0,
    ciudad: (d['ciudad'] ?? '').toString(),
    departamento: (d['departamento'] ?? '').toString(),
    mapsUrl: (d['mapsUrl'] ?? '').toString(),
  );
}

/// Lo que se busca en Google para un establecimiento: su nombre (con el
/// subcentro) y la ciudad si ya se sabe. "Cómbita · Alta" → "Cómbita Alta".
String textoBusquedaLugar(String nombre, {String ciudad = ''}) {
  final base = nombre.replaceAll('·', ' ').replaceAll(RegExp(r'\s+'), ' ');
  final c = ciudad.trim();
  final t = base.trim();
  if (c.isEmpty || areaClave(t).contains(areaClave(c))) return t;
  return '$t, $c';
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
///
/// Desde el 28 sep 2026 vale también para cerrar ([accion] `cerrar`): "no
/// puede estar en una ubicación diferente". El acta se abre y se cierra en el
/// establecimiento.
VerificacionUbicacion verificarUbicacionInicio({
  required VisitaUbicacion? referencia,
  required double? lat,
  required double? lng,
  double? precisionMetros,
  String accion = 'iniciar',
}) {
  final cerrar = accion == 'cerrar';
  if (lat == null || lng == null) {
    return VerificacionUbicacion(
      permitido: false,
      motivo:
          'No se pudo obtener la ubicación del dispositivo. Activa el GPS y '
          'dale permiso a la aplicación: sin ubicación la visita no se '
          '${cerrar ? 'cierra' : 'inicia'}.',
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
          '${cerrar ? 'La visita se cierra en el establecimiento: vuelve a él para cerrarla.' : 'Acércate al establecimiento para iniciar.'}',
    );
  }
  return VerificacionUbicacion(permitido: true, distancia: d);
}

// ── Registro de visita: "¿dónde estoy y qué me toca aquí?" ─────────────────
//
// Reunión del 18 sep 2026: al profesional le sale una sección propia donde,
// al llegar, la app "jala" la visita que tiene programada en ese sitio. Si
// llegó a un establecimiento sin visita programada, no lo deja iniciar
// nada: tiene que corregirlo el jefe inmediato.

/// La visita del profesional junto con la referencia del maestro que le
/// aplica y a qué distancia está de ella.
class VisitaEnSitio {
  final VisitaProfesional visita;
  final VisitaUbicacion? referencia;
  final double? distancia;

  /// Dentro del radio, descontando la precisión del GPS (misma tolerancia
  /// que [verificarUbicacionInicio]).
  final bool enElSitio;

  const VisitaEnSitio({
    required this.visita,
    required this.referencia,
    required this.distancia,
    required this.enElSitio,
  });
}

class RegistroVisitaResultado {
  /// Visitas del profesional en el sitio donde está, listas para iniciar o
  /// continuar (programadas con fecha cumplida, o en curso).
  final List<VisitaEnSitio> listas;

  /// Visitas en este sitio pero programadas para más adelante.
  final List<VisitaEnSitio> paraDespues;

  /// Referencia del maestro dentro de cuyo radio está el profesional, si hay.
  final VisitaUbicacion? ubicacionActual;

  /// La referencia más cercana cuando no está dentro de ninguna.
  final VisitaUbicacion? masCercana;
  final double? distanciaMasCercana;

  const RegistroVisitaResultado({
    required this.listas,
    required this.paraDespues,
    required this.ubicacionActual,
    required this.masCercana,
    required this.distanciaMasCercana,
  });

  bool get enUnEstablecimiento => ubicacionActual != null;
}

/// Referencia que aplica a una visita: la del subcentro si tiene la suya,
/// si no la del centro. Mismo criterio que `VisitasService.ubicacionPara`,
/// pero sobre una lista ya cargada.
VisitaUbicacion? referenciaDeVisita(
  VisitaProfesional v,
  List<VisitaUbicacion> ubicaciones,
) {
  if (v.subcentroId.isNotEmpty) {
    for (final u in ubicaciones) {
      if (u.centroId == v.centroId && u.subcentroId == v.subcentroId) return u;
    }
  }
  for (final u in ubicaciones) {
    if (u.centroId == v.centroId && u.subcentroId.isEmpty) return u;
  }
  return null;
}

/// Cruza la posición del profesional con sus visitas pendientes. Pura, para
/// probarla sin GPS ni Firestore.
RegistroVisitaResultado resolverRegistroVisita({
  required double lat,
  required double lng,
  double? precisionMetros,
  required List<VisitaUbicacion> ubicaciones,
  required List<VisitaProfesional> visitasDelProfesional,
  required DateTime ahora,
}) {
  final tolerancia = (precisionMetros ?? 0).clamp(0, 100).toDouble();
  bool dentro(VisitaUbicacion u, double d) => d - tolerancia <= u.radioMetros;

  VisitaUbicacion? actual;
  VisitaUbicacion? cercana;
  double? dActual;
  double? dCercana;
  for (final u in ubicaciones) {
    final d = distanciaMetros(lat, lng, u.lat, u.lng);
    if (dentro(u, d) && (dActual == null || d < dActual)) {
      actual = u;
      dActual = d;
    }
    if (dCercana == null || d < dCercana) {
      cercana = u;
      dCercana = d;
    }
  }

  final listas = <VisitaEnSitio>[];
  final despues = <VisitaEnSitio>[];
  for (final v in visitasDelProfesional) {
    if (v.estado != kVisitaProgramada && v.estado != kVisitaEnCurso) continue;
    final ref = referenciaDeVisita(v, ubicaciones);
    if (ref == null) continue;
    final d = distanciaMetros(lat, lng, ref.lat, ref.lng);
    if (!dentro(ref, d)) continue;
    final item = VisitaEnSitio(
      visita: v,
      referencia: ref,
      distancia: d,
      enElSitio: true,
    );
    if (v.estado == kVisitaEnCurso || visitaSePuedeIniciar(v, ahora)) {
      listas.add(item);
    } else if (_soloDia(ahora).isBefore(_soloDia(v.fechaProgramada))) {
      despues.add(item);
    }
    // Una programada de un día que ya pasó no se ofrece: se pide cambio de
    // fecha (28 sep 2026).
  }
  listas.sort(
    (a, b) => a.visita.fechaProgramada.compareTo(b.visita.fechaProgramada),
  );
  despues.sort(
    (a, b) => a.visita.fechaProgramada.compareTo(b.visita.fechaProgramada),
  );
  return RegistroVisitaResultado(
    listas: listas,
    paraDespues: despues,
    ubicacionActual: actual,
    masCercana: actual == null ? cercana : null,
    distanciaMasCercana: actual == null ? dCercana : null,
  );
}

/// Lo que el profesional elige en "Registro de visita" (28 sep 2026: "el
/// supervisor debe seleccionar la visita"): las de hoy por iniciar, las que
/// tiene en curso y las que pasaron sin hacerse, que solo se pueden pedir
/// para otra fecha. Cada lista en orden de fecha y luego de establecimiento.
({
  List<VisitaProfesional> hoy,
  List<VisitaProfesional> enCurso,
  List<VisitaProfesional> vencidas,
})
visitasParaRegistro(Iterable<VisitaProfesional> visitas, DateTime ahora) {
  int orden(VisitaProfesional a, VisitaProfesional b) {
    final f = a.fechaProgramada.compareTo(b.fechaProgramada);
    return f != 0 ? f : a.establecimiento.compareTo(b.establecimiento);
  }

  final hoy = <VisitaProfesional>[];
  final enCurso = <VisitaProfesional>[];
  final vencidas = <VisitaProfesional>[];
  for (final v in visitas) {
    if (v.estado == kVisitaEnCurso) {
      enCurso.add(v);
    } else if (visitaSePuedeIniciar(v, ahora)) {
      hoy.add(v);
    } else if (visitaVencida(v, ahora)) {
      vencidas.add(v);
    }
  }
  return (
    hoy: hoy..sort(orden),
    enCurso: enCurso..sort(orden),
    vencidas: vencidas..sort(orden),
  );
}

// ── La visita ───────────────────────────────────────────────────────────────

/// "Visita No 00001" (documento "Visitas - octubre 03"). Vacío mientras el
/// servidor no le ha dado número (recién programada) o si es de prueba.
String numeroVisitaTexto(int? numero) =>
    numero == null ? '' : 'Visita No ${numeroVisitaCorto(numero)}';

/// El número con cinco cifras ("00001"), o vacío.
String numeroVisitaCorto(int? numero) =>
    numero == null ? '' : numero.toString().padLeft(5, '0');

int? _numeroVisita(Object? raw) {
  final n = raw is num ? raw : num.tryParse('${raw ?? ''}');
  return n != null && n == n.roundToDouble() && n > 0 ? n.toInt() : null;
}

class VisitaProfesional {
  final String id;
  final String empresaId;

  /// Consecutivo por empresa que asigna el servidor al crear la visita
  /// (`visitasAsignarNumero`). Null en las de prueba y mientras llega.
  /// No va en [toMap]: la app nunca lo escribe.
  final int? numero;
  final String formatoId;
  final String formatoNombre;

  /// Copia del formato asignado: una edición posterior no altera el acta.
  final VisitaFormato? formatoAsignado;

  /// Identifica recorridos de ensayo que Administración puede eliminar.
  final bool esPrueba;
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

  /// Usuario que firma por el establecimiento desde su módulo (rol
  /// Firmante). Lo fija el profesional al pedirle la firma; con él puede
  /// leer la visita y estampar solo su firma.
  final String firmanteEstablecimientoId;
  final List<VisitaReprogramacion> reprogramaciones;

  /// Fotos que el profesional agrega al final, fuera de las preguntas
  /// (26 sep 2026). Opcionales, con marca de agua, y en el informe van como
  /// anexos junto con las de cada ítem.
  final List<VisitaEvidencia> evidenciasAdicionales;

  /// La última solicitud de cambio de fecha del profesional (28 sep 2026).
  final VisitaSolicitudFecha? solicitudFecha;

  const VisitaProfesional({
    this.id = '',
    required this.empresaId,
    this.numero,
    required this.formatoId,
    required this.formatoNombre,
    this.formatoAsignado,
    this.esPrueba = false,
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
    this.firmanteEstablecimientoId = '',
    this.reprogramaciones = const [],
    this.evidenciasAdicionales = const [],
    this.solicitudFecha,
  });

  /// Desde el 28 sep 2026 la visita se programa sin formato: el profesional
  /// lo elige al iniciarla. Las programadas antes lo traen desde el inicio.
  bool get tieneFormato => formatoId.isNotEmpty || formatoAsignado != null;

  String get establecimiento =>
      subcentroNombre.isEmpty ? centroNombre : '$centroNombre $subcentroNombre';

  /// Clave del establecimiento (centro o centro|subcentro), la misma del
  /// consolidado y de los filtros.
  String get claveEstablecimiento =>
      subcentroId.isEmpty ? centroId : '$centroId|$subcentroId';

  /// "Visita No 00001", o vacío si todavía no tiene número.
  String get numeroTexto => numeroVisitaTexto(numero);

  List<VisitaFilaTabla> filasDe(String tablaId) => tablas[tablaId] ?? const [];

  bool get firmada => firmaProfesional != null && firmaEstablecimiento != null;

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'formatoId': formatoId,
    'formatoNombre': formatoNombre,
    if (formatoAsignado != null) 'formatoAsignado': formatoAsignado!.toMap(),
    'esPrueba': esPrueba,
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
    'firmanteEstablecimientoId': firmanteEstablecimientoId,
    'reprogramaciones': reprogramaciones.map((r) => r.toMap()).toList(),
    'evidenciasAdicionales': evidenciasAdicionales
        .map((e) => e.toMap())
        .toList(),
    if (solicitudFecha != null) 'solicitudCambioFecha': solicitudFecha!.toMap(),
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
    VisitaFirma? firma(Object? raw) =>
        raw is Map ? VisitaFirma.fromMap(Map<String, dynamic>.from(raw)) : null;
    final fp = d['fechaProgramada'];
    return VisitaProfesional(
      id: id,
      empresaId: (d['empresaId'] ?? '').toString(),
      numero: _numeroVisita(d['numero']),
      formatoId: (d['formatoId'] ?? '').toString(),
      formatoNombre: (d['formatoNombre'] ?? '').toString(),
      formatoAsignado: d['formatoAsignado'] is Map
          ? VisitaFormato.fromMap(
              (d['formatoId'] ?? '').toString(),
              Map<String, dynamic>.from(d['formatoAsignado'] as Map),
            )
          : null,
      esPrueba: d['esPrueba'] == true,
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
      firmanteEstablecimientoId: (d['firmanteEstablecimientoId'] ?? '')
          .toString(),
      reprogramaciones: [
        for (final r in (d['reprogramaciones'] as List? ?? const []))
          if (r is Map)
            VisitaReprogramacion.fromMap(Map<String, dynamic>.from(r)),
      ],
      evidenciasAdicionales: [
        for (final e in (d['evidenciasAdicionales'] as List? ?? const []))
          if (e is Map) VisitaEvidencia.fromMap(Map<String, dynamic>.from(e)),
      ],
      solicitudFecha: d['solicitudCambioFecha'] is Map
          ? VisitaSolicitudFecha.fromMap(
              Map<String, dynamic>.from(d['solicitudCambioFecha'] as Map),
            )
          : null,
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
    // Las preguntas de formulario (texto, número…) no califican.
    if (!it.califica) continue;
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
    if (!it.califica) {
      final valor = r?.valor.trim() ?? '';
      if (valor.isEmpty) {
        if (it.obligatoria) {
          errores.add('Ítem ${it.orden} sin responder: ${it.texto}');
        }
      } else if (!valorValidoParaItem(it, valor)) {
        errores.add(
          it.tipo == kItemTipoNumero
              ? 'Ítem ${it.orden}: "$valor" no es un número.'
              : 'Ítem ${it.orden}: "$valor" no es una de las opciones.',
        );
      }
      continue;
    }
    if (r == null || r.resultado.isEmpty) {
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
    final filas = filasParaTabla(t, visita.filasDe(t.id));
    if (filas.isEmpty) {
      // Un establecimiento sin extintores es un hallazgo, no una tabla vacía:
      // se registra una fila "No cuenta".
      errores.add('${t.nombre}: no hay ninguna fila registrada.');
    }
    for (var i = 0; i < filas.length; i++) {
      final f = filas[i];
      final nombre = nombreFilaTabla(t, f, i);
      for (final c in t.camposEstado) {
        if (!estadoValidoEnEscala(t.escala, f.estados[c.id])) {
          errores.add('$nombre: falta "${c.label}".');
        }
      }
      if (f.tieneHallazgo && f.observacion.trim().isEmpty) {
        errores.add('$nombre tiene novedad y no dice cuál.');
      }
    }
  }
  if (!visita.responsableEstablecimiento.completo) {
    errores.add('Falta el nombre del responsable del establecimiento.');
  }
  if (exigirFirmas) {
    if (visita.firmaProfesional == null) {
      errores.add('Falta la firma del profesional que realiza la visita.');
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

  /// Del plan de acción: a quién va la tarea y de qué área. Vacío = al jefe
  /// que programó, como antes.
  final String responsableId;
  final String responsableNombre;
  final String areaId;
  final String areaNombre;

  const VisitaHallazgo({
    required this.clave,
    required this.elemento,
    required this.novedad,
    this.accion = '',
    this.evidencias = const [],
    this.responsableId = '',
    this.responsableNombre = '',
    this.areaId = '',
    this.areaNombre = '',
  });
}

List<VisitaHallazgo> hallazgosDeVisita(
  VisitaFormato formato,
  Map<String, VisitaRespuesta> respuestas, {
  Map<String, List<VisitaFilaTabla>> tablas = const {},
}) {
  final out = <VisitaHallazgo>[];
  for (final it in formato.itemsOrdenados) {
    if (!it.califica) continue;
    final r = respuestas[it.id];
    if (r?.resultado != kItemNoCumple) continue;
    out.add(
      VisitaHallazgo(
        clave: it.id,
        elemento: 'Ítem ${it.orden}: ${it.texto}',
        novedad: r!.observacion,
        accion: r.accion,
        evidencias: r.evidencias,
        responsableId: r.accionResponsableId,
        responsableNombre: r.accionResponsableNombre,
        areaId: r.accionAreaId,
        areaNombre: r.accionAreaNombre,
      ),
    );
  }
  for (final t in formato.tablas) {
    final filas = filasParaTabla(t, tablas[t.id] ?? const []);
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
  if (h.areaNombre.trim().isNotEmpty) b.writeln('Área: ${h.areaNombre}');
  if (h.evidencias.isNotEmpty) {
    b.writeln('Evidencias: ${h.evidencias.length}');
  }
  b.writeln('Profesional: ${v.profesionalNombre}');
  if (v.numero != null) b.writeln(v.numeroTexto);
  return b.toString().trim();
}

/// Fecha límite de corrección: cinco días corridos. Es un punto de partida
/// para la maqueta; cuando cada área diga su plazo, se parametriza en el
/// formato.
DateTime fechaLimiteHallazgo(DateTime cierre) =>
    cierre.add(const Duration(days: 5));

/// Se inicia el día programado y solo ese día (28 sep 2026: "la visita debe
/// terminarse el mismo día, no permitir enviar con fechas diferentes").
/// Antes no, porque la marca de hora no correspondería a la programación; y
/// después tampoco: si el día pasó, el profesional pide el cambio de fecha a
/// su jefe. Una visita de prueba se puede iniciar ese día o después.
bool visitaSePuedeIniciar(VisitaProfesional v, DateTime ahora) {
  if (v.estado != kVisitaProgramada) return false;
  final dia = _soloDia(v.fechaProgramada);
  if (v.esPrueba) return !ahora.isBefore(dia);
  return _soloDia(ahora) == dia;
}

/// Por qué no se puede iniciar hoy, en palabras. Null = se puede.
String? motivoNoIniciaHoy(VisitaProfesional v, DateTime ahora) {
  if (v.estado != kVisitaProgramada || visitaSePuedeIniciar(v, ahora)) {
    return null;
  }
  final dia = _soloDia(v.fechaProgramada);
  final fecha = _ddmmaaaa(dia);
  return _soloDia(ahora).isBefore(dia)
      ? 'Esta visita es para el $fecha: se inicia ese día.'
      : 'Esta visita era para el $fecha y no se cumplió. Solicita la '
            'reasignación a tu jefe inmediato: queda registrada con tu motivo.';
}

/// Por qué no se puede cerrar hoy (28 sep 2026). Se cierra el mismo día en
/// que se inició, que es el día programado. Null = se puede. Las pruebas no
/// tienen esta restricción.
String? motivoNoCierraHoy(VisitaProfesional v, DateTime ahora) {
  if (v.esPrueba || v.estado != kVisitaEnCurso) return null;
  final hoy = _soloDia(ahora);
  final inicio = v.inicio?.at.toDate().toLocal();
  final diaInicio = inicio == null
      ? _soloDia(v.fechaProgramada)
      : _soloDia(inicio);
  if (hoy == diaInicio && hoy == _soloDia(v.fechaProgramada)) return null;
  return 'La visita se inició el ${_ddmmaaaa(diaInicio)} y debía cerrarse '
      'ese mismo día. Pídele a tu jefe inmediato el cambio de fecha: si lo '
      'aprueba, la vuelves a iniciar en el establecimiento y conservas lo '
      'que ya respondiste (las firmas se hacen de nuevo).';
}

String _ddmmaaaa(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

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

/// La visita no se cumplió (1 oct 2026): pasó su día sin hacerse
/// (programada) o sin cerrarse (en curso). Solo se reasigna si el
/// profesional lo solicita primero, y la reasignación queda marcada como
/// incumplimiento ([VisitaReprogramacion.incumplida]). Las pruebas no
/// cuentan. Mismo criterio que `esReprogramacionDeVisita` en las reglas.
bool visitaIncumplida(VisitaProfesional v, DateTime ahora) {
  if (v.esPrueba) return false;
  if (v.estado != kVisitaProgramada && v.estado != kVisitaEnCurso) {
    return false;
  }
  return _soloDia(ahora).isAfter(_soloDia(v.fechaProgramada));
}

/// Lo que se le dice al jefe que intenta mover una visita incumplida sin
/// solicitud del profesional.
String mensajeReasignacionRequerida(VisitaProfesional v) =>
    'La visita del ${_ddmmaaaa(_soloDia(v.fechaProgramada))} no se cumplió. '
    'Para reasignarla, primero ${v.profesionalNombre.trim().isEmpty ? 'el profesional' : v.profesionalNombre.trim()} '
    'debe solicitarlo desde su Registro de visita; así queda el registro del '
    'incumplimiento con su motivo.';

// ── Consolidado mensual ─────────────────────────────────────────────────────

class ConsolidadoEstablecimiento {
  final String clave;
  final String nombre;
  final int visitas;
  final int? promedio;
  final int hallazgos;

  /// El área de la fila cuando el consolidado combina varias áreas: cada
  /// establecimiento sale una vez por área, con el color de su área.
  final String areaId;
  final String areaNombre;

  const ConsolidadoEstablecimiento({
    required this.clave,
    required this.nombre,
    required this.visitas,
    required this.promedio,
    required this.hallazgos,
    this.areaId = '',
    this.areaNombre = '',
  });
}

/// Una línea por área del consolidado combinado (26 sep 2026): cuántas se
/// hicieron, cuántas faltan y cómo salió cada área en el periodo.
class ConsolidadoArea {
  final String areaId;
  final String nombre;
  final int terminadas;
  final int programadas;
  final int canceladas;
  final int? promedio;
  final int hallazgos;

  const ConsolidadoArea({
    required this.areaId,
    required this.nombre,
    required this.terminadas,
    required this.programadas,
    required this.canceladas,
    required this.promedio,
    required this.hallazgos,
  });

  int get total => terminadas + programadas + canceladas;
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

  /// Una línea por área, en orden alfabético (26 sep 2026). Es la base de
  /// los colores del consolidado combinado.
  final List<ConsolidadoArea> porArea;

  const ConsolidadoMensual({
    required this.visitasTerminadas,
    required this.visitasProgramadas,
    required this.visitasCanceladas,
    required this.promedioGeneral,
    required this.hallazgos,
    required this.porEstablecimiento,
    required this.itemsCriticos,
    this.porArea = const [],
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

/// La visita cae entre [desde] y [hasta], ambos días incluidos (26 sep 2026:
/// "un consolidado según las fechas que se asignen", no solo por mes).
bool visitaEnRango(VisitaProfesional v, DateTime desde, DateTime hasta) {
  final d = DateTime(
    v.fechaProgramada.year,
    v.fechaProgramada.month,
    v.fechaProgramada.day,
  );
  return !d.isBefore(DateTime(desde.year, desde.month, desde.day)) &&
      !d.isAfter(DateTime(hasta.year, hasta.month, hasta.day));
}

/// Filtros de las listas de visitas (Mis visitas y Cronograma). Vacío o
/// null = sin ese filtro. [texto] busca en establecimiento, formato, área,
/// profesional y número de visita, sin tildes ni mayúsculas.
List<VisitaProfesional> filtrarVisitas(
  Iterable<VisitaProfesional> visitas, {
  String texto = '',
  String estado = '',
  DateTime? desde,
  DateTime? hasta,
  String establecimiento = '',
  String areaId = '',
  String profesionalId = '',
  DateTime? ahora,
}) {
  final q = areaClave(texto);
  final hoy = ahora ?? DateTime.now();
  return [
    for (final v in visitas)
      if ((estado.isEmpty ||
              (estado == kVisitaVencidaFiltro
                  ? visitaVencida(v, hoy)
                  : v.estado == estado)) &&
          (desde == null ||
              !v.fechaProgramada.isBefore(
                DateTime(desde.year, desde.month, desde.day),
              )) &&
          (hasta == null ||
              v.fechaProgramada.isBefore(
                DateTime(hasta.year, hasta.month, hasta.day + 1),
              )) &&
          (establecimiento.isEmpty ||
              v.claveEstablecimiento == establecimiento) &&
          (areaId.isEmpty || mismaAreaVisitas(v.areaId, areaId)) &&
          (profesionalId.isEmpty || v.profesionalId == profesionalId) &&
          (q.isEmpty ||
              areaClave(
                '${v.establecimiento} ${v.formatoNombre} ${v.areaNombre} '
                '${v.profesionalNombre} ${v.numeroTexto}',
              ).contains(q)))
        v,
  ];
}

/// Valor del filtro de estado para "vencidas" (programadas que ya pasaron
/// y nadie inició). No es un estado guardado.
const String kVisitaVencidaFiltro = 'vencida';

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

/// [separarPorArea]: en el consolidado combinado (varias áreas) cada
/// establecimiento sale una vez por área, para poder pintarlo con el color
/// de su área; con un área sola da lo mismo.
ConsolidadoMensual consolidarMes(
  Iterable<VisitaProfesional> visitas, {
  Map<String, VisitaFormato> formatos = const {},
  bool separarPorArea = false,
}) {
  final reales = visitas.where((v) => !v.esPrueba).toList();
  final terminadas = reales.where((v) => v.estado == kVisitaTerminada);
  final programadas = reales.where((v) => v.estado == kVisitaProgramada);
  final canceladas = reales.where((v) => v.estado == kVisitaCancelada);

  final porEst = <String, List<VisitaProfesional>>{};
  for (final v in terminadas) {
    final clave = separarPorArea
        ? '${v.areaId}#${v.claveEstablecimiento}'
        : v.claveEstablecimiento;
    porEst.putIfAbsent(clave, () => []).add(v);
  }

  final incumplidos = <String, int>{};
  final textoItem = <String, String>{};
  var hallazgos = 0;
  for (final v in terminadas) {
    // La copia del formato que lleva la visita, si el maestro ya no lo trae.
    final f = formatos[v.formatoId] ?? v.formatoAsignado;
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
              areaId: separarPorArea ? e.value.first.areaId : '',
              areaNombre: separarPorArea ? e.value.first.areaNombre : '',
            ),
          )
          .toList()
        ..sort((a, b) {
          // Los peores primero: es lo que el director quiere ver.
          final pa = a.promedio ?? 101, pb = b.promedio ?? 101;
          if (pa != pb) return pa.compareTo(pb);
          return a.nombre.compareTo(b.nombre);
        });

  final porAreaVisitas = <String, List<VisitaProfesional>>{};
  for (final v in reales) {
    porAreaVisitas.putIfAbsent(v.areaId, () => []).add(v);
  }
  final areas =
      porAreaVisitas.entries.map((e) {
        final hechas = e.value
            .where((v) => v.estado == kVisitaTerminada)
            .toList();
        return ConsolidadoArea(
          areaId: e.key,
          nombre: e.value.first.areaNombre,
          terminadas: hechas.length,
          programadas: e.value
              .where((v) => v.estado == kVisitaProgramada)
              .length,
          canceladas: e.value.where((v) => v.estado == kVisitaCancelada).length,
          promedio: promedio(hechas),
          hallazgos: hechas.fold(0, (acc, v) => acc + hallazgosDe(v)),
        );
      }).toList()..sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

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
    porArea: areas,
  );
}

/// Colores de las áreas en el consolidado combinado (ARGB). Los usan la
/// pantalla (`Color`) y el PDF (`PdfColor`), para que "saber cuál es cuál"
/// sea igual en los dos. Ninguno es el rojo/verde de los estados.
const List<int> kPaletaAreasVisitas = [
  0xFF2563EB, // azul
  0xFFEA580C, // naranja
  0xFF0D9488, // verde azulado
  0xFF9333EA, // morado
  0xFFDB2777, // rosado
  0xFF854D0E, // café
  0xFF0891B2, // cian
  0xFF65A30D, // lima
  0xFF4F46E5, // índigo
  0xFFCA8A04, // mostaza
];

int colorAreaVisitas(Map<String, int> indice, String areaId) =>
    kPaletaAreasVisitas[(indice[areaId] ?? 0) % kPaletaAreasVisitas.length];

/// Posición de cada área en la paleta del consolidado. Se calcula sobre
/// TODAS las áreas que puede ver la persona (no las filtradas) y en el orden
/// en que llegan, para que un área conserve su color al cambiar el filtro y
/// sea el mismo en la pantalla y en el PDF.
Map<String, int> indiceColorAreas(Iterable<String> areaIds) {
  final out = <String, int>{};
  for (final id in areaIds) {
    out.putIfAbsent(id, () => out.length);
  }
  return out;
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

// ── Grupos de profesionales (25 sep 2026) ───────────────────────────────────

/// Un grupo de profesionales de un área con los establecimientos que le
/// tocan. Es el maestro que pidió la dirección: asignar quién va a dónde una
/// vez, y no escogerlo en cada visita.
class VisitaGrupo {
  final String id;
  final String empresaId;
  final String nombre;
  final String areaId;
  final String areaNombre;
  final List<String> centroIds;
  final List<String> profesionalIds;

  /// Coordinadores del grupo: ven las visitas de sus profesionales.
  final List<String> coordinadorIds;

  const VisitaGrupo({
    this.id = '',
    required this.empresaId,
    required this.nombre,
    this.areaId = '',
    this.areaNombre = '',
    this.centroIds = const [],
    this.profesionalIds = const [],
    this.coordinadorIds = const [],
  });

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'nombre': nombre,
    'areaId': areaId,
    'areaNombre': areaNombre,
    'centroIds': centroIds,
    'profesionalIds': profesionalIds,
    'coordinadorIds': coordinadorIds,
  };

  factory VisitaGrupo.fromMap(String id, Map<String, dynamic> d) => VisitaGrupo(
    id: id,
    empresaId: (d['empresaId'] ?? '').toString(),
    nombre: (d['nombre'] ?? '').toString(),
    areaId: (d['areaId'] ?? '').toString(),
    areaNombre: (d['areaNombre'] ?? '').toString(),
    centroIds: [
      for (final c in (d['centroIds'] as List? ?? const [])) c.toString(),
    ],
    profesionalIds: [
      for (final p in (d['profesionalIds'] as List? ?? const [])) p.toString(),
    ],
    coordinadorIds: [
      for (final p in (d['coordinadorIds'] as List? ?? const [])) p.toString(),
    ],
  );

  VisitaGrupo copyWith({
    String? nombre,
    String? areaId,
    String? areaNombre,
    List<String>? centroIds,
    List<String>? profesionalIds,
    List<String>? coordinadorIds,
  }) => VisitaGrupo(
    id: id,
    empresaId: empresaId,
    nombre: nombre ?? this.nombre,
    areaId: areaId ?? this.areaId,
    areaNombre: areaNombre ?? this.areaNombre,
    centroIds: centroIds ?? this.centroIds,
    profesionalIds: profesionalIds ?? this.profesionalIds,
    coordinadorIds: coordinadorIds ?? this.coordinadorIds,
  );
}

/// El coordinador solo consulta: ni programa, ni diligencia, ni aprueba.
bool visitasPuedeVerComoCoordinador(String? rol) =>
    rol == kVisitasRolCoordinador;

List<String> validarGrupo(VisitaGrupo g) => [
  if (g.nombre.trim().isEmpty) 'El grupo necesita un nombre.',
];

/// Grupos a los que pertenece un profesional.
List<VisitaGrupo> gruposDe(String profesionalId, List<VisitaGrupo> grupos) => [
  for (final g in grupos)
    if (g.profesionalIds.contains(profesionalId)) g,
];

/// Establecimientos del profesional según sus grupos, sin repetir.
Set<String> centrosDelProfesional(
  String profesionalId,
  List<VisitaGrupo> grupos,
) => {for (final g in gruposDe(profesionalId, grupos)) ...g.centroIds};

/// Los establecimientos del grupo del profesional primero (en el orden en
/// que llegan) y luego el resto: programar ofrece arriba lo que le toca.
List<T> ordenarPorGrupo<T>(
  List<T> centros,
  Set<String> delGrupo,
  String Function(T) idDe,
) => [
  ...centros.where((c) => delGrupo.contains(idDe(c))),
  ...centros.where((c) => !delGrupo.contains(idDe(c))),
];

// ── Formatos por área y cargo (25 sep 2026) ─────────────────────────────────

/// Un formato sin cargos aplica a todo el área; con cargos, solo a esos.
bool formatoAplicaACargo(VisitaFormato f, String cargo) {
  if (f.cargos.isEmpty) return true;
  final c = areaClave(cargo);
  return c.isNotEmpty && f.cargos.any((x) => areaClave(x) == c);
}

/// Mismo área aunque una venga como id de catálogo y otra como nombre.
bool mismaAreaVisitas(String a, String b) {
  if (a.trim().isEmpty || b.trim().isEmpty) return false;
  if (a == b) return true;
  String nombre(String v) {
    final t = v.trim();
    final corte = RegExp(r'^[A-Za-z]+[_-]?\d+[_-]').matchAsPrefix(t);
    return corte == null ? t : t.substring(corte.end);
  }

  return areaClave(nombre(a)) == areaClave(nombre(b));
}

/// Formato que se propone al programar: el del área del profesional que
/// nombra su cargo; si ninguno lo nombra, el predeterminado del área; si
/// no hay, el primero. Los borradores solo en visitas de prueba.
VisitaFormato? formatoPropuesto(
  List<VisitaFormato> formatos, {
  required String areaId,
  String cargo = '',
  bool permitirBorrador = false,
}) {
  final candidatos = [
    for (final f in formatos)
      if (f.usable &&
          (permitirBorrador || !f.esBorrador) &&
          mismaAreaVisitas(f.areaId, areaId) &&
          formatoAplicaACargo(f, cargo))
        f,
  ];
  if (candidatos.isEmpty) return null;
  final delCargo = candidatos.where(
    (f) => f.cargos.isNotEmpty && formatoAplicaACargo(f, cargo),
  );
  return delCargo.where((f) => f.predeterminado).firstOrNull ??
      delCargo.firstOrNull ??
      candidatos.where((f) => f.predeterminado).firstOrNull ??
      candidatos.first;
}

/// Formatos que el profesional puede diligenciar en una visita (28 sep 2026:
/// "el formato no es necesario al programar; el profesional selecciona el
/// formato a diligenciar al momento de la visita"). Los usables del
/// departamento de la visita —con el id tal cual, como lo comparan las
/// reglas— que aplican a su cargo; los borradores solo en visitas de prueba.
/// Primero el que se propondría ([formatoPropuesto]) y luego por nombre.
List<VisitaFormato> formatosParaVisita(
  List<VisitaFormato> formatos, {
  required VisitaProfesional visita,
  String cargo = '',
}) {
  final lista = [
    for (final f in formatos)
      if (f.usable &&
          f.empresaId == visita.empresaId &&
          f.areaId == visita.areaId &&
          (visita.esPrueba || !f.esBorrador) &&
          formatoAplicaACargo(f, cargo))
        f,
  ]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  final propuesto = formatoPropuesto(
    lista,
    areaId: visita.areaId,
    cargo: cargo,
    permitirBorrador: visita.esPrueba,
  );
  if (propuesto == null) return lista;
  return [propuesto, ...lista.where((f) => f.id != propuesto.id)];
}

// ── Programar varias fechas (25 sep 2026) ───────────────────────────────────

DateTime _soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Agrega o quita un día de la selección del calendario.
Set<DateTime> alternarDia(Set<DateTime> seleccion, DateTime dia) {
  final d = _soloDia(dia);
  final out = {for (final s in seleccion) _soloDia(s)};
  if (!out.remove(d)) out.add(d);
  return out;
}

/// Una fila de la programación en lote: un día y el establecimiento.
class FilaProgramacion {
  final DateTime fecha;
  final String centroId;
  final String subcentroId;

  const FilaProgramacion({
    required this.fecha,
    this.centroId = '',
    this.subcentroId = '',
  });

  FilaProgramacion copyWith({String? centroId, String? subcentroId}) =>
      FilaProgramacion(
        fecha: fecha,
        centroId: centroId ?? this.centroId,
        subcentroId: subcentroId ?? this.subcentroId,
      );

  /// La misma clave de establecimiento que la visita (`centro` o
  /// `centro|sub`).
  String get clave => subcentroId.isEmpty ? centroId : '$centroId|$subcentroId';
}

/// La ubicación que va a usar la visita al iniciar, igual que
/// `VisitasService.ubicacionPara`: la del subcentro si tiene la suya, si no
/// la del centro. Null = no se podrá iniciar (salvo que sea de prueba).
VisitaUbicacion? ubicacionQueAplica(
  Iterable<VisitaUbicacion> ubicaciones,
  String centroId, {
  String subcentroId = '',
}) {
  VisitaUbicacion? delCentro;
  for (final u in ubicaciones) {
    if (u.centroId != centroId) continue;
    if (subcentroId.isNotEmpty && u.subcentroId == subcentroId) return u;
    if (u.subcentroId.isEmpty) delCentro = u;
  }
  return delCentro;
}

/// Qué impide programar el lote. Vacío = se puede.
List<String> validarProgramacion(
  List<FilaProgramacion> filas, {
  required DateTime hoy,
}) {
  final errores = <String>[];
  if (filas.isEmpty) errores.add('Elige al menos un día en el calendario.');
  final vistos = <String>{};
  for (final f in filas) {
    final dia =
        '${f.fecha.day.toString().padLeft(2, '0')}/'
        '${f.fecha.month.toString().padLeft(2, '0')}';
    if (_soloDia(f.fecha).isBefore(_soloDia(hoy))) {
      errores.add('$dia ya pasó: una visita no se programa hacia atrás.');
    }
    if (f.centroId.trim().isEmpty) {
      errores.add('$dia no tiene establecimiento.');
      continue;
    }
    final clave = '${_soloDia(f.fecha)}|${f.centroId}|${f.subcentroId}';
    if (!vistos.add(clave)) {
      errores.add('$dia tiene el mismo establecimiento dos veces.');
    }
  }
  return errores;
}

// ── Ejecución por secciones (25 sep 2026) ───────────────────────────────────

/// Una "página" del formato al ejecutarlo: una sección de preguntas o una
/// tabla. Con 77 preguntas en una sola lista el profesional se perdía
/// bajando; ahora avanza sección por sección y ve cuáles le faltan.
class VisitaPaso {
  final String parte;
  final String parteNombre;
  final String seccion;
  final List<VisitaFormatoItem> items;
  final VisitaFormatoTabla? tabla;

  /// "2/3" cuando una sección larga se partió en varias páginas.
  final String tramo;

  const VisitaPaso({
    this.parte = '',
    this.parteNombre = '',
    this.seccion = '',
    this.items = const [],
    this.tabla,
    this.tramo = '',
  });

  String get titulo {
    final base =
        tabla?.nombre ??
        (seccion.isNotEmpty
            ? seccion
            : (parteNombre.isNotEmpty ? parteNombre : 'Preguntas'));
    return tramo.isEmpty ? base : '$base ($tramo)';
  }
}

/// Pasos del formato: por parte, luego por sección en el orden del formato,
/// y cada tabla como paso propio al final de su parte. Una sección de más de
/// [maxItems] preguntas se parte en tramos: 20, el mismo tamaño de página
/// del resto de la app.
List<VisitaPaso> pasosDeFormato(VisitaFormato f, {int maxItems = 20}) {
  final partes = f.partes.isEmpty
      ? const [VisitaFormatoParte(codigo: '', nombre: '')]
      : f.partes;
  final pasos = <VisitaPaso>[];
  for (final p in partes) {
    final secciones = <String, List<VisitaFormatoItem>>{};
    for (final it in f.itemsDeParte(p.codigo)) {
      secciones.putIfAbsent(it.seccion, () => []).add(it);
    }
    for (final s in secciones.entries) {
      final tramos = (s.value.length / maxItems).ceil();
      for (var i = 0; i < tramos; i++) {
        final desde = i * maxItems;
        final hasta = desde + maxItems > s.value.length
            ? s.value.length
            : desde + maxItems;
        pasos.add(
          VisitaPaso(
            parte: p.codigo,
            parteNombre: p.nombre,
            seccion: s.key,
            items: s.value.sublist(desde, hasta),
            tramo: tramos > 1 ? '${i + 1}/$tramos' : '',
          ),
        );
      }
    }
    for (final t in f.tablasDeParte(p.codigo)) {
      pasos.add(VisitaPaso(parte: p.codigo, parteNombre: p.nombre, tabla: t));
    }
  }
  return pasos;
}

/// ¿A la pregunta le falta algo para poder cerrar? Mismo criterio de
/// [validarCierreVisita]: responderla, y si no cumple, decir por qué y la
/// foto donde se exige.
bool itemPendiente(VisitaFormatoItem it, VisitaRespuesta? r) {
  if (!it.califica) {
    final valor = r?.valor.trim() ?? '';
    if (valor.isEmpty) return it.obligatoria;
    return !valorValidoParaItem(it, valor);
  }
  if (r == null || r.resultado.isEmpty) return true;
  if (!resultadosPermitidos(it.tipo).contains(r.resultado)) return true;
  if (r.resultado == kItemNoCumple) {
    if (r.observacion.trim().isEmpty) return true;
    if (it.requiereEvidencia && r.evidencias.isEmpty) return true;
  }
  return false;
}

/// Lo que falta en una tabla: sin filas cuenta como un pendiente (se
/// registra "No cuenta"), más cada fila incompleta.
int pendientesDeTabla(VisitaFormatoTabla t, List<VisitaFilaTabla> guardadas) {
  final filas = filasParaTabla(t, guardadas);
  if (filas.isEmpty) return 1;
  var n = 0;
  for (final f in filas) {
    if (filaTablaPendiente(t, f)) n++;
  }
  return n;
}

/// A la fila le falta un estado, o tiene novedad y no dice cuál.
bool filaTablaPendiente(VisitaFormatoTabla t, VisitaFilaTabla f) =>
    t.camposEstado.any(
      (c) => !estadoValidoEnEscala(t.escala, f.estados[c.id]),
    ) ||
    (f.tieneHallazgo && f.observacion.trim().isEmpty);

int pendientesDePaso(VisitaPaso paso, VisitaProfesional v) {
  if (paso.tabla != null) {
    return pendientesDeTabla(paso.tabla!, v.filasDe(paso.tabla!.id));
  }
  return paso.items
      .where((it) => itemPendiente(it, v.respuestas[it.id]))
      .length;
}

/// Cargo con que firma el profesional (26 sep 2026: nombre y cargo del
/// profesional salen del sistema y no se editan en el acta, "porque pueden
/// meter mal un dedo"). El de su ficha; si la ficha no lo tiene, el rol.
String cargoProfesionalDeActa(String cargoFicha, String areaNombre) {
  final c = cargoFicha.trim();
  if (c.isNotEmpty) return c;
  final a = areaNombre.trim();
  return a.isEmpty ? 'Profesional' : 'Profesional de $a';
}

/// A quién va la tarea de un hallazgo: al responsable del plan de acción si
/// lo eligieron; si no, al jefe que programó la visita.
({String id, String nombre, String areaId}) destinatarioHallazgo(
  VisitaProfesional v,
  VisitaHallazgo h,
) => h.responsableId.trim().isNotEmpty
    ? (
        id: h.responsableId,
        nombre: h.responsableNombre,
        areaId: h.areaId.trim().isEmpty ? v.areaId : h.areaId,
      )
    : (
        id: v.asignadoPorId,
        nombre: v.asignadoPorNombre,
        areaId: h.areaId.trim().isEmpty ? v.areaId : h.areaId,
      );

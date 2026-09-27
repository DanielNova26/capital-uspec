// lib/core/multiempresa_sync.dart
//
// Cómo está una persona en cada una de sus empresas y qué hay que escribir
// para dejarla igual en todas.
//
// El problema que resuelve: la misma cédula vive en varias razones sociales y
// cada una guarda su propio bloque en `empresasDetalle.{empresaId}`. Cuando ese
// bloque está incompleto, las pantallas caen a los datos raíz —que son de la
// empresa principal— y la persona aparece en la empresa B con el cargo de la
// empresa A. Otras veces el bloque sí existe pero apunta a un id de catálogo
// de la otra empresa, o a un cargo que ya no se llama así. Resultado: el mismo
// empleado sale con dos cargos distintos según la empresa activa, y los
// filtros por área, cargo y centro de cada módulo lo pierden.
//
// Aquí no se lee ni se escribe Firestore. Se reciben los documentos ya
// cargados y se devuelve:
//   * [analizarPersona]: la ficha por empresa (área, cargo, centro de costos,
//     centros de operación y de trabajo, estado) y la lista de descuadres.
//   * [planearSincronizacion]: los campos a escribir en cada empresa para
//     igualarla a una empresa de referencia, y las entradas de catálogo que
//     haya que crear en la empresa destino (se buscan por nombre, nunca se
//     duplican).
//   * [planearEnvioCatalogo]: qué áreas, cargos y centros le faltan a una
//     empresa para tener el mismo catálogo que otra, sin tocar al personal.

import '../utils/user_company.dart';
import 'area_directory.dart';

/// Qué catálogo de la empresa se está mirando.
enum TipoCatalogo { area, cargo, centro }

extension TipoCatalogoX on TipoCatalogo {
  String get coleccion => switch (this) {
    TipoCatalogo.area => 'TBL_AREAS',
    TipoCatalogo.cargo => 'TBL_CARGOS',
    TipoCatalogo.centro => 'TBL_CENTROS_COSTOS',
  };

  /// Campo del documento de catálogo que repite su propio id.
  String get campoId => switch (this) {
    TipoCatalogo.area => 'areaId',
    TipoCatalogo.cargo => 'cargoId',
    TipoCatalogo.centro => 'centroId',
  };

  String get etiqueta => switch (this) {
    TipoCatalogo.area => 'Área',
    TipoCatalogo.cargo => 'Cargo',
    TipoCatalogo.centro => 'Centro de costos',
  };
}

/// Clave de comparación de nombres de catálogo: sin tildes, mayúsculas,
/// espacios ni signos. "Auxiliar de Cocina" y "AUXILIAR  DE COCINA" empatan.
String claveCatalogo(String? value) => areaClave((value ?? '').trim());

/// Id de catálogo con la misma forma que usa el cargue de Excel y Talento
/// Humano: `{empresaId}_{slug}`, sin tildes.
String idCatalogo(String empresaId, String base) {
  final slug = _sinTildes(base)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return '${empresaId.trim()}_${slug.isEmpty ? 'item' : slug}';
}

/// ¿Los datos raíz del usuario pertenecen a [empresaId]?
///
/// Mismo criterio de Interventoría (`puedeUsarDatosRaizInterventoria`): la
/// raíz es de la empresa principal. Sin principal escrita, solo vale si la
/// persona tiene una única empresa.
bool raizEsDeEmpresa(Map<String, dynamic> data, String empresaId) {
  final principal = normalizeEmpresaId(data['empresaId']?.toString());
  if (principal != null) return principal == empresaId;
  final empresas = extractUserEmpresaIds(data);
  return empresas.length == 1 && empresas.single == empresaId;
}

// ─── Catálogo por empresa ────────────────────────────────────────────────────

/// Un área, cargo o centro de una empresa.
class EntradaCatalogo {
  final TipoCatalogo tipo;
  final String id;
  final String empresaId;
  final String nombre;

  /// Código del centro de costos (solo centros).
  final String codigo;

  /// Área del cargo (solo cargos).
  final String areaId;
  final String areaNombre;

  /// Cargo jefe (solo cargos).
  final String parentId;

  final bool enabled;

  /// Documento completo, para copiarlo a otra empresa.
  final Map<String, dynamic> datos;

  const EntradaCatalogo({
    required this.tipo,
    required this.id,
    required this.empresaId,
    required this.nombre,
    this.codigo = '',
    this.areaId = '',
    this.areaNombre = '',
    this.parentId = '',
    this.enabled = true,
    this.datos = const <String, dynamic>{},
  });

  factory EntradaCatalogo.desdeDoc(
    TipoCatalogo tipo,
    String docId,
    Map<String, dynamic> data, {
    String? empresaId,
  }) {
    String texto(String key) => (data[key] ?? '').toString().trim();
    final empresa = texto('empresaId').isNotEmpty
        ? texto('empresaId')
        : (empresaId ?? '').trim();
    var nombre = texto('nombre');
    if (nombre.isEmpty) nombre = texto('descripcion');
    if (nombre.isEmpty || pareceAreaId(nombre)) {
      nombre = areaNombreLegible(id: docId, nombre: nombre, empresaId: empresa);
    }
    return EntradaCatalogo(
      tipo: tipo,
      id: docId,
      empresaId: empresa,
      nombre: nombre,
      codigo: texto('codigo'),
      areaId: texto('areaId'),
      areaNombre: texto('areaNombre').isNotEmpty
          ? texto('areaNombre')
          : texto('area'),
      parentId: texto('parent_cargo'),
      enabled: data['enabled'] != false,
      datos: Map<String, dynamic>.from(data),
    );
  }
}

/// Áreas, cargos y centros de UNA empresa, indexados por id y por nombre.
class CatalogoEmpresa {
  final String empresaId;
  final Map<TipoCatalogo, Map<String, EntradaCatalogo>> _porId = {
    for (final t in TipoCatalogo.values) t: <String, EntradaCatalogo>{},
  };
  final Map<TipoCatalogo, Map<String, EntradaCatalogo>> _porClave = {
    for (final t in TipoCatalogo.values) t: <String, EntradaCatalogo>{},
  };
  final Map<String, EntradaCatalogo> _centrosPorCodigo = {};

  CatalogoEmpresa(this.empresaId);

  Iterable<EntradaCatalogo> entradas(TipoCatalogo tipo) =>
      _porClave[tipo]!.values;

  /// Agrega una entrada. Si ya había otra con el mismo nombre, se queda la
  /// preferible: habilitada y con id de esta empresa.
  void registrar(EntradaCatalogo e) {
    _porId[e.tipo]![e.id] = e;
    final alterno = (e.datos[e.tipo.campoId] ?? '').toString().trim();
    if (alterno.isNotEmpty && alterno != e.id) {
      _porId[e.tipo]!.putIfAbsent(alterno, () => e);
    }
    final clave = claveCatalogo(e.nombre);
    if (clave.isNotEmpty) {
      final actual = _porClave[e.tipo]![clave];
      if (actual == null || _puntaje(e) > _puntaje(actual)) {
        _porClave[e.tipo]![clave] = e;
      }
    }
    if (e.tipo == TipoCatalogo.centro) {
      final codigo = claveCatalogo(e.codigo);
      if (codigo.isNotEmpty) {
        final actual = _centrosPorCodigo[codigo];
        if (actual == null || _puntaje(e) > _puntaje(actual)) {
          _centrosPorCodigo[codigo] = e;
        }
      }
    }
  }

  int _puntaje(EntradaCatalogo e) =>
      (e.enabled ? 2 : 0) + (e.id.startsWith('${empresaId}_') ? 1 : 0);

  EntradaCatalogo? porId(TipoCatalogo tipo, String? id) {
    final v = (id ?? '').trim();
    return v.isEmpty ? null : _porId[tipo]![v];
  }

  bool contieneId(TipoCatalogo tipo, String? id) => porId(tipo, id) != null;

  /// Busca por nombre; si el texto es un id crudo, por el nombre que se lee
  /// en él. Los centros también se reconocen por su código.
  EntradaCatalogo? porNombre(
    TipoCatalogo tipo,
    String? nombre, {
    String codigo = '',
  }) {
    final raw = (nombre ?? '').trim();
    if (raw.isNotEmpty) {
      final hit = _porClave[tipo]![claveCatalogo(raw)];
      if (hit != null) return hit;
      if (pareceAreaId(raw)) {
        final legible = areaNombreLegible(id: raw, empresaId: empresaId);
        final porLegible = _porClave[tipo]![claveCatalogo(legible)];
        if (porLegible != null) return porLegible;
      }
    }
    if (tipo == TipoCatalogo.centro) {
      final c = claveCatalogo(codigo);
      if (c.isNotEmpty) return _centrosPorCodigo[c];
    }
    return null;
  }

  /// Un id libre en esta empresa para una entrada nueva llamada [nombre].
  String idLibre(TipoCatalogo tipo, String base) {
    final inicial = idCatalogo(empresaId, base);
    var candidato = inicial;
    var n = 2;
    while (_porId[tipo]!.containsKey(candidato)) {
      candidato = '${inicial}_$n';
      n++;
    }
    return candidato;
  }

  CatalogoEmpresa copia() {
    final c = CatalogoEmpresa(empresaId);
    for (final t in TipoCatalogo.values) {
      _porId[t]!.values.toSet().forEach(c.registrar);
    }
    return c;
  }

  /// Arma los catálogos de todas las empresas a partir de los documentos
  /// crudos de `TBL_AREAS`, `TBL_CARGOS` y `TBL_CENTROS_COSTOS`.
  static Map<String, CatalogoEmpresa> agrupar({
    Iterable<({String id, Map<String, dynamic> data})> areas = const [],
    Iterable<({String id, Map<String, dynamic> data})> cargos = const [],
    Iterable<({String id, Map<String, dynamic> data})> centros = const [],
    Iterable<String> empresas = const [],
  }) {
    final out = <String, CatalogoEmpresa>{
      for (final e in empresas)
        if (e.trim().isNotEmpty) e.trim(): CatalogoEmpresa(e.trim()),
    };
    void cargar(
      TipoCatalogo tipo,
      Iterable<({String id, Map<String, dynamic> data})> docs,
    ) {
      for (final d in docs) {
        final entrada = EntradaCatalogo.desdeDoc(tipo, d.id, d.data);
        if (entrada.empresaId.isEmpty) continue;
        out
            .putIfAbsent(
              entrada.empresaId,
              () => CatalogoEmpresa(entrada.empresaId),
            )
            .registrar(entrada);
      }
    }

    cargar(TipoCatalogo.area, areas);
    cargar(TipoCatalogo.cargo, cargos);
    cargar(TipoCatalogo.centro, centros);
    return out;
  }
}

Map<String, CatalogoEmpresa> copiarCatalogos(
  Map<String, CatalogoEmpresa> catalogos,
) => {for (final e in catalogos.entries) e.key: e.value.copia()};

// ─── Ficha por empresa ───────────────────────────────────────────────────────

enum EstadoMembresia { activa, apagada, retirada }

extension EstadoMembresiaX on EstadoMembresia {
  String get etiqueta => switch (this) {
    EstadoMembresia.activa => 'Activa',
    EstadoMembresia.apagada => 'Apagada',
    EstadoMembresia.retirada => 'Retirada',
  };
}

EstadoMembresia estadoMembresia(Map<String, dynamic> data, String empresaId) {
  final detail = getUserCompanyDetail(data, empresaId);
  if (detail?['activo'] == false) return EstadoMembresia.apagada;
  return isPersonaActivaEnEmpresa(data, empresaId)
      ? EstadoMembresia.activa
      : EstadoMembresia.retirada;
}

/// Qué tiene mal un valor de catálogo guardado en la persona.
enum ProblemaValor {
  ninguno,

  /// La empresa no tiene el dato en su bloque: se está viendo el de la
  /// empresa principal.
  heredado,

  /// El id guardado es del catálogo de otra empresa.
  deOtraEmpresa,

  /// Ni el id ni el nombre existen en el catálogo de esta empresa.
  fueraDeCatalogo,

  /// El nombre existe en el catálogo pero el id guardado no es el suyo.
  sinEnlace,

  /// El id existe pero el nombre guardado es otro (se renombró el cargo).
  nombreDesactualizado,
}

/// Un valor de catálogo (área, cargo o centro) tal como lo tiene la persona
/// en una empresa.
class ValorCatalogo {
  final TipoCatalogo tipo;
  final String id;

  /// Lo que ven los módulos: el nombre guardado en la persona.
  final String nombreGuardado;

  /// La entrada del catálogo de la empresa a la que corresponde, si se halló.
  final EntradaCatalogo? entrada;

  final ProblemaValor problema;

  const ValorCatalogo({
    required this.tipo,
    this.id = '',
    this.nombreGuardado = '',
    this.entrada,
    this.problema = ProblemaValor.ninguno,
  });

  bool get vacio => id.isEmpty && nombreGuardado.isEmpty;

  /// Nombre para mostrar: el del catálogo si se halló; si no, el guardado, y
  /// si solo hay un id, el nombre que se lee en él. Nunca un id crudo.
  String get nombre {
    if (entrada != null) return entrada!.nombre;
    if (nombreGuardado.isNotEmpty && !pareceAreaId(nombreGuardado)) {
      return nombreGuardado;
    }
    final base = nombreGuardado.isNotEmpty ? nombreGuardado : id;
    return base.isEmpty ? '' : areaNombreLegible(id: base);
  }

  String get clave => claveCatalogo(nombre);
}

/// La persona en una de sus empresas.
class PuestoEmpresa {
  final String empresaId;
  final EstadoMembresia estado;
  final bool esPrincipal;
  final ValorCatalogo area;
  final ValorCatalogo cargo;
  final ValorCatalogo centro;
  final List<ValorCatalogo> operacion;
  final List<ValorCatalogo> trabajo;
  final String jefeNombre;

  /// Lo que dice `TBL_ESTRUCTURA_ORGANIZACIONAL` para esta empresa (vacío si
  /// no tiene bloque).
  final String estructuraArea;
  final String estructuraCargo;

  const PuestoEmpresa({
    required this.empresaId,
    required this.estado,
    required this.esPrincipal,
    required this.area,
    required this.cargo,
    required this.centro,
    this.operacion = const [],
    this.trabajo = const [],
    this.jefeNombre = '',
    this.estructuraArea = '',
    this.estructuraCargo = '',
  });

  bool get activa => estado == EstadoMembresia.activa;
}

enum TipoDescuadre {
  sinArea,
  sinCargo,
  heredado,
  deOtraEmpresa,
  fueraDeCatalogo,
  sinEnlace,
  nombreDesactualizado,
  estructuraDesalineada,
  areaDistinta,
  cargoDistinto,
}

extension TipoDescuadreX on TipoDescuadre {
  String get etiqueta => switch (this) {
    TipoDescuadre.sinArea => 'Sin área',
    TipoDescuadre.sinCargo => 'Sin cargo',
    TipoDescuadre.heredado => 'Heredado de otra empresa',
    TipoDescuadre.deOtraEmpresa => 'Id de otra empresa',
    TipoDescuadre.fueraDeCatalogo => 'No está en el catálogo',
    TipoDescuadre.sinEnlace => 'Sin enlace al catálogo',
    TipoDescuadre.nombreDesactualizado => 'Nombre desactualizado',
    TipoDescuadre.estructuraDesalineada => 'Estructura distinta',
    TipoDescuadre.areaDistinta => 'Área distinta entre empresas',
    TipoDescuadre.cargoDistinto => 'Cargo distinto entre empresas',
  };
}

class Descuadre {
  final TipoDescuadre tipo;

  /// Empresa donde está el problema; null si es entre empresas.
  final String? empresaId;
  final TipoCatalogo? campo;
  final String detalle;

  const Descuadre({
    required this.tipo,
    required this.detalle,
    this.empresaId,
    this.campo,
  });
}

class PersonaMultiempresa {
  final String cedula;
  final String empresaPrincipal;
  final List<PuestoEmpresa> puestos;
  final List<Descuadre> descuadres;

  const PersonaMultiempresa({
    required this.cedula,
    required this.empresaPrincipal,
    required this.puestos,
    required this.descuadres,
  });

  Iterable<PuestoEmpresa> get activas => puestos.where((p) => p.activa);
  bool get esMultiempresa => activas.length > 1;
  bool get sincronizada => descuadres.isEmpty;

  PuestoEmpresa? puesto(String empresaId) {
    for (final p in puestos) {
      if (p.empresaId == empresaId) return p;
    }
    return null;
  }

  List<String> get empresaIds => [for (final p in puestos) p.empresaId];

  /// Empresa que conviene usar de referencia: la principal si sigue activa;
  /// si no, la primera activa.
  String? get referenciaSugerida {
    final principal = puesto(empresaPrincipal);
    if (principal != null && principal.activa) return principal.empresaId;
    for (final p in puestos) {
      if (p.activa) return p.empresaId;
    }
    return puestos.isEmpty ? null : puestos.first.empresaId;
  }
}

String _texto(Map<String, dynamic>? data, List<String> keys) {
  if (data == null) return '';
  for (final k in keys) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

bool _presente(Map<String, dynamic>? data, List<String> keys) =>
    data != null && keys.any(data.containsKey);

List<String> _lista(Object? raw) => raw is Iterable && raw is! String
    ? raw.map((v) => v.toString().trim()).where((v) => v.isNotEmpty).toList()
    : <String>[];

const _kAreaId = ['areaId', 'area_id'];
const _kAreaNombre = ['area', 'areaNombre', 'area_nombre'];
const _kCargoId = ['cargoId', 'cargo_id'];
const _kCargoNombre = ['cargo', 'cargoNombre'];
const _kCentroId = ['centroId', 'centro_id'];
const _kCentroNombre = ['centroCostos', 'centro_nombre', 'centro_costos'];
const _kCentroCodigo = ['centroCodigo', 'centro_codigo'];

/// La entrada de otra empresa a la que apunta [id], para poder mostrar su
/// nombre en vez de un id crudo.
EntradaCatalogo? _entradaAjena(
  TipoCatalogo tipo,
  String id,
  String empresaId,
  Map<String, CatalogoEmpresa> catalogos,
) {
  for (final c in catalogos.values) {
    if (c.empresaId == empresaId) continue;
    final hit = c.porId(tipo, id);
    if (hit != null) return hit;
  }
  return null;
}

bool _idDeOtraEmpresa(
  TipoCatalogo tipo,
  String id,
  String empresaId,
  Map<String, CatalogoEmpresa> catalogos,
  Iterable<String> empresasConocidas,
) {
  if (id.isEmpty || id.startsWith('${empresaId}_')) return false;
  for (final c in catalogos.values) {
    if (c.empresaId != empresaId && c.contieneId(tipo, id)) return true;
  }
  for (final e in empresasConocidas) {
    if (e != empresaId && id.startsWith('${e}_')) return true;
  }
  return false;
}

ValorCatalogo _resolverValor({
  required TipoCatalogo tipo,
  required Map<String, dynamic>? detalle,
  required Map<String, dynamic> raiz,
  required bool raizLegitima,
  required List<String> idKeys,
  required List<String> nombreKeys,
  List<String> codigoKeys = const [],
  required String empresaId,
  required CatalogoEmpresa catalogo,
  required Map<String, CatalogoEmpresa> catalogos,
  required Iterable<String> empresasConocidas,
}) {
  final idPropio = _texto(detalle, idKeys);
  final nombrePropio = _texto(detalle, nombreKeys);
  final idRaiz = _texto(raiz, idKeys);
  final nombreRaiz = _texto(raiz, nombreKeys);
  // Un campo escrito en vacío dentro del bloque de la empresa es una
  // respuesta ("aquí no tiene"), no un hueco: no se completa con la raíz de
  // otra empresa. Solo el campo ausente cae a la raíz.
  final tieneId = _presente(detalle, idKeys);
  final tieneNombre = _presente(detalle, nombreKeys);
  String elegir(bool tiene, String propio, String deRaiz) {
    if (propio.isNotEmpty) return propio;
    if (tiene && !raizLegitima) return '';
    return deRaiz;
  }

  final id = elegir(tieneId, idPropio, idRaiz);
  final nombre = elegir(tieneNombre, nombrePropio, nombreRaiz);
  // Heredado es lo que se VE de otra empresa: el nombre. Un id heredado con
  // nombre propio se detecta abajo como id de otra empresa o sin enlace.
  final heredado =
      !raizLegitima &&
      !tieneNombre &&
      nombre.isNotEmpty &&
      nombre == nombreRaiz;
  final codigo = _texto(detalle, codigoKeys).isNotEmpty
      ? _texto(detalle, codigoKeys)
      : (raizLegitima ? _texto(raiz, codigoKeys) : '');

  final porId = catalogo.porId(tipo, id);
  // Datos viejos guardan el nombre en el campo del id ("Mantenimiento" en
  // `areaId`): sin nombre, se busca también por lo que diga el id.
  final porNombre = catalogo.porNombre(
    tipo,
    nombre.isNotEmpty ? nombre : id,
    codigo: codigo,
  );
  // Manda el nombre: es lo último que escribió Talento Humano y lo que ven
  // los módulos. El id solo decide cuando el nombre no está en el catálogo.
  final entrada = porNombre ?? porId;

  ProblemaValor problema;
  if (id.isEmpty && nombre.isEmpty) {
    problema = ProblemaValor.ninguno;
  } else if (heredado) {
    problema = ProblemaValor.heredado;
  } else if (porId == null &&
      _idDeOtraEmpresa(tipo, id, empresaId, catalogos, empresasConocidas)) {
    problema = ProblemaValor.deOtraEmpresa;
  } else if (entrada == null) {
    problema = ProblemaValor.fueraDeCatalogo;
  } else if (porId == null || porId.id != entrada.id) {
    problema = ProblemaValor.sinEnlace;
  } else if (nombre.isNotEmpty &&
      claveCatalogo(nombre) != claveCatalogo(entrada.nombre)) {
    problema = ProblemaValor.nombreDesactualizado;
  } else {
    problema = ProblemaValor.ninguno;
  }

  return ValorCatalogo(
    tipo: tipo,
    id: id,
    nombreGuardado: nombre.isNotEmpty
        ? nombre
        : (_entradaAjena(tipo, id, empresaId, catalogos)?.nombre ?? ''),
    entrada: entrada,
    problema: problema,
  );
}

List<ValorCatalogo> _resolverLista({
  required Map<String, dynamic>? detalle,
  required Map<String, dynamic> raiz,
  required bool raizLegitima,
  required String idsKey,
  required String nombresKey,
  required String legacyIdKey,
  required String legacyNombreKey,
  required String empresaId,
  required CatalogoEmpresa catalogo,
  required Map<String, CatalogoEmpresa> catalogos,
  required Iterable<String> empresasConocidas,
}) {
  ({List<String> ids, List<String> nombres}) leer(Map<String, dynamic>? m) {
    if (m == null) return (ids: <String>[], nombres: <String>[]);
    final ids = _lista(m[idsKey]);
    final nombres = _lista(m[nombresKey]);
    final legacy = _texto(m, [legacyIdKey]);
    if (legacy.isNotEmpty && !ids.contains(legacy)) {
      ids.add(legacy);
      nombres.add(_texto(m, [legacyNombreKey]));
    }
    return (ids: ids, nombres: nombres);
  }

  final propio = leer(detalle);
  final deRaiz = leer(raiz);
  final tiene = _presente(detalle, [idsKey, legacyIdKey]);
  final heredado = !tiene && deRaiz.ids.isNotEmpty && !raizLegitima;
  final usado = propio.ids.isNotEmpty || (tiene && !raizLegitima)
      ? propio
      : deRaiz;
  final alineados = usado.nombres.length == usado.ids.length;

  final out = <ValorCatalogo>[];
  for (var i = 0; i < usado.ids.length; i++) {
    final id = usado.ids[i];
    final nombre = alineados ? usado.nombres[i] : '';
    final porId = catalogo.porId(TipoCatalogo.centro, id);
    final entrada = porId ?? catalogo.porNombre(TipoCatalogo.centro, nombre);
    ProblemaValor problema;
    if (heredado) {
      problema = ProblemaValor.heredado;
    } else if (porId != null) {
      problema = ProblemaValor.ninguno;
    } else if (_idDeOtraEmpresa(
      TipoCatalogo.centro,
      id,
      empresaId,
      catalogos,
      empresasConocidas,
    )) {
      problema = ProblemaValor.deOtraEmpresa;
    } else if (entrada != null) {
      problema = ProblemaValor.sinEnlace;
    } else {
      problema = ProblemaValor.fueraDeCatalogo;
    }
    out.add(
      ValorCatalogo(
        tipo: TipoCatalogo.centro,
        id: id,
        nombreGuardado: nombre.isNotEmpty
            ? nombre
            : (_entradaAjena(
                    TipoCatalogo.centro,
                    id,
                    empresaId,
                    catalogos,
                  )?.nombre ??
                  ''),
        entrada: entrada,
        problema: problema,
      ),
    );
  }
  return out;
}

/// Bloque de la estructura organizacional para [empresaId].
Map<String, dynamic>? bloqueEstructura(
  Map<String, dynamic>? estructura,
  String empresaId,
) {
  if (estructura == null) return null;
  final detail = getUserCompanyDetail(estructura, empresaId);
  if (detail != null) return detail;
  return raizEsDeEmpresa(estructura, empresaId) ? estructura : null;
}

/// La ficha multiempresa de una persona y sus descuadres.
///
/// [usuario] es el documento de `TBL_USUARIOS`; [estructura], el de
/// `TBL_ESTRUCTURA_ORGANIZACIONAL` (puede faltar). [catalogos] trae el
/// catálogo de cada empresa (ver [CatalogoEmpresa.agrupar]).
///
/// Solo se buscan descuadres en las empresas donde la persona está activa:
/// en una empresa apagada o retirada el cargo es historia, no un error.
PersonaMultiempresa analizarPersona({
  required String cedula,
  required Map<String, dynamic> usuario,
  Map<String, dynamic>? estructura,
  required Map<String, CatalogoEmpresa> catalogos,
  Map<String, String> nombresEmpresa = const {},
}) {
  String nombreDe(String id) {
    final n = (nombresEmpresa[id] ?? '').trim();
    return n.isEmpty ? id : n;
  }

  final empresas = extractUserEmpresaIds(usuario);
  final principal = normalizeEmpresaId(usuario['empresaId']?.toString()) ?? '';
  final conocidas = {...catalogos.keys, ...empresas};
  final puestos = <PuestoEmpresa>[];
  final descuadres = <Descuadre>[];

  for (final empresaId in empresas) {
    final catalogo = catalogos[empresaId] ?? CatalogoEmpresa(empresaId);
    final detalle = getUserCompanyDetail(usuario, empresaId);
    final legitima = raizEsDeEmpresa(usuario, empresaId);

    ValorCatalogo valor(
      TipoCatalogo tipo,
      List<String> idKeys,
      List<String> nombreKeys, {
      List<String> codigoKeys = const [],
    }) => _resolverValor(
      tipo: tipo,
      detalle: detalle,
      raiz: usuario,
      raizLegitima: legitima,
      idKeys: idKeys,
      nombreKeys: nombreKeys,
      codigoKeys: codigoKeys,
      empresaId: empresaId,
      catalogo: catalogo,
      catalogos: catalogos,
      empresasConocidas: conocidas,
    );

    List<ValorCatalogo> lista(
      String idsKey,
      String nombresKey,
      String legacyId,
      String legacyNombre,
    ) => _resolverLista(
      detalle: detalle,
      raiz: usuario,
      raizLegitima: legitima,
      idsKey: idsKey,
      nombresKey: nombresKey,
      legacyIdKey: legacyId,
      legacyNombreKey: legacyNombre,
      empresaId: empresaId,
      catalogo: catalogo,
      catalogos: catalogos,
      empresasConocidas: conocidas,
    );

    final bloqueOrg = bloqueEstructura(estructura, empresaId);
    final puesto = PuestoEmpresa(
      empresaId: empresaId,
      estado: estadoMembresia(usuario, empresaId),
      esPrincipal: empresaId == principal,
      area: valor(TipoCatalogo.area, _kAreaId, _kAreaNombre),
      cargo: valor(TipoCatalogo.cargo, _kCargoId, _kCargoNombre),
      centro: valor(
        TipoCatalogo.centro,
        _kCentroId,
        _kCentroNombre,
        codigoKeys: _kCentroCodigo,
      ),
      operacion: lista(
        'centrosOperacionIds',
        'centrosOperacionNombres',
        'centroOperacionId',
        'centroOperacion',
      ),
      trabajo: lista(
        'centrosTrabajoIds',
        'centrosTrabajoNombres',
        'centroTrabajoId',
        'centroTrabajo',
      ),
      jefeNombre: _texto(detalle, const ['jefeNombre', 'jefe_directo']).isEmpty
          ? (legitima ? _texto(usuario, const ['jefeNombre']) : '')
          : _texto(detalle, const ['jefeNombre', 'jefe_directo']),
      estructuraArea: _texto(bloqueOrg, _kAreaNombre),
      estructuraCargo: _texto(bloqueOrg, _kCargoNombre),
    );
    puestos.add(puesto);
    if (puesto.activa) {
      descuadres.addAll(
        _descuadresDelPuesto(puesto, bloqueOrg, nombreDe(empresaId)),
      );
    }
  }

  final activas = puestos.where((p) => p.activa).toList();
  if (activas.length > 1) {
    String resumen(ValorCatalogo Function(PuestoEmpresa) campo) => activas
        .where((p) => !campo(p).vacio)
        .map((p) => '${nombreDe(p.empresaId)}: ${campo(p).nombre}')
        .join(' · ');
    final areas = {
      for (final p in activas)
        if (!p.area.vacio) p.area.clave,
    };
    if (areas.length > 1) {
      descuadres.add(
        Descuadre(
          tipo: TipoDescuadre.areaDistinta,
          campo: TipoCatalogo.area,
          detalle: resumen((p) => p.area),
        ),
      );
    }
    final cargos = {
      for (final p in activas)
        if (!p.cargo.vacio) p.cargo.clave,
    };
    if (cargos.length > 1) {
      descuadres.add(
        Descuadre(
          tipo: TipoDescuadre.cargoDistinto,
          campo: TipoCatalogo.cargo,
          detalle: resumen((p) => p.cargo),
        ),
      );
    }
  }

  return PersonaMultiempresa(
    cedula: cedula,
    empresaPrincipal: principal,
    puestos: puestos,
    descuadres: descuadres,
  );
}

List<Descuadre> _descuadresDelPuesto(
  PuestoEmpresa p,
  Map<String, dynamic>? bloqueOrg,
  String e,
) {
  final out = <Descuadre>[];
  final empresaId = p.empresaId;

  void porProblema(ValorCatalogo v, String etiqueta) {
    final tipo = switch (v.problema) {
      ProblemaValor.ninguno => null,
      ProblemaValor.heredado => TipoDescuadre.heredado,
      ProblemaValor.deOtraEmpresa => TipoDescuadre.deOtraEmpresa,
      ProblemaValor.fueraDeCatalogo => TipoDescuadre.fueraDeCatalogo,
      ProblemaValor.sinEnlace => TipoDescuadre.sinEnlace,
      ProblemaValor.nombreDesactualizado => TipoDescuadre.nombreDesactualizado,
    };
    if (tipo == null) return;
    final detalle = switch (v.problema) {
      ProblemaValor.heredado =>
        '$etiqueta en $e: no tiene uno propio y se ve "${v.nombre}", '
            'que es de la empresa principal.',
      ProblemaValor.deOtraEmpresa =>
        '$etiqueta en $e está enlazado a "${v.nombre}" del catálogo de '
            'otra empresa.',
      ProblemaValor.fueraDeCatalogo =>
        '$etiqueta "${v.nombre}" no existe en el catálogo de $e.',
      ProblemaValor.sinEnlace =>
        '$etiqueta "${v.nombre}" en $e no está enlazado a su registro del '
            'catálogo.',
      ProblemaValor.nombreDesactualizado =>
        '$etiqueta en $e dice "${v.nombreGuardado}" pero el catálogo lo '
            'llama "${v.nombre}".',
      ProblemaValor.ninguno => '',
    };
    out.add(
      Descuadre(
        tipo: tipo,
        empresaId: empresaId,
        campo: v.tipo,
        detalle: detalle,
      ),
    );
  }

  if (p.area.vacio) {
    out.add(
      Descuadre(
        tipo: TipoDescuadre.sinArea,
        empresaId: empresaId,
        campo: TipoCatalogo.area,
        detalle: 'No tiene área en $e.',
      ),
    );
  } else {
    porProblema(p.area, 'Área');
  }
  if (p.cargo.vacio) {
    out.add(
      Descuadre(
        tipo: TipoDescuadre.sinCargo,
        empresaId: empresaId,
        campo: TipoCatalogo.cargo,
        detalle: 'No tiene cargo en $e.',
      ),
    );
  } else {
    porProblema(p.cargo, 'Cargo');
  }
  // Un centro vacío es válido (cargos corporativos sin sede fija).
  if (!p.centro.vacio) porProblema(p.centro, 'Centro de costos');
  for (final c in p.operacion) {
    porProblema(c, 'Centro de operación');
  }
  for (final c in p.trabajo) {
    porProblema(c, 'Centro de trabajo');
  }

  if (bloqueOrg != null) {
    final diferencias = <String>[];
    if (p.estructuraArea.isNotEmpty &&
        !p.area.vacio &&
        claveCatalogo(p.estructuraArea) != p.area.clave &&
        claveCatalogo(p.estructuraArea) !=
            claveCatalogo(p.area.nombreGuardado)) {
      diferencias.add('área "${p.estructuraArea}"');
    }
    if (p.estructuraCargo.isNotEmpty &&
        !p.cargo.vacio &&
        claveCatalogo(p.estructuraCargo) != p.cargo.clave &&
        claveCatalogo(p.estructuraCargo) !=
            claveCatalogo(p.cargo.nombreGuardado)) {
      diferencias.add('cargo "${p.estructuraCargo}"');
    }
    Set<String> ids(List<String> keys) => {
      for (final k in keys) ..._lista(bloqueOrg[k]),
    };
    final orgOperacion = ids(const ['centrosOperacionIds']);
    final orgTrabajo = ids(const ['centrosTrabajoIds']);
    final usrOperacion = {for (final c in p.operacion) c.id};
    final usrTrabajo = {for (final c in p.trabajo) c.id};
    if (bloqueOrg.containsKey('centrosOperacionIds') &&
        !_mismoConjunto(orgOperacion, usrOperacion)) {
      diferencias.add('otros centros de operación');
    }
    if (bloqueOrg.containsKey('centrosTrabajoIds') &&
        !_mismoConjunto(orgTrabajo, usrTrabajo)) {
      diferencias.add('otros centros de trabajo');
    }
    if (diferencias.isNotEmpty) {
      out.add(
        Descuadre(
          tipo: TipoDescuadre.estructuraDesalineada,
          empresaId: empresaId,
          detalle:
              'La estructura organizacional de $e tiene '
              '${diferencias.join(', ')}.',
        ),
      );
    }
  }
  return out;
}

bool _mismoConjunto(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

// ─── Plan de sincronización ──────────────────────────────────────────────────

/// Una entrada de catálogo que hay que crear en una empresa.
class EntradaNueva {
  final TipoCatalogo tipo;
  final String empresaId;
  final String id;
  final String nombre;

  /// Documento a escribir (sin marcas de tiempo: las pone el servicio).
  final Map<String, dynamic> datos;

  const EntradaNueva({
    required this.tipo,
    required this.empresaId,
    required this.id,
    required this.nombre,
    required this.datos,
  });
}

/// Cédula que entra o sale del arreglo `cedulas` de un cargo o área.
class MovimientoCedula {
  final String coleccion;
  final String docId;
  final bool agregar;

  const MovimientoCedula({
    required this.coleccion,
    required this.docId,
    required this.agregar,
  });
}

/// Lo que se escribe en una empresa de la persona.
class AjusteEmpresa {
  final String empresaId;

  /// La persona todavía no pertenece a esta empresa: hay que vincularla.
  final bool vincular;

  /// Campos del bloque `empresasDetalle.{empresaId}` de `TBL_USUARIOS`. Si la
  /// empresa es la principal, también van a la raíz.
  final Map<String, dynamic> usuario;

  /// Campos del bloque de la empresa en `TBL_ESTRUCTURA_ORGANIZACIONAL`.
  final Map<String, dynamic> estructura;

  /// Campos de `TBL_EMPLEADOS/{empresaId}_{cedula}` (solo si existe).
  final Map<String, dynamic> empleado;

  final List<MovimientoCedula> cedulas;

  const AjusteEmpresa({
    required this.empresaId,
    this.vincular = false,
    this.usuario = const {},
    this.estructura = const {},
    this.empleado = const {},
    this.cedulas = const [],
  });

  bool get vacio =>
      !vincular && usuario.isEmpty && estructura.isEmpty && empleado.isEmpty;
}

class PlanPersona {
  final String cedula;
  final String referenciaId;
  final List<AjusteEmpresa> ajustes;
  final List<EntradaNueva> nuevas;

  /// Lo que no se pudo resolver (p. ej. la referencia no tiene cargo).
  final List<String> avisos;

  const PlanPersona({
    required this.cedula,
    required this.referenciaId,
    required this.ajustes,
    required this.nuevas,
    required this.avisos,
  });

  bool get vacio => nuevas.isEmpty && ajustes.every((a) => a.vacio);
}

/// Campos de un documento de catálogo que NO se copian a otra empresa: ids
/// propios, ocupantes y marcas de tiempo.
const Set<String> _kNoCopiar = {
  'empresaId',
  'areaId',
  'cargoId',
  'centroId',
  'area',
  'areaNombre',
  'parent_cargo',
  'cedulas',
  'createdAt',
  'updatedAt',
  'updatedBy',
  'empresaOrigenId',
  'registroOrigenId',
  'enabled',
};

/// Resuelve (o planea crear) en [destino] la entrada equivalente a [origen].
///
/// Las entradas nuevas se registran en [destino] en el acto, así que la
/// siguiente persona que necesite el mismo cargo lo encuentra y no se crea dos
/// veces.
EntradaCatalogo _equivalente({
  required TipoCatalogo tipo,
  required String nombre,
  String codigo = '',
  EntradaCatalogo? origen,
  required CatalogoEmpresa destino,
  required Map<String, CatalogoEmpresa> catalogos,
  required List<EntradaNueva> nuevas,
}) {
  final hit = destino.porNombre(tipo, nombre, codigo: codigo);
  if (hit != null) return hit;

  final base = tipo == TipoCatalogo.centro && codigo.isNotEmpty
      ? codigo
      : nombre;
  final id = destino.idLibre(tipo, base);
  final datos = <String, dynamic>{
    if (origen != null)
      for (final e in origen.datos.entries)
        if (!_kNoCopiar.contains(e.key)) e.key: e.value,
    'empresaId': destino.empresaId,
    tipo.campoId: id,
    'nombre': nombre,
    'enabled': true,
    if (origen != null) ...{
      'empresaOrigenId': origen.empresaId,
      'registroOrigenId': origen.id,
    },
  };
  var areaId = '';
  var areaNombre = '';
  if (tipo == TipoCatalogo.cargo && origen != null) {
    // El cargo viaja con su área: se busca o crea también en el destino.
    final catOrigen = catalogos[origen.empresaId];
    final areaOrigen =
        catOrigen?.porId(TipoCatalogo.area, origen.areaId) ??
        catOrigen?.porNombre(TipoCatalogo.area, origen.areaNombre);
    final nombreArea = areaOrigen?.nombre ?? origen.areaNombre;
    if (nombreArea.trim().isNotEmpty) {
      final area = _equivalente(
        tipo: TipoCatalogo.area,
        nombre: nombreArea,
        origen: areaOrigen,
        destino: destino,
        catalogos: catalogos,
        nuevas: nuevas,
      );
      areaId = area.id;
      areaNombre = area.nombre;
      datos['areaId'] = area.id;
      datos['area'] = area.nombre;
      datos['areaNombre'] = area.nombre;
    }
    // El cargo jefe solo se enlaza si ya existe en el destino: crearlo
    // arrastraría toda la cadena de mando de la otra empresa.
    final parent = catOrigen?.porId(TipoCatalogo.cargo, origen.parentId);
    final parentDestino = parent == null
        ? null
        : destino.porNombre(TipoCatalogo.cargo, parent.nombre);
    if (parentDestino != null) datos['parent_cargo'] = parentDestino.id;
  }

  final entrada = EntradaCatalogo(
    tipo: tipo,
    id: id,
    empresaId: destino.empresaId,
    nombre: nombre,
    codigo: (datos['codigo'] ?? '').toString(),
    areaId: areaId,
    areaNombre: areaNombre,
    datos: datos,
  );
  destino.registrar(entrada);
  nuevas.add(
    EntradaNueva(
      tipo: tipo,
      empresaId: destino.empresaId,
      id: id,
      nombre: nombre,
      datos: datos,
    ),
  );
  return entrada;
}

/// Qué parte del puesto se sincroniza.
class CamposSincronizacion {
  final bool area;
  final bool cargo;

  /// Centro de costos, centros de operación y centros de trabajo.
  final bool centros;

  const CamposSincronizacion({
    this.area = true,
    this.cargo = true,
    this.centros = true,
  });

  bool get ninguno => !area && !cargo && !centros;
}

bool _iguales(Object? a, Object? b) {
  if (a is Iterable && b is Iterable) {
    final la = a.map((e) => e.toString()).toList();
    final lb = b.map((e) => e.toString()).toList();
    if (la.length != lb.length) return false;
    for (var i = 0; i < la.length; i++) {
      if (la[i] != lb[i]) return false;
    }
    return true;
  }
  return (a ?? '').toString().trim() == (b ?? '').toString().trim();
}

/// Campos que son alias de otro (el mismo dato con otro nombre). Que falten
/// no es un cambio; que estén con otro valor, sí.
const Set<String> _kAlias = {
  'areaNombre',
  'centroCodigo',
  'centro_codigo',
  'centro_nombre',
  'centrosOperacionNombres',
  'centroOperacionId',
  'centroOperacion',
  'centrosTrabajoNombres',
  'centroTrabajoId',
  'centroTrabajo',
};

bool _vacioCampo(Object? v) =>
    v == null || (v is Iterable ? v.isEmpty : v.toString().trim().isEmpty);

/// Devuelve [campos] si alguno difiere de lo que hay en [actual] (o en
/// [raiz] cuando también se escribe allí); si todo coincide, vacío.
Map<String, dynamic> _siCambia(
  Map<String, dynamic> campos,
  Map<String, dynamic>? actual, {
  Map<String, dynamic>? raiz,
}) {
  bool difiere(Map<String, dynamic>? m, String key, Object? valor) {
    final v = m?[key];
    if (_kAlias.contains(key) && _vacioCampo(v)) return false;
    return !_iguales(v, valor);
  }

  for (final e in campos.entries) {
    if (difiere(actual, e.key, e.value)) return campos;
    if (raiz != null && difiere(raiz, e.key, e.value)) return campos;
  }
  return const {};
}

/// Planea dejar a la persona, en cada empresa de [destinos], con el mismo
/// área, cargo y centros que tiene en [referenciaId].
///
/// Cada valor se traduce al catálogo de la empresa destino buscando por
/// nombre (los centros también por código); si allí no existe, se planea
/// crearlo copiando el de la referencia. La propia referencia puede ir en
/// [destinos]: así se enlazan sus ids y se completa su bloque si estaba
/// heredando datos de otra empresa.
///
/// [catalogos] se modifica: las entradas nuevas quedan registradas. Para una
/// vista previa pasa [copiarCatalogos].
PlanPersona planearSincronizacion({
  required PersonaMultiempresa persona,
  required Map<String, dynamic> usuario,
  Map<String, dynamic>? estructura,
  required String referenciaId,
  required Iterable<String> destinos,
  required Map<String, CatalogoEmpresa> catalogos,
  CamposSincronizacion campos = const CamposSincronizacion(),
  Map<String, String> nombresEmpresa = const {},
}) {
  final referencia = persona.puesto(referenciaId);
  final nuevas = <EntradaNueva>[];
  final avisos = <String>[];
  final ajustes = <AjusteEmpresa>[];
  if (referencia == null) {
    return PlanPersona(
      cedula: persona.cedula,
      referenciaId: referenciaId,
      ajustes: const [],
      nuevas: const [],
      avisos: ['La persona no pertenece a $referenciaId.'],
    );
  }
  final nombreRef = (nombresEmpresa[referenciaId] ?? '').trim().isEmpty
      ? referenciaId
      : nombresEmpresa[referenciaId]!.trim();
  if (campos.area && referencia.area.vacio) {
    avisos.add('En $nombreRef no tiene área: el área no se toca.');
  }
  if (campos.cargo && referencia.cargo.vacio) {
    avisos.add('En $nombreRef no tiene cargo: el cargo no se toca.');
  }
  final principal = persona.empresaPrincipal;
  final orgPrincipal = normalizeEmpresaId(estructura?['empresaId']?.toString());

  for (final destinoId in {...destinos}) {
    final destino = catalogos.putIfAbsent(
      destinoId,
      () => CatalogoEmpresa(destinoId),
    );
    final actual = persona.puesto(destinoId);
    final vincular = actual == null;
    final detalle = getUserCompanyDetail(usuario, destinoId);
    final esPrincipal = destinoId == principal;
    final raiz = esPrincipal ? usuario : null;
    final orgBloque = getUserCompanyDetail(estructura ?? const {}, destinoId);
    final orgRaiz = orgPrincipal == destinoId ? estructura : null;
    // Sin documento de estructura no hay nada que alinear: lo crea Talento
    // Humano con todos los datos de la persona al sincronizar su pantalla.
    final hayEstructura = estructura != null;

    final usr = <String, dynamic>{};
    final org = <String, dynamic>{};
    final emp = <String, dynamic>{};
    final movimientos = <MovimientoCedula>[];

    EntradaCatalogo? equivalente(ValorCatalogo v) {
      if (v.vacio) return null;
      final catRef = catalogos[referenciaId];
      final origen =
          v.entrada ??
          catRef?.porId(v.tipo, v.id) ??
          catRef?.porNombre(v.tipo, v.nombre);
      return _equivalente(
        tipo: v.tipo,
        nombre: v.nombre,
        codigo: origen?.codigo ?? '',
        origen: origen,
        destino: destino,
        catalogos: catalogos,
        nuevas: nuevas,
      );
    }

    void mover(TipoCatalogo tipo, ValorCatalogo? antes, EntradaCatalogo nueva) {
      movimientos.add(
        MovimientoCedula(
          coleccion: tipo.coleccion,
          docId: nueva.id,
          agregar: true,
        ),
      );
      final anterior = antes?.entrada;
      if (anterior != null &&
          anterior.id != nueva.id &&
          anterior.empresaId == destinoId) {
        movimientos.add(
          MovimientoCedula(
            coleccion: tipo.coleccion,
            docId: anterior.id,
            agregar: false,
          ),
        );
      }
    }

    if (campos.area) {
      final area = equivalente(referencia.area);
      if (area != null) {
        final u = _siCambia(
          {'areaId': area.id, 'area': area.nombre, 'areaNombre': area.nombre},
          detalle,
          raiz: raiz,
        );
        usr.addAll(u);
        org.addAll(
          _siCambia(
            {'areaId': area.id, 'area': area.nombre, 'areaNombre': area.nombre},
            orgBloque,
            raiz: orgRaiz,
          ),
        );
        if (u.isNotEmpty) {
          emp.addAll({'areaId': area.id, 'areaNombre': area.nombre});
          mover(TipoCatalogo.area, actual?.area, area);
        }
      }
    }
    if (campos.cargo) {
      final cargo = equivalente(referencia.cargo);
      if (cargo != null) {
        final u = _siCambia(
          {'cargoId': cargo.id, 'cargo': cargo.nombre},
          detalle,
          raiz: raiz,
        );
        usr.addAll(u);
        org.addAll(
          _siCambia(
            {'cargoId': cargo.id, 'cargo': cargo.nombre},
            orgBloque,
            raiz: orgRaiz,
          ),
        );
        if (u.isNotEmpty) {
          emp.addAll({'cargoId': cargo.id, 'cargoNombre': cargo.nombre});
          mover(TipoCatalogo.cargo, actual?.cargo, cargo);
        }
      }
    }
    if (campos.centros) {
      final centro = equivalente(referencia.centro);
      if (centro != null) {
        final u = _siCambia(
          {
            'centroId': centro.id,
            'centroCodigo': centro.codigo.isEmpty ? centro.id : centro.codigo,
            'centroCostos': centro.nombre,
          },
          detalle,
          raiz: raiz,
        );
        usr.addAll(u);
        org.addAll(
          _siCambia(
            {
              'centroId': centro.id,
              'centro_codigo': centro.id,
              'centro_nombre': centro.nombre,
              'centroCostos': centro.nombre,
            },
            orgBloque,
            raiz: orgRaiz,
          ),
        );
        if (u.isNotEmpty) {
          emp.addAll({'centroId': centro.id, 'centroCostos': centro.nombre});
        }
      }

      Map<String, dynamic>? grupo(
        List<ValorCatalogo> valores,
        String idsKey,
        String nombresKey,
        String idKey,
        String nombreKey,
      ) {
        // Sin centros en la referencia no se vacía el destino: igual que con
        // el área y el cargo, un dato que falta no es una orden de borrar.
        if (valores.isEmpty) return null;
        final mapeados = <String, String>{};
        for (final v in valores) {
          final e = equivalente(v);
          if (e != null) mapeados[e.id] = e.nombre;
        }
        final ids = mapeados.keys.toList()..sort();
        return {
          idsKey: ids,
          nombresKey: [for (final id in ids) mapeados[id]!],
          idKey: ids.length == 1 ? ids.single : '',
          nombreKey: ids.length == 1 ? mapeados[ids.single]! : '',
        };
      }

      final operacion = grupo(
        referencia.operacion,
        'centrosOperacionIds',
        'centrosOperacionNombres',
        'centroOperacionId',
        'centroOperacion',
      );
      final trabajo = grupo(
        referencia.trabajo,
        'centrosTrabajoIds',
        'centrosTrabajoNombres',
        'centroTrabajoId',
        'centroTrabajo',
      );
      for (final g in [operacion, trabajo]) {
        if (g == null) continue;
        final u = _siCambia(g, detalle, raiz: raiz);
        usr.addAll(u);
        org.addAll(_siCambia(g, orgBloque, raiz: orgRaiz));
        if (u.isNotEmpty) emp.addAll(g);
      }
    }

    if (vincular) {
      usr['empresaNombre'] = nombresEmpresa[destinoId] ?? destinoId;
      usr['activo'] = true;
      // Lo que no se trae se deja escrito en vacío: si falta, las pantallas
      // mostrarían en la empresa nueva el dato de la principal.
      for (final k in const [
        'areaId',
        'area',
        'areaNombre',
        'cargoId',
        'cargo',
        'centroId',
        'centroCostos',
        'centroOperacionId',
        'centroOperacion',
        'centroTrabajoId',
        'centroTrabajo',
      ]) {
        usr.putIfAbsent(k, () => '');
      }
      for (final k in const [
        'centrosOperacionIds',
        'centrosOperacionNombres',
        'centrosTrabajoIds',
        'centrosTrabajoNombres',
      ]) {
        usr.putIfAbsent(k, () => <String>[]);
      }
    }
    if (!hayEstructura) org.clear();
    ajustes.add(
      AjusteEmpresa(
        empresaId: destinoId,
        vincular: vincular,
        usuario: usr,
        estructura: org,
        empleado: emp,
        cedulas: movimientos,
      ),
    );
  }

  return PlanPersona(
    cedula: persona.cedula,
    referenciaId: referenciaId,
    ajustes: ajustes,
    nuevas: nuevas,
    avisos: avisos,
  );
}

// ─── Envío de catálogo entre empresas ────────────────────────────────────────

/// Un cargo que existe en las dos empresas pero cuelga de áreas distintas.
class CargoConAreaDistinta {
  final String nombre;
  final String areaOrigen;
  final String areaDestino;

  const CargoConAreaDistinta({
    required this.nombre,
    required this.areaOrigen,
    required this.areaDestino,
  });
}

class PlanCatalogo {
  final String origenId;
  final String destinoId;
  final List<EntradaNueva> nuevas;
  final int yaExistian;
  final List<CargoConAreaDistinta> cargosConAreaDistinta;

  const PlanCatalogo({
    required this.origenId,
    required this.destinoId,
    required this.nuevas,
    required this.yaExistian,
    required this.cargosConAreaDistinta,
  });

  Iterable<EntradaNueva> de(TipoCatalogo tipo) =>
      nuevas.where((n) => n.tipo == tipo);
}

/// Qué le falta a [destinoId] para tener el catálogo de [origenId].
///
/// No toca a nadie del personal: solo crea áreas, cargos y centros que no
/// existan con ese nombre en el destino. Los cargos llevan su área (creada si
/// falta) y su cargo jefe si ya existe allá. Con [ids] se envía solo una
/// parte del catálogo (ids del origen).
PlanCatalogo planearEnvioCatalogo({
  required String origenId,
  required String destinoId,
  required Map<String, CatalogoEmpresa> catalogos,
  Set<TipoCatalogo> tipos = const {TipoCatalogo.area, TipoCatalogo.cargo},
  Set<String>? ids,
}) {
  final origen = catalogos[origenId] ?? CatalogoEmpresa(origenId);
  final destino = catalogos.putIfAbsent(
    destinoId,
    () => CatalogoEmpresa(destinoId),
  );
  final nuevas = <EntradaNueva>[];
  var existian = 0;
  final conAreaDistinta = <CargoConAreaDistinta>[];

  // Áreas y centros primero: los cargos se enlazan a ellos.
  for (final tipo in const [
    TipoCatalogo.area,
    TipoCatalogo.centro,
    TipoCatalogo.cargo,
  ]) {
    if (!tipos.contains(tipo)) continue;
    final entradas = origen.entradas(tipo).toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    for (final e in entradas) {
      if (ids != null && !ids.contains(e.id)) continue;
      if (!e.enabled) continue;
      final hit = destino.porNombre(tipo, e.nombre, codigo: e.codigo);
      if (hit != null) {
        // Ya estaba antes de este envío (lo que se creó en este mismo plan
        // no cuenta como existente).
        if (!nuevas.any((n) => n.tipo == tipo && n.id == hit.id)) {
          existian++;
          if (tipo == TipoCatalogo.cargo) {
            final areaO = claveCatalogo(e.areaNombre);
            final areaD = claveCatalogo(hit.areaNombre);
            if (areaO.isNotEmpty && areaD.isNotEmpty && areaO != areaD) {
              conAreaDistinta.add(
                CargoConAreaDistinta(
                  nombre: e.nombre,
                  areaOrigen: e.areaNombre,
                  areaDestino: hit.areaNombre,
                ),
              );
            }
          }
        }
        continue;
      }
      _equivalente(
        tipo: tipo,
        nombre: e.nombre,
        codigo: e.codigo,
        origen: e,
        destino: destino,
        catalogos: catalogos,
        nuevas: nuevas,
      );
    }
  }

  // Los cargos se crearon en orden alfabético: un auxiliar pudo quedar antes
  // que su jefe. Ya con todos creados, se enlaza el jefe que haya llegado.
  for (final n in nuevas) {
    if (n.tipo != TipoCatalogo.cargo || n.datos.containsKey('parent_cargo')) {
      continue;
    }
    final original = origen.porId(
      TipoCatalogo.cargo,
      (n.datos['registroOrigenId'] ?? '').toString(),
    );
    final jefe = origen.porId(TipoCatalogo.cargo, original?.parentId);
    final jefeDestino = jefe == null
        ? null
        : destino.porNombre(TipoCatalogo.cargo, jefe.nombre);
    if (jefeDestino != null) n.datos['parent_cargo'] = jefeDestino.id;
  }

  return PlanCatalogo(
    origenId: origenId,
    destinoId: destinoId,
    nuevas: nuevas,
    yaExistian: existian,
    cargosConAreaDistinta: conAreaDistinta,
  );
}

String _sinTildes(String s) {
  const origen = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑçÇàèìòùÀÈÌÒÙâêîôûÂÊÎÔÛãõÃÕ';
  const destino = 'aeiouAEIOUaeiouAEIOUnNcCaeiouAEIOUaeiouAEIOUaoAO';
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final char = String.fromCharCode(rune);
    final idx = origen.indexOf(char);
    buffer.write(idx >= 0 ? destino[idx] : char);
  }
  return buffer.toString();
}

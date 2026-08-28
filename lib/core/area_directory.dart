// lib/core/area_directory.dart
//
// Nombres de área legibles y listas sin duplicados.
//
// Dos problemas reales que resuelve este archivo:
//
//  1. **IDs crudos en pantalla.** Los documentos de `TBL_AREAS` se crean con
//     id `{empresaId}_{slug(nombre)}` (ver SeederService). Cuando al documento
//     le falta `nombre`, media app caía en `?? d.id` y el usuario terminaba
//     leyendo "EMPRESA_002_mantenimiento" en un desplegable. Aquí se
//     reconstruye "Mantenimiento" a partir del id.
//
//  2. **La misma área repetida.** Varias pantallas arman la lista de áreas a
//     partir de los USUARIOS, y el área de un usuario a veces es el id real
//     ("EMPRESA_002_mantenimiento") y a veces el nombre ("Mantenimiento")
//     porque `areaId` venía vacío. Deduplicar por id deja "Mantenimiento" dos
//     y tres veces. Aquí se agrupa por nombre normalizado y cada opción
//     conserva TODOS los ids equivalentes, para que filtrar por área siga
//     encontrando a la gente sin importar con qué variante quedó guardada.

/// Una opción de área lista para mostrar.
class AreaOpcion {
  /// Id preferido: el que parece id de catálogo (con prefijo de empresa).
  final String id;

  /// Nombre legible, nunca un id crudo.
  final String nombre;

  /// Todos los ids con los que esta misma área aparece en los datos.
  final Set<String> ids;

  const AreaOpcion({required this.id, required this.nombre, required this.ids});

  /// ¿Este registro (usuario, tarea, hallazgo) pertenece al área?
  /// Compara por id y, como respaldo, por nombre normalizado.
  bool contiene(String? areaIdONombre) {
    final raw = (areaIdONombre ?? '').trim();
    if (raw.isEmpty) return false;
    if (ids.contains(raw)) return true;
    return areaClave(raw) == areaClave(nombre);
  }
}

/// Clave de comparación de áreas: sin tildes, sin espacios ni signos.
/// "Talento Humano", "talento_humano" y "TALENTO-HUMANO" caen en la misma.
String areaClave(String value) {
  return _sinTildes(
    value,
  ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '').trim();
}

/// ¿El texto parece un id de catálogo y no un nombre? Ej. "EMPRESA_002_mantenimiento".
bool pareceAreaId(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  // Un nombre real no lleva guiones bajos ni el prefijo de empresa.
  return v.contains('_') || RegExp(r'^[A-Z]+\d+$').hasMatch(v);
}

/// Nombre legible de un área.
///
/// Usa `nombre` si trae algo; si no, reconstruye el nombre desde el id
/// quitando el prefijo de empresa: `EMPRESA_002_talento_humano` →
/// "Talento Humano". Nunca devuelve vacío.
String areaNombreLegible({
  required String id,
  String? nombre,
  String? empresaId,
}) {
  final limpio = (nombre ?? '').trim();
  if (limpio.isNotEmpty && !pareceAreaId(limpio)) return limpio;

  final base = limpio.isNotEmpty ? limpio : id.trim();
  if (base.isEmpty) return 'Sin área';

  var slug = base;
  final empresa = (empresaId ?? '').trim();
  if (empresa.isNotEmpty &&
      slug.toLowerCase().startsWith('${empresa.toLowerCase()}_')) {
    slug = slug.substring(empresa.length + 1);
  } else {
    // Sin conocer la empresa: quitar un prefijo con forma de id de empresa
    // ("EMPRESA_002_", "EMP12_"), nunca una palabra suelta del nombre.
    final match = RegExp(r'^[A-Za-z]+[_-]?\d+[_-]').matchAsPrefix(slug);
    if (match != null) slug = slug.substring(match.end);
  }

  final palabras = slug
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(
        (w) => w.length == 1
            ? w.toUpperCase()
            : '${w[0].toUpperCase()}${w.substring(1)}',
      )
      .toList();

  final resultado = palabras.join(' ').trim();
  return resultado.isEmpty ? 'Sin área' : resultado;
}

/// Agrupa áreas por nombre, ordenadas alfabéticamente.
///
/// Cada entrada de [crudas] es (id, nombre). El nombre puede venir vacío o ser
/// un id: se normaliza con [areaNombreLegible] antes de agrupar.
List<AreaOpcion> areasUnicas(
  Iterable<({String id, String? nombre})> crudas, {
  String? empresaId,
}) {
  final porClave = <String, ({String id, String nombre, Set<String> ids})>{};

  for (final cruda in crudas) {
    final id = cruda.id.trim();
    if (id.isEmpty) continue;
    final nombre = areaNombreLegible(
      id: id,
      nombre: cruda.nombre,
      empresaId: empresaId,
    );
    final clave = areaClave(nombre);
    if (clave.isEmpty) continue;

    final actual = porClave[clave];
    if (actual == null) {
      porClave[clave] = (id: id, nombre: nombre, ids: {id});
      continue;
    }
    actual.ids.add(id);
    // Entre variantes se prefiere el id de catálogo sobre el nombre suelto:
    // es el que otras colecciones guardan y con el que se puede unir.
    if (!pareceAreaId(actual.id) && pareceAreaId(id)) {
      porClave[clave] = (id: id, nombre: actual.nombre, ids: actual.ids);
    }
  }

  final salida = porClave.values
      .map((e) => AreaOpcion(id: e.id, nombre: e.nombre, ids: e.ids))
      .toList();
  salida.sort(
    (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
  );
  return salida;
}

/// Catálogo de áreas ya normalizado, pensado para las pantallas que filtran
/// por área con un desplegable.
///
/// Guarda las opciones agrupadas y resuelve las dos preguntas que hace cada
/// pantalla: qué mostrar en el desplegable y si un registro cae dentro del
/// filtro elegido (aunque su área esté guardada con otra variante del id).
class AreaCatalogo {
  final List<AreaOpcion> opciones;

  const AreaCatalogo(this.opciones);

  const AreaCatalogo.vacio() : opciones = const <AreaOpcion>[];

  factory AreaCatalogo.desde(
    Iterable<({String id, String? nombre})> crudas, {
    String? empresaId,
  }) => AreaCatalogo(areasUnicas(crudas, empresaId: empresaId));

  bool get isEmpty => opciones.isEmpty;
  bool get isNotEmpty => opciones.isNotEmpty;

  /// Etiqueta legible de un área guardada en un registro.
  /// Si no está en el catálogo, se reconstruye desde el id: nunca sale crudo.
  String nombreDe(String? areaIdONombre, {String? empresaId}) {
    final raw = (areaIdONombre ?? '').trim();
    if (raw.isEmpty) return 'Sin área';
    for (final opcion in opciones) {
      if (opcion.contiene(raw)) return opcion.nombre;
    }
    return areaNombreLegible(id: raw, empresaId: empresaId);
  }

  /// ¿El registro con área [valor] pasa el filtro [filtro]?
  /// [filtro] es el id de una opción, o [todas] para no filtrar.
  bool coincide({
    required String? filtro,
    required String? valor,
    String todas = 'todas',
  }) {
    final f = (filtro ?? '').trim();
    if (f.isEmpty || f == todas) return true;
    final opcion = opciones.where((o) => o.id == f).firstOrNull;
    if (opcion == null) return areaClave(f) == areaClave((valor ?? '').trim());
    return opcion.contiene(valor);
  }

  /// Mapa id→nombre para los `DropdownButton` que ya usan `Map<String,String>`.
  Map<String, String> comoMapa({
    String todasKey = 'todas',
    String todasLabel = 'Todas las áreas',
  }) => {
    todasKey: todasLabel,
    for (final opcion in opciones) opcion.id: opcion.nombre,
  };
}

String _sinTildes(String s) {
  const origen = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑçÇ';
  const destino = 'aeiouAEIOUaeiouAEIOUnNcC';
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final char = String.fromCharCode(rune);
    final idx = origen.indexOf(char);
    buffer.write(idx >= 0 ? destino[idx] : char);
  }
  return buffer.toString();
}

// lib/core/subcentros_costo.dart
//
// Subcentros de un centro de costo.
//
// Cómbita está registrado una vez, pero opera como Alta y Media. Picota, como
// ERE 1 y ERE 2. Al registrar un acta hay que poder decir a cuál de las dos
// corresponde, sin que dejen de ser el mismo establecimiento.
//
// POR QUÉ VIVEN DENTRO DEL CENTRO Y NO COMO CENTROS APARTE
//
// La alternativa era crear un documento por subcentro en TBL_CENTROS_COSTOS
// con un `padreId`. Se descartó por dos razones:
//
//  1. La asignación de hallazgos resuelve el cargo responsable buscando quién
//     tiene ese cargo EN el establecimiento. La gente está adscrita a Cómbita,
//     no a "Cómbita Alta". Partir el centro dejaría a esos hallazgos sin
//     responsable, que es el problema que acabamos de cerrar.
//  2. Facturación y Talento Humano listan los centros de la misma colección.
//     Un documento nuevo por subcentro les aparecería como establecimiento
//     independiente sin que nadie lo pidiera.
//
// Si algún día un subcentro necesita presupuesto o facturación propios, deja
// de ser un subcentro y toca promoverlo a centro. Ese es otro cambio.

/// Un subcentro dentro de un centro de costo.
class SubcentroCosto {
  /// Estable: se guarda en las visitas y hallazgos ya registrados. Renombrar
  /// el subcentro no debe cambiarlo, o el histórico deja de resolver.
  final String id;
  final String nombre;
  final bool enabled;

  const SubcentroCosto({
    required this.id,
    required this.nombre,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'enabled': enabled,
  };

  SubcentroCosto copyWith({String? nombre, bool? enabled}) => SubcentroCosto(
    id: id,
    nombre: nombre ?? this.nombre,
    enabled: enabled ?? this.enabled,
  );
}

/// Identificador a partir del nombre: minúsculas, sin acentos ni signos.
///
/// Se calcula una sola vez, al crear el subcentro. Después el id manda.
String slugSubcentro(String nombre) {
  const acentos = 'áéíóúüñÁÉÍÓÚÜÑ';
  const planas = 'aeiouunAEIOUUN';
  final buffer = StringBuffer();
  for (final rune in nombre.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = acentos.indexOf(ch);
    final limpio = i >= 0 ? planas[i].toLowerCase() : ch;
    if (RegExp(r'[a-z0-9]').hasMatch(limpio)) {
      buffer.write(limpio);
    } else if (buffer.isNotEmpty && !buffer.toString().endsWith('_')) {
      buffer.write('_');
    }
  }
  final out = buffer.toString();
  return out.endsWith('_') ? out.substring(0, out.length - 1) : out;
}

/// Lee los subcentros del documento de un centro de costo.
///
/// Acepta que la lista traiga textos sueltos además de mapas: así se puede
/// sembrar a mano desde la consola de Firebase sin romper la app.
List<SubcentroCosto> subcentrosDesdeData(Object? raw) {
  if (raw is! Iterable) return const [];
  final out = <SubcentroCosto>[];
  final vistos = <String>{};
  for (final item in raw) {
    String id;
    String nombre;
    var enabled = true;
    if (item is Map) {
      nombre = (item['nombre'] ?? '').toString().trim();
      id = (item['id'] ?? '').toString().trim();
      enabled = item['enabled'] is bool ? item['enabled'] as bool : true;
    } else {
      nombre = item.toString().trim();
      id = '';
    }
    if (nombre.isEmpty) continue;
    if (id.isEmpty) id = slugSubcentro(nombre);
    if (id.isEmpty || !vistos.add(id)) continue;
    out.add(SubcentroCosto(id: id, nombre: nombre, enabled: enabled));
  }
  out.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  return List.unmodifiable(out);
}

/// Nombre del establecimiento para mostrar: el centro y, si lo hay, el
/// subcentro. Se usa en listados y PDF para que "Cómbita" no aparezca dos
/// veces sin saber cuál es cuál.
String nombreEstablecimiento(String centro, String subcentro) {
  final c = centro.trim();
  final s = subcentro.trim();
  if (s.isEmpty) return c;
  if (c.isEmpty) return s;
  return '$c — $s';
}

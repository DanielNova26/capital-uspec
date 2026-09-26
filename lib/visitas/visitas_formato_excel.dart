// lib/visitas/visitas_formato_excel.dart
//
// Formatos de visita desde Excel (26 sep 2026). Dos caminos:
//
//  1. La PLANTILLA (`assets/visitas_plantilla_formato.xlsx`): hoja
//     "Preguntas" (una fila por pregunta) y hoja "Tablas" (una fila por
//     tabla). El tipo de respuesta se escribe en palabras ("Cumple / No
//     cumple / No aplica", "Lista de opciones"…); el "elemento" de antes no
//     le decía nada a nadie. Los códigos viejos (calificacion, si_no,
//     elemento) se siguen aceptando.
//  2. CUALQUIER OTRO EXCEL (el formato que ya usa el área, uno de Google
//     Sheets descargado): se busca la columna de las preguntas, las secciones
//     y el encabezado del documento, y sale un borrador que se revisa en el
//     editor antes de guardar. Es "mirar a ver si se puede adaptar": lo que
//     se tuvo que suponer se dice en `avisos`.
//
// El mismo adaptador lee lo que se pega desde Excel en el editor (texto con
// tabuladores), así copiar y pegar y subir el archivo dan lo mismo.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;

import 'visitas_models.dart';

/// Lo que sale de leer un Excel: el borrador del formato y lo que se tuvo
/// que suponer para armarlo.
class ImportacionFormato {
  final VisitaFormato formato;
  final List<String> avisos;

  /// `true` si el archivo era la plantilla; `false` si se adaptó otro Excel.
  final bool desdePlantilla;

  const ImportacionFormato({
    required this.formato,
    this.avisos = const [],
    this.desdePlantilla = true,
  });
}

/// Lee un Excel de formato. Si es la plantilla la usa tal cual; si no, lo
/// adapta. Siempre devuelve un borrador: la jefatura lo revisa antes de
/// habilitar visitas reales.
ImportacionFormato leerFormatoVisitasExcel(
  Uint8List bytes, {
  required String empresaId,
  required String areaId,
  required String areaNombre,
  required String nombre,
}) {
  _exigirAreaYNombre(areaId, nombre);
  final libro = _decodificar(bytes);
  if (_esPlantilla(libro)) {
    return ImportacionFormato(
      formato: _desdePlantilla(
        libro,
        empresaId: empresaId,
        areaId: areaId,
        areaNombre: areaNombre,
        nombre: nombre,
      ),
    );
  }
  return _adaptarLibro(
    libro,
    empresaId: empresaId,
    areaId: areaId,
    areaNombre: areaNombre,
    nombre: nombre,
  );
}

/// Importa la plantilla. Lanza [FormatException] con el motivo si algo no
/// cuadra; nunca devuelve un formato a medias. [hojaPreguntas] y
/// [hojaTablas] permiten leer las hojas de ejemplo en las pruebas.
VisitaFormato importarFormatoVisitasExcel(
  Uint8List bytes, {
  required String empresaId,
  required String areaId,
  required String areaNombre,
  required String nombre,
  String hojaPreguntas = kHojaPreguntas,
  String hojaTablas = kHojaTablas,
}) {
  _exigirAreaYNombre(areaId, nombre);
  return _desdePlantilla(
    _decodificar(bytes),
    empresaId: empresaId,
    areaId: areaId,
    areaNombre: areaNombre,
    nombre: nombre,
    hojaPreguntas: hojaPreguntas,
    hojaTablas: hojaTablas,
  );
}

/// Preguntas sacadas de lo que se pegó desde Excel (filas separadas por
/// salto de línea y columnas por tabulador). Si la primera fila trae los
/// encabezados de la plantilla se respetan; si no, se adapta igual que un
/// Excel cualquiera. [desdeOrden] numera a continuación de las que ya hay.
({List<VisitaFormatoItem> items, List<String> avisos})
preguntasDesdeTextoPegado(
  String texto, {
  int desdeOrden = 1,
  String prefijoId = 'p',
}) {
  final filas = [
    for (final linea in const LineSplitter().convert(texto))
      if (linea.trim().isNotEmpty) linea.split('\t').map(_limpiar).toList(),
  ];
  if (filas.isEmpty) return (items: const [], avisos: const []);
  final cab = filas.first.map(_clave).toList();
  if (cab.contains(_clave('Pregunta'))) {
    final items = _preguntasPlantilla(
      filas,
      desdeOrden: desdeOrden,
      prefijoId: prefijoId,
    );
    return (items: items, avisos: const []);
  }
  final r = _adaptarRejilla(
    filas,
    hoja: '',
    desdeOrden: desdeOrden,
    prefijoId: prefijoId,
  );
  return (items: r.items, avisos: r.avisos);
}

/// Las hojas del libro como texto (hoja → filas → celdas), ya limpias. Pasa
/// por la misma normalización que el importador: los archivos de openpyxl y
/// de algunas versiones de Excel traen rutas que el lector no entiende.
Map<String, List<List<String>>> leerHojasExcel(Uint8List bytes) {
  final libro = _decodificar(bytes);
  return {for (final e in libro.tables.entries) e.key: _rejilla(e.value)};
}

// ── Plantilla ───────────────────────────────────────────────────────────────

const String kHojaPreguntas = 'Preguntas';
const String kHojaTablas = 'Tablas';

/// Encabezados de la hoja Preguntas, en orden. La plantilla y el editor
/// (vista tabla) usan los mismos nombres.
const List<String> kColumnasPreguntas = [
  'Sección',
  'Pregunta',
  'Tipo de respuesta',
  'Opciones (separadas por ;)',
  'Obligatoria',
  'Foto obligatoria si no cumple',
  'Cantidad esperada',
  'Ayuda para el profesional',
];

const List<String> kColumnasTablas = [
  'Tabla',
  'Cada fila es un(a)',
  'Columnas para escribir (separadas por ;)',
  'Columnas para calificar (separadas por ;)',
  'Escala',
  'Filas fijas (separadas por ;)',
];

void _exigirAreaYNombre(String areaId, String nombre) {
  if (areaId.trim().isEmpty || nombre.trim().isEmpty) {
    throw const FormatException(
      'Selecciona el área y escribe el nombre del formato.',
    );
  }
}

xl.Excel _decodificar(Uint8List bytes) {
  try {
    return xl.Excel.decodeBytes(_normalizarRelaciones(bytes));
  } catch (_) {
    throw const FormatException(
      'No se pudo leer el archivo. Ábrelo en Excel o Google Sheets y '
      'guárdalo como .xlsx.',
    );
  }
}

List<List<String>> _rejilla(xl.Sheet hoja) => [
  for (final fila in hoja.rows)
    [for (final c in fila) _limpiar(_texto(c?.value))],
];

xl.Sheet? _hoja(xl.Excel libro, String nombre) {
  final k = _clave(nombre);
  for (final e in libro.tables.entries) {
    if (_clave(e.key) == k) return e.value;
  }
  return null;
}

/// Es la plantilla si tiene la hoja Preguntas con la columna Pregunta en la
/// primera fila (la de antes o la de ahora).
bool _esPlantilla(xl.Excel libro) {
  final h = _hoja(libro, kHojaPreguntas);
  if (h == null || h.rows.isEmpty) return false;
  return h.rows.first
      .map((c) => _clave(_texto(c?.value)))
      .contains(_clave('Pregunta'));
}

VisitaFormato _desdePlantilla(
  xl.Excel libro, {
  required String empresaId,
  required String areaId,
  required String areaNombre,
  required String nombre,
  String hojaPreguntas = kHojaPreguntas,
  String hojaTablas = kHojaTablas,
}) {
  final hp =
      _hoja(libro, hojaPreguntas) ??
      (hojaPreguntas == kHojaPreguntas && libro.tables.isNotEmpty
          ? libro.tables.values.first
          : null);
  if (hp == null) {
    throw FormatException('El Excel no tiene la hoja "$hojaPreguntas".');
  }
  final filas = _rejilla(hp);
  final items = filas.isEmpty
      ? const <VisitaFormatoItem>[]
      : _preguntasPlantilla(filas);
  final ht = _hoja(libro, hojaTablas);
  final tablas = ht == null
      ? const <VisitaFormatoTabla>[]
      : _tablasPlantilla(_rejilla(ht));
  if (items.isEmpty && tablas.isEmpty) {
    throw const FormatException(
      'Agrega al menos una pregunta (hoja Preguntas) o una tabla (hoja '
      'Tablas) antes de importar. Las hojas de ejemplo son solo de muestra.',
    );
  }
  final formato = VisitaFormato(
    empresaId: empresaId,
    areaId: areaId,
    areaNombre: areaNombre,
    nombre: nombre.trim(),
    estado: kFormatoBorrador,
    items: items,
    tablas: tablas,
  );
  final errores = validarFormato(formato);
  if (errores.isNotEmpty) throw FormatException(errores.join(' '));
  return formato;
}

/// Preguntas de una rejilla con encabezados de plantilla en la primera fila.
List<VisitaFormatoItem> _preguntasPlantilla(
  List<List<String>> filas, {
  int desdeOrden = 1,
  String prefijoId = 'p',
}) {
  final cab = filas.first.map(_clave).toList();
  int col(List<String> nombres) {
    for (final n in nombres) {
      final i = cab.indexOf(_clave(n));
      if (i >= 0) return i;
    }
    return -1;
  }

  final cPregunta = col(const ['Pregunta']);
  if (cPregunta < 0) {
    throw const FormatException(
      'Falta la columna Pregunta en la primera fila.',
    );
  }
  final cSeccion = col(const ['Sección']);
  final cTipo = col(const ['Tipo de respuesta', 'Tipo']);
  final cOpciones = col(const ['Opciones (separadas por ;)', 'Opciones']);
  final cObligatoria = col(const ['Obligatoria']);
  final cFoto = col(const [
    'Foto obligatoria si no cumple',
    'Evidencia obligatoria',
    'Foto obligatoria',
  ]);
  final cUnidad = col(const ['Cantidad esperada', 'Unidad']);
  final cAyuda = col(const ['Ayuda para el profesional', 'Ayuda']);
  String celda(List<String> fila, int c) =>
      c < 0 || c >= fila.length ? '' : fila[c];

  final items = <VisitaFormatoItem>[];
  for (var i = 1; i < filas.length; i++) {
    final fila = filas[i];
    if (fila.every((c) => c.isEmpty)) continue;
    final pregunta = celda(fila, cPregunta);
    if (pregunta.isEmpty) {
      throw FormatException('Fila ${i + 1}: falta la pregunta.');
    }
    final tipoTexto = celda(fila, cTipo);
    final tipo = tipoDesdeTexto(tipoTexto);
    if (tipo == null) {
      throw FormatException(
        'Fila ${i + 1}: tipo de respuesta no reconocido: "$tipoTexto". '
        'Usa uno de la lista: ${kItemTiposLabel.values.join(' · ')}.',
      );
    }
    final foto = _siNo(celda(fila, cFoto), porDefecto: false);
    if (foto == null) {
      throw FormatException(
        'Fila ${i + 1}: "Foto obligatoria si no cumple" debe ser Sí o No.',
      );
    }
    final obligatoria = _siNo(celda(fila, cObligatoria), porDefecto: true);
    if (obligatoria == null) {
      throw FormatException('Fila ${i + 1}: "Obligatoria" debe ser Sí o No.');
    }
    final opciones = _lista(celda(fila, cOpciones));
    final orden = desdeOrden + items.length;
    items.add(
      VisitaFormatoItem(
        id: '$prefijoId${orden.toString().padLeft(3, '0')}',
        orden: orden,
        seccion: celda(fila, cSeccion),
        texto: pregunta,
        tipo: tipo,
        requiereEvidencia: itemCalifica(tipo) && foto,
        unidad: tipo == kItemTipoElemento ? celda(fila, cUnidad) : '',
        opciones: tipo == kItemTipoOpcion ? opciones : const [],
        // Las que califican siempre se contestan.
        obligatoria: itemCalifica(tipo) || obligatoria,
        ayuda: celda(fila, cAyuda),
      ),
    );
  }
  return items;
}

/// Tablas de la hoja Tablas: una fila por tabla.
List<VisitaFormatoTabla> _tablasPlantilla(List<List<String>> filas) {
  if (filas.isEmpty) return const [];
  final cab = filas.first.map(_clave).toList();
  int col(List<String> nombres) {
    for (final n in nombres) {
      final i = cab.indexOf(_clave(n));
      if (i >= 0) return i;
    }
    return -1;
  }

  final cTabla = col(const ['Tabla']);
  if (cTabla < 0) return const [];
  final cFila = col(const ['Cada fila es un(a)', 'Nombre de cada fila']);
  final cTexto = col(const [
    'Columnas para escribir (separadas por ;)',
    'Columnas para escribir',
  ]);
  final cEstado = col(const [
    'Columnas para calificar (separadas por ;)',
    'Columnas para calificar',
  ]);
  final cEscala = col(const ['Escala']);
  final cFijas = col(const ['Filas fijas (separadas por ;)', 'Filas fijas']);
  String celda(List<String> fila, int c) =>
      c < 0 || c >= fila.length ? '' : fila[c];

  final out = <VisitaFormatoTabla>[];
  for (var i = 1; i < filas.length; i++) {
    final fila = filas[i];
    if (fila.every((c) => c.isEmpty)) continue;
    final nombre = celda(fila, cTabla);
    if (nombre.isEmpty) {
      throw FormatException('Tablas, fila ${i + 1}: falta el nombre.');
    }
    final estados = _lista(celda(fila, cEstado));
    if (estados.isEmpty) {
      throw FormatException(
        'Tabla "$nombre": escribe al menos una columna para calificar.',
      );
    }
    final escalaTexto = celda(fila, cEscala);
    final escala = escalaDesdeTexto(escalaTexto);
    if (escala == null) {
      throw FormatException(
        'Tabla "$nombre": escala no reconocida: "$escalaTexto". Usa '
        '${kEscalasLabel.values.join(' · ')}.',
      );
    }
    out.add(
      VisitaFormatoTabla(
        id: 't${out.length + 1}',
        nombre: nombre,
        etiquetaFila: celda(fila, cFila).isEmpty ? 'Fila' : celda(fila, cFila),
        camposTexto: [
          for (final (j, l) in _lista(celda(fila, cTexto)).indexed)
            VisitaTablaCampo('c${j + 1}', l),
        ],
        camposEstado: [
          for (final (j, l) in estados.indexed)
            VisitaTablaCampo('e${j + 1}', l),
        ],
        escala: escala,
        filasFijas: _lista(celda(fila, cFijas)),
      ),
    );
  }
  return out;
}

/// El tipo a partir de lo que dice la celda: el nombre de la lista, el
/// código viejo o una forma parecida. Vacío = Cumple / No cumple / No aplica.
/// Null si no se reconoce.
String? tipoDesdeTexto(String texto) {
  final k = _clave(texto);
  if (k.isEmpty) return kItemTipoCalificacion;
  for (final e in kItemTiposLabel.entries) {
    if (_clave(e.value) == k || _clave(e.key) == k) return e.key;
  }
  const alias = {
    'calificacion': kItemTipoCalificacion,
    'cumplenocumple': kItemTipoCalificacion,
    '10na': kItemTipoCalificacion,
    'cumple': kItemTipoCalificacion,
    'sino': kItemTipoSiNo,
    'elemento': kItemTipoElemento,
    'elementos': kItemTipoElemento,
    'cantidadyvencimiento': kItemTipoElemento,
    'inventario': kItemTipoElemento,
    'lista': kItemTipoOpcion,
    'opcion': kItemTipoOpcion,
    'opciones': kItemTipoOpcion,
    'seleccion': kItemTipoOpcion,
    'seleccionunica': kItemTipoOpcion,
    'texto': kItemTipoTexto,
    'textocorto': kItemTipoTexto,
    'respuestacorta': kItemTipoTexto,
    'textolargo': kItemTipoParrafo,
    'respuestalarga': kItemTipoParrafo,
    'parrafo': kItemTipoParrafo,
    'numero': kItemTipoNumero,
    'numerico': kItemTipoNumero,
    'fecha': kItemTipoFecha,
  };
  return alias[k];
}

String? escalaDesdeTexto(String texto) {
  final k = _clave(texto);
  if (k.isEmpty) return kEscalaBmrnc;
  for (final e in kEscalasLabel.entries) {
    if (_clave(e.value) == k || _clave(e.key) == k) return e.key;
  }
  const alias = {
    'bmrnc': kEscalaBmrnc,
    'bmr': kEscalaBmrnc,
    'buenomaloregular': kEscalaBmrnc,
    'cumplenocumple': kEscalaCumple,
    'cumple': kEscalaCumple,
    'cnc': kEscalaCumple,
    'sino': kEscalaSiNo,
  };
  return alias[k];
}

bool? _siNo(String texto, {required bool porDefecto}) {
  final k = _clave(texto);
  if (k.isEmpty) return porDefecto;
  if (const ['si', 'true', '1', 'x', 'obligatoria'].contains(k)) return true;
  if (const ['no', 'false', '0'].contains(k)) return false;
  return null;
}

List<String> _lista(String texto) => [
  for (final p in texto.split(RegExp(r'[;\n|]')))
    if (p.trim().isNotEmpty) p.trim(),
];

// ── Adaptar cualquier Excel ─────────────────────────────────────────────────

/// Palabras que señalan la columna de las preguntas, de la más fiable a la
/// menos. En el Excel de SST la de preguntas es "PARÁMETROS DE EVALUACIÓN" y
/// "ITEMS A EVALUAR" es la de secciones: por eso "parametro" va antes que
/// "item".
const _kPalabrasPregunta = [
  'parametro',
  'pregunta',
  'aspectoaverificar',
  'aspectoaevaluar',
  'criterio',
  'requisito',
  'queseverifica',
  'queserevisa',
  'descripcion',
  'actividad',
  'aspecto',
  'elemento',
  'condicion',
  'concepto',
  'item',
];

const _kPalabrasSeccion = [
  'seccion',
  'itemsaevaluar',
  'componente',
  'categoria',
  'capitulo',
  'grupo',
  'tema',
  'modulo',
  'area',
];

/// Rótulos que no son preguntas: totales, firmas, pies del formato.
const _kRotulosIgnorados = [
  'subtotal',
  'total',
  'calificacion',
  'observacionesgenerales',
  'observaciones',
  'firma',
  'nombre',
  'cargo',
  'fecha',
  'responsable',
  'criteriosdecalificacion',
  'nota',
  'elaboro',
  'reviso',
  'aprobo',
];

ImportacionFormato _adaptarLibro(
  xl.Excel libro, {
  required String empresaId,
  required String areaId,
  required String areaNombre,
  required String nombre,
}) {
  final avisos = <String>[];
  final porHoja = <({String hoja, _Adaptado r, _Encabezado enc})>[];
  var orden = 1;
  for (final e in libro.tables.entries) {
    final k = _clave(e.key);
    if (k.startsWith('instruccion') || k.startsWith('ejemplo')) continue;
    final grid = _rejilla(e.value);
    if (grid.isEmpty) continue;
    final r = _adaptarRejilla(
      grid,
      hoja: e.key,
      desdeOrden: orden,
      prefijoId: 'p',
    );
    if (r.items.isEmpty) continue;
    orden += r.items.length;
    porHoja.add((hoja: e.key, r: r, enc: _encabezadoDe(grid)));
  }
  if (porHoja.isEmpty) {
    throw const FormatException(
      'No se encontraron preguntas en el Excel. Revisa que tenga una '
      'columna con lo que se revisa (Pregunta, Parámetro, Aspecto, '
      'Descripción…) o descarga la plantilla y copia ahí las preguntas.',
    );
  }
  // Con varias hojas, cada hoja es una parte del formato (como el Excel de
  // SST: una hoja por inspección, cada una con su encabezado).
  final varias = porHoja.length > 1;
  final partes = <VisitaFormatoParte>[];
  final items = <VisitaFormatoItem>[];
  final usados = <String>{};
  for (final h in porHoja) {
    avisos.addAll(h.r.avisos);
    var parte = '';
    if (varias) {
      var codigo = h.enc.codigo.isNotEmpty ? h.enc.codigo : h.hoja.trim();
      while (!usados.add(codigo)) {
        codigo = '$codigo·';
      }
      parte = codigo;
      partes.add(
        VisitaFormatoParte(
          codigo: codigo,
          nombre: (h.enc.titulo.isNotEmpty ? h.enc.titulo : h.hoja)
              .toUpperCase(),
          version: h.enc.version.isEmpty ? '1' : h.enc.version,
          elaboracion: h.enc.elaboracion,
        ),
      );
    }
    for (final it in h.r.items) {
      items.add(it.copyWith(parte: parte));
    }
  }
  final enc = porHoja.first.enc;
  avisos.add(
    'Todas quedaron como "${kItemTiposLabel[kItemTipoCalificacion]}" salvo '
    'donde el Excel decía otra cosa. Revisa el tipo de cada pregunta antes '
    'de guardar.',
  );
  final formato = VisitaFormato(
    empresaId: empresaId,
    areaId: areaId,
    areaNombre: areaNombre,
    nombre: nombre.trim(),
    estado: kFormatoBorrador,
    items: items,
    partes: partes,
    codigo: varias ? '' : enc.codigo,
    versionDocumento: varias ? '' : enc.version,
    elaboracion: varias ? '' : enc.elaboracion,
  );
  final errores = validarFormato(formato);
  if (errores.isNotEmpty) throw FormatException(errores.join(' '));
  return ImportacionFormato(
    formato: formato,
    avisos: avisos,
    desdePlantilla: false,
  );
}

class _Adaptado {
  final List<VisitaFormatoItem> items;
  final List<String> avisos;
  const _Adaptado(this.items, this.avisos);
}

/// Busca en una rejilla la columna de preguntas y las secciones.
_Adaptado _adaptarRejilla(
  List<List<String>> grid, {
  required String hoja,
  required int desdeOrden,
  required String prefijoId,
}) {
  final donde = hoja.isEmpty ? 'Lo pegado' : 'Hoja "$hoja"';
  final avisos = <String>[];
  int? filaCab;
  var cPregunta = -1;
  var cSeccion = -1;
  var cTipo = -1;
  var cUnidad = -1;
  var tipoPorColumnas = kItemTipoCalificacion;

  // 1. Encabezado: la primera fila (de las 40 primeras) con una celda que
  //    nombra la columna de preguntas.
  for (var r = 0; r < grid.length && r < 40 && filaCab == null; r++) {
    final claves = grid[r].map(_clave).toList();
    for (final palabra in _kPalabrasPregunta) {
      final c = claves.indexWhere(
        (k) => k.isNotEmpty && k.length <= 40 && k.startsWith(palabra),
      );
      if (c >= 0) {
        filaCab = r;
        cPregunta = c;
        break;
      }
    }
  }
  if (filaCab != null) {
    final claves = grid[filaCab].map(_clave).toList();
    for (final palabra in _kPalabrasSeccion) {
      final c = claves.indexWhere(
        (k) => k.isNotEmpty && k.length <= 40 && k.startsWith(palabra),
      );
      if (c >= 0 && c != cPregunta) {
        cSeccion = c;
        break;
      }
    }
    cTipo = claves.indexWhere((k) => k == 'tipo' || k.startsWith('tipode'));
    cUnidad = claves.indexWhere(
      (k) =>
          k == 'unidad' || k.startsWith('cantidadesperada') || k == 'cantidad',
    );
    final tieneSi = claves.contains('si');
    final tieneNo = claves.contains('no');
    final tieneNa = claves.contains('na') || claves.contains('noaplica');
    if (tieneSi && tieneNo && !tieneNa) tipoPorColumnas = kItemTipoSiNo;
    if (cUnidad >= 0) tipoPorColumnas = kItemTipoElemento;
    avisos.add(
      '$donde: las preguntas salen de la columna '
      '"${grid[filaCab][cPregunta]}"'
      '${cSeccion >= 0 ? ' y las secciones de "${grid[filaCab][cSeccion]}"' : ''}.',
    );
  } else {
    // 2. Sin encabezado: la columna con más textos largos.
    final conteo = <int, int>{};
    for (final fila in grid) {
      for (var c = 0; c < fila.length; c++) {
        final t = fila[c];
        if (t.length >= 12 && double.tryParse(t) == null) {
          conteo[c] = (conteo[c] ?? 0) + 1;
        }
      }
    }
    if (conteo.isEmpty) return _Adaptado(const [], avisos);
    cPregunta = conteo.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    avisos.add(
      '$donde: no tenía encabezado de preguntas; se tomó la columna '
      '${_letraColumna(cPregunta)}, la de textos más largos.',
    );
  }

  final items = <VisitaFormatoItem>[];
  var seccion = '';
  final desde = filaCab == null ? 0 : filaCab + 1;
  final cabClaves = filaCab == null
      ? const <String>{}
      : grid[filaCab].map(_clave).where((k) => k.isNotEmpty).toSet();
  for (var r = desde; r < grid.length; r++) {
    final fila = grid[r];
    final llenas = [
      for (var c = 0; c < fila.length; c++)
        if (fila[c].isNotEmpty) c,
    ];
    if (llenas.isEmpty) continue;
    String celda(int c) => c < 0 || c >= fila.length ? '' : fila[c];
    // Encabezado repetido (el formato ocupa varias páginas).
    if (_clave(celda(cPregunta)).isNotEmpty &&
        cabClaves.contains(_clave(celda(cPregunta)))) {
      continue;
    }
    final sec = celda(cSeccion);
    if (sec.isNotEmpty && !_esRotuloIgnorado(sec)) seccion = sec;
    var texto = celda(cPregunta);
    if (texto.isEmpty) {
      // Una fila con un solo título (y en otra columna) abre sección.
      if (llenas.length == 1 && _pareceTitulo(fila[llenas.single])) {
        seccion = fila[llenas.single];
      }
      continue;
    }
    if (_esRotuloIgnorado(texto) || double.tryParse(texto) != null) continue;
    if (llenas.length == 1 && cSeccion < 0 && _pareceTitulo(texto)) {
      seccion = texto;
      continue;
    }
    texto = texto.replaceFirst(RegExp(r'^\d+(\.\d+)*[\.\)\-]?\s+'), '').trim();
    if (texto.length < 3) continue;
    var tipo = tipoPorColumnas;
    final tipoCelda = celda(cTipo);
    if (tipoCelda.isNotEmpty) tipo = tipoDesdeTexto(tipoCelda) ?? tipo;
    final orden = desdeOrden + items.length;
    items.add(
      VisitaFormatoItem(
        id: '$prefijoId${orden.toString().padLeft(3, '0')}',
        orden: orden,
        seccion: seccion,
        texto: texto,
        tipo: tipo,
        unidad: tipo == kItemTipoElemento ? celda(cUnidad) : '',
      ),
    );
  }
  if (items.isNotEmpty) {
    avisos.add('$donde: ${items.length} pregunta(s).');
  }
  return _Adaptado(items, avisos);
}

class _Encabezado {
  final String titulo;
  final String codigo;
  final String version;
  final String elaboracion;
  const _Encabezado({
    this.titulo = '',
    this.codigo = '',
    this.version = '',
    this.elaboracion = '',
  });
}

/// Título, código, versión y elaboración de las primeras filas del Excel,
/// como vienen en los formatos del sistema de gestión (celda "CÓDIGO" y a
/// su lado "F-UT-SST-02").
_Encabezado _encabezadoDe(List<List<String>> grid) {
  String junto(List<String> etiquetas) {
    for (var r = 0; r < grid.length && r < 12; r++) {
      final fila = grid[r];
      for (var c = 0; c < fila.length; c++) {
        final k = _clave(fila[c]);
        for (final e in etiquetas) {
          if (!k.startsWith(e)) continue;
          // "CÓDIGO: F-UT-01" en la misma celda.
          final dos = fila[c].split(':');
          if (dos.length > 1 && dos.sublist(1).join(':').trim().isNotEmpty) {
            return dos.sublist(1).join(':').trim();
          }
          if (k != e) continue;
          for (var d = c + 1; d < fila.length; d++) {
            if (fila[d].isNotEmpty) return fila[d];
          }
          if (r + 1 < grid.length &&
              c < grid[r + 1].length &&
              grid[r + 1][c].isNotEmpty) {
            return grid[r + 1][c];
          }
        }
      }
    }
    return '';
  }

  var titulo = '';
  for (var r = 0; r < grid.length && r < 8; r++) {
    for (final t in grid[r]) {
      final k = _clave(t);
      if (t.length > titulo.length &&
          (k.contains('formato') ||
              k.contains('inspeccion') ||
              k.contains('listadechequeo') ||
              k.contains('verificacion')) &&
          !k.startsWith('sistema')) {
        titulo = t;
      }
    }
  }
  return _Encabezado(
    titulo: titulo,
    codigo: junto(const ['codigo']),
    version: junto(const ['version']),
    elaboracion: junto(const ['fechadeelaboracion', 'elaboracion']),
  );
}

/// Solo rótulos cortos ("FIRMA:", "Subtotal", "Nombre del responsable"): una
/// pregunta larga que empieza por "Fecha de vencimiento…" sí es pregunta.
bool _esRotuloIgnorado(String t) {
  final k = _clave(t);
  if (k.isEmpty) return true;
  if (t.trim().length > 35 && !t.trim().endsWith(':')) return false;
  return _kRotulosIgnorados.any(k.startsWith);
}

/// Un título de sección: corto, sin signo de pregunta y en mayúsculas (o
/// terminado en dos puntos).
bool _pareceTitulo(String t) {
  final s = t.trim();
  if (s.isEmpty || s.length > 80 || s.contains('?')) return false;
  if (s.endsWith(':')) return true;
  final letras = s.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑáéíóúñ]'), '');
  return letras.length >= 3 && letras == letras.toUpperCase();
}

String _letraColumna(int c) {
  var n = c + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

// ── Utilidades ──────────────────────────────────────────────────────────────

/// Algunas herramientas Excel escriben destinos absolutos y prefijos `x:`
/// en el XML. El lector `excel` espera rutas relativas y etiquetas sin prefijo.
Uint8List _normalizarRelaciones(Uint8List bytes) {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    final reconstruido = Archive();
    var cambios = false;
    for (final archivo in zip) {
      if (!archivo.name.startsWith('xl/') ||
          !archivo.name.endsWith('.xml') && !archivo.name.endsWith('.rels')) {
        reconstruido.addFile(archivo);
        continue;
      }
      final original = utf8.decode(archivo.content as List<int>);
      var xml = original.replaceAll('Target="/xl/', 'Target="');
      xml = xml
          .replaceAll('xmlns:x=', 'xmlns=')
          .replaceAll('<x:', '<')
          .replaceAll('</x:', '</');
      if (archivo.name.startsWith('xl/worksheets/')) {
        xml = xml.replaceAllMapped(
          RegExp(r'<c\b[^>]*\bt="str"[^>]*/>'),
          (m) => m.group(0)!.replaceAll(' t="str"', ''),
        );
      }
      if (xml != original) cambios = true;
      final contenido = utf8.encode(xml);
      reconstruido.addFile(
        ArchiveFile(archivo.name, contenido.length, contenido),
      );
    }
    if (!cambios) return bytes;
    final codificado = ZipEncoder().encode(reconstruido);
    return codificado == null ? bytes : Uint8List.fromList(codificado);
  } catch (_) {
    return bytes;
  }
}

String _dos(int n) => n.toString().padLeft(2, '0');

String _texto(xl.CellValue? valor) => switch (valor) {
  xl.TextCellValue v => v.value.toString(),
  xl.IntCellValue v => v.value.toString(),
  xl.DoubleCellValue v =>
    v.value == v.value.roundToDouble()
        ? v.value.toInt().toString()
        : v.value.toString(),
  xl.BoolCellValue v => v.value ? 'Sí' : 'No',
  xl.FormulaCellValue v => v.formula,
  xl.DateCellValue v => '${_dos(v.day)}/${_dos(v.month)}/${v.year}',
  xl.DateTimeCellValue v => '${_dos(v.day)}/${_dos(v.month)}/${v.year}',
  _ => '',
};

/// Sin saltos de línea dobles ni espacios de sobra.
String _limpiar(String t) =>
    t.replaceAll('\r', '').replaceAll(RegExp(r'[ \t]+'), ' ').trim();

/// Clave para comparar: minúsculas, sin tildes y solo letras y números.
String _clave(String valor) => valor
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[áàä]'), 'a')
    .replaceAll(RegExp(r'[éèë]'), 'e')
    .replaceAll(RegExp(r'[íìï]'), 'i')
    .replaceAll(RegExp(r'[óòö]'), 'o')
    .replaceAll(RegExp(r'[úùü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

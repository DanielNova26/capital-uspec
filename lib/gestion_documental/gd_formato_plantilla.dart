// Plantilla Excel de formato institucional generada por la app.
//
// Oscar (reunión 12 sep 2026) no quiere que cada quien arme su encabezado:
// "unos ponen un logo, otros otro, otros un código arriba, otros abajo".
// Por eso la plantilla no es un archivo suelto: se genera por registro con
// los datos que ya tiene la Biblioteca (código, nombre, área, versión)
// y el logo de la empresa, y el encabezado queda BLOQUEADO con protección de
// hoja. De la fila 7 hacia abajo todas las celdas están desbloqueadas: ahí
// cada dependencia arma el contenido como necesite (bordes, combinaciones,
// filas nuevas...).
//
// Se escribe OOXML a mano en vez de usar el paquete `excel` porque ese
// paquete no sabe insertar imágenes ni proteger hojas, y post-procesar su
// salida sería más frágil que armar una estructura fija y pequeña.
//
// La geometría reproduce el modelo que entregó el jefe el 14 sep 2026
// ("1. Formato modelo v1.xlsx"): bordes finos azul marino, logo en A1:C4,
// empresa en D1:L1, nombre del formato en D2:L3, área en D4:L4,
// etiquetas en M:N y valores en O:Q; filas 1-4 de 14.25 pt y dos filas
// separadoras (5 y 6) de 2 y 8 pt. Los rellenos son los de la versión del
// 12 sep, que el jefe sí quiere: título en blanco sobre el color primario,
// empresa/área/etiquetas sobre el secundario claro y una franja del
// primario en la fila 6.
//
// Sin dependencias de Flutter: se prueba en `flutter test` sin widgets.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Colores del encabezado. El primario (azul marino del modelo del jefe)
/// pinta bordes, el fondo del título, la franja separadora y el texto de
/// etiquetas, empresa y área; el secundario es el relleno claro de
/// etiquetas, empresa y área. `TBL_EMPRESAS.colorPrimario` /
/// `colorSecundario` (hex sin `#`) los reemplazan por empresa si existen.
const String kGdPlantillaColorPrimario = '0D1B68';
const String kGdPlantillaColorSecundario = 'E8EEF5';

/// Clave de la protección de hoja. No es un secreto fuerte (Excel usa un
/// hash de 16 bits): es un candado para que nadie toque el encabezado por
/// accidente. Calidad la conoce por si hay que corregir algo a mano.
const String kGdPlantillaClaveHoja = 'CALIDAD-USPEC';

/// Primera fila editable. Las filas 1-4 son el encabezado y la 5 y 6 son
/// separadores; todo lo demás queda desbloqueado.
const int kGdPlantillaPrimeraFilaLibre = 7;

/// Celda donde va "quién · cuándo" validó (etiqueta *Aprobado* en M2). El
/// sello de Calidad la reescribe sobre el archivo subido.
const String kGdPlantillaCeldaAprobado = 'O2';

class GdPlantillaFormatoDatos {
  final String empresaNombre;
  final String titulo;
  final String codigo;
  final String area;
  final String version;
  final DateTime fecha;

  /// Nombre de quien validó, o null si aún no pasa por Calidad.
  final String? aprobadoPor;
  final DateTime? aprobadoEn;

  /// PNG o JPEG. Cualquier otro formato se ignora y se escribe el nombre
  /// de la empresa en el recuadro del logo.
  final Uint8List? logo;
  final String colorPrimario;
  final String colorSecundario;

  const GdPlantillaFormatoDatos({
    required this.empresaNombre,
    required this.titulo,
    required this.codigo,
    required this.area,
    required this.version,
    required this.fecha,
    this.aprobadoPor,
    this.aprobadoEn,
    this.logo,
    this.colorPrimario = kGdPlantillaColorPrimario,
    this.colorSecundario = kGdPlantillaColorSecundario,
  });
}

/// Nombre de archivo sugerido: `LOG-001_Acta_de_baja_v1.xlsx`.
String gdNombreArchivoPlantilla(GdPlantillaFormatoDatos datos) {
  final titulo = datos.titulo
      .trim()
      .replaceAll(RegExp(r'[^\wÁÉÍÓÚáéíóúÑñ]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final base = [
    datos.codigo.trim(),
    if (titulo.isNotEmpty) titulo,
    datos.version.trim(),
  ].where((s) => s.isNotEmpty).join('_');
  return '$base.xlsx';
}

/// Hash de clave de hoja (algoritmo heredado de Excel, el mismo que usa
/// openpyxl). Devuelve 4 dígitos hex en mayúscula.
String gdHashClaveHoja(String clave) {
  var hash = 0;
  final max = clave.length < 255 ? clave.length : 255;
  for (var i = 0; i < max; i++) {
    final value = clave.codeUnitAt(i) << (i + 1);
    final rotated = value >> 15;
    hash ^= ((value & 0x7fff) | rotated);
  }
  hash ^= clave.length;
  hash ^= 0xCE4B;
  return hash.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// Genera el .xlsx completo.
Uint8List gdGenerarPlantillaFormato(GdPlantillaFormatoDatos datos) {
  final logo = _ImagenInfo.detectar(datos.logo);
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes(logo));
  add('_rels/.rels', _rootRels);
  add('xl/workbook.xml', _workbook);
  add('xl/_rels/workbook.xml.rels', _workbookRels);
  add('xl/styles.xml', _styles(datos));
  add('xl/worksheets/sheet1.xml', _sheet(datos, logo != null));
  if (logo != null) {
    add('xl/worksheets/_rels/sheet1.xml.rels', _sheetRels);
    add('xl/drawings/drawing1.xml', _drawing(logo));
    add('xl/drawings/_rels/drawing1.xml.rels', _drawingRels(logo));
    archive.addFile(
      ArchiveFile(
        'xl/media/image1.${logo.extension}',
        logo.bytes.length,
        logo.bytes,
      ),
    );
  }
  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped ?? const []);
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometría del encabezado
// ─────────────────────────────────────────────────────────────────────────────

// Anchos de columna (atributo `width` de OOXML, que ya incluye el relleno;
// Excel lo muestra como 4.86). En el modelo TODAS las columnas A-Q son
// angostas e iguales: el encabezado mide 497 pt y cabe en carta vertical, y
// la cuadrícula fina le sirve a cada dependencia para armar el contenido.
// R es un margen derecho casi invisible. A-C: logo, D-L: empresa/título/
// dependencia, M-N: etiquetas, O-Q: valores.
const double _anchoColumna = 5.63;
const double _anchoColumnaMargen = 0.82;
final List<double> _anchosColumnas = [
  ...List.filled(17, _anchoColumna), // A-Q
  _anchoColumnaMargen, // R
];
const String _ultimaColumna = 'R';
const List<String> _columnasLogo = ['A', 'B', 'C'];
const List<String> _columnasTitulo = [
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
];
const List<String> _columnasEtiqueta = ['M', 'N'];
const List<String> _columnasValor = ['O', 'P', 'Q'];

const double _altoFilaEncabezadoPt = 14.25;
const double _altoFilaSeparador1Pt = 2;
const double _altoFilaSeparador2Pt = 8;
const int _filasEncabezado = 4;
const int _emuPorPixel = 9525;
const int _emuPorPunto = 12700;

int _anchoColumnaEmu(int index) {
  // `width` ya trae el relleno: px = width * 7 (ancho de dígito de Arial 10).
  // Verificado en Excel: width 5.63 -> 39 px -> 29.25 pt.
  final px = (_anchosColumnas[index] * 7).round();
  return px * _emuPorPixel;
}

int _altoFilaEncabezadoEmu() => (_altoFilaEncabezadoPt * _emuPorPunto).round();

// ─────────────────────────────────────────────────────────────────────────────
// Partes del paquete
// ─────────────────────────────────────────────────────────────────────────────

String _contentTypes(_ImagenInfo? logo) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    )
    ..write(
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    )
    ..write('<Default Extension="xml" ContentType="application/xml"/>');
  if (logo != null) {
    b.write(
      '<Default Extension="${logo.extension}" ContentType="${logo.mime}"/>',
    );
  }
  b
    ..write(
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
    )
    ..write(
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    )
    ..write(
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
  if (logo != null) {
    b.write(
      '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>',
    );
  }
  b.write('</Types>');
  return b.toString();
}

const String _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

const String _workbook =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="Formato" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>';

const String _workbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

const String _sheetRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>'
    '</Relationships>';

String _drawingRels(_ImagenInfo logo) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.${logo.extension}"/>'
    '</Relationships>';

/// Índices de `cellXfs` en `_styles`. El 0 (no se referencia: es el que
/// Excel aplica a toda celda que no exista en el XML) va DESBLOQUEADO, para
/// que el contenido sea libre sin tener que escribir cada celda.
class _Xf {
  static const logo = 1;
  static const titulo = 2;
  static const dependencia = 3;
  static const etiqueta = 4;
  static const valor = 5;
  static const separador = 6;
  static const hueco = 8;
  static const empresa = 7;
}

String _styles(GdPlantillaFormatoDatos datos) {
  final primario = _hex(datos.colorPrimario, kGdPlantillaColorPrimario);
  final secundario = _hex(datos.colorSecundario, kGdPlantillaColorSecundario);
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="6">'
      '<font><sz val="10"/><name val="Arial"/></font>' // 0 base
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>' // 1 título (blanco sobre primario)
      '<font><b/><sz val="11"/><color rgb="FF$primario"/><name val="Arial"/></font>' // 2 etiqueta / empresa
      '<font><sz val="11"/><name val="Arial"/></font>' // 3 valor
      '<font><sz val="11"/><color rgb="FF$primario"/><name val="Arial"/></font>' // 4 dependencia
      '<font><i/><sz val="11"/><color rgb="FF64748B"/><name val="Arial"/></font>' // 5 logo (texto de respaldo)
      '</fonts>'
      // Los dos primeros rellenos son obligatorios en el esquema.
      '<fills count="4">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF$primario"/><bgColor indexed="64"/></patternFill></fill>' // 2
      '<fill><patternFill patternType="solid"><fgColor rgb="FF$secundario"/><bgColor indexed="64"/></patternFill></fill>' // 3
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border>'
      '<left style="thin"><color rgb="FF$primario"/></left>'
      '<right style="thin"><color rgb="FF$primario"/></right>'
      '<top style="thin"><color rgb="FF$primario"/></top>'
      '<bottom style="thin"><color rgb="FF$primario"/></bottom>'
      '<diagonal/></border>'
      '</borders>'
      // El estilo "Normal" también sin candado: es lo que Excel aplica a
      // cualquier celda que no tenga estilo propio.
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" applyProtection="1"><protection locked="0"/></xf></cellStyleXfs>'
      '<cellXfs count="9">'
      // 0 libre: sin candado. Es el estilo de todo lo que no sea encabezado.
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyProtection="1"><protection locked="0"/></xf>'
      // 1 logo
      '<xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" wrapText="1"/><protection locked="1"/></xf>'
      // 2 título: blanco sobre primario
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" wrapText="1"/><protection locked="1"/></xf>'
      // 3 dependencia sobre secundario (una sola fila: se encoge la letra)
      '<xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" shrinkToFit="1"/><protection locked="1"/></xf>'
      // 4 etiqueta sobre secundario
      '<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="left" vertical="center"/><protection locked="1"/></xf>'
      // 5 valor (nombres largos en "Aprobado": se encoge la letra)
      '<xf numFmtId="0" fontId="3" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" shrinkToFit="1"/><protection locked="1"/></xf>'
      // 6 franja separadora (fila 6) en primario, con candado.
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="0" xfId="0" applyFill="1" applyProtection="1"><protection locked="1"/></xf>'
      // 7 empresa (D1:L1): negrilla primario sobre secundario, una sola fila.
      '<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" shrinkToFit="1"/><protection locked="1"/></xf>'
      // 8 hueco (fila 5): en blanco, con candado.
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyProtection="1"><protection locked="1"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}

String _sheet(GdPlantillaFormatoDatos datos, bool conLogo) {
  final fecha = _fecha(datos.fecha);
  // La celda "Aprobado" (O2:Q2) mide 87 pt: cabe el nombre, no el nombre
  // con fecha y hora. El modelo del jefe pone ahí solo "[usuario]"; la fecha
  // y hora exactas de validación quedan en el registro de la Biblioteca.
  final aprobado =
      datos.aprobadoPor == null || datos.aprobadoPor!.trim().isEmpty
      ? 'Pendiente'
      : datos.aprobadoPor!.trim();

  // Celdas del encabezado. Las combinadas solo llevan valor en la primera;
  // las demás se escriben vacías con el mismo estilo para que el borde y el
  // candado cubran todo el bloque.
  List<_Celda> bloque(List<String> columnas, int estilo, [String? texto]) => [
    for (var i = 0; i < columnas.length; i++)
      _Celda(columnas[i], estilo, i == 0 ? texto : null),
  ];
  List<_Celda> filaDato(List<_Celda> centro, String etiqueta, String valor) => [
    ...bloque(_columnasLogo, _Xf.logo),
    ...centro,
    ...bloque(_columnasEtiqueta, _Xf.etiqueta, etiqueta),
    ...bloque(_columnasValor, _Xf.valor, valor),
  ];
  final todas = [
    ..._columnasLogo,
    ..._columnasTitulo,
    ..._columnasEtiqueta,
    ..._columnasValor,
    _ultimaColumna,
  ];

  final filas = <int, List<_Celda>>{
    1: [
      ...bloque(_columnasLogo, _Xf.logo, conLogo ? '' : datos.empresaNombre),
      ...bloque(
        _columnasTitulo,
        _Xf.empresa,
        datos.empresaNombre.toUpperCase(),
      ),
      ...bloque(_columnasEtiqueta, _Xf.etiqueta, 'Versión'),
      ...bloque(_columnasValor, _Xf.valor, datos.version),
    ],
    2: filaDato(
      // Títulos siempre en mayúscula (regla del jefe, 14 sep 2026).
      bloque(_columnasTitulo, _Xf.titulo, datos.titulo.toUpperCase()),
      'Aprobado',
      aprobado,
    ),
    3: filaDato(bloque(_columnasTitulo, _Xf.titulo), 'Fecha', fecha),
    4: filaDato(
      bloque(_columnasTitulo, _Xf.dependencia, datos.area),
      'Código',
      datos.codigo,
    ),
    5: bloque(todas, _Xf.hueco),
    6: bloque(todas, _Xf.separador),
  };
  final altos = <int, double>{
    for (var f = 1; f <= _filasEncabezado; f++) f: _altoFilaEncabezadoPt,
    5: _altoFilaSeparador1Pt,
    6: _altoFilaSeparador2Pt,
  };

  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    )
    ..write('<dimension ref="A1:${_ultimaColumna}6"/>')
    ..write(
      '<sheetViews><sheetView workbookViewId="0" tabSelected="1">'
      '<pane ySplit="6" topLeftCell="A$kGdPlantillaPrimeraFilaLibre" activePane="bottomLeft" state="frozen"/>'
      '<selection pane="bottomLeft" activeCell="A$kGdPlantillaPrimeraFilaLibre" sqref="A$kGdPlantillaPrimeraFilaLibre"/>'
      '</sheetView></sheetViews>',
    )
    ..write('<sheetFormatPr defaultRowHeight="15"/>')
    ..write('<cols>');
  for (var i = 0; i < _anchosColumnas.length; i++) {
    b.write(
      '<col min="${i + 1}" max="${i + 1}" width="${_anchosColumnas[i]}" customWidth="1"/>',
    );
  }
  b
    ..write('</cols>')
    ..write('<sheetData>');
  filas.forEach((fila, celdas) {
    b.write('<row r="$fila" ht="${altos[fila]}" customHeight="1">');
    for (final c in celdas) {
      b.write(c.xml(fila));
    }
    b.write('</row>');
  });
  b
    ..write('</sheetData>')
    // Candado: encabezado intocable; contenido con formato, filas y
    // ordenamiento libres. `1` = prohibido, `0` = permitido.
    ..write(
      '<sheetProtection password="${gdHashClaveHoja(kGdPlantillaClaveHoja)}" '
      'sheet="1" objects="1" scenarios="1" '
      'formatCells="0" formatColumns="0" formatRows="0" '
      'insertRows="0" deleteRows="0" insertColumns="1" deleteColumns="1" '
      'insertHyperlinks="0" sort="0" autoFilter="0" pivotTables="1" '
      // Ni seleccionar el encabezado: así tampoco se pueden insertar filas
      // entre sus celdas.
      'selectLockedCells="1" selectUnlockedCells="0"/>',
    )
    ..write(
      '<mergeCells count="11">'
      '<mergeCell ref="A1:C4"/>'
      '<mergeCell ref="D1:L1"/>'
      '<mergeCell ref="D2:L3"/>'
      '<mergeCell ref="D4:L4"/>'
      '<mergeCell ref="M1:N1"/><mergeCell ref="O1:Q1"/>'
      '<mergeCell ref="M2:N2"/><mergeCell ref="O2:Q2"/>'
      '<mergeCell ref="M3:N3"/><mergeCell ref="O3:Q3"/>'
      '<mergeCell ref="M4:N4"/><mergeCell ref="O4:Q4"/>'
      '</mergeCells>',
    )
    ..write(
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>',
    )
    ..write(
      '<pageSetup orientation="portrait" fitToWidth="1" fitToHeight="0"/>',
    );
  if (conLogo) b.write('<drawing r:id="rId1"/>');
  b.write('</worksheet>');
  return b.toString();
}

class _Celda {
  final String columna;
  final int estilo;
  final String? texto;
  const _Celda(this.columna, this.estilo, [this.texto]);

  String xml(int fila) {
    final ref = '$columna$fila';
    if (texto == null || texto!.isEmpty) return '<c r="$ref" s="$estilo"/>';
    return '<c r="$ref" s="$estilo" t="inlineStr"><is><t xml:space="preserve">${_esc(texto!)}</t></is></c>';
  }
}

String _drawing(_ImagenInfo logo) {
  // Recuadro A1:C4 en EMU, con margen, y el logo centrado sin deformar.
  const margen = 40000;
  var anchoCaja = -2 * margen;
  for (var i = 0; i < _columnasLogo.length; i++) {
    anchoCaja += _anchoColumnaEmu(i);
  }
  final altoCaja = _altoFilaEncabezadoEmu() * _filasEncabezado - 2 * margen;
  final escala = _min(anchoCaja / logo.ancho, altoCaja / logo.alto);
  final cx = (logo.ancho * escala).round();
  final cy = (logo.alto * escala).round();
  final x = margen + ((anchoCaja - cx) / 2).round();
  final y = margen + ((altoCaja - cy) / 2).round();

  // Excel espera el offset dentro de la columna/fila de origen.
  var col = 0;
  var colOff = x;
  while (col < _columnasLogo.length - 1 && colOff >= _anchoColumnaEmu(col)) {
    colOff -= _anchoColumnaEmu(col);
    col++;
  }
  final altoFila = _altoFilaEncabezadoEmu();
  final row = y ~/ altoFila;
  final rowOff = y - row * altoFila;

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
      '<xdr:oneCellAnchor>'
      '<xdr:from><xdr:col>$col</xdr:col><xdr:colOff>$colOff</xdr:colOff>'
      '<xdr:row>$row</xdr:row><xdr:rowOff>$rowOff</xdr:rowOff></xdr:from>'
      '<xdr:ext cx="$cx" cy="$cy"/>'
      '<xdr:pic>'
      '<xdr:nvPicPr><xdr:cNvPr id="2" name="Logo empresa"/>'
      '<xdr:cNvPicPr><a:picLocks noChangeAspect="1" noMove="1" noResize="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
      '<xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId1"/>'
      '<a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
      '<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>'
      '</xdr:pic>'
      '<xdr:clientData/>'
      '</xdr:oneCellAnchor>'
      '</xdr:wsDr>';
}

// ─────────────────────────────────────────────────────────────────────────────
// Imagen: solo se necesita saber formato y tamaño, no decodificarla.
// ─────────────────────────────────────────────────────────────────────────────

class _ImagenInfo {
  final Uint8List bytes;
  final String extension;
  final String mime;
  final int ancho;
  final int alto;

  const _ImagenInfo(
    this.bytes,
    this.extension,
    this.mime,
    this.ancho,
    this.alto,
  );

  static _ImagenInfo? detectar(Uint8List? bytes) {
    if (bytes == null || bytes.length < 24) return null;
    // PNG: firma de 8 bytes y el IHDR trae ancho/alto en los bytes 16-23.
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final data = ByteData.sublistView(bytes);
      final ancho = data.getUint32(16);
      final alto = data.getUint32(20);
      if (ancho == 0 || alto == 0) return null;
      return _ImagenInfo(bytes, 'png', 'image/png', ancho, alto);
    }
    // JPEG: recorrer marcadores hasta un SOF (C0-C3, C5-C7, C9-CB, CD-CF).
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var i = 2;
      while (i + 9 < bytes.length) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = bytes[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        final esSof =
            marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC;
        final len = (bytes[i + 2] << 8) | bytes[i + 3];
        if (esSof) {
          final alto = (bytes[i + 5] << 8) | bytes[i + 6];
          final ancho = (bytes[i + 7] << 8) | bytes[i + 8];
          if (ancho == 0 || alto == 0) return null;
          return _ImagenInfo(bytes, 'jpeg', 'image/jpeg', ancho, alto);
        }
        i += 2 + len;
      }
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utilidades
// ─────────────────────────────────────────────────────────────────────────────

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _fecha(DateTime d) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year}';
}

/// Hex de 6 dígitos sin `#`; si el valor no sirve, vuelve al de defecto.
String _hex(String valor, String defecto) {
  final limpio = valor.trim().replaceAll('#', '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(limpio) ? limpio : defecto;
}

double _min(double a, double b) => a < b ? a : b;

// ─────────────────────────────────────────────────────────────────────────────
// Sello de validación sobre el archivo que subió el usuario
// ─────────────────────────────────────────────────────────────────────────────

/// Escribe quién validó en la celda *Aprobado* del archivo que el usuario
/// subió, sin re-serializar el libro: se abre el zip, se cambia esa única
/// celda en el XML de la hoja y se vuelve a cerrar. Todo lo demás (formato
/// del contenido, imágenes, fórmulas) queda byte a byte igual. La fecha y
/// hora ([aprobadoEn]) no caben en la celda del modelo: quedan en el
/// registro de la Biblioteca, no en el Excel.
///
/// La celda es [kGdPlantillaCeldaAprobado] (O2) en el encabezado actual, e
/// I2 en las plantillas descargadas antes del modelo del 14 sep 2026 (se
/// reconocen por la combinación C1:G3); esas siguen sellándose.
///
/// Devuelve los bytes nuevos, o `null` con el motivo cuando el archivo no es
/// un `.xlsx` que conserve el encabezado de la plantilla.
({Uint8List? bytes, String detalle}) gdSellarPlantillaValidada(
  Uint8List xlsx, {
  required String aprobadoPor,
  required DateTime aprobadoEn,
}) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(xlsx, verify: true);
  } catch (_) {
    return (bytes: null, detalle: 'El archivo no es un .xlsx legible.');
  }

  // La hoja de la plantilla: la que sigue protegida con nuestra clave o, si
  // la desprotegieron, la que conserva la combinación del título (D2:L3 hoy,
  // C1:G3 en el encabezado anterior).
  final hash = gdHashClaveHoja(kGdPlantillaClaveHoja);
  const mergeActual = '<mergeCell ref="D2:L3"/>';
  const mergeAnterior = '<mergeCell ref="C1:G3"/>';
  ArchiveFile? hoja;
  String? xml;
  for (final criterio in ['password="$hash"', mergeActual, mergeAnterior]) {
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('xl/worksheets/sheet')) continue;
      final texto = utf8.decode(f.content as List<int>, allowMalformed: true);
      if (texto.contains(criterio)) {
        hoja = f;
        xml = texto;
        break;
      }
    }
    if (hoja != null) break;
  }
  if (hoja == null || xml == null) {
    return (
      bytes: null,
      detalle: 'El archivo no conserva el encabezado de la plantilla.',
    );
  }

  // Encabezado anterior: la celda "Aprobado" era I2 y su etiqueta H2.
  final esAnterior = !xml.contains(mergeActual) && xml.contains(mergeAnterior);
  final celdaAprobado = esAnterior ? 'I2' : kGdPlantillaCeldaAprobado;
  final celdaEtiqueta = esAnterior ? 'H2' : 'M2';

  final texto = aprobadoPor.trim();
  String celda(String estilo) =>
      '<c r="$celdaAprobado"$estilo t="inlineStr"><is><t xml:space="preserve">${_esc(texto)}</t></is></c>';
  RegExp celdaRe(String ref) =>
      RegExp('<c r="$ref"(\\s[^>]*?)?(?:/>|>.*?</c>)', dotAll: true);

  // La celda puede venir como la escribimos (inlineStr) o como la deja Excel
  // al guardar (t="s" con índice a sharedStrings); se conserva su estilo.
  String nuevoXml;
  final m = celdaRe(celdaAprobado).firstMatch(xml);
  if (m != null) {
    final attrs = m.group(1) ?? '';
    final s = RegExp(r'\ss="\d+"').firstMatch(attrs)?.group(0) ?? '';
    nuevoXml = xml.replaceRange(m.start, m.end, celda(s));
  } else {
    // Sin la celda (raro: está bloqueada), se cuelga detrás de la etiqueta.
    final h2 = celdaRe(celdaEtiqueta).firstMatch(xml);
    if (h2 == null) {
      return (bytes: null, detalle: 'No se encontró la celda "Aprobado".');
    }
    final s =
        RegExp(r'\ss="\d+"').firstMatch(h2.group(1) ?? '')?.group(0) ?? '';
    nuevoXml = xml.replaceRange(h2.end, h2.end, celda(s));
  }

  final salida = Archive();
  for (final f in archive.files) {
    if (f.name == hoja.name) {
      final encoded = utf8.encode(nuevoXml);
      salida.addFile(ArchiveFile(f.name, encoded.length, encoded));
    } else {
      salida.addFile(f);
    }
  }
  final zipped = ZipEncoder().encode(salida);
  if (zipped == null) {
    return (bytes: null, detalle: 'No se pudo volver a empaquetar el archivo.');
  }
  return (
    bytes: Uint8List.fromList(zipped),
    detalle: 'Sello escrito en $celdaAprobado.',
  );
}

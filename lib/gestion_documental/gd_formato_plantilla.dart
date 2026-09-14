// Plantilla Excel de formato institucional generada por la app.
//
// Oscar (reunión 12 sep 2026) no quiere que cada quien arme su encabezado:
// "unos ponen un logo, otros otro, otros un código arriba, otros abajo".
// Por eso la plantilla no es un archivo suelto: se genera por registro con
// los datos que ya tiene la Biblioteca (código, nombre, dependencia, versión)
// y el logo de la empresa, y el encabezado queda BLOQUEADO con protección de
// hoja. De la fila 7 hacia abajo todas las celdas están desbloqueadas: ahí
// cada dependencia arma el contenido como necesite (bordes, combinaciones,
// filas nuevas...).
//
// Se escribe OOXML a mano en vez de usar el paquete `excel` porque ese
// paquete no sabe insertar imágenes ni proteger hojas, y post-procesar su
// salida sería más frágil que armar una estructura fija y pequeña.
//
// Sin dependencias de Flutter: se prueba en `flutter test` sin widgets.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Colores del encabezado. Provisionales hasta que Oscar entregue los
/// corporativos; `TBL_EMPRESAS.colorPrimario` / `colorSecundario` (hex sin
/// `#`) los reemplazan por empresa si existen.
const String kGdPlantillaColorPrimario = '1F3A5F';
const String kGdPlantillaColorSecundario = 'E8EEF5';

/// Clave de la protección de hoja. No es un secreto fuerte (Excel usa un
/// hash de 16 bits): es un candado para que nadie toque el encabezado por
/// accidente. Calidad la conoce por si hay que corregir algo a mano.
const String kGdPlantillaClaveHoja = 'CALIDAD-USPEC';

/// Primera fila editable. Las filas 1-5 son el encabezado y la 6 un
/// separador; todo lo demás queda desbloqueado.
const int kGdPlantillaPrimeraFilaLibre = 7;

class GdPlantillaFormatoDatos {
  final String empresaNombre;
  final String titulo;
  final String codigo;
  final String dependencia;
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
    required this.dependencia,
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
      ArchiveFile('xl/media/image1.${logo.extension}', logo.bytes.length,
          logo.bytes),
    );
  }
  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped ?? const []);
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometría del encabezado
// ─────────────────────────────────────────────────────────────────────────────

// Anchos de columna en "caracteres" de Excel. A-B: logo, C-G: título,
// H: etiquetas, I-J: valores.
const List<double> _anchosColumnas = [14, 14, 16, 16, 16, 16, 16, 12, 14, 14];
const double _altoFilaEncabezadoPt = 22;
const double _altoFilaSeparadorPt = 6;
const int _emuPorPixel = 9525;
const int _emuPorPunto = 12700;

int _anchoColumnaEmu(int index) {
  // Aproximación estándar de Excel: px = chars*7 + 5 (fuente de 10-11 pt).
  final px = _anchosColumnas[index] * 7 + 5;
  return (px * _emuPorPixel).round();
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
  static const empresa = 7;
}

String _styles(GdPlantillaFormatoDatos datos) {
  final primario = _hex(datos.colorPrimario, kGdPlantillaColorPrimario);
  final secundario = _hex(datos.colorSecundario, kGdPlantillaColorSecundario);
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="6">'
      '<font><sz val="10"/><name val="Arial"/></font>' // 0 base
      '<font><b/><sz val="14"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>' // 1 título
      '<font><b/><sz val="9"/><color rgb="FF$primario"/><name val="Arial"/></font>' // 2 etiqueta
      '<font><sz val="9"/><name val="Arial"/></font>' // 3 valor
      '<font><b/><sz val="11"/><color rgb="FF$primario"/><name val="Arial"/></font>' // 4 dependencia
      '<font><i/><sz val="8"/><color rgb="FF64748B"/><name val="Arial"/></font>' // 5 empresa
      '</fonts>'
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
      '<cellXfs count="8">'
      // 0 libre: sin candado. Es el estilo de todo lo que no sea encabezado.
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyProtection="1"><protection locked="0"/></xf>'
      // 1 logo
      '<xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" wrapText="1"/><protection locked="1"/></xf>'
      // 2 título
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" wrapText="1"/><protection locked="1"/></xf>'
      // 3 dependencia
      '<xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center" wrapText="1"/><protection locked="1"/></xf>'
      // 4 etiqueta
      '<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="left" vertical="center" indent="1"/><protection locked="1"/></xf>'
      // 5 valor
      '<xf numFmtId="0" fontId="3" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="left" vertical="center" indent="1" wrapText="1"/><protection locked="1"/></xf>'
      // 6 separador
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="0" xfId="0" applyFill="1" applyProtection="1"><protection locked="1"/></xf>'
      // 7 empresa (línea pequeña bajo la dependencia)
      '<xf numFmtId="0" fontId="5" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1">'
      '<alignment horizontal="center" vertical="center"/><protection locked="1"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}

String _sheet(GdPlantillaFormatoDatos datos, bool conLogo) {
  final fecha = _fecha(datos.fecha);
  final aprobado = datos.aprobadoPor == null || datos.aprobadoPor!.trim().isEmpty
      ? 'Pendiente de validación'
      : datos.aprobadoEn == null
      ? datos.aprobadoPor!.trim()
      : '${datos.aprobadoPor!.trim()} · ${_fecha(datos.aprobadoEn!)}';

  // Celdas del encabezado. Las combinadas solo llevan valor en la primera;
  // las demás se escriben vacías con el mismo estilo para que el borde y el
  // candado cubran todo el bloque.
  final filas = <int, List<_Celda>>{
    1: [
      _Celda('A', _Xf.logo, conLogo ? '' : datos.empresaNombre),
      _Celda('B', _Xf.logo),
      _Celda('C', _Xf.titulo, datos.titulo),
      for (final c in ['D', 'E', 'F', 'G']) _Celda(c, _Xf.titulo),
      _Celda('H', _Xf.etiqueta, 'Versión'),
      _Celda('I', _Xf.valor, datos.version),
      _Celda('J', _Xf.valor),
    ],
    2: [
      _Celda('A', _Xf.logo),
      _Celda('B', _Xf.logo),
      for (final c in ['C', 'D', 'E', 'F', 'G']) _Celda(c, _Xf.titulo),
      _Celda('H', _Xf.etiqueta, 'Aprobado'),
      _Celda('I', _Xf.valor, aprobado),
      _Celda('J', _Xf.valor),
    ],
    3: [
      _Celda('A', _Xf.logo),
      _Celda('B', _Xf.logo),
      for (final c in ['C', 'D', 'E', 'F', 'G']) _Celda(c, _Xf.titulo),
      _Celda('H', _Xf.etiqueta, 'Fecha'),
      _Celda('I', _Xf.valor, fecha),
      _Celda('J', _Xf.valor),
    ],
    4: [
      _Celda('A', _Xf.logo),
      _Celda('B', _Xf.logo),
      _Celda('C', _Xf.dependencia, datos.dependencia),
      for (final c in ['D', 'E', 'F', 'G']) _Celda(c, _Xf.dependencia),
      _Celda('H', _Xf.etiqueta, 'Código'),
      _Celda('I', _Xf.valor, datos.codigo),
      _Celda('J', _Xf.valor),
    ],
    5: [
      _Celda('A', _Xf.logo),
      _Celda('B', _Xf.logo),
      _Celda('C', _Xf.empresa, datos.empresaNombre),
      for (final c in ['D', 'E', 'F', 'G']) _Celda(c, _Xf.empresa),
      _Celda('H', _Xf.etiqueta, 'Empresa'),
      _Celda('I', _Xf.valor, datos.empresaNombre),
      _Celda('J', _Xf.valor),
    ],
    6: [for (final c in 'ABCDEFGHIJ'.split('')) _Celda(c, _Xf.separador)],
  };

  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    )
    ..write('<dimension ref="A1:J6"/>')
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
    final alto = fila == 6 ? _altoFilaSeparadorPt : _altoFilaEncabezadoPt;
    b.write('<row r="$fila" ht="$alto" customHeight="1">');
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
      '<mergeCells count="4">'
      '<mergeCell ref="A1:B5"/>'
      '<mergeCell ref="C1:G3"/>'
      '<mergeCell ref="C4:G4"/>'
      '<mergeCell ref="C5:G5"/>'
      '</mergeCells>',
    )
    ..write(
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>',
    )
    ..write('<pageSetup orientation="portrait" fitToWidth="1" fitToHeight="0"/>');
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
  // Recuadro A1:B5 en EMU, con margen, y el logo centrado sin deformar.
  const margen = 60000;
  final anchoCaja = _anchoColumnaEmu(0) + _anchoColumnaEmu(1) - 2 * margen;
  final altoCaja = _altoFilaEncabezadoEmu() * 5 - 2 * margen;
  final escala = _min(anchoCaja / logo.ancho, altoCaja / logo.alto);
  final cx = (logo.ancho * escala).round();
  final cy = (logo.alto * escala).round();
  final x = margen + ((anchoCaja - cx) / 2).round();
  final y = margen + ((altoCaja - cy) / 2).round();

  // Excel espera el offset dentro de la columna/fila de origen.
  final anchoA = _anchoColumnaEmu(0);
  final col = x >= anchoA ? 1 : 0;
  final colOff = x >= anchoA ? x - anchoA : x;
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

  const _ImagenInfo(this.bytes, this.extension, this.mime, this.ancho, this.alto);

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
        final esSof = marker >= 0xC0 &&
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

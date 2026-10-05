// Plantilla Word de formato institucional generada por la app (5 oct 2026).
//
// Pedido del usuario: "así como me permite generar el Excel cuando quiero
// cargar un formato, así mismo me permita un Word, con las mismas
// especificaciones, el mismo encabezado y un pie de página bonito".
//
// Es la misma plantilla de `gd_formato_plantilla.dart`, con los mismos datos
// (`GdPlantillaFormatoDatos`) y la misma geometría del modelo del jefe:
// logo a la izquierda en las cuatro filas, TIPO arriba, título en mayúscula
// en dos filas, área abajo, y a la derecha Versión, Aprobado, Fecha y Código
// con la etiqueta sobre el color secundario. En Word el encabezado va en el
// ENCABEZADO de página (se repite en cada hoja) y el pie lleva empresa,
// código, versión y "Página X de Y".
//
// "Aprobado" es un control de contenido bloqueado con la etiqueta
// [kGdPlantillaWordEtiquetaAprobado]: Calidad lo sella al validar
// ([gdSellarPlantillaWordValidada]) aunque Word haya reescrito el resto del
// archivo al guardarlo.
//
// Se escribe OOXML a mano, igual que el Excel: sin dependencias de Flutter,
// se prueba en `flutter test`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'gd_formato_plantilla.dart';

/// Etiqueta (`w:tag`) del control de contenido donde va quién validó.
const String kGdPlantillaWordEtiquetaAprobado = 'gdAprobado';

/// Nombre de archivo sugerido: `LOG-001_Acta_de_baja_v1.docx`.
String gdNombreArchivoPlantillaWord(GdPlantillaFormatoDatos datos) =>
    gdNombreArchivoPlantilla(datos).replaceAll(RegExp(r'\.xlsx$'), '.docx');

/// Genera el .docx completo.
Uint8List gdGenerarPlantillaFormatoWord(GdPlantillaFormatoDatos datos) {
  final logo = _Imagen.detectar(datos.logo);
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes(logo));
  add('_rels/.rels', _rootRels);
  add('docProps/core.xml', _core(datos));
  add('docProps/app.xml', _app);
  add('word/document.xml', _document(datos));
  add('word/_rels/document.xml.rels', _documentRels);
  add('word/styles.xml', _styles(datos));
  add('word/settings.xml', _settings);
  add('word/header1.xml', _header(datos, logo));
  add('word/footer1.xml', _footer(datos));
  if (logo != null) {
    add('word/_rels/header1.xml.rels', _headerRels(logo));
    archive.addFile(
      ArchiveFile(
        'word/media/logo.${logo.extension}',
        logo.bytes.length,
        logo.bytes,
      ),
    );
  }
  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped ?? const []);
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometría (twips: 1 pt = 20; 1 cm ≈ 567)
// ─────────────────────────────────────────────────────────────────────────────

// Carta vertical con márgenes laterales de 2 cm: 9972 twips útiles. Las
// columnas guardan la proporción del Excel (logo 3, centro 9, etiqueta 2,
// valor 3 de 17 columnas), con la etiqueta algo más ancha para "Aprobado".
const int _anchoPagina = 12240;
const int _altoPagina = 15840;
const int _margenLateral = 1134;
const int _anchoUtil = _anchoPagina - 2 * _margenLateral; // 9972
const int _colLogo = 1760;
const int _colEtiqueta = 1300;
const int _colValor = 1812;
const int _colCentro = _anchoUtil - _colLogo - _colEtiqueta - _colValor;
const int _altoFila = 320;
const int _emuPorTwip = 635;

// ─────────────────────────────────────────────────────────────────────────────
// Partes del paquete
// ─────────────────────────────────────────────────────────────────────────────

const String _w =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

String _contentTypes(_Imagen? logo) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '${logo == null ? '' : '<Default Extension="${logo.extension}" ContentType="${logo.mime}"/>'}'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
    '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
    '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    '</Types>';

const String _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
    '</Relationships>';

const String _documentRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>'
    '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
    '</Relationships>';

String _headerRels(_Imagen logo) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdLogo" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/logo.${logo.extension}"/>'
    '</Relationships>';

String _core(GdPlantillaFormatoDatos d) {
  final ahora = DateTime.now().toUtc().toIso8601String().split('.').first;
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc('${d.codigo.trim()} ${d.titulo.trim()}'.trim())}</dc:title>'
      '<dc:subject>${_esc(d.area.trim())}</dc:subject>'
      '<dc:creator>${_esc(d.empresaNombre.trim())}</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${ahora}Z</dcterms:created>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">${ahora}Z</dcterms:modified>'
      '</cp:coreProperties>';
}

const String _app =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>Gestión documental</Application>'
    '</Properties>';

const String _settings =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:defaultTabStop w:val="708"/>'
    '<w:characterSpacingControl w:val="doNotCompress"/>'
    '<w:compat><w:compatSetting w:name="compatibilityMode" '
    'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>'
    '</w:settings>';

/// Estilos: Arial como el Excel, títulos 1 y 2 en el color primario y una
/// "Tabla con cuadrícula" con bordes finos del mismo color, que es la que
/// Word usa al insertar una tabla.
String _styles(GdPlantillaFormatoDatos d) {
  final primario = _hex(d.colorPrimario, kGdPlantillaColorPrimario);
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles $_w>'
      '<w:docDefaults>'
      '<w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" w:cs="Arial"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="es-CO"/>'
      '</w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
      '</w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/><w:qFormat/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading1">'
      '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
      '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr>'
      '<w:rPr><w:b/><w:bCs/><w:color w:val="$primario"/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr>'
      '</w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2">'
      '<w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
      '<w:pPr><w:keepNext/><w:spacing w:before="200" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr>'
      '<w:rPr><w:b/><w:bCs/><w:color w:val="$primario"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>'
      '</w:style>'
      '<w:style w:type="paragraph" w:styleId="Header">'
      '<w:name w:val="header"/><w:basedOn w:val="Normal"/>'
      '<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Footer">'
      '<w:name w:val="footer"/><w:basedOn w:val="Normal"/>'
      '<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:style>'
      '<w:style w:type="table" w:default="1" w:styleId="TableNormal">'
      '<w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/>'
      '<w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar>'
      '<w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>'
      '<w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/>'
      '</w:tblCellMar></w:tblPr></w:style>'
      '<w:style w:type="table" w:styleId="TableGrid">'
      '<w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:uiPriority w:val="39"/>'
      '<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
      '<w:tblPr><w:tblBorders>${_bordes(primario)}</w:tblBorders></w:tblPr>'
      '</w:style>'
      '</w:styles>';
}

String _bordes(String color) =>
    '<w:top w:val="single" w:sz="4" w:space="0" w:color="$color"/>'
    '<w:left w:val="single" w:sz="4" w:space="0" w:color="$color"/>'
    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="$color"/>'
    '<w:right w:val="single" w:sz="4" w:space="0" w:color="$color"/>'
    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="$color"/>'
    '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="$color"/>';

/// Cuerpo: un párrafo vacío donde se empieza a escribir el formato, y la
/// sección con carta vertical, encabezado y pie.
String _document(GdPlantillaFormatoDatos d) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_w><w:body>'
    '<w:p><w:pPr><w:pStyle w:val="Normal"/></w:pPr></w:p>'
    '<w:sectPr>'
    '<w:headerReference w:type="default" r:id="rId3"/>'
    '<w:footerReference w:type="default" r:id="rId4"/>'
    '<w:pgSz w:w="$_anchoPagina" w:h="$_altoPagina"/>'
    '<w:pgMar w:top="2268" w:right="$_margenLateral" w:bottom="1418" '
    'w:left="$_margenLateral" w:header="567" w:footer="567" w:gutter="0"/>'
    '<w:cols w:space="708"/>'
    '</w:sectPr>'
    '</w:body></w:document>';

// ─────────────────────────────────────────────────────────────────────────────
// Encabezado
// ─────────────────────────────────────────────────────────────────────────────

String _header(GdPlantillaFormatoDatos d, _Imagen? logo) {
  final primario = _hex(d.colorPrimario, kGdPlantillaColorPrimario);
  final secundario = _hex(d.colorSecundario, kGdPlantillaColorSecundario);
  final aprobado = d.aprobadoPor == null || d.aprobadoPor!.trim().isEmpty
      ? 'Pendiente'
      : d.aprobadoPor!.trim();
  // Fila 1: el tipo (FORMATO, PROCEDIMIENTO...); si no viene, la empresa.
  final tipo = (d.tipo.trim().isEmpty ? d.empresaNombre : d.tipo)
      .trim()
      .toUpperCase();

  String run(
    String texto, {
    bool negrita = false,
    int medioPuntos = 18,
    String? color,
    bool cursiva = false,
  }) =>
      '<w:r><w:rPr>${negrita ? '<w:b/><w:bCs/>' : ''}'
      '${cursiva ? '<w:i/><w:iCs/>' : ''}'
      '${color == null ? '' : '<w:color w:val="$color"/>'}'
      '<w:sz w:val="$medioPuntos"/><w:szCs w:val="$medioPuntos"/></w:rPr>'
      '<w:t xml:space="preserve">${_esc(texto)}</w:t></w:r>';

  String parrafo(String contenido, {String alineacion = 'center'}) =>
      '<w:p><w:pPr><w:pStyle w:val="Header"/><w:jc w:val="$alineacion"/></w:pPr>'
      '$contenido</w:p>';

  String celda(
    int ancho,
    String contenido, {
    String? relleno,
    String? vMerge,
  }) =>
      '<w:tc><w:tcPr><w:tcW w:w="$ancho" w:type="dxa"/>'
      '${vMerge == null ? '' : '<w:vMerge w:val="$vMerge"/>'}'
      '${relleno == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$relleno"/>'}'
      '<w:vAlign w:val="center"/></w:tcPr>$contenido</w:tc>';

  // Celdas que continúan una combinación vertical: vacías, sin texto.
  String continua(int ancho) => celda(ancho, parrafo(''), vMerge: 'continue');

  String etiqueta(String texto) => celda(
    _colEtiqueta,
    parrafo(run(texto, negrita: true, color: primario), alineacion: 'left'),
    relleno: secundario,
  );
  String valor(String contenido) => celda(_colValor, parrafo(contenido));

  final aprobadoSdt =
      '<w:sdt><w:sdtPr><w:alias w:val="Aprobado"/>'
      '<w:tag w:val="$kGdPlantillaWordEtiquetaAprobado"/>'
      '<w:lock w:val="sdtContentLocked"/><w:text/></w:sdtPr>'
      '<w:sdtContent>${run(aprobado)}</w:sdtContent></w:sdt>';

  final contenidoLogo = logo == null
      ? parrafo(run(d.empresaNombre.trim(), cursiva: true, color: '64748B'))
      : parrafo(_dibujoLogo(logo));

  String fila(String celdas) =>
      '<w:tr><w:trPr><w:trHeight w:val="$_altoFila" w:hRule="atLeast"/>'
      '<w:cantSplit/></w:trPr>$celdas</w:tr>';

  final tabla = StringBuffer()
    ..write('<w:tbl><w:tblPr>')
    ..write('<w:tblW w:w="$_anchoUtil" w:type="dxa"/>')
    ..write('<w:jc w:val="center"/>')
    ..write('<w:tblBorders>${_bordes(primario)}</w:tblBorders>')
    ..write('<w:tblLayout w:type="fixed"/>')
    ..write(
      '<w:tblCellMar><w:top w:w="30" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>'
      '<w:bottom w:w="30" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>',
    )
    ..write('<w:tblLook w:val="0000" w:firstRow="0" w:lastRow="0" ')
    ..write('w:firstColumn="0" w:lastColumn="0" w:noHBand="1" w:noVBand="1"/>')
    ..write('</w:tblPr>')
    ..write('<w:tblGrid>')
    ..write('<w:gridCol w:w="$_colLogo"/><w:gridCol w:w="$_colCentro"/>')
    ..write('<w:gridCol w:w="$_colEtiqueta"/><w:gridCol w:w="$_colValor"/>')
    ..write('</w:tblGrid>')
    ..write(
      fila(
        celda(_colLogo, contenidoLogo, vMerge: 'restart') +
            celda(
              _colCentro,
              parrafo(
                run(tipo, negrita: true, medioPuntos: 20, color: primario),
              ),
            ) +
            etiqueta('Versión') +
            valor(run(d.version.trim())),
      ),
    )
    ..write(
      fila(
        continua(_colLogo) +
            // Títulos siempre en mayúscula (regla del jefe, 14 sep 2026).
            celda(
              _colCentro,
              parrafo(
                run(
                  d.titulo.trim().toUpperCase(),
                  negrita: true,
                  medioPuntos: 22,
                  color: primario,
                ),
              ),
              vMerge: 'restart',
            ) +
            etiqueta('Aprobado') +
            valor(aprobadoSdt),
      ),
    )
    ..write(
      fila(
        continua(_colLogo) +
            continua(_colCentro) +
            etiqueta('Fecha') +
            valor(run(_fecha(d.fecha))),
      ),
    )
    ..write(
      fila(
        continua(_colLogo) +
            celda(_colCentro, parrafo(run(d.area.trim(), color: primario))) +
            etiqueta('Código') +
            valor(run(d.codigo.trim())),
      ),
    )
    ..write('</w:tbl>');

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:hdr $_w $_dibujoNs>'
      '$tabla'
      // Word exige un párrafo después de la tabla; deja aire con el cuerpo.
      '<w:p><w:pPr><w:pStyle w:val="Header"/><w:spacing w:after="0"/>'
      '<w:rPr><w:sz w:val="8"/></w:rPr></w:pPr></w:p>'
      '</w:hdr>';
}

const String _dibujoNs =
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

/// Logo centrado en su recuadro (las cuatro filas), sin deformar.
String _dibujoLogo(_Imagen logo) {
  final anchoCaja = (_colLogo - 2 * 80 - 40) * _emuPorTwip;
  final altoCaja = (4 * _altoFila - 2 * 30) * _emuPorTwip;
  final escala = _min(anchoCaja / logo.ancho, altoCaja / logo.alto);
  final cx = (logo.ancho * escala).round();
  final cy = (logo.alto * escala).round();
  return '<w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="1" name="Logo empresa"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="logo.${logo.extension}"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="rIdLogo"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic>'
      '</wp:inline></w:drawing></w:r>';
}

// ─────────────────────────────────────────────────────────────────────────────
// Pie de página
// ─────────────────────────────────────────────────────────────────────────────

/// Línea fina del color primario; a la izquierda la empresa y el código con
/// su versión, a la derecha "Página X de Y".
String _footer(GdPlantillaFormatoDatos d) {
  final primario = _hex(d.colorPrimario, kGdPlantillaColorPrimario);
  String run(String texto, {bool negrita = false, String color = '64748B'}) =>
      '<w:r><w:rPr>${negrita ? '<w:b/><w:bCs/>' : ''}<w:color w:val="$color"/>'
      '<w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>'
      '<w:t xml:space="preserve">${_esc(texto)}</w:t></w:r>';
  String campo(String instruccion) =>
      '<w:r><w:rPr><w:b/><w:color w:val="$primario"/><w:sz w:val="16"/></w:rPr>'
      '<w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:rPr><w:b/><w:color w:val="$primario"/><w:sz w:val="16"/></w:rPr>'
      '<w:instrText xml:space="preserve"> $instruccion </w:instrText></w:r>'
      '<w:r><w:rPr><w:b/><w:color w:val="$primario"/><w:sz w:val="16"/></w:rPr>'
      '<w:fldChar w:fldCharType="separate"/></w:r>'
      '<w:r><w:rPr><w:b/><w:color w:val="$primario"/><w:sz w:val="16"/></w:rPr>'
      '<w:t>1</w:t></w:r>'
      '<w:r><w:rPr><w:b/><w:color w:val="$primario"/><w:sz w:val="16"/></w:rPr>'
      '<w:fldChar w:fldCharType="end"/></w:r>';

  final referencia = [
    d.codigo.trim(),
    if (d.version.trim().isNotEmpty) 'Versión ${d.version.trim()}',
  ].where((s) => s.isNotEmpty).join(' · ');
  final empresa = d.empresaNombre.trim();

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:ftr $_w>'
      '<w:p><w:pPr><w:pStyle w:val="Footer"/>'
      '<w:pBdr><w:top w:val="single" w:sz="6" w:space="6" w:color="$primario"/></w:pBdr>'
      '<w:tabs><w:tab w:val="right" w:pos="$_anchoUtil"/></w:tabs></w:pPr>'
      '${empresa.isEmpty ? '' : run(empresa.toUpperCase(), negrita: true, color: primario)}'
      '${empresa.isNotEmpty && referencia.isNotEmpty ? run('  ·  ') : ''}'
      '${referencia.isEmpty ? '' : run(referencia)}'
      '<w:r><w:tab/></w:r>'
      '${run('Página ')}${campo('PAGE')}${run(' de ')}${campo('NUMPAGES')}'
      '</w:p>'
      '</w:ftr>';
}

// ─────────────────────────────────────────────────────────────────────────────
// Sello de validación sobre el Word que subió el usuario
// ─────────────────────────────────────────────────────────────────────────────

/// Escribe quién validó en el control "Aprobado" del encabezado del Word que
/// subió el usuario, sin tocar nada más del archivo: se abre el zip, se
/// cambia el contenido de ese control y se vuelve a cerrar. La fecha y hora
/// de validación quedan en el registro de la Biblioteca, como en el Excel.
///
/// Devuelve los bytes nuevos, o `null` con el motivo cuando el archivo no es
/// un `.docx` que conserve el encabezado de la plantilla.
({Uint8List? bytes, String detalle}) gdSellarPlantillaWordValidada(
  Uint8List docx, {
  required String aprobadoPor,
  required DateTime aprobadoEn,
}) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(docx, verify: true);
  } catch (_) {
    return (bytes: null, detalle: 'El archivo no es un .docx legible.');
  }
  // Word (o LibreOffice) puede repetir el encabezado al guardar (primera
  // página, pares e impares): se sella en todas las partes y en cada copia.
  final sellados = <String, String>{};
  for (final f in archive.files) {
    if (!f.isFile || !f.name.startsWith('word/') || !f.name.endsWith('.xml')) {
      continue;
    }
    final texto = utf8.decode(f.content as List<int>, allowMalformed: true);
    final nuevo = _sellarXml(texto, aprobadoPor.trim());
    if (nuevo != null) sellados[f.name] = nuevo;
  }
  if (sellados.isEmpty) {
    return (
      bytes: null,
      detalle: 'El archivo no conserva el encabezado de la plantilla.',
    );
  }

  final salida = Archive();
  for (final f in archive.files) {
    final nuevoXml = sellados[f.name];
    if (nuevoXml != null) {
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
    detalle: 'Sello escrito en el encabezado del Word.',
  );
}

/// El XML con cada control "Aprobado" lleno con [nombre], o null si la
/// parte no tiene ninguno. Se conserva el formato del texto que había.
String? _sellarXml(String xml, String nombre) {
  final marca = 'w:val="$kGdPlantillaWordEtiquetaAprobado"';
  if (!xml.contains(marca)) return null;
  final b = StringBuffer();
  var desde = 0;
  var sellos = 0;
  while (true) {
    final iMarca = xml.indexOf(marca, desde);
    if (iMarca < 0) break;
    final iInicio = xml.indexOf('<w:sdtContent>', iMarca);
    final iFin = iInicio < 0 ? -1 : xml.indexOf('</w:sdtContent>', iInicio);
    if (iInicio < 0 || iFin < 0) break;
    final contenido = iInicio + '<w:sdtContent>'.length;
    final actual = xml.substring(contenido, iFin);
    final rPr =
        RegExp(
          r'<w:rPr>.*?</w:rPr>',
          dotAll: true,
        ).firstMatch(actual)?.group(0) ??
        '';
    b
      ..write(xml.substring(desde, contenido))
      ..write('<w:r>$rPr<w:t xml:space="preserve">${_esc(nombre)}</w:t></w:r>');
    desde = iFin;
    sellos++;
  }
  if (sellos == 0) return null;
  b.write(xml.substring(desde));
  return b.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Utilidades
// ─────────────────────────────────────────────────────────────────────────────

/// Formato y tamaño del logo, sin decodificarlo (PNG o JPEG).
class _Imagen {
  final Uint8List bytes;
  final String extension;
  final String mime;
  final int ancho;
  final int alto;
  const _Imagen(this.bytes, this.extension, this.mime, this.ancho, this.alto);

  static _Imagen? detectar(Uint8List? bytes) {
    if (bytes == null || bytes.length < 24) return null;
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final data = ByteData.sublistView(bytes);
      final ancho = data.getUint32(16);
      final alto = data.getUint32(20);
      if (ancho == 0 || alto == 0) return null;
      return _Imagen(bytes, 'png', 'image/png', ancho, alto);
    }
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
          return _Imagen(bytes, 'jpeg', 'image/jpeg', ancho, alto);
        }
        i += 2 + len;
      }
    }
    return null;
  }
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _fecha(DateTime d) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year}';
}

String _hex(String valor, String defecto) {
  final limpio = valor.trim().replaceAll('#', '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(limpio) ? limpio : defecto;
}

double _min(double a, double b) => a < b ? a : b;

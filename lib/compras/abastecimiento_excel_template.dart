import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;

import 'abastecimiento_models.dart';

/// Valores guardados de la empresa activa que el modelo ofrece como listas
/// desplegables. Se leen al descargarlo, así el archivo trae lo vigente.
class AbastecimientoPlantillaCatalogo {
  final List<String> proveedores;
  final List<String> categorias;
  final List<String> productos;
  final List<String> grupos;
  final List<String> destinos;
  final List<String> unidades;

  const AbastecimientoPlantillaCatalogo({
    this.proveedores = const [],
    this.categorias = const [],
    this.productos = const [],
    this.grupos = const [],
    this.destinos = const [],
    this.unidades = const [],
  });
}

/// Hoja oculta con los valores de los desplegables. Su encabezado no se
/// confunde con el de la carga, así el importador la ignora.
const String kHojaListasAbastecimiento = 'Listas';

/// Filas del modelo que llevan desplegables (de la 6 a la 1005).
const int _primeraFilaDatos = 6;
const int _ultimaFilaDatos = 1005;

/// Construye el modelo oficial para cargar Compras - Abastecimiento.
///
/// El periodo de consumo no vive en una columna: se selecciona de forma
/// explícita en la aplicación al cargar el archivo y se aplica a toda la carga.
/// Proveedor, categoría, grupo y estado se eligen de listas con lo guardado
/// en la empresa; producto, destino y unidad sugieren lo guardado y admiten
/// escribir otro valor, porque son informativos.
Uint8List construirPlantillaAbastecimiento({
  AbastecimientoPlantillaCatalogo catalogo =
      const AbastecimientoPlantillaCatalogo(),
}) {
  final excel = xl.Excel.createExcel();
  excel.rename('Sheet1', 'Abastecimiento');
  final sheet = excel['Abastecimiento'];

  const headers = <String>[
    'PROVEEDOR',
    'CATEGORIA',
    'PRODUCTO',
    'GRUPO',
    'CIUDAD ENTREGA',
    'CONDICION',
    'CANTIDAD',
    'UM',
    'PRECIO',
    'FECHA ENTREGA',
    'FECHA SEGUNDA ENTREGA',
    'OC',
    'ESTADO',
    'FECHA RECIBIDO',
    'NUMERO ENTRADA',
    'OBSERVACIONES',
  ];

  final lastColumn = xl.CellIndex.indexByColumnRow(
    columnIndex: headers.length - 1,
    rowIndex: 0,
  );
  sheet.merge(xl.CellIndex.indexByString('A1'), lastColumn);
  final title = sheet.cell(xl.CellIndex.indexByString('A1'));
  title.value = xl.TextCellValue('MODELO DE CARGA COMPRAS - ABASTECIMIENTO');
  title.cellStyle = xl.CellStyle(
    bold: true,
    fontSize: 15,
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#0F4C81'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
  );
  sheet.setRowHeight(0, 30);

  sheet.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
    xl.CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 1),
  );
  final note = sheet.cell(xl.CellIndex.indexByString('A2'));
  note.value = xl.TextCellValue(
    'Diligencie una fila por producto. El periodo de consumo se selecciona en la aplicación al cargar este archivo.',
  );
  note.cellStyle = xl.CellStyle(
    italic: true,
    fontColorHex: xl.ExcelColor.fromHexString('#334155'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#EAF1F8'),
    textWrapping: xl.TextWrapping.WrapText,
  );
  sheet.setRowHeight(1, 28);

  sheet.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
    xl.CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 2),
  );
  final required = sheet.cell(xl.CellIndex.indexByString('A3'));
  required.value = xl.TextCellValue(
    'Obligatorios: PROVEEDOR, CATEGORIA, PRODUCTO, GRUPO, FECHA ENTREGA y OC. Elija los valores de las listas desplegables; la OC identifica la entrega.',
  );
  required.cellStyle = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.fromHexString('#9A3412'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#FFF7ED'),
    textWrapping: xl.TextWrapping.WrapText,
  );
  sheet.setRowHeight(2, 28);

  final headerStyle = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#16845B'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
    textWrapping: xl.TextWrapping.WrapText,
  );
  for (var column = 0; column < headers.length; column++) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 4),
    );
    cell.value = xl.TextCellValue(headers[column]);
    cell.cellStyle = headerStyle;
  }
  sheet.setRowHeight(4, 34);

  final bodyStyle = xl.CellStyle(
    verticalAlign: xl.VerticalAlign.Center,
    textWrapping: xl.TextWrapping.WrapText,
    backgroundColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
  );
  for (var row = 5; row < 25; row++) {
    for (var column = 0; column < headers.length; column++) {
      sheet
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: row,
                ),
              )
              .cellStyle =
          bodyStyle;
    }
  }

  const widths = <double>[
    30,
    22,
    30,
    16,
    24,
    19,
    14,
    11,
    14,
    18,
    21,
    17,
    16,
    18,
    19,
    36,
  ];
  for (var column = 0; column < widths.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
  }

  final instructions = excel['Instrucciones'];
  instructions.appendRow([
    xl.TextCellValue('CAMPO'),
    xl.TextCellValue('OBLIGATORIO'),
    xl.TextCellValue('INDICACIÓN'),
  ]);
  const instructionRows = <List<String>>[
    [
      'PROVEEDOR',
      'Sí',
      'Elija de la lista: proveedores activos de la empresa.',
    ],
    [
      'CATEGORIA',
      'Sí',
      'Elija de la lista; debe ser una categoría asociada al proveedor.',
    ],
    [
      'PRODUCTO',
      'Sí',
      'Sugiere los productos guardados; puede escribir otro (es informativo).',
    ],
    ['GRUPO', 'Sí', 'Elija de la lista: grupos activos de Compras.'],
    [
      'CIUDAD ENTREGA',
      'No',
      'Sugiere las bodegas de la empresa; puede escribir otro destino.',
    ],
    ['CANTIDAD', 'No', 'Valor numérico mayor o igual a cero.'],
    ['UM', 'No', 'Sugiere unidades como KG o UND; puede escribir otra.'],
    ['FECHA ENTREGA', 'Sí', 'Fecha válida de Excel en formato día/mes/año.'],
    [
      'OC',
      'Sí',
      'Número de orden de compra o servicio. Con el mismo producto actualiza '
          'la entrega existente solo si sigue Programada. Una OC pertenece a '
          'un solo proveedor.',
    ],
    ['ESTADO', 'No', 'Elija: Programado, Entregado, Reprogramado o Cancelado.'],
    [
      'PERIODO DE CONSUMO',
      'En la aplicación',
      'Se elige al cargar el Excel según la configuración de Compras de la '
          'empresa.',
    ],
  ];
  for (final row in instructionRows) {
    instructions.appendRow(row.map(xl.TextCellValue.new).toList());
  }
  final instructionsHeader = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#0F4C81'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
  );
  for (var column = 0; column < 3; column++) {
    instructions
            .cell(
              xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
            )
            .cellStyle =
        instructionsHeader;
  }
  instructions.setColumnWidth(0, 27);
  instructions.setColumnWidth(1, 17);
  instructions.setColumnWidth(2, 65);
  for (var row = 1; row <= instructionRows.length; row++) {
    for (var column = 0; column < 3; column++) {
      instructions
          .cell(
            xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
          )
          .cellStyle = xl.CellStyle(
        verticalAlign: xl.VerticalAlign.Center,
        textWrapping: xl.TextWrapping.WrapText,
        backgroundColorHex: row.isEven
            ? xl.ExcelColor.fromHexString('#F1F5F9')
            : xl.ExcelColor.fromHexString('#FFFFFF'),
      );
    }
  }

  final estados = AbastecimientoEstado.values.map((item) => item.label);
  final listas = <_ListaDesplegable>[
    _ListaDesplegable(
      encabezado: 'PROVEEDORES',
      columnaModelo: 'A',
      valores: catalogo.proveedores,
      titulo: 'Proveedor',
      ayuda: 'Proveedores activos de la empresa.',
      estricta: true,
    ),
    _ListaDesplegable(
      encabezado: 'CATEGORIAS',
      columnaModelo: 'B',
      valores: catalogo.categorias,
      titulo: 'Categoría',
      ayuda: 'Debe estar asociada al proveedor elegido.',
      estricta: true,
    ),
    _ListaDesplegable(
      encabezado: 'PRODUCTOS',
      columnaModelo: 'C',
      valores: catalogo.productos,
      titulo: 'Producto',
      ayuda: 'Productos guardados; puede escribir otro.',
      estricta: false,
    ),
    _ListaDesplegable(
      encabezado: 'GRUPOS',
      columnaModelo: 'D',
      valores: catalogo.grupos,
      titulo: 'Grupo',
      ayuda: 'Grupos activos de Compras.',
      estricta: true,
    ),
    _ListaDesplegable(
      encabezado: 'DESTINOS',
      columnaModelo: 'E',
      valores: catalogo.destinos,
      titulo: 'Ciudad de entrega',
      ayuda: 'Bodegas de la empresa; puede escribir otro destino.',
      estricta: false,
    ),
    _ListaDesplegable(
      encabezado: 'UNIDADES',
      columnaModelo: 'H',
      valores: catalogo.unidades.isEmpty
          ? kUnidadesAbastecimientoBase
          : catalogo.unidades,
      titulo: 'Unidad de medida',
      ayuda: 'Unidades frecuentes; puede escribir otra.',
      estricta: false,
    ),
    _ListaDesplegable(
      encabezado: 'ESTADOS',
      columnaModelo: 'M',
      valores: estados.toList(),
      titulo: 'Estado',
      ayuda: 'Programado, Entregado, Reprogramado o Cancelado.',
      estricta: true,
    ),
  ];

  final listSheet = excel[kHojaListasAbastecimiento];
  for (var column = 0; column < listas.length; column++) {
    final lista = listas[column];
    listSheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .value = xl.TextCellValue(
      lista.encabezado,
    );
    for (var row = 0; row < lista.valores.length; row++) {
      listSheet
          .cell(
            xl.CellIndex.indexByColumnRow(
              columnIndex: column,
              rowIndex: row + 1,
            ),
          )
          .value = xl.TextCellValue(
        lista.valores[row],
      );
    }
    listSheet.setColumnWidth(column, 32);
  }

  excel.setDefaultSheet('Abastecimiento');
  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el modelo de Abastecimiento.');
  }

  final validaciones = <String>[
    for (var column = 0; column < listas.length; column++)
      if (listas[column].valores.isNotEmpty)
        listas[column].validacion(_letraColumna(column)),
    // Números y fechas: evitan textos que el importador no puede leer.
    for (final column in const ['G', 'I'])
      _validacionDatos(
        tipo: 'decimal',
        operador: 'greaterThanOrEqual',
        formula: '0',
        columna: column,
        titulo: 'Valor numérico',
        mensaje: 'Escriba un número mayor o igual a cero.',
      ),
    for (final column in const ['J', 'K', 'N'])
      _validacionDatos(
        tipo: 'date',
        operador: 'greaterThan',
        // 1 ene 2020 en la numeración de fechas de Excel.
        formula: '43831',
        columna: column,
        titulo: 'Fecha',
        mensaje: 'Escriba una fecha válida en formato día/mes/año.',
      ),
  ];
  return _agregarDesplegables(
    Uint8List.fromList(encoded),
    hojaModelo: 'Abastecimiento',
    hojaListas: kHojaListasAbastecimiento,
    validaciones: validaciones,
  );
}

class _ListaDesplegable {
  final String encabezado;
  final String columnaModelo;
  final List<String> valores;
  final String titulo;
  final String ayuda;

  /// Estricta: solo acepta valores de la lista. Si no, avisa y deja seguir.
  final bool estricta;

  const _ListaDesplegable({
    required this.encabezado,
    required this.columnaModelo,
    required this.valores,
    required this.titulo,
    required this.ayuda,
    required this.estricta,
  });

  String validacion(String columnaLista) {
    final ultima = valores.length + 1;
    return '<dataValidation type="list" allowBlank="1" '
        'showInputMessage="1" showErrorMessage="1" '
        'errorStyle="${estricta ? 'stop' : 'warning'}" '
        'errorTitle="${_xml(titulo)}" '
        'error="${_xml(estricta ? 'Elija un valor de la lista.' : 'El valor no está en la lista. ¿Desea dejarlo así?')}" '
        'promptTitle="${_xml(titulo)}" prompt="${_xml(ayuda)}" '
        'sqref="$columnaModelo$_primeraFilaDatos:$columnaModelo$_ultimaFilaDatos">'
        '<formula1>$kHojaListasAbastecimiento!\$$columnaLista\$2:'
        '\$$columnaLista\$$ultima</formula1>'
        '</dataValidation>';
  }
}

String _validacionDatos({
  required String tipo,
  required String operador,
  required String formula,
  required String columna,
  required String titulo,
  required String mensaje,
}) =>
    '<dataValidation type="$tipo" operator="$operador" allowBlank="1" '
    'showInputMessage="1" showErrorMessage="1" errorStyle="stop" '
    'errorTitle="${_xml(titulo)}" error="${_xml(mensaje)}" '
    'promptTitle="${_xml(titulo)}" prompt="${_xml(mensaje)}" '
    'sqref="$columna$_primeraFilaDatos:$columna$_ultimaFilaDatos">'
    '<formula1>$formula</formula1></dataValidation>';

String _letraColumna(int index) {
  var value = index + 1;
  var result = '';
  while (value > 0) {
    final rest = (value - 1) % 26;
    result = String.fromCharCode(65 + rest) + result;
    value = (value - 1) ~/ 26;
  }
  return result;
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// El paquete excel no escribe validaciones de datos ni hojas ocultas: se
/// agregan al XML del libro ya generado. Solo se tocan workbook.xml (para
/// ocultar la hoja de listas) y el XML de la hoja del modelo.
Uint8List _agregarDesplegables(
  Uint8List bytes, {
  required String hojaModelo,
  required String hojaListas,
  required List<String> validaciones,
}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? leer(String name) {
    final file = archive.findFile(name);
    return file == null ? null : utf8.decode(file.content as List<int>);
  }

  final workbook = leer('xl/workbook.xml');
  final rels = leer('xl/_rels/workbook.xml.rels');
  if (workbook == null || rels == null) {
    throw StateError('No fue posible generar el modelo de Abastecimiento.');
  }

  String? rutaHoja(String nombre) {
    final sheet = RegExp(
      '<sheet\\b[^>]*\\bname="${RegExp.escape(nombre)}"[^>]*/>',
    ).firstMatch(workbook)?.group(0);
    final relId = sheet == null
        ? null
        : RegExp(r'\br:id="([^"]+)"').firstMatch(sheet)?.group(1);
    if (relId == null) return null;
    final relation = RegExp(
      '<Relationship\\b[^>]*\\bId="${RegExp.escape(relId)}"[^>]*/>',
    ).firstMatch(rels)?.group(0);
    final target = relation == null
        ? null
        : RegExp(r'\bTarget="([^"]+)"').firstMatch(relation)?.group(1);
    if (target == null) return null;
    return target.startsWith('/') ? target.substring(1) : 'xl/$target';
  }

  final modelPath = rutaHoja(hojaModelo);
  final modelXml = modelPath == null ? null : leer(modelPath);
  if (modelPath == null || modelXml == null) {
    throw StateError('No fue posible generar el modelo de Abastecimiento.');
  }

  // Orden del esquema: dataValidations va después de sheetData, mergeCells y
  // conditionalFormatting, y antes de hyperlinks, pageMargins y lo demás.
  const siguientes = [
    '<hyperlinks',
    '<printOptions',
    '<pageMargins',
    '<pageSetup',
    '<headerFooter',
    '<rowBreaks',
    '<colBreaks',
    '<customProperties',
    '<cellWatches',
    '<ignoredErrors',
    '<smartTags',
    '<drawing',
    '<legacyDrawing',
    '<picture',
    '<oleObjects',
    '<controls',
    '<webPublishItems',
    '<tableParts',
    '<extLst',
    '</worksheet>',
  ];
  var insertAt = -1;
  for (final tag in siguientes) {
    final index = modelXml.indexOf(tag, modelXml.indexOf('</sheetData>'));
    if (index >= 0 && (insertAt < 0 || index < insertAt)) insertAt = index;
  }
  if (insertAt < 0 || validaciones.isEmpty) return bytes;
  final nextModel =
      '${modelXml.substring(0, insertAt)}'
      '<dataValidations count="${validaciones.length}">'
      '${validaciones.join()}</dataValidations>'
      '${modelXml.substring(insertAt)}';

  final nextWorkbook = workbook.replaceFirstMapped(
    RegExp('<sheet\\b[^>]*\\bname="${RegExp.escape(hojaListas)}"[^>]*/>'),
    (match) {
      final tag = match.group(0)!;
      return tag.contains('state="')
          ? tag.replaceFirst(RegExp(r'state="[^"]*"'), 'state="hidden"')
          : tag.replaceFirst('<sheet ', '<sheet state="hidden" ');
    },
  );

  final rebuilt = Archive();
  for (final file in archive) {
    final replacement = file.name == modelPath
        ? nextModel
        : file.name == 'xl/workbook.xml'
        ? nextWorkbook
        : null;
    if (replacement == null) {
      rebuilt.addFile(file);
    } else {
      final encoded = utf8.encode(replacement);
      rebuilt.addFile(ArchiveFile(file.name, encoded.length, encoded));
    }
  }
  final output = ZipEncoder().encode(rebuilt);
  if (output == null) {
    throw StateError('No fue posible generar el modelo de Abastecimiento.');
  }
  return Uint8List.fromList(output);
}

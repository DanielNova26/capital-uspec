import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

/// Construye el modelo oficial para cargar Compras - Abastecimiento.
///
/// El periodo de consumo no vive en una columna: se selecciona de forma
/// explícita en la aplicación al cargar el archivo y se aplica a toda la carga.
Uint8List construirPlantillaAbastecimiento() {
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
    'Obligatorios: PROVEEDOR, CATEGORIA, PRODUCTO, GRUPO, FECHA ENTREGA y OC. Use los nombres registrados en los catálogos.',
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
    ['PROVEEDOR', 'Sí', 'Nombre exacto de un proveedor activo.'],
    ['CATEGORIA', 'Sí', 'Categoría asociada al proveedor.'],
    ['PRODUCTO', 'Sí', 'Descripción del producto o ingrediente.'],
    ['GRUPO', 'Sí', 'Grupo activo del catálogo de Compras.'],
    ['CIUDAD ENTREGA', 'No', 'Bodega, ciudad o establecimiento de destino.'],
    ['CANTIDAD', 'No', 'Valor numérico.'],
    ['UM', 'No', 'Unidad de medida, por ejemplo KG o UND.'],
    ['FECHA ENTREGA', 'Sí', 'Fecha válida de Excel en formato día/mes/año.'],
    ['OC', 'Sí', 'Número de orden de compra o servicio.'],
    ['ESTADO', 'No', 'Programado, Entregado, Reprogramado o Cancelado.'],
    [
      'PERIODO DE CONSUMO',
      'En la aplicación',
      'Seleccione uno de los cuatro periodos disponibles al cargar el Excel.',
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

  excel.setDefaultSheet('Abastecimiento');
  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el modelo de Abastecimiento.');
  }
  return Uint8List.fromList(encoded);
}

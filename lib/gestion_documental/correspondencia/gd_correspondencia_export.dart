import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import 'gd_correspondencia_models.dart';

Uint8List construirExcelCorrespondencia({
  required List<GdExpediente> expedientes,
  required String empresaId,
  required String alcance,
}) {
  final excel = xl.Excel.createExcel();
  excel.rename('Sheet1', 'Correspondencia');
  final sheet = excel['Correspondencia'];

  const headers = <String>[
    'Código interno',
    'Radicado',
    'Código externo',
    'Fecha de recepción',
    'Tipo documental',
    'Alias / asunto',
    'Asunto original',
    'Remitente',
    'Buzón receptor',
    'Área',
    'Responsable',
    'Prioridad',
    'Fecha límite',
    'Estado',
    'Vencido',
    'Respuesta enviada',
    'Fecha de envío',
    'Canal de respuesta',
    'Adjuntos recibidos',
    'Adjuntos de respuesta',
  ];

  final lastColumn = xl.CellIndex.indexByColumnRow(
    columnIndex: headers.length - 1,
    rowIndex: 0,
  );
  sheet.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    lastColumn,
  );
  final title = sheet.cell(xl.CellIndex.indexByString('A1'));
  title.value = xl.TextCellValue('HISTÓRICO DE GESTIÓN DE CORRESPONDENCIA');
  title.cellStyle = xl.CellStyle(
    bold: true,
    fontSize: 15,
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#17324D'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
  );
  sheet.setRowHeight(0, 30);

  sheet.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
    xl.CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 1),
  );
  final generated = DateTime.now();
  final meta = sheet.cell(xl.CellIndex.indexByString('A2'));
  meta.value = xl.TextCellValue(
    'Empresa: $empresaId · Alcance: $alcance · Registros: ${expedientes.length} · '
    'Generado: ${_fechaTexto(generated)}',
  );
  meta.cellStyle = xl.CellStyle(
    italic: true,
    fontColorHex: xl.ExcelColor.fromHexString('#475569'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#E8F0F5'),
  );

  final headerStyle = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#157A8A'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
    textWrapping: xl.TextWrapping.WrapText,
  );
  for (var column = 0; column < headers.length; column++) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 3),
    );
    cell.value = xl.TextCellValue(headers[column]);
    cell.cellStyle = headerStyle;
  }
  sheet.setRowHeight(3, 32);

  for (var index = 0; index < expedientes.length; index++) {
    final row = expedientes[index];
    final values = <xl.CellValue>[
      xl.TextCellValue(row.codigoInterno),
      xl.TextCellValue(row.radicado),
      xl.TextCellValue(row.codigoExterno),
      _dateValue(row.fechaRecepcion),
      xl.TextCellValue(row.tipoDocumental),
      xl.TextCellValue(row.titulo),
      xl.TextCellValue(row.asunto),
      xl.TextCellValue(row.remitente),
      xl.TextCellValue(row.correoCuenta),
      xl.TextCellValue(row.areaNombre),
      xl.TextCellValue(row.responsableNombre),
      xl.TextCellValue(_capitalizar(row.prioridad)),
      _dateValue(row.fechaLimite),
      xl.TextCellValue(row.estadoOperativo.etiqueta),
      xl.TextCellValue(row.vencido ? 'Sí' : 'No'),
      xl.TextCellValue(row.respondido ? 'Sí' : 'No'),
      _dateValue(row.enviadoAt),
      xl.TextCellValue(_canalRespuesta(row)),
      xl.IntCellValue(row.adjuntosEntrada.length),
      xl.IntCellValue(row.adjuntosRespuesta.length),
    ];
    final rowIndex = index + 4;
    for (var column = 0; column < values.length; column++) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
      );
      cell.value = values[column];
      cell.cellStyle = xl.CellStyle(
        verticalAlign: xl.VerticalAlign.Top,
        textWrapping: xl.TextWrapping.WrapText,
        numberFormat: values[column] is xl.DateTimeCellValue
            ? const xl.CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy hh:mm')
            : xl.NumFormat.standard_0,
        backgroundColorHex: index.isOdd
            ? xl.ExcelColor.fromHexString('#F5F8FA')
            : xl.ExcelColor.fromHexString('#FFFFFF'),
      );
    }
  }

  const widths = <double>[
    19,
    19,
    19,
    20,
    22,
    34,
    34,
    30,
    29,
    22,
    27,
    12,
    20,
    14,
    11,
    17,
    20,
    21,
    16,
    19,
  ];
  for (var column = 0; column < widths.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
  }

  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el histórico de correspondencia.');
  }
  return Uint8List.fromList(encoded);
}

xl.CellValue _dateValue(DateTime? value) => value == null
    ? xl.TextCellValue('')
    : xl.DateTimeCellValue.fromDateTime(value);

String _fechaTexto(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _capitalizar(String value) {
  final clean = value.trim().toLowerCase();
  return clean.isEmpty ? '' : '${clean[0].toUpperCase()}${clean.substring(1)}';
}

String _canalRespuesta(GdExpediente row) {
  if (!row.respondido) return 'Pendiente';
  if (row.respuestaExternaRegistrada)
    return 'Declarada fuera de la app, con soporte';
  if (row.envioOrigen == 'buzon_externo') return 'Detectado en el buzón';
  final canal = row.envioCanal.trim().isEmpty ? row.proveedor : row.envioCanal;
  return canal.toLowerCase().contains('microsoft')
      ? 'Microsoft 365'
      : canal.toLowerCase().contains('gmail')
      ? 'Gmail'
      : canal;
}

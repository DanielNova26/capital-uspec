import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

class ResumeManagementRow {
  final String document;
  final String fullName;
  final String status;
  final String action;
  final String correctionNote;
  final String phone;
  final String email;
  final String position;
  final String area;
  final String costCenter;
  final DateTime? requestedAt;
  final DateTime? updatedAt;

  const ResumeManagementRow({
    required this.document,
    required this.fullName,
    required this.status,
    required this.action,
    this.correctionNote = '',
    this.phone = '',
    this.email = '',
    this.position = '',
    this.area = '',
    this.costCenter = '',
    this.requestedAt,
    this.updatedAt,
  });

  String get statusLabel => switch (status) {
    'requiere_cambios' => 'Correcciones pendientes',
    'en_revision' => 'En revisión por Talento Humano',
    _ => 'Sin enviar',
  };
}

Uint8List buildResumeManagementReport({
  required List<ResumeManagementRow> rows,
  required String empresaId,
  String empresaNombre = '',
  DateTime? generatedAt,
}) {
  final now = generatedAt ?? DateTime.now();
  final ordered = [...rows]
    ..sort((a, b) {
      final byStatus = _statusOrder(a.status).compareTo(_statusOrder(b.status));
      if (byStatus != 0) return byStatus;
      return a.fullName.compareTo(b.fullName);
    });
  final excel = xl.Excel.createExcel();
  excel.rename('Sheet1', 'Pendientes HV');
  final pending = excel['Pendientes HV'];
  final summary = excel['Resumen'];
  const headers = [
    'Estado',
    'Gestión requerida',
    'Documento',
    'Nombre completo',
    'Teléfono',
    'Correo',
    'Cargo',
    'Área',
    'Centro de costo',
    'Corrección u observación',
    'Fecha de devolución',
    'Última actualización',
    'Días sin gestión',
  ];

  pending.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    xl.CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 0),
  );
  final title = pending.cell(xl.CellIndex.indexByString('A1'));
  title.value = xl.TextCellValue('GESTIÓN PENDIENTE DE HOJAS DE VIDA');
  title.cellStyle = xl.CellStyle(
    bold: true,
    fontSize: 15,
    fontColorHex: xl.ExcelColor.white,
    backgroundColorHex: xl.ExcelColor.fromHexString('#173B5E'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
  );
  pending.setRowHeight(0, 30);
  pending.merge(
    xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
    xl.CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 1),
  );
  final meta = pending.cell(xl.CellIndex.indexByString('A2'));
  meta.value = xl.TextCellValue(
    'Empresa: ${empresaNombre.trim().isEmpty ? empresaId : empresaNombre.trim()} · '
    'Personas por gestionar: ${ordered.length} · Generado: ${_dateLabel(now)}',
  );
  meta.cellStyle = xl.CellStyle(
    italic: true,
    fontColorHex: xl.ExcelColor.fromHexString('#475569'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#EAF4FB'),
  );

  final headerStyle = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.white,
    backgroundColorHex: xl.ExcelColor.fromHexString('#246B9E'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
    textWrapping: xl.TextWrapping.WrapText,
  );
  for (var column = 0; column < headers.length; column++) {
    final cell = pending.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 3),
    );
    cell.value = xl.TextCellValue(headers[column]);
    cell.cellStyle = headerStyle;
  }
  pending.setRowHeight(3, 38);

  for (var index = 0; index < ordered.length; index++) {
    final row = ordered[index];
    final referenceDate = row.updatedAt ?? row.requestedAt;
    final days = referenceDate == null
        ? null
        : DateTime(now.year, now.month, now.day)
              .difference(
                DateTime(
                  referenceDate.year,
                  referenceDate.month,
                  referenceDate.day,
                ),
              )
              .inDays
              .clamp(0, 99999);
    final values = <xl.CellValue>[
      xl.TextCellValue(row.statusLabel),
      xl.TextCellValue(row.action),
      xl.TextCellValue(row.document),
      xl.TextCellValue(row.fullName),
      xl.TextCellValue(row.phone),
      xl.TextCellValue(row.email),
      xl.TextCellValue(row.position),
      xl.TextCellValue(row.area),
      xl.TextCellValue(row.costCenter),
      xl.TextCellValue(row.correctionNote),
      row.requestedAt == null
          ? xl.TextCellValue('')
          : xl.DateTimeCellValue.fromDateTime(row.requestedAt!),
      row.updatedAt == null
          ? xl.TextCellValue('')
          : xl.DateTimeCellValue.fromDateTime(row.updatedAt!),
      days == null ? xl.TextCellValue('') : xl.IntCellValue(days),
    ];
    final rowIndex = index + 4;
    for (var column = 0; column < values.length; column++) {
      final cell = pending.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
      );
      cell.value = values[column];
      cell.cellStyle = xl.CellStyle(
        verticalAlign: xl.VerticalAlign.Top,
        textWrapping: xl.TextWrapping.WrapText,
        backgroundColorHex: xl.ExcelColor.fromHexString(
          column == 0
              ? _statusColor(row.status)
              : index.isOdd
              ? '#F7F9FB'
              : '#FFFFFF',
        ),
        numberFormat: values[column] is xl.DateTimeCellValue
            ? const xl.CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy')
            : xl.NumFormat.standard_0,
        bold: column == 0,
      );
    }
  }

  const widths = <double>[25, 31, 16, 29, 17, 28, 24, 22, 24, 42, 20, 20, 16];
  for (var column = 0; column < widths.length; column++) {
    pending.setColumnWidth(column, widths[column]);
  }

  final counts = {
    'Sin enviar': ordered.where((row) => row.status == 'sin_enviar').length,
    'En revisión': ordered.where((row) => row.status == 'en_revision').length,
    'Correcciones pendientes': ordered
        .where((row) => row.status == 'requiere_cambios')
        .length,
  };
  summary.merge(
    xl.CellIndex.indexByString('A1'),
    xl.CellIndex.indexByString('D1'),
  );
  final summaryTitle = summary.cell(xl.CellIndex.indexByString('A1'));
  summaryTitle.value = xl.TextCellValue('RESUMEN DE GESTIÓN DOCUMENTAL');
  summaryTitle.cellStyle = title.cellStyle;
  summary.setRowHeight(0, 30);
  summary.cell(xl.CellIndex.indexByString('A3')).value = xl.TextCellValue(
    'Estado',
  );
  summary.cell(xl.CellIndex.indexByString('B3')).value = xl.TextCellValue(
    'Personas',
  );
  summary.cell(xl.CellIndex.indexByString('A3')).cellStyle = headerStyle;
  summary.cell(xl.CellIndex.indexByString('B3')).cellStyle = headerStyle;
  var summaryRow = 3;
  for (final entry in counts.entries) {
    summary
        .cell(
          xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: summaryRow),
        )
        .value = xl.TextCellValue(
      entry.key,
    );
    summary
        .cell(
          xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: summaryRow),
        )
        .value = xl.IntCellValue(
      entry.value,
    );
    summaryRow++;
  }
  summary
      .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: summaryRow))
      .value = xl.TextCellValue(
    'Total pendiente',
  );
  summary
      .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: summaryRow))
      .value = xl.IntCellValue(
    ordered.length,
  );
  summary.setColumnWidth(0, 31);
  summary.setColumnWidth(1, 16);

  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el informe de hojas de vida.');
  }
  return Uint8List.fromList(encoded);
}

int _statusOrder(String status) => switch (status) {
  'requiere_cambios' => 0,
  'en_revision' => 1,
  _ => 2,
};

String _statusColor(String status) => switch (status) {
  'requiere_cambios' => '#FEE2E2',
  'en_revision' => '#FEF3C7',
  _ => '#E2E8F0',
};

String _dateLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

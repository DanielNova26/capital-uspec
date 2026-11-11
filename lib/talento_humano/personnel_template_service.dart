import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../compras/abastecimiento_excel_template.dart'
    show agregarDesplegablesXlsx;

const _personal = 'PERSONAL';
const _instrucciones = 'INSTRUCCIONES';
const _listas = 'LISTAS';
const _columnas = [
  ('cedula', 'Documento', 22.0),
  ('tipo_documento', 'Tipo de documento', 29.0),
  ('nombres', 'Nombres', 26.0),
  ('apellidos', 'Apellidos', 26.0),
  ('correo', 'Correo', 36.0),
  ('area', 'Área', 30.0),
  ('cargo', 'Cargo', 40.0),
  ('centroCostos', 'Centro de costos', 36.0),
  ('jefe', 'Jefe directo', 38.0),
  ('estado', 'Estado', 16.0),
];

Uint8List construirPlantillaPersonal({
  required String empresaId,
  required String empresaNombre,
  required int limite,
  required Map<String, List<String>> catalogos,
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', _personal);
  excel.setDefaultSheet(_personal);
  final personal = excel[_personal];
  final guia = excel[_instrucciones];
  final ejemplo = excel['EJEMPLO'];
  final listas = excel[_listas];
  final cabecera = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#173B5E'),
    verticalAlign: VerticalAlign.Center,
  );
  final texto = CellStyle(numberFormat: NumFormat.standard_49);
  for (final hoja in [personal, ejemplo]) {
    for (final (i, (_, titulo, ancho)) in _columnas.indexed) {
      _celda(hoja, i, 0)
        ..value = TextCellValue(titulo)
        ..cellStyle = cabecera;
      hoja.setColumnWidth(i, ancho);
    }
    hoja.setRowHeight(0, 26);
  }
  for (var i = 1; i <= limite; i++) {
    _celda(personal, 0, i).cellStyle = texto;
  }

  final notas = [
    'Carga masiva de empleados',
    'Empresa: $empresaNombre',
    empresaId,
    'Diligencia PERSONAL desde la fila 2. Puedes cargar hasta $limite empleados por archivo.',
    'Obligatorios: documento (solo dígitos), tipo de documento, nombres y apellidos.',
    'Abre los desplegables para elegir tipo de documento, área, cargo, centro, jefe directo y estado.',
    'Si dejas el estado vacío, la persona quedará activa.',
    'Consulta EJEMPLO para ver cómo diligenciar una fila. La aplicación carga únicamente PERSONAL.',
    'Conserva los encabezados y el identificador de empresa de la fila 3.',
  ];
  for (final (i, nota) in notas.indexed) {
    final celda = _celda(guia, 0, i)..value = TextCellValue(nota);
    if (i == 0) celda.cellStyle = cabecera;
  }
  guia.setColumnWidth(0, 110);
  guia.setRowHeight(0, 26);

  final muestra = [
    '0012345678',
    catalogos['tipo_documento']?.firstOrNull ?? '',
    'Andrea',
    'Pérez',
    'andrea.perez@example.com',
    catalogos['area']?.firstOrNull ?? '',
    '',
    catalogos['centroCostos']?.firstOrNull ?? '',
    '',
    'ACTIVO',
  ];
  for (final (i, valor) in muestra.indexed) {
    _celda(ejemplo, i, 1).value = TextCellValue(valor);
  }

  final validaciones = <String>[];
  for (final (i, (campo, titulo, _)) in _columnas.indexed) {
    final opciones = catalogos[campo] ?? const [];
    if (opciones.isEmpty) continue;
    _celda(listas, i, 0).value = TextCellValue(titulo);
    for (final (j, valor) in opciones.indexed) {
      _celda(listas, i, j + 1).value = TextCellValue(valor);
    }
    final col = String.fromCharCode(65 + i);
    final ultimaOpcion = opciones.length + 1;
    validaciones.add(
      '<dataValidation type="list" allowBlank="1" showErrorMessage="1" '
      'errorStyle="stop" errorTitle="Valor fuera de catálogo" '
      'error="Selecciona un valor del desplegable." '
      'sqref="${col}2:$col${limite + 1}">'
      '<formula1>INDIRECT("$_listas!\$$col\$2:\$$col\$$ultimaOpcion")</formula1>'
      '</dataValidation>',
    );
  }

  final bytes = excel.encode();
  if (bytes == null) throw StateError('No se pudo generar la plantilla.');
  return agregarDesplegablesXlsx(
    Uint8List.fromList(bytes),
    hojaModelo: _personal,
    hojaListas: _listas,
    validaciones: validaciones,
    modelo: 'Talento Humano',
  );
}

class ArchivoCargaPersonal {
  final String empresaId;
  final List<Map<String, Object>> filas;

  const ArchivoCargaPersonal(this.empresaId, this.filas);

  static ArchivoCargaPersonal leer(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final personal = excel.tables[_personal];
    final guia = excel.tables[_instrucciones];
    final empresaId = guia?.cell(CellIndex.indexByString('A3')).value;
    if (personal == null || empresaId is! TextCellValue) {
      throw const FormatException(
        'Descarga la plantilla de la empresa activa y copia las filas en PERSONAL.',
      );
    }
    final headers = personal.row(0);
    if (headers.length < _columnas.length ||
        _columnas.indexed.any(
          (entry) => headers[entry.$1]?.value.toString() != entry.$2.$2,
        )) {
      throw const FormatException(
        'Conserva los encabezados de la hoja PERSONAL.',
      );
    }
    if (personal.maxRows > 10001) {
      throw const FormatException(
        'Copia las filas diligenciadas en una plantilla nueva y vuelve a subirla.',
      );
    }

    final filas = <Map<String, Object>>[];
    for (var i = 1; i < personal.maxRows; i++) {
      final row = personal.row(i);
      final fila = i + 1;
      final datos = <String, Object>{
        for (final (j, (campo, _, _)) in _columnas.indexed)
          campo: _leerCelda(j < row.length ? row[j]?.value : null, fila),
      };
      if (datos.values.every((value) => value == '')) continue;
      filas.add({'fila': fila, ...datos});
    }
    if (filas.isEmpty) {
      throw const FormatException('Agrega al menos un empleado en PERSONAL.');
    }
    return ArchivoCargaPersonal(empresaId.toString(), filas);
  }
}

Data _celda(Sheet hoja, int columna, int fila) =>
    hoja.cell(CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: fila));

String _leerCelda(CellValue? valor, int fila) {
  if (valor == null) return '';
  if (valor is TextCellValue || valor is IntCellValue) {
    return valor.toString().trim();
  }
  if (valor is DoubleCellValue &&
      valor.value.isFinite &&
      valor.value == valor.value.truncateToDouble() &&
      valor.value.abs() < 1e15) {
    return valor.value.toInt().toString();
  }
  throw FormatException(
    'Fila $fila: usa texto o elige un valor del desplegable.',
  );
}

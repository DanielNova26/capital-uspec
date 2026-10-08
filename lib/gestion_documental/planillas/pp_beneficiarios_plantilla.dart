import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import '../../compras/abastecimiento_excel_template.dart'
    show agregarDesplegablesXlsx;
import 'pp_archivo_plano.dart';

/// Hoja oculta con los valores de los desplegables.
const String kHojaListasBeneficiarios = 'Listas';

/// Hoja de datos: se llama igual que la que lee `PpCuentasExcelParser`.
const String kHojaCuentas = 'CUENTAS';

/// Filas con desplegables (de la 2 a la 1001; la 1 es la cabecera).
const int _primeraFila = 2;
const int _ultimaFila = 1001;

const List<String> kCabecerasModeloCuentas = [
  'Identificación',
  'Tipo Id',
  'Dígito V',
  'Apellidos y Nombres',
  'Forma Pago',
  'Banco',
  'Tipo Cuenta',
  'No Cuenta',
  'E-mail',
];

/// Desplegables del modelo. El texto empieza por el código, que es lo que lee
/// el importador (`codigoDeDesplegable`).
const List<String> kOpcionesTipoId = ['1 - Cédula', '2 - NIT'];
const List<String> kOpcionesTipoCuenta = ['01 - Corriente', '02 - Ahorros'];
const List<String> kOpcionesFormaPago = [
  '1 - Con fecha límite',
  '2 - Con fecha límite',
  '3 - Sin fecha límite',
];

/// Del valor de un desplegable ("0013 - BBVA") al código ("0013").
///
/// Si la celda trae solo el código —o un archivo viejo— se devuelve igual.
String codigoDeDesplegable(String valor) {
  final v = valor.trim();
  final m = RegExp(r'^(\d+)\s*(?:[-–:]|$)').firstMatch(v);
  return m == null ? v : m.group(1)!;
}

String _xml(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _letra(int i) => String.fromCharCode(65 + i);

/// Modelo oficial para cargar el maestro de beneficiarios de pago.
///
/// Banco, tipo de cuenta, tipo de identificación y forma de pago se eligen de
/// listas (el banco con su código ACH y su nombre, así nadie teclea "0013").
/// Identificación, dígito y cuenta se fuerzan a texto para que Excel no se
/// coma los ceros ni los pase a notación científica.
Uint8List construirModeloBeneficiarios() {
  final excel = xl.Excel.createExcel();
  excel.rename('Sheet1', kHojaCuentas);
  final sheet = excel[kHojaCuentas];

  final cabecera = xl.CellStyle(
    bold: true,
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: xl.ExcelColor.fromHexString('#0F4C81'),
    horizontalAlign: xl.HorizontalAlign.Center,
    verticalAlign: xl.VerticalAlign.Center,
    textWrapping: xl.TextWrapping.WrapText,
  );
  for (var c = 0; c < kCabecerasModeloCuentas.length; c++) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
    );
    cell.value = xl.TextCellValue(kCabecerasModeloCuentas[c]);
    cell.cellStyle = cabecera;
    sheet.setColumnWidth(c, c == 3 ? 38 : (c == 8 ? 32 : 18));
  }
  sheet.setRowHeight(0, 32);

  // Texto ('@') en identificación, dígito y cuenta, para que Excel no se coma
  // los ceros ni pase una cuenta larga a notación científica. Sin fila de
  // ejemplo: el importador la leería como un beneficiario real.
  final texto = xl.CellStyle(numberFormat: xl.NumFormat.standard_49);
  for (final c in const [0, 2, 7]) {
    for (var r = _primeraFila - 1; r < _ultimaFila; r++) {
      sheet
              .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .cellStyle =
          texto;
    }
  }

  final bancos = [
    for (final e in kBancosAch.entries) '${e.key} - ${e.value}',
  ];
  final listas = <(String, List<String>)>[
    ('Tipo Id', kOpcionesTipoId),
    ('Forma Pago', kOpcionesFormaPago),
    ('Banco', bancos),
    ('Tipo Cuenta', kOpcionesTipoCuenta),
  ];
  final listSheet = excel[kHojaListasBeneficiarios];
  for (var c = 0; c < listas.length; c++) {
    listSheet
        .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
        .value = xl.TextCellValue(
      listas[c].$1,
    );
    for (var r = 0; r < listas[c].$2.length; r++) {
      listSheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
          .value = xl.TextCellValue(
        listas[c].$2[r],
      );
    }
    listSheet.setColumnWidth(c, 30);
  }

  final ayuda = excel['Instrucciones'];
  const lineas = [
    'MODELO DE CARGA - BENEFICIARIOS DE PAGO',
    '',
    '1. Diligencie una fila por beneficiario en la hoja CUENTAS, desde la fila 2. Ejemplo: 1234567890 | 1 - Cédula | 0 | PEREZ GOMEZ JUAN | 1 - Con fecha límite | 0013 - BBVA | 02 - Ahorros | 000123456789.',
    '2. Obligatorios: Identificación (sin puntos ni guiones), Apellidos y Nombres (máx. 36 caracteres), Banco y No Cuenta.',
    '3. Tipo Id, Forma Pago, Banco y Tipo Cuenta se eligen de la lista desplegable.',
    '4. Forma Pago 1 o 2 lleva fecha límite; la 3 no la lleva (el archivo plano usa ocho ceros).',
    '5. Dígito V: solo para NIT; para cédula deje 0.',
    '6. Identificación, Dígito V y No Cuenta están en formato texto: escriba los números tal cual, con sus ceros.',
    '7. Si el banco no aparece en la lista, escriba su código ACH de 4 dígitos; se acepta con una advertencia.',
    '8. No cambie los nombres de las cabeceras ni inserte columnas.',
  ];
  for (var i = 0; i < lineas.length; i++) {
    final cell = ayuda.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
    );
    cell.value = xl.TextCellValue(lineas[i]);
    if (i == 0) cell.cellStyle = xl.CellStyle(bold: true, fontSize: 14);
  }
  ayuda.setColumnWidth(0, 120);

  excel.setDefaultSheet(kHojaCuentas);
  final encoded = excel.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('No fue posible generar el modelo de beneficiarios.');
  }

  String lista(
    int colLista,
    String colModelo,
    int cantidad,
    String titulo,
    String msg, {
    bool estricta = true,
  }) =>
      '<dataValidation type="list" allowBlank="1" showInputMessage="1" '
      'showErrorMessage="1" errorStyle="${estricta ? 'stop' : 'warning'}" '
      'errorTitle="${_xml(titulo)}" '
      'error="${_xml(estricta ? 'Elija un valor de la lista.' : 'El valor no está en la lista. ¿Desea dejarlo así?')}" '
      'promptTitle="${_xml(titulo)}" prompt="${_xml(msg)}" '
      'sqref="$colModelo$_primeraFila:$colModelo$_ultimaFila">'
      '<formula1>$kHojaListasBeneficiarios!\$${_letra(colLista)}\$2:'
      '\$${_letra(colLista)}\$${cantidad + 1}</formula1></dataValidation>';

  final validaciones = [
    lista(0, 'B', kOpcionesTipoId.length, 'Tipo de identificación',
        '1 = cédula, 2 = NIT.'),
    lista(1, 'E', kOpcionesFormaPago.length, 'Forma de pago',
        '1 o 2 llevan fecha límite; 3 no.'),
    // El banco avisa pero deja seguir: hay entidades más nuevas que el
    // catálogo (0507, 0551, 0809).
    lista(2, 'F', bancos.length, 'Banco',
        'Elija el banco. Si no está, escriba su código ACH.',
        estricta: false),
    lista(3, 'G', kOpcionesTipoCuenta.length, 'Tipo de cuenta',
        '01 = corriente, 02 = ahorros.'),
  ];

  final bytes = agregarDesplegablesXlsx(
    Uint8List.fromList(encoded),
    hojaModelo: kHojaCuentas,
    hojaListas: kHojaListasBeneficiarios,
    validaciones: validaciones,
    modelo: 'beneficiarios',
  );
  return bytes;
}

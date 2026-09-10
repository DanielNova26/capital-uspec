import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'pp_cuentas_models.dart';

/// Lee la hoja `CUENTAS` del Excel de Tesorería.
///
/// Columnas, en el orden de la plantilla del banco: Identificación, Tipo Id,
/// Dígito V, Apellidos y Nombres, Forma Pago, Banco, Tipo Cuenta, No Cuenta.
/// Se buscan por nombre, no por posición, porque la hoja se edita a mano y una
/// columna insertada correría todo lo demás en silencio.
///
/// ## El riesgo de este archivo son los números
///
/// Excel guarda casi todo como número aunque se vea como texto. Una cuenta de
/// doce dígitos leída como decimal vuelve convertida en `1.1161004988e11`, y un
/// banco guardado como el número 13 pierde sus ceros. Por eso [_texto] trata
/// cada tipo de celda por separado en vez de confiar en `toString()`: es la
/// diferencia entre importar una cuenta bancaria y importar basura con forma de
/// cuenta bancaria.
class PpCuentasExcelParser {
  /// Nombres aceptados para cada campo, ya normalizados.
  static const Map<String, List<String>> _columnas = {
    'cedula': ['identificacion', 'cedula', 'documento', 'nrodocumento'],
    'tipoId': ['tipoid', 'tipodocumento'],
    'digitoV': ['digitov', 'digitoverificacion', 'dv'],
    'nombre': ['apellidosynombres', 'nombre', 'nombres', 'beneficiario'],
    'formaPago': ['formapago'],
    'banco': ['banco', 'codigobanco'],
    'tipoCuenta': ['tipocuenta'],
    'numeroCuenta': ['nocuenta', 'numerocuenta', 'cuenta'],
    'email': ['email', 'correo', 'correoelectronico'],
  };

  /// Devuelve las filas leídas, sin juzgarlas.
  ///
  /// La revisión es de [analizarImportacionCuentas]: separar leer de validar
  /// permite probar cada cosa por su lado y, sobre todo, enseñarle a Tesorería
  /// la lista completa con sus problemas antes de escribir nada.
  List<CuentaBancaria> parse({
    required Uint8List bytes,
    required String empresaId,
    String hoja = 'CUENTAS',
  }) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = _hoja(excel, hoja);
    if (sheet == null || sheet.rows.length < 2) return const [];

    final encabezados = sheet.rows.first
        .map((c) => _canon(_texto(c?.value)))
        .toList(growable: false);

    int indiceDe(String campo) {
      for (final alias in _columnas[campo]!) {
        final i = encabezados.indexOf(alias);
        if (i >= 0) return i;
      }
      return -1;
    }

    final idx = {for (final campo in _columnas.keys) campo: indiceDe(campo)};
    // Sin cédula ni cuenta no hay nada que importar, y adivinar la posición
    // sería peor que no importar.
    if (idx['cedula']! < 0 || idx['numeroCuenta']! < 0) return const [];

    final cuentas = <CuentaBancaria>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final fila = sheet.rows[i];
      String valor(String campo, [String pordefecto = '']) {
        final j = idx[campo]!;
        if (j < 0 || j >= fila.length) return pordefecto;
        final v = _texto(fila[j]?.value).trim();
        return v.isEmpty ? pordefecto : v;
      }

      final cedula = valor('cedula');
      final cuenta = valor('numeroCuenta');
      if (cedula.isEmpty && cuenta.isEmpty) continue; // fila en blanco

      cuentas.add(
        CuentaBancaria(
          cedula: cedula,
          empresaId: empresaId,
          nombre: valor('nombre'),
          bancoCodigo: valor('banco'),
          numeroCuenta: cuenta,
          tipoId: valor('tipoId', '1'),
          digitoVerificacion: valor('digitoV', '0'),
          formaPago: valor('formaPago', '1'),
          tipoCuenta: valor('tipoCuenta', '2'),
          email: valor('email'),
        ),
      );
    }
    return cuentas;
  }

  Sheet? _hoja(Excel excel, String preferida) {
    for (final entry in excel.tables.entries) {
      if (_canon(entry.key) == _canon(preferida)) return entry.value;
    }
    // Si no está por nombre, se busca la que tenga la cabecera esperada: la
    // hoja se ha llamado "Beneficiarios" y "CUENTAS" en distintas versiones.
    for (final sheet in excel.tables.values) {
      if (sheet.rows.isEmpty) continue;
      final cabecera = sheet.rows.first.map((c) => _canon(_texto(c?.value)));
      if (cabecera.contains('identificacion') &&
          cabecera.any((h) => h.contains('cuenta'))) {
        return sheet;
      }
    }
    return null;
  }

  /// Convierte una celda a texto **sin** perder ceros ni ganar exponentes.
  String _texto(dynamic v) {
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString();
    // Un entero se escribe como entero: `toString()` sobre un double de doce
    // dígitos devuelve notación científica y la cuenta queda inservible.
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
    }
    if (v is FormulaCellValue) return v.formula;
    if (v is BoolCellValue) return v.value ? '1' : '0';
    return v.toString();
  }

  String _canon(String input) {
    final lower = input.trim().toLowerCase();
    final sinTilde = lower
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    return sinTilde.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}

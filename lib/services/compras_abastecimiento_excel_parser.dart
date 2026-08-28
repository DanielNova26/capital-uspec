import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;

import '../compras/abastecimiento_models.dart';

class AbastecimientoImportRow {
  final String hoja;
  final int fila;
  final String proveedorId;
  final String proveedor;
  final String categoria;
  final String productoId;
  final String producto;
  final String grupoId;
  final String grupo;
  final String destino;
  final String condicion;
  final double? cantidad;
  final String unidad;
  final double? precio;
  final DateTime? fechaProgramada;
  final DateTime? fechaSegundaEntrega;
  final String ordenCompra;
  final String recepcionId;
  final DateTime? fechaRecibido;
  final AbastecimientoEstado? estadoExplicito;
  final String observaciones;

  const AbastecimientoImportRow({
    required this.hoja,
    required this.fila,
    this.proveedorId = '',
    required this.proveedor,
    required this.categoria,
    this.productoId = '',
    required this.producto,
    this.grupoId = '',
    required this.grupo,
    required this.destino,
    required this.condicion,
    required this.cantidad,
    required this.unidad,
    required this.precio,
    required this.fechaProgramada,
    required this.fechaSegundaEntrega,
    required this.ordenCompra,
    this.recepcionId = '',
    required this.fechaRecibido,
    required this.estadoExplicito,
    required this.observaciones,
  });

  String get importKey {
    final oc = _normalizar(ordenCompra);
    return '${_normalizar(hoja)}|$oc|${_normalizar(proveedor)}|'
        '${_normalizar(producto)}|${_normalizar(grupo)}|'
        '${_normalizar(destino)}';
  }

  List<AbastecimientoPendencia> get pendencias =>
      detectarPendenciasAbastecimiento(observaciones);

  AbastecimientoImportRow copyWith({
    String? proveedorId,
    String? proveedor,
    String? categoria,
    String? productoId,
    String? producto,
    String? grupoId,
    String? grupo,
    String? recepcionId,
    DateTime? fechaRecibido,
  }) => AbastecimientoImportRow(
    hoja: hoja,
    fila: fila,
    proveedorId: proveedorId ?? this.proveedorId,
    proveedor: proveedor ?? this.proveedor,
    categoria: categoria ?? this.categoria,
    productoId: productoId ?? this.productoId,
    producto: producto ?? this.producto,
    grupoId: grupoId ?? this.grupoId,
    grupo: grupo ?? this.grupo,
    destino: destino,
    condicion: condicion,
    cantidad: cantidad,
    unidad: unidad,
    precio: precio,
    fechaProgramada: fechaProgramada,
    fechaSegundaEntrega: fechaSegundaEntrega,
    ordenCompra: ordenCompra,
    recepcionId: recepcionId ?? this.recepcionId,
    fechaRecibido: fechaRecibido ?? this.fechaRecibido,
    estadoExplicito: estadoExplicito,
    observaciones: observaciones,
  );
}

class AbastecimientoExcelIssue {
  final String hoja;
  final int fila;
  final String mensaje;

  const AbastecimientoExcelIssue({
    required this.hoja,
    required this.fila,
    required this.mensaje,
  });
}

class AbastecimientoExcelParseResult {
  final List<AbastecimientoImportRow> filas;
  final List<AbastecimientoExcelIssue> incidencias;
  final List<String> hojasLeidas;

  const AbastecimientoExcelParseResult({
    required this.filas,
    required this.incidencias,
    required this.hojasLeidas,
  });

  int get omitidas => incidencias.length;
}

class ComprasAbastecimientoExcelParser {
  AbastecimientoExcelParseResult parse(Uint8List bytes) {
    final excel = xl.Excel.decodeBytes(_fixNumFmtIds(bytes));
    final filas = <AbastecimientoImportRow>[];
    final incidencias = <AbastecimientoExcelIssue>[];
    final hojasLeidas = <String>[];

    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      final headerIndex = _encontrarCabecera(sheet);
      if (headerIndex == null) continue;
      hojasLeidas.add(entry.key);

      final headers = <String, int>{};
      final headerRow = sheet.rows[headerIndex];
      for (var column = 0; column < headerRow.length; column++) {
        final key = _canon(_cellText(headerRow[column]?.value));
        if (key.isNotEmpty) headers.putIfAbsent(key, () => column);
      }

      for (var index = headerIndex + 1; index < sheet.rows.length; index++) {
        final row = sheet.rows[index];
        final proveedor = _value(row, headers, const ['proveedor']);
        final producto = _value(row, headers, const [
          'producto',
          'ingrediente',
        ]);
        final categoria = _value(row, headers, const ['categoria']);

        if (proveedor.isEmpty && producto.isEmpty && categoria.isEmpty) {
          continue;
        }
        if (proveedor.isEmpty || producto.isEmpty) {
          incidencias.add(
            AbastecimientoExcelIssue(
              hoja: entry.key,
              fila: index + 1,
              mensaje: proveedor.isEmpty
                  ? 'Falta proveedor.'
                  : 'Falta producto.',
            ),
          );
          continue;
        }

        final kg = _number(row, headers, const ['kg']);
        final und = _number(row, headers, const ['und', 'unidad']);
        final cantidadGeneral = _number(row, headers, const [
          'cant',
          'cantidad',
          'cantidades',
        ]);
        final cantidad = cantidadGeneral ?? kg ?? und;
        final unidad = cantidadGeneral != null
            ? _value(row, headers, const ['um', 'unidadmedida'])
            : kg != null
            ? 'KG'
            : und != null
            ? 'UND'
            : '';

        final estadoRaw = _value(row, headers, const ['entrada', 'estado']);
        final fechaRecibido = _date(row, headers, const [
          'fecharecibido',
          'fecharecibida',
        ]);
        final estadoExplicito = fechaRecibido != null
            ? AbastecimientoEstado.recibido
            : _parseEstadoExplicito(estadoRaw);

        filas.add(
          AbastecimientoImportRow(
            hoja: entry.key,
            fila: index + 1,
            proveedor: proveedor,
            categoria: categoria,
            producto: producto,
            grupo: _value(row, headers, const ['grupo']),
            destino: _value(row, headers, const [
              'ciudadentrega',
              'bodega',
              'establecimiento',
              'establecimientoo',
            ]),
            condicion: _value(row, headers, const ['condicion']),
            cantidad: cantidad,
            unidad: unidad,
            precio: _number(row, headers, const ['precio', 'costounitario']),
            fechaProgramada: _date(row, headers, const [
              'fechaentrega',
              'fechaprimeraentrega',
              'fechalimite',
            ]),
            fechaSegundaEntrega: _date(row, headers, const [
              'fechasegundaentrega',
              'fechaentrega2',
            ]),
            ordenCompra: _value(row, headers, const [
              'oc',
              'os',
              'ordendecompra',
            ]),
            fechaRecibido: fechaRecibido,
            estadoExplicito: estadoExplicito,
            observaciones: _value(row, headers, const [
              'observaciones',
              'observacion',
            ]),
          ),
        );
      }
    }

    return AbastecimientoExcelParseResult(
      filas: filas,
      incidencias: incidencias,
      hojasLeidas: hojasLeidas,
    );
  }

  int? _encontrarCabecera(xl.Sheet sheet) {
    final limit = sheet.rows.length < 15 ? sheet.rows.length : 15;
    for (var index = 0; index < limit; index++) {
      final headers = sheet.rows[index]
          .map((cell) => _canon(_cellText(cell?.value)))
          .toSet();
      final hasProveedor = headers.contains('proveedor');
      final hasProducto = headers.contains('producto');
      final hasFecha = headers.any(
        (header) =>
            header == 'fechaentrega' ||
            header == 'fechaprimeraentrega' ||
            header == 'fechalimite',
      );
      if (hasProveedor && hasProducto && hasFecha) return index;
    }
    return null;
  }

  String _value(
    List<xl.Data?> row,
    Map<String, int> headers,
    List<String> aliases,
  ) {
    for (final alias in aliases) {
      final index = headers[_canon(alias)];
      if (index == null || index >= row.length) continue;
      final value = _cellText(row[index]?.value).trim();
      if (value.isNotEmpty && !value.startsWith('#')) return value;
    }
    return '';
  }

  double? _number(
    List<xl.Data?> row,
    Map<String, int> headers,
    List<String> aliases,
  ) {
    for (final alias in aliases) {
      final index = headers[_canon(alias)];
      if (index == null || index >= row.length) continue;
      final raw = row[index]?.value;
      if (raw is xl.IntCellValue) return raw.value.toDouble();
      if (raw is xl.DoubleCellValue) return raw.value;
      final value = _cellText(raw).replaceAll(RegExp(r'[^0-9,.-]'), '');
      if (value.isEmpty) continue;
      final normalized = value.contains(',') && value.contains('.')
          ? value.replaceAll(',', '')
          : value.replaceAll(',', '.');
      final parsed = double.tryParse(normalized);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _date(
    List<xl.Data?> row,
    Map<String, int> headers,
    List<String> aliases,
  ) {
    for (final alias in aliases) {
      final index = headers[_canon(alias)];
      if (index == null || index >= row.length) continue;
      final value = row[index]?.value;
      if (value is xl.DateCellValue) {
        return DateTime(value.year, value.month, value.day);
      }
      if (value is xl.DateTimeCellValue) return value.asDateTimeLocal();
      final parsed = _parseDateText(_cellText(value));
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _parseDateText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;
    final match = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$',
    ).firstMatch(text);
    if (match == null) return null;
    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    // La plantilla operativa colombiana usa día/mes/año. Si el segundo valor
    // supera 12 se interpreta como mes/día/año para conservar compatibilidad.
    if (second > 12 && first <= 12) return DateTime(year, first, second);
    return DateTime(year, second, first);
  }

  AbastecimientoEstado? _parseEstadoExplicito(String raw) {
    final value = _normalizar(raw);
    if (value.isEmpty) return null;
    if (value.contains('no entrega') || value.contains('no va')) {
      return AbastecimientoEstado.noEntrega;
    }
    if (value.contains('cancel') || value.contains('anulad')) {
      return AbastecimientoEstado.cancelado;
    }
    if (value.contains('recibid') || value.contains('entregad')) {
      return AbastecimientoEstado.recibido;
    }
    if (value.contains('camino') || value.contains('despach')) {
      return AbastecimientoEstado.enCamino;
    }
    if (value.contains('confirm')) return AbastecimientoEstado.confirmado;
    if (value.contains('reprogram')) {
      return AbastecimientoEstado.reprogramado;
    }
    if (value.contains('program')) return AbastecimientoEstado.programado;
    return null;
  }

  String _cellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) return value.value.toString();
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) return value.value.toString();
    if (value is xl.BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
    if (value is xl.DateCellValue) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';
    }
    if (value is xl.DateTimeCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is xl.FormulaCellValue) return value.formula;
    return value.toString();
  }

  String _canon(String value) => _normalizar(value).replaceAll(' ', '');

  /// El paquete excel 4.x rechaza formatos personalizados con IDs menores a
  /// 164. Algunos consolidados creados por Excel de escritorio sí los traen.
  /// Se remapea únicamente styles.xml en memoria; el archivo original nunca se
  /// altera y los valores de las celdas permanecen intactos.
  Uint8List _fixNumFmtIds(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final styles = archive.findFile('xl/styles.xml');
      if (styles == null) return bytes;
      var xml = utf8.decode(styles.content as List<int>);
      final numFormatsBlock = RegExp(
        r'<numFmts\b[^>]*>.*?</numFmts>',
      ).firstMatch(xml)?.group(0);
      if (numFormatsBlock == null) return bytes;
      final definitions = RegExp(r'<numFmt\b[^>]*\bnumFmtId="(\d+)"');
      final ids = <int>{};
      for (final match in definitions.allMatches(numFormatsBlock)) {
        final id = int.tryParse(match.group(1) ?? '') ?? 0;
        if (id < 164) ids.add(id);
      }
      if (ids.isEmpty) return bytes;

      var nextId = 500;
      final remap = <int, int>{};
      for (final id in ids) {
        remap[id] = nextId++;
      }
      xml = xml.replaceAllMapped(RegExp(r'numFmtId="(\d+)"'), (match) {
        final id = int.tryParse(match.group(1) ?? '') ?? -1;
        return 'numFmtId="${remap[id] ?? id}"';
      });

      final rebuilt = Archive();
      for (final file in archive) {
        if (file.name == 'xl/styles.xml') {
          final encoded = utf8.encode(xml);
          rebuilt.addFile(
            ArchiveFile('xl/styles.xml', encoded.length, encoded),
          );
        } else {
          rebuilt.addFile(file);
        }
      }
      final encoded = ZipEncoder().encode(rebuilt);
      if (encoded != null) return Uint8List.fromList(encoded);
    } catch (_) {
      // Se conserva el error original de Excel.decodeBytes si el archivo no es
      // un XLSX válido o no puede reconstruirse.
    }
    return bytes;
  }
}

String _normalizar(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

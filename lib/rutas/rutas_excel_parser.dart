// lib/rutas/rutas_excel_parser.dart

import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'rutas_models.dart';

class RutaExcelRow {
  final int? numero;
  final String sede;
  final String direccion;
  final double? lat;
  final double? lng;
  final double? distanciaKm;
  final String rango;
  final int excelRowNumber;

  const RutaExcelRow({
    required this.numero,
    required this.sede,
    required this.direccion,
    required this.lat,
    required this.lng,
    required this.distanciaKm,
    required this.rango,
    required this.excelRowNumber,
  });

  String get codigo {
    final prefix = numero == null
        ? 'Ruta'
        : 'Ruta ${numero.toString().padLeft(2, '0')}';
    return sede.trim().isEmpty ? prefix : '$prefix - ${sede.trim()}';
  }

  RutaStop toStop() => RutaStop(
    nombre: sede.trim(),
    direccionRaw: direccion.trim(),
    direccionLimpia: direccion.trim(),
    lat: lat,
    lng: lng,
    orden: 0,
    distanciaCentroKm: distanciaKm,
    rangoDistancia: rango.trim(),
  );
}

class RutasExcelParseResult {
  final List<RutaExcelRow> rutas;
  final int skippedRows;
  final int headerRowNumber;
  final String? error;

  const RutasExcelParseResult({
    required this.rutas,
    required this.skippedRows,
    required this.headerRowNumber,
    this.error,
  });

  bool get exitoso => error == null && rutas.isNotEmpty;
}

class RutasExcelParser {
  RutasExcelParseResult parse(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes);
      final sheet = _findSheet(excel);
      if (sheet == null || sheet.rows.isEmpty) {
        return const RutasExcelParseResult(
          rutas: [],
          skippedRows: 0,
          headerRowNumber: 0,
          error: 'No se encontro una hoja valida en el Excel.',
        );
      }

      final headerIndex = _findHeaderRowIndex(sheet);
      if (headerIndex < 0) {
        return const RutasExcelParseResult(
          rutas: [],
          skippedRows: 0,
          headerRowNumber: 0,
          error:
              'No se encontraron encabezados de rutas. Se esperan columnas como Sede, Direccion, Latitud y Longitud.',
        );
      }

      final headers = sheet.rows[headerIndex]
          .map((c) => _canon(_cellToString(c?.value)))
          .toList(growable: false);

      final rutas = <RutaExcelRow>[];
      var skipped = 0;

      for (var i = headerIndex + 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final isBlank = row.every(
          (c) => _cellToString(c?.value).trim().isEmpty,
        );
        if (isBlank) continue;

        final map = <String, String>{};
        for (var j = 0; j < headers.length; j++) {
          final key = headers[j];
          if (key.isEmpty) continue;
          map[key] = j < row.length ? _cellToString(row[j]?.value).trim() : '';
        }

        final sede = _pick(map, ['sede', 'nombre', 'destino', 'parada']);
        final direccion = _pick(map, [
          'direccion',
          'direccin',
          'direccionraw',
          'ubicacion',
        ]);
        if (sede.isEmpty && direccion.isEmpty) {
          skipped++;
          continue;
        }

        rutas.add(
          RutaExcelRow(
            numero: _parseInt(_pick(map, ['n', 'no', 'nro', 'numero'])),
            sede: sede.isEmpty ? direccion : sede,
            direccion: direccion,
            lat: _parseDouble(_pick(map, ['latitud', 'lat'])),
            lng: _parseDouble(_pick(map, ['longitud', 'lng', 'lon'])),
            distanciaKm: _parseDouble(
              _pick(map, [
                'distanciaenlinearectakm',
                'distancia_linea_recta_km',
                'distanciakm',
                'distancia',
              ]),
            ),
            rango: _pick(map, ['rango', 'rangodistancia']),
            excelRowNumber: i + 1,
          ),
        );
      }

      return RutasExcelParseResult(
        rutas: rutas,
        skippedRows: skipped,
        headerRowNumber: headerIndex + 1,
      );
    } catch (e) {
      return RutasExcelParseResult(
        rutas: const [],
        skippedRows: 0,
        headerRowNumber: 0,
        error: 'Error al procesar Excel de rutas: $e',
      );
    }
  }

  Sheet? _findSheet(Excel excel) {
    for (final entry in excel.tables.entries) {
      final name = _canon(entry.key);
      if (name.contains('ruta') || name.contains('distancia')) {
        return entry.value;
      }
    }
    return excel.tables.isEmpty ? null : excel.tables.values.first;
  }

  int _findHeaderRowIndex(Sheet sheet) {
    var bestIndex = -1;
    var bestScore = -1;
    final limit = sheet.rows.length < 30 ? sheet.rows.length : 30;

    for (var i = 0; i < limit; i++) {
      final normalized = sheet.rows[i]
          .map((c) => _canon(_cellToString(c?.value)))
          .where((v) => v.isNotEmpty)
          .toSet();
      if (normalized.isEmpty) continue;

      var score = 0;
      if (normalized.contains('sede') ||
          normalized.contains('destino') ||
          normalized.contains('parada')) {
        score += 4;
      }
      if (normalized.contains('direccion') ||
          normalized.contains('direccin') ||
          normalized.contains('ubicacion')) {
        score += 4;
      }
      if (normalized.contains('latitud') || normalized.contains('lat')) {
        score += 2;
      }
      if (normalized.contains('longitud') ||
          normalized.contains('lng') ||
          normalized.contains('lon')) {
        score += 2;
      }
      if (normalized.any((h) => h.contains('distancia'))) score += 1;

      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestScore >= 6 ? bestIndex : -1;
  }

  String _pick(Map<String, String> map, List<String> keys) {
    for (final key in keys) {
      final value = map[_canon(key)] ?? '';
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String _cellToString(dynamic value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is DateCellValue) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is FormulaCellValue) return value.formula;
    return value.toString();
  }

  int? _parseInt(String raw) {
    if (raw.trim().isEmpty) return null;
    return int.tryParse(raw.replaceAll(RegExp(r'[^0-9-]'), ''));
  }

  double? _parseDouble(String raw) {
    if (raw.trim().isEmpty) return null;
    var value = raw
        .trim()
        .replaceAll(RegExp(r'[^\d,\.\-]'), '')
        .replaceAll(',', '.');
    if (value.indexOf('.') != value.lastIndexOf('.')) {
      final last = value.lastIndexOf('.');
      value =
          value.substring(0, last).replaceAll('.', '') + value.substring(last);
    }
    return double.tryParse(value);
  }

  String _canon(String input) {
    final lower = input.trim().toLowerCase();
    final repl = lower
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    return repl.replaceAll(RegExp(r'[^a-z0-9_]+'), '');
  }
}

// lib/gestion_documental/planillas/pp_excel_parser.dart
//
// Parser del Excel de planillas de pago.
//
// El Excel debe tener una hoja con al menos estas columnas (nombres flexibles):
//   nombre_planilla / planilla / nombre
//   fecha            / fecha_planilla / fecha_pago
//   valor            / monto          / total
//   archivo_pdf      / pdf            / nombre_archivo  (opcional)
//
// Cualquier columna adicional se almacena en `extras` para cruce posterior.
//
// Estrategia de matching PDF↔Excel en PpMatcher:
//   1. Exacto por nombre de archivo (columna archivo_pdf == nombre del PDF).
//   2. Fuzzy por nombre de planilla: normaliza ambos, calcula similitud simple.
//   3. Por posición si las anteriores fallan y hay igual número de PDFs y filas.
//   4. Sin coincidencia → flag `sin_coincidencia`, requiere conciliación manual.

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import 'pp_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PARSER
// ─────────────────────────────────────────────────────────────────────────────

class PpExcelParser {
  PpExcelParseResult parse(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(_fixNumFmtIds(bytes));
      Sheet? sheet = _findSheet(excel);
      if (sheet == null || sheet.rows.isEmpty) {
        return const PpExcelParseResult(
          filas: [],
          columnas: [],
          error: 'No se encontró hoja válida en el Excel.',
        );
      }

      final headerRowIndex = _findHeaderRowIndex(sheet);
      final sheetTitle = _extractSheetTitle(sheet, headerRowIndex);
      final rawHeaders = sheet.rows[headerRowIndex]
          .map((c) => _cellText(sheet, headerRowIndex, c?.columnIndex ?? 0))
          .toList(growable: false);
      final headers = rawHeaders.map(_normalize).toList(growable: false);

      // Detectar formato Alimentar Capital: encabezados contienen 'cte' y 'aho'
      final isAcFormat = headers.contains('cte') || headers.contains('aho');
      final acConsecutivo = isAcFormat
          ? _extractAcConsecutivo(sheet, headerRowIndex)
          : null;

      final filas = <PpExcelFila>[];
      var omitidas = 0;
      var internalRowIndex = 0;

      for (var i = headerRowIndex + 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.every(
          (c) => _cellText(sheet, i, c?.columnIndex ?? 0).trim().isEmpty,
        )) {
          continue;
        }

        final map = <String, String>{};
        for (var j = 0; j < headers.length; j++) {
          final key = headers[j];
          if (key.isEmpty) continue;
          map[key] = j < row.length ? _cellText(sheet, i, j).trim() : '';
        }

        // Formato AC: el identificador viene de la columna "No" (columna A del Excel).
        // Filas con el mismo valor en "No" → mismo PDF consolidado.
        // Formato estándar: cada fila tiene su propio identificador de planilla.
        final String nombre;
        if (isAcFormat) {
          nombre = map['no'] ?? '';
        } else {
          nombre = _pick(map, [
            'consolidado',
            'planilla',
            'nombre_planilla',
            'n_planilla',
            'numero_planilla',
            'nombre',
          ]);
        }

        final fechaRaw = _pick(map, [
          'fecha_programada',
          'fecha',
          'fecha_planilla',
          'fecha_pago',
          'fecha_banco',
          'fecha_entrega',
          'fecha_de_cargue',
        ]);
        final valorRaw = _pick(map, [
          'valor_a_pagar',
          'valor',
          'monto',
          'total',
          'valor_planilla',
        ]);
        final archivoPdf = _pick(map, [
          'archivo_pdf',
          'pdf',
          'nombre_archivo',
          'archivo',
        ]);

        if (nombre.isEmpty && archivoPdf.isEmpty) {
          omitidas++;
          continue;
        }

        final extras = Map<String, String>.from(map)
          ..remove('no')
          ..remove('consolidado')
          ..remove('nombre_planilla')
          ..remove('planilla')
          ..remove('n_planilla')
          ..remove('numero_planilla')
          ..remove('nombre')
          ..remove('fecha')
          ..remove('fecha_planilla')
          ..remove('fecha_pago')
          ..remove('fecha_entrega')
          ..remove('fecha_de_cargue')
          ..remove('valor')
          ..remove('monto')
          ..remove('total')
          ..remove('valor_planilla')
          ..remove('archivo_pdf')
          ..remove('pdf')
          ..remove('nombre_archivo')
          ..remove('archivo');

        // Normalizar revisado_* → revisado
        final revisadoKey = extras.keys.firstWhere(
          (k) => k.startsWith('revisado') && k != 'revisado',
          orElse: () => '',
        );
        if (revisadoKey.isNotEmpty && !extras.containsKey('revisado')) {
          extras['revisado'] = extras[revisadoKey]!;
          extras.remove(revisadoKey);
        }

        // Normalizar n_factura_* → no_factura_orden_de_compra
        if (!extras.containsKey('no_factura_orden_de_compra') &&
            extras.containsKey('n_factura_orden_de_compra')) {
          extras['no_factura_orden_de_compra'] =
              extras['n_factura_orden_de_compra']!;
          extras.remove('n_factura_orden_de_compra');
        }
        // Normalizar n_cuenta → no_cuenta
        if (!extras.containsKey('no_cuenta') &&
            extras.containsKey('n_cuenta')) {
          extras['no_cuenta'] = extras['n_cuenta']!;
          extras.remove('n_cuenta');
        }

        filas.add(
          PpExcelFila(
            rowIndex: internalRowIndex++,
            excelRowNumber: i + 1,
            nombrePlanilla: nombre.isEmpty ? null : nombre,
            fecha: _parseDate(fechaRaw),
            valor: _parseDouble(valorRaw),
            nombreArchivoPdf: archivoPdf.isEmpty ? null : archivoPdf,
            extras: extras,
          ),
        );
      }

      return PpExcelParseResult(
        filas: filas,
        columnas: rawHeaders.where((h) => h.isNotEmpty).toList(),
        headerRowNumber: headerRowIndex + 1,
        filasOmitidas: omitidas,
        sheetTitle: isAcFormat ? sheetTitle : null,
        acConsecutivo: acConsecutivo,
      );
    } catch (e) {
      return PpExcelParseResult(
        filas: [],
        columnas: [],
        error: 'Error al procesar Excel: $e',
      );
    }
  }

  Sheet? _findSheet(Excel excel) {
    // Preferir hojas con nombres relacionados a planillas/pago
    const preferred = [
      'planillas',
      'pago',
      'planillas_pago',
      'consolidado',
      'hoja1',
      'sheet1',
      'data',
    ];
    for (final name in preferred) {
      final key = excel.tables.keys.firstWhere(
        (k) => _normalize(k).contains(name),
        orElse: () => '',
      );
      if (key.isNotEmpty) return excel.tables[key];
    }
    // Fallback: primera hoja disponible
    if (excel.tables.isNotEmpty) return excel.tables.values.first;
    return null;
  }

  int _findHeaderRowIndex(Sheet sheet) {
    var bestIndex = 0;
    var bestScore = -1;
    final limit = sheet.rows.length < 30 ? sheet.rows.length : 30;

    for (var rowIndex = 0; rowIndex < limit; rowIndex++) {
      final normalized = sheet.rows[rowIndex]
          .map(
            (c) => _normalize(_cellText(sheet, rowIndex, c?.columnIndex ?? 0)),
          )
          .where((v) => v.isNotEmpty)
          .toSet();
      if (normalized.isEmpty) {
        continue;
      }

      var score = 0;
      if (normalized.contains('planilla') ||
          normalized.contains('consolidado')) {
        score += 3;
      }
      if (normalized.contains('valor_a_pagar') ||
          normalized.contains('valor')) {
        score += 3;
      }
      if (normalized.contains('fecha_programada') ||
          normalized.contains('fecha')) {
        score += 2;
      }
      if (normalized.contains('proveedor')) score += 2;
      if (normalized.contains('banco')) score += 1;
      // Alimentar Capital format indicators
      if (normalized.contains('nit')) score += 2;
      if (normalized.contains('dv')) score += 1;
      if (normalized.contains('cte') || normalized.contains('aho')) score += 1;

      if (score > bestScore) {
        bestScore = score;
        bestIndex = rowIndex;
      }
    }

    return bestIndex;
  }

  /// Extrae el título del bloque de portada (filas antes del encabezado).
  /// Busca la primera celda con texto en mayúsculas de más de 5 caracteres.
  String? _extractSheetTitle(Sheet sheet, int headerRowIndex) {
    for (var i = 0; i < headerRowIndex; i++) {
      final row = sheet.rows[i];
      for (var j = 0; j < row.length; j++) {
        final text = _cellText(sheet, i, j).trim();
        if (text.length > 5 &&
            text == text.toUpperCase() &&
            RegExp(r'[A-Z]{2}').hasMatch(text) &&
            !RegExp(r'^\d').hasMatch(text)) {
          return text;
        }
      }
    }
    return null;
  }

  /// Extrae el N° CONSECUTIVO del bloque de portada buscando una celda que
  /// contenga "CONSECUTIVO" y retornando el valor numérico en celdas adyacentes.
  String? _extractAcConsecutivo(Sheet sheet, int headerRowIndex) {
    for (var i = 0; i < headerRowIndex; i++) {
      final row = sheet.rows[i];
      for (var j = 0; j < row.length; j++) {
        final text = _cellText(sheet, i, j).trim().toUpperCase();
        if (text.contains('CONSECUTIVO')) {
          // Buscar el primer valor no vacío a la derecha en la misma fila
          for (var k = j + 1; k < row.length && k < j + 6; k++) {
            final val = _cellText(sheet, i, k).trim();
            if (val.isNotEmpty) return val;
          }
        }
      }
    }
    return null;
  }

  String _pick(Map<String, String> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAllMapped(RegExp(r'[áéíóú\s\-]'), (m) {
        const map = {
          'á': 'a',
          'é': 'e',
          'í': 'i',
          'ó': 'o',
          'ú': 'u',
          ' ': '_',
          '-': '_',
        };
        return map[m.group(0)!] ?? m.group(0)!;
      })
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');

  String _cellText(Sheet sheet, int rowIndex, int colIndex) {
    final rows = sheet.rows;
    if (rowIndex < 0 || rowIndex >= rows.length) return '';
    final row = rows[rowIndex];
    if (colIndex < 0 || colIndex >= row.length) return '';
    return _cellStr(sheet, rowIndex, colIndex, row[colIndex]?.value);
  }

  String _cellStr(Sheet sheet, int rowIndex, int colIndex, dynamic value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is DateCellValue) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is FormulaCellValue) {
      final evaluated = _evaluateFormulaCell(sheet, rowIndex, colIndex, {});
      if (evaluated != null) {
        return evaluated.toString();
      }
      return value.formula;
    }
    return value.toString();
  }

  String? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    // ISO format
    final iso = RegExp(r'^(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})$');
    var m = iso.firstMatch(raw.trim());
    if (m != null) {
      return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
    }
    // DD/MM/YYYY
    final dmy = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$');
    m = dmy.firstMatch(raw.trim());
    if (m != null) {
      return '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
    }
    return raw.trim(); // devolver tal cual si no se reconoce el formato
  }

  double? _parseDouble(String raw) {
    if (raw.isEmpty) return null;
    final normalizedRaw = raw.trim();
    final cleaned = normalizedRaw.replaceAll(RegExp(r'[\$\s]'), '');
    // Manejar separadores colombianos (1.234.567,89 → 1234567.89)
    final colonFormat = RegExp(r'^[\d.]+,\d{2}$');
    if (colonFormat.hasMatch(normalizedRaw)) {
      final normalized = normalizedRaw.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    final standard = cleaned.replaceAll(',', '');
    return double.tryParse(standard);
  }

  double? _evaluateFormulaCell(
    Sheet sheet,
    int rowIndex,
    int colIndex,
    Map<String, double?> cache,
  ) {
    final key = '$rowIndex:$colIndex';
    if (cache.containsKey(key)) return cache[key];
    cache[key] = null;

    final rows = sheet.rows;
    if (rowIndex < 0 || rowIndex >= rows.length) return null;
    final row = rows[rowIndex];
    if (colIndex < 0 || colIndex >= row.length) return null;

    final value = row[colIndex]?.value;
    if (value is IntCellValue) return cache[key] = value.value.toDouble();
    if (value is DoubleCellValue) return cache[key] = value.value;
    if (value is TextCellValue) {
      return cache[key] = _parseDouble(value.value.toString());
    }
    if (value is FormulaCellValue) {
      final expression = value.formula
          .replaceFirst('=', '')
          .replaceFirst('+', '')
          .trim();
      final resolved = expression.replaceAllMapped(
        RegExp(r'\$?([A-Z]+)\$?(\d+)'),
        (match) {
          final colRef = _columnNameToIndex(match.group(1)!);
          final rowRef = int.tryParse(match.group(2) ?? '') ?? 0;
          final cellValue =
              _evaluateFormulaCell(sheet, rowRef - 1, colRef, cache) ?? 0;
          return cellValue.toString();
        },
      );
      if (!RegExp(r'^[0-9\.\+\-\*\/\(\)\s]+$').hasMatch(resolved)) return null;
      return cache[key] = _evaluateArithmetic(resolved);
    }
    return null;
  }

  int _columnNameToIndex(String columnName) {
    var result = 0;
    for (final codeUnit in columnName.codeUnits) {
      result = result * 26 + (codeUnit - 64);
    }
    return result - 1;
  }

  double? _evaluateArithmetic(String input) {
    final parser = _SimpleExpressionParser(input);
    return parser.parse();
  }

  // El paquete excel 4.x exige numFmtId >= 164 para formatos custom.
  // Algunos archivos Excel usan IDs < 164 para custom formats (válido en OOXML
  // pero no tolerado por la librería). Este método remapea esos IDs antes de parsear.
  Uint8List _fixNumFmtIds(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final stylesEntry = archive.findFile('xl/styles.xml');
      if (stylesEntry == null) return bytes;

      var xml = utf8.decode(stylesEntry.content as List<int>);

      // Recolectar IDs custom (< 164) definidos en <numFmt numFmtId="N" ...>
      final defPattern = RegExp(r'<numFmt\b[^>]*\bnumFmtId="(\d+)"');
      final idsToRemap = <int>{};
      for (final m in defPattern.allMatches(xml)) {
        final id = int.tryParse(m.group(1) ?? '') ?? 0;
        if (id < 164) idsToRemap.add(id);
      }
      if (idsToRemap.isEmpty) return bytes;

      // Asignar nuevos IDs desde 500 para evitar colisiones
      var next = 500;
      final remap = <int, int>{};
      for (final id in idsToRemap) {
        remap[id] = next++;
      }

      // Reemplazar todos los numFmtId="N" → numFmtId="N_nuevo" en styles.xml
      xml = xml.replaceAllMapped(RegExp(r'numFmtId="(\d+)"'), (m) {
        final id = int.tryParse(m.group(1) ?? '') ?? -1;
        return 'numFmtId="${remap[id] ?? id}"';
      });

      // Reconstruir ZIP con styles.xml parcheado
      final newArchive = Archive();
      for (final file in archive) {
        if (file.name == 'xl/styles.xml') {
          final encoded = utf8.encode(xml);
          newArchive.addFile(
            ArchiveFile('xl/styles.xml', encoded.length, encoded),
          );
        } else {
          newArchive.addFile(file);
        }
      }
      final reencoded = ZipEncoder().encode(newArchive);
      if (reencoded != null) return Uint8List.fromList(reencoded);
    } catch (_) {}
    return bytes;
  }
}

class _SimpleExpressionParser {
  final String source;
  int _index = 0;

  _SimpleExpressionParser(String source) : source = source.replaceAll(' ', '');

  double? parse() {
    if (source.isEmpty) return null;
    final value = _parseExpression();
    if (value == null || _index != source.length) return null;
    return value;
  }

  double? _parseExpression() {
    var value = _parseTerm();
    while (value != null && _index < source.length) {
      final op = source[_index];
      if (op != '+' && op != '-') break;
      _index++;
      final rhs = _parseTerm();
      if (rhs == null) return null;
      value = op == '+' ? value + rhs : value - rhs;
    }
    return value;
  }

  double? _parseTerm() {
    var value = _parseFactor();
    while (value != null && _index < source.length) {
      final op = source[_index];
      if (op != '*' && op != '/') break;
      _index++;
      final rhs = _parseFactor();
      if (rhs == null) return null;
      value = op == '*' ? value * rhs : value / rhs;
    }
    return value;
  }

  double? _parseFactor() {
    if (_index >= source.length) return null;
    if (source[_index] == '+') {
      _index++;
      return _parseFactor();
    }
    if (source[_index] == '-') {
      _index++;
      final value = _parseFactor();
      return value == null ? null : -value;
    }
    if (source[_index] == '(') {
      _index++;
      final value = _parseExpression();
      if (_index >= source.length || source[_index] != ')') return null;
      _index++;
      return value;
    }

    final start = _index;
    while (_index < source.length &&
        RegExp(r'[0-9.]').hasMatch(source[_index])) {
      _index++;
    }
    if (start == _index) return null;
    return double.tryParse(source.substring(start, _index));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MATCHER PDF ↔ FILA EXCEL
// ─────────────────────────────────────────────────────────────────────────────

class PpMatcher {
  /// Recibe la lista de nombres de archivos PDF y las filas del Excel.
  /// Retorna un resultado de matching por cada PDF.
  /// Las filas sin PDF correspondiente se incluyen en [filasHuerfanas].
  static ({List<PpMatchResult> matches, List<PpExcelFila> filasHuerfanas})
  match({required List<String> pdfNombres, required List<PpExcelFila> filas}) {
    final usedRowIndices = <int>{};
    final matches = <PpMatchResult>[];

    for (final pdf in pdfNombres) {
      // 1. Exacto por nombre de archivo en columna archivo_pdf
      final exactoIdx = filas.indexWhere(
        (f) =>
            !usedRowIndices.contains(f.rowIndex) &&
            f.nombreArchivoPdf != null &&
            _normalizeFilename(f.nombreArchivoPdf!) == _normalizeFilename(pdf),
      );
      if (exactoIdx >= 0) {
        usedRowIndices.add(filas[exactoIdx].rowIndex);
        matches.add(
          PpMatchResult(
            pdfNombre: pdf,
            filaExcel: filas[exactoIdx],
            matchEstado: PpMatchEstado.coincidencia_exacta,
            score: 1.0,
          ),
        );
        continue;
      }

      // 2. Fuzzy por nombre de planilla
      PpExcelFila? mejorFila;
      double mejorScore = 0;
      for (final fila in filas) {
        if (usedRowIndices.contains(fila.rowIndex)) continue;
        if (fila.nombrePlanilla == null) continue;
        final score = _similarity(
          _normalizeFilename(pdf),
          _normalizeFilename(fila.nombrePlanilla!),
        );
        if (score > mejorScore) {
          mejorScore = score;
          mejorFila = fila;
        }
      }

      if (mejorFila != null && mejorScore >= 0.6) {
        usedRowIndices.add(mejorFila.rowIndex);
        matches.add(
          PpMatchResult(
            pdfNombre: pdf,
            filaExcel: mejorFila,
            matchEstado: PpMatchEstado.coincidencia_parcial,
            score: mejorScore,
          ),
        );
        continue;
      }

      // 3. Sin coincidencia
      matches.add(
        PpMatchResult(
          pdfNombre: pdf,
          filaExcel: null,
          matchEstado: PpMatchEstado.sin_coincidencia,
        ),
      );
    }

    // 4. Posicional como último recurso: si hay PDFs sin match y filas sin asignar
    final sinMatchIndices = matches
        .asMap()
        .entries
        .where((e) => e.value.matchEstado == PpMatchEstado.sin_coincidencia)
        .map((e) => e.key)
        .toList();
    final filasLibres = filas
        .where((f) => !usedRowIndices.contains(f.rowIndex))
        .toList();

    if (sinMatchIndices.length == filasLibres.length &&
        sinMatchIndices.isNotEmpty) {
      for (var i = 0; i < sinMatchIndices.length; i++) {
        final idx = sinMatchIndices[i];
        usedRowIndices.add(filasLibres[i].rowIndex);
        matches[idx] = PpMatchResult(
          pdfNombre: matches[idx].pdfNombre,
          filaExcel: filasLibres[i],
          matchEstado: PpMatchEstado.coincidencia_parcial,
          score: 0.3,
        );
      }
    }

    // Filas huérfanas (sin PDF)
    final filasHuerfanas = filas
        .where((f) => !usedRowIndices.contains(f.rowIndex))
        .toList();

    return (matches: matches, filasHuerfanas: filasHuerfanas);
  }

  static String _normalizeFilename(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\.pdf$'), '')
      .replaceAll(RegExp(r'[\s_\-]'), '');

  /// Similitud simple basada en bigramas (Dice coefficient).
  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.length < 2 || b.length < 2) return 0.0;
    final biA = _bigrams(a);
    final biB = _bigrams(b);
    final intersection = biA.where((bg) => biB.contains(bg)).length;
    return 2 * intersection / (biA.length + biB.length);
  }

  static List<String> _bigrams(String s) {
    final result = <String>[];
    for (var i = 0; i < s.length - 1; i++) {
      result.add(s.substring(i, i + 2));
    }
    return result;
  }
}

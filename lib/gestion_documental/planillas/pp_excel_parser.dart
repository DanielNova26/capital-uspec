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
        return const PpExcelParseResult(filas: [], columnas: [], error: 'No se encontró hoja válida en el Excel.');
      }

      final rawHeaders = sheet.rows.first
          .map((c) => _cellStr(c?.value))
          .toList(growable: false);
      final headers = rawHeaders.map(_normalize).toList(growable: false);

      final filas = <PpExcelFila>[];
      var omitidas = 0;

      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.every((c) => _cellStr(c?.value).trim().isEmpty)) continue;

        final map = <String, String>{};
        for (var j = 0; j < headers.length; j++) {
          final key = headers[j];
          if (key.isEmpty) continue;
          map[key] = j < row.length ? _cellStr(row[j]?.value).trim() : '';
        }

        final nombre = _pick(map, ['nombre_planilla', 'planilla', 'nombre']);
        final fechaRaw = _pick(map, ['fecha', 'fecha_planilla', 'fecha_pago']);
        final valorRaw = _pick(map, ['valor', 'monto', 'total', 'valor_planilla']);
        final archivoPdf = _pick(map, ['archivo_pdf', 'pdf', 'nombre_archivo', 'archivo']);

        if (nombre.isEmpty && archivoPdf.isEmpty) {
          omitidas++;
          continue;
        }

        final extras = Map<String, String>.from(map)
          ..remove('nombre_planilla')
          ..remove('planilla')
          ..remove('nombre')
          ..remove('fecha')
          ..remove('fecha_planilla')
          ..remove('fecha_pago')
          ..remove('valor')
          ..remove('monto')
          ..remove('total')
          ..remove('valor_planilla')
          ..remove('archivo_pdf')
          ..remove('pdf')
          ..remove('nombre_archivo')
          ..remove('archivo');

        filas.add(PpExcelFila(
          rowIndex: i - 1,
          nombrePlanilla: nombre.isEmpty ? null : nombre,
          fecha: _parseDate(fechaRaw),
          valor: _parseDouble(valorRaw),
          nombreArchivoPdf: archivoPdf.isEmpty ? null : archivoPdf,
          extras: extras,
        ));
      }

      return PpExcelParseResult(
        filas: filas,
        columnas: rawHeaders.where((h) => h.isNotEmpty).toList(),
        filasOmitidas: omitidas,
      );
    } catch (e) {
      return PpExcelParseResult(filas: [], columnas: [], error: 'Error al procesar Excel: $e');
    }
  }

  Sheet? _findSheet(Excel excel) {
    // Preferir hojas con nombres relacionados a planillas/pago
    const preferred = ['planillas', 'pago', 'planillas_pago', 'hoja1', 'sheet1', 'data'];
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

  String _pick(Map<String, String> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  String _normalize(String s) => s.toLowerCase()
      .replaceAllMapped(RegExp(r'[áéíóú\s\-]'), (m) {
        const map = {'á':'a','é':'e','í':'i','ó':'o','ú':'u',' ':'_','-':'_'};
        return map[m.group(0)!] ?? m.group(0)!;
      })
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');

  String _cellStr(dynamic value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is DateCellValue) return '${value.year}-${value.month.toString().padLeft(2,'0')}-${value.day.toString().padLeft(2,'0')}';
    return value.toString();
  }

  String? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    // ISO format
    final iso = RegExp(r'^(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})$');
    var m = iso.firstMatch(raw.trim());
    if (m != null) {
      return '${m.group(1)}-${m.group(2)!.padLeft(2,'0')}-${m.group(3)!.padLeft(2,'0')}';
    }
    // DD/MM/YYYY
    final dmy = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$');
    m = dmy.firstMatch(raw.trim());
    if (m != null) {
      return '${m.group(3)}-${m.group(2)!.padLeft(2,'0')}-${m.group(1)!.padLeft(2,'0')}';
    }
    return raw.trim(); // devolver tal cual si no se reconoce el formato
  }

  double? _parseDouble(String raw) {
    if (raw.isEmpty) return null;
    final cleaned = raw.replaceAll(RegExp(r'[\$,\.]'), '').replaceAll(',', '.');
    // Manejar separadores colombianos (1.234.567,89 → 1234567.89)
    final colonFormat = RegExp(r'^[\d.]+,\d{2}$');
    if (colonFormat.hasMatch(raw.trim())) {
      final normalized = raw.trim().replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return double.tryParse(cleaned);
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
      xml = xml.replaceAllMapped(
        RegExp(r'numFmtId="(\d+)"'),
        (m) {
          final id = int.tryParse(m.group(1) ?? '') ?? -1;
          return 'numFmtId="${remap[id] ?? id}"';
        },
      );

      // Reconstruir ZIP con styles.xml parcheado
      final newArchive = Archive();
      for (final file in archive) {
        if (file.name == 'xl/styles.xml') {
          final encoded = utf8.encode(xml);
          newArchive.addFile(ArchiveFile('xl/styles.xml', encoded.length, encoded));
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

// ─────────────────────────────────────────────────────────────────────────────
// MATCHER PDF ↔ FILA EXCEL
// ─────────────────────────────────────────────────────────────────────────────

class PpMatcher {
  /// Recibe la lista de nombres de archivos PDF y las filas del Excel.
  /// Retorna un resultado de matching por cada PDF.
  /// Las filas sin PDF correspondiente se incluyen en [filasHuerfanas].
  static ({
    List<PpMatchResult> matches,
    List<PpExcelFila> filasHuerfanas,
  }) match({
    required List<String> pdfNombres,
    required List<PpExcelFila> filas,
  }) {
    final usedRowIndices = <int>{};
    final matches = <PpMatchResult>[];

    for (final pdf in pdfNombres) {
      // 1. Exacto por nombre de archivo en columna archivo_pdf
      final exactoIdx = filas.indexWhere(
        (f) => !usedRowIndices.contains(f.rowIndex) &&
               f.nombreArchivoPdf != null &&
               _normalizeFilename(f.nombreArchivoPdf!) == _normalizeFilename(pdf),
      );
      if (exactoIdx >= 0) {
        usedRowIndices.add(filas[exactoIdx].rowIndex);
        matches.add(PpMatchResult(
          pdfNombre: pdf,
          filaExcel: filas[exactoIdx],
          matchEstado: PpMatchEstado.coincidencia_exacta,
          score: 1.0,
        ));
        continue;
      }

      // 2. Fuzzy por nombre de planilla
      PpExcelFila? mejorFila;
      double mejorScore = 0;
      for (final fila in filas) {
        if (usedRowIndices.contains(fila.rowIndex)) continue;
        if (fila.nombrePlanilla == null) continue;
        final score = _similarity(_normalizeFilename(pdf), _normalizeFilename(fila.nombrePlanilla!));
        if (score > mejorScore) {
          mejorScore = score;
          mejorFila = fila;
        }
      }

      if (mejorFila != null && mejorScore >= 0.6) {
        usedRowIndices.add(mejorFila.rowIndex);
        matches.add(PpMatchResult(
          pdfNombre: pdf,
          filaExcel: mejorFila,
          matchEstado: PpMatchEstado.coincidencia_parcial,
          score: mejorScore,
        ));
        continue;
      }

      // 3. Sin coincidencia
      matches.add(PpMatchResult(
        pdfNombre: pdf,
        filaExcel: null,
        matchEstado: PpMatchEstado.sin_coincidencia,
      ));
    }

    // 4. Posicional como último recurso: si hay PDFs sin match y filas sin asignar
    final sinMatchIndices = matches
        .asMap()
        .entries
        .where((e) => e.value.matchEstado == PpMatchEstado.sin_coincidencia)
        .map((e) => e.key)
        .toList();
    final filasLibres = filas.where((f) => !usedRowIndices.contains(f.rowIndex)).toList();

    if (sinMatchIndices.length == filasLibres.length && sinMatchIndices.isNotEmpty) {
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
    final filasHuerfanas = filas.where((f) => !usedRowIndices.contains(f.rowIndex)).toList();

    return (matches: matches, filasHuerfanas: filasHuerfanas);
  }

  static String _normalizeFilename(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\.pdf$'), '').replaceAll(RegExp(r'[\s_\-]'), '');

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

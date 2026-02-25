import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:todo/compras/compras_req_engine.dart';

class ComprasReqExcelParseResult {
  final List<ReqDocumentoDoc> docs;
  final int skippedRows;

  const ComprasReqExcelParseResult({
    required this.docs,
    required this.skippedRows,
  });
}

/// Parser para la hoja REQ_DOCUMENTOS de la parametrización de Compras.
class ComprasReqExcelParser {
  ComprasReqExcelParseResult parse({
    required Uint8List bytes,
    required String empresaId,
  }) {
    final excel = Excel.decodeBytes(bytes);

    Sheet? sheet = excel.tables['REQ_DOCUMENTOS'];
    sheet ??= _findReqSheet(excel);
    if (sheet == null || sheet.rows.isEmpty) {
      return const ComprasReqExcelParseResult(docs: [], skippedRows: 0);
    }

    final headers = sheet.rows.first
        .map((c) => _canon(_cellToString(c?.value)))
        .toList(growable: false);

    final docs = <ReqDocumentoDoc>[];
    var skipped = 0;

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final isBlank = row.every((c) => _cellToString(c?.value).trim().isEmpty);
      if (isBlank) continue;

      final map = <String, String>{};
      for (var j = 0; j < headers.length; j++) {
        final key = headers[j];
        if (key.isEmpty) continue;
        final value = j < row.length ? _cellToString(row[j]?.value).trim() : '';
        map[key] = value;
      }

      final keyApp = _pick(map, ['keyapp', 'key_app']);
      final nivel = _pick(map, ['nivel']);
      final etapa = _pick(map, ['etapa']);
      final categoriaApp = _pick(map, ['categoriaapp', 'categoria_app']);

      if (keyApp.isEmpty || nivel.isEmpty || etapa.isEmpty || categoriaApp.isEmpty) {
        skipped++;
        continue;
      }

      docs.add(ReqDocumentoDoc(
        empresaId: empresaId,
        categoriaApp: categoriaApp,
        materiaPrima: _pick(map, ['materiaprima', 'materia_prima']),
        origen: _pick(map, ['origen'], fallback: 'AMBOS').toUpperCase(),
        nivel: nivel.toUpperCase(),
        etapa: etapa.toUpperCase(),
        codDoc: _pick(map, ['coddoc', 'cod_doc']),
        keyApp: keyApp,
        documentoRequerido: _pick(map, ['documentorequerido', 'documento_requerido']),
        obligatorio: _pick(map, ['obligatorio'], fallback: 'SI').toUpperCase(),
        condicion: _pick(map, ['condicion', 'condición']),
        norma: _pick(map, ['norma']),
        entidad: _pick(map, ['entidad']),
        frecuencia: _pick(map, ['frecuencia']),
        observaciones: _pick(map, ['observaciones']),
        activo: true,
      ));
    }

    return ComprasReqExcelParseResult(docs: docs, skippedRows: skipped);
  }

  Sheet? _findReqSheet(Excel excel) {
    for (final entry in excel.tables.entries) {
      final n = _canon(entry.key);
      if (n == 'reqdocumentos' || n == 'req_documentos') return entry.value;
    }
    return null;
  }

  String _pick(Map<String, String> map, List<String> keys, {String fallback = ''}) {
    for (final k in keys) {
      final v = map[_canon(k)] ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    }
    return fallback;
  }

  String _cellToString(dynamic v) => v?.toString() ?? '';

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

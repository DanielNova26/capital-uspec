import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:todo/compras/compras_models.dart';

class ComprasProductosExcelParseResult {
  final List<ProductoDoc> productos;
  final int skippedRows;

  const ComprasProductosExcelParseResult({
    required this.productos,
    required this.skippedRows,
  });
}

/// Parser para el maestro inicial de productos.
/// Columnas esperadas: CODIGO_PRODUCTO, NOMBRE_PRODUCTO, CATEGORIA,
/// UNIDAD_MEDIDA, ORIGEN (NACIONAL/IMPORTADO), PERECEDERO (SI/NO)
class ComprasProductosExcelParser {
  ComprasProductosExcelParseResult parse({
    required Uint8List bytes,
    required String empresaId,
    required List<String> categoriasValidas,
    required List<String> unidadesValidas,
  }) {
    final excel = Excel.decodeBytes(bytes);

    Sheet? sheet = _findSheet(excel);
    if (sheet == null || sheet.rows.isEmpty) {
      return const ComprasProductosExcelParseResult(
          productos: [], skippedRows: 0);
    }

    final headers = sheet.rows.first
        .map((c) => _canon(_cellToString(c?.value)))
        .toList(growable: false);

    final productos = <ProductoDoc>[];
    var skipped = 0;

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final isBlank =
          row.every((c) => _cellToString(c?.value).trim().isEmpty);
      if (isBlank) continue;

      final map = <String, String>{};
      for (var j = 0; j < headers.length; j++) {
        final key = headers[j];
        if (key.isEmpty) continue;
        final value =
            j < row.length ? _cellToString(row[j]?.value).trim() : '';
        map[key] = value;
      }

      final nombre = _pick(
          map, ['nombreproducto', 'nombre_producto', 'nombre', 'product']);
      if (nombre.isEmpty) {
        skipped++;
        continue;
      }

      final codigo =
          _pick(map, ['codigoproducto', 'codigo_producto', 'codigo', 'code']);

      // Categoria: buscar coincidencia accent-insensitive
      final categoriaRaw =
          _pick(map, ['categoria', 'category', 'categoría']);
      final categoria = _matchList(categoriaRaw, categoriasValidas);

      // Unidad de medida: buscar coincidencia accent-insensitive
      final unidadRaw =
          _pick(map, ['unidadmedida', 'unidad_medida', 'unidad', 'um']);
      final unidadMedida = _matchList(unidadRaw, unidadesValidas);

      if (categoria.isEmpty || unidadMedida.isEmpty) {
        skipped++;
        continue;
      }

      final origenRaw =
          _pick(map, ['origen', 'origin']).toUpperCase().trim();
      final origen =
          (origenRaw == 'IMPORTADO') ? 'IMPORTADO' : 'NACIONAL';

      final perecederoRaw =
          _pick(map, ['perecedero', 'esPerecedero']).toUpperCase().trim();
      final esPerecedero =
          perecederoRaw == 'SI' || perecederoRaw == 'S' || perecederoRaw == '1';

      productos.add(ProductoDoc(
        empresaId: empresaId,
        codigo: codigo,
        nombre: nombre,
        unidadMedida: unidadMedida,
        categoria: categoria,
        esPerecedero: esPerecedero,
        origen: origen,
        createdAt: Timestamp.now(),
      ));
    }

    return ComprasProductosExcelParseResult(
      productos: productos,
      skippedRows: skipped,
    );
  }

  /// Busca el valor en la lista usando comparación accent-insensitive.
  /// Devuelve el valor canónico de la lista (con tildes correctas) o ''.
  String _matchList(String raw, List<String> list) {
    if (raw.isEmpty) return '';
    final rawCanon = _canon(raw);
    for (final item in list) {
      if (_canon(item) == rawCanon) return item;
    }
    return '';
  }

  Sheet? _findSheet(Excel excel) {
    for (final entry in excel.tables.entries) {
      final n = _canon(entry.key);
      if (n == 'productos' || n == 'maestroproductos' ||
          n == 'maestro_productos' || n == 'listadoproductos') {
        return entry.value;
      }
    }
    return excel.tables.values.isNotEmpty ? excel.tables.values.first : null;
  }

  String _pick(Map<String, String> map, List<String> keys,
      {String fallback = ''}) {
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

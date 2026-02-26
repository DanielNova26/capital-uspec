import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:todo/compras/compras_models.dart';

class ComprasProveedoresExcelParseResult {
  final List<ProveedorDoc> proveedores;
  final int skippedRows;

  const ComprasProveedoresExcelParseResult({
    required this.proveedores,
    required this.skippedRows,
  });
}

/// Parser para el maestro inicial de proveedores.
/// Columnas esperadas: NIT, RAZON SOCIAL, DIRECCION, TELEFONO, CORREO,
/// DEPARTAMENTO, CIUDAD, PROV. LOCAL
class ComprasProveedoresExcelParser {
  ComprasProveedoresExcelParseResult parse({
    required Uint8List bytes,
    required String empresaId,
  }) {
    final excel = Excel.decodeBytes(bytes);

    // Busca la hoja PROVEEDORES o usa la primera disponible
    Sheet? sheet = _findSheet(excel);
    if (sheet == null || sheet.rows.isEmpty) {
      return const ComprasProveedoresExcelParseResult(
          proveedores: [], skippedRows: 0);
    }

    final headers = sheet.rows.first
        .map((c) => _canon(_cellToString(c?.value)))
        .toList(growable: false);

    final proveedores = <ProveedorDoc>[];
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

      final nit = _pick(map, ['nit']);
      final razonSocial =
          _pick(map, ['razonsocial', 'razon_social', 'razonsocial']);

      if (nit.isEmpty || razonSocial.isEmpty) {
        skipped++;
        continue;
      }

      final esLocalRaw =
          _pick(map, ['provlocal', 'prov_local', 'provlocal', 'eslocal'])
              .toUpperCase();
      final esLocal = esLocalRaw == 'SI' || esLocalRaw == 'S';

      proveedores.add(ProveedorDoc(
        empresaId: empresaId,
        nit: nit,
        razonSocial: razonSocial,
        direccion: _pick(map, ['direccion']),
        telefono: _pick(map, ['telefono']),
        email: _pick(map, ['correo', 'email', 'correoelectronico']).toLowerCase(),
        departamento: _pick(map, ['departamento']),
        ciudad: _pick(map, ['ciudad']),
        esLocal: esLocal,
        categorias: const [],
        documentos: const {},
        createdAt: Timestamp.now(),
      ));
    }

    return ComprasProveedoresExcelParseResult(
      proveedores: proveedores,
      skippedRows: skipped,
    );
  }

  Sheet? _findSheet(Excel excel) {
    // Intenta nombre exacto o canonicalizado
    for (final entry in excel.tables.entries) {
      final n = _canon(entry.key);
      if (n == 'proveedores' || n == 'maestroproveedores' ||
          n == 'maestro_proveedores') {
        return entry.value;
      }
    }
    // Fallback: primera hoja
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

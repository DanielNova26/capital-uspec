// lib/bootstrap/static_excel_catalogs_seed.dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class StaticExcelCatalogsSeed {
  final _db = FirebaseFirestore.instance;

  /// Cambia este valor si actualizas el Excel y quieres reseed una sola vez.
  static const int _seedVersion = 2;

  Future<void> runIfNotSeeded({String assetsPath = 'assets/seeds/catalogos_base.xlsx'}) async {
    final seeded = await _alreadySeeded();
    if (seeded) return;
    await _seedFromExcel(assetsPath: assetsPath);
    await _markSeeded();
  }

  /// Fuerza la siembra aunque ya se haya ejecutado antes.
  Future<void> runForce({String assetsPath = 'assets/seeds/catalogos_base.xlsx'}) async {
    await _seedFromExcel(assetsPath: assetsPath);
    await _markSeeded();
  }

  Future<bool> _alreadySeeded() async {
    final doc = await _db.collection('TBL_CONFIG').doc('STATIC_SEEDS').get();
    final data = doc.data();
    if (data == null) return false;
    final bool catalogsSeeded = data['catalogsSeeded'] == true;
    final int version = (data['version'] is int) ? data['version'] as int : 0;
    return catalogsSeeded && version >= _seedVersion;
  }

  Future<void> _markSeeded() async {
    await _db.collection('TBL_CONFIG').doc('STATIC_SEEDS').set({
      'catalogsSeeded': true,
      'source': 'assets/seeds/catalogos_base.xlsx',
      'seededAt': FieldValue.serverTimestamp(),
      'version': _seedVersion,
    }, SetOptions(merge: true));
  }

  Future<void> _seedFromExcel({required String assetsPath}) async {
    final byteData = await rootBundle.load(assetsPath);
    final bytes = byteData.buffer.asUint8List();
    final excel = Excel.decodeBytes(bytes);

    final depRows = _readSheet(excel, 'DEPARTAMENTOS');
    final ciuRows = _readSheet(excel, 'CIUDADES');
    final tipRows = _readSheet(excel, 'TIPO_DOCUMENTO');

    await _seedDepartamentos(depRows);
    await _seedCiudades(ciuRows);
    await _seedTiposDocumento(tipRows);
  }

  List<Map<String, dynamic>> _readSheet(Excel excel, String name) {
    final sheet = excel.tables[name];
    if (sheet == null || sheet.maxRows < 2) return [];

    final headerRow = sheet.rows.first;
    final keys = <String>[];
    for (final cell in headerRow) {
      keys.add(_cellToString(cell?.value));
    }

    final out = <Map<String, dynamic>>[];
    for (int r = 1; r < sheet.maxRows; r++) {
      final row = sheet.rows[r];
      if (row.every((c) => _cellToString(c?.value).isEmpty)) continue;

      final m = <String, dynamic>{};
      for (int c = 0; c < keys.length; c++) {
        final key = keys[c];
        final val = c < row.length ? row[c]?.value : null;
        m[key] = _cellToString(val);
      }
      out.add(m);
    }
    return out;
  }

  // --- Helpers de conversión a String seguros para excel:^4.0.6 ---

  String _normalizeNumericString(String s) =>
      s.endsWith('.0') ? s.substring(0, s.length - 2) : s;

  String _asString(Object? o) {
    if (o == null) return '';
    final s = o.toString().trim();
    return _normalizeNumericString(s);
  }

  String _cellToString(dynamic v) {
    if (v == null) return '';
    if (v is TextCellValue) return _asString(v.value);
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return _normalizeNumericString(v.value.toString());
    if (v is BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
    if (v is DateCellValue) return _asString(v);          // estable para 4.x
    if (v is FormulaCellValue) return _asString(v.formula);
    return _asString(v);
  }

  String _onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
  String _daneDepto(String raw) {
    final d = _onlyDigits(raw);
    return d.isEmpty ? '' : d.padLeft(2, '0');
  }
  String _daneCiudad(String raw) {
    final d = _onlyDigits(raw);
    return d.isEmpty ? '' : d.padLeft(5, '0');
  }

  Future<void> _seedDepartamentos(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_DEPARTAMENTOS');
    final now = FieldValue.serverTimestamp();
    const size = 400;
    for (int i = 0; i < rows.length; i += size) {
      final chunk = rows.sublist(i, i + size > rows.length ? rows.length : i + size);
      final batch = _db.batch();
      for (final r in chunk) {
        final cod = _daneDepto(r['cod_dane'] ?? '');
        final nombre = (r['nombre'] ?? '').toString().trim();
        if (cod.isEmpty || nombre.isEmpty) continue;
        batch.set(col.doc(cod), {
          'cod_dane': cod,
          'nombre': nombre,
          'createdAt': now,
          'updatedAt': now
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> _seedCiudades(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_CIUDADES');
    final now = FieldValue.serverTimestamp();
    const size = 400;
    for (int i = 0; i < rows.length; i += size) {
      final chunk = rows.sublist(i, i + size > rows.length ? rows.length : i + size);
      final batch = _db.batch();
      for (final r in chunk) {
        final cod = _daneCiudad(r['cod_dane'] ?? '');
        final nombre = (r['nombre'] ?? '').toString().trim();
        final codDep = _daneDepto(r['cod_departamento'] ?? '');
        if (cod.isEmpty || nombre.isEmpty || codDep.isEmpty) continue;
        batch.set(col.doc(cod), {
          'cod_dane': cod,
          'nombre': nombre,
          'cod_departamento': codDep,
          'createdAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> _seedTiposDocumento(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final col = _db.collection('TBL_TIPO_DOCUMENTO');
    final now = FieldValue.serverTimestamp();
    const size = 400;
    for (int i = 0; i < rows.length; i += size) {
      final chunk = rows.sublist(i, i + size > rows.length ? rows.length : i + size);
      final batch = _db.batch();
      for (final r in chunk) {
        final codigo = (r['codigo'] ?? '').toString().trim();
        final descripcion = (r['descripcion'] ?? '').toString().trim();
        final tipoPersona = (r['tipo_persona'] ?? '').toString().trim();
        if (codigo.isEmpty || descripcion.isEmpty) continue;
        batch.set(col.doc(codigo), {
          'codigo': codigo,
          'descripcion': descripcion,
          'tipo_persona': tipoPersona.isEmpty ? null : tipoPersona,
          'createdAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }
}

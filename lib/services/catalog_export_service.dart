// lib/services/catalog_export_service.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class CatalogExportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _ciudades => _db.collection('TBL_CIUDADES');
  CollectionReference<Map<String, dynamic>> get _departamentos => _db.collection('TBL_DEPARTAMENTOS');
  CollectionReference<Map<String, dynamic>> get _tiposDoc => _db.collection('TBL_TIPO_DOCUMENTO');

  CellValue _t(String? s) => TextCellValue((s ?? '').toString());

  Future<Uint8List> exportToExcelBytes() async {
    final excel = Excel.createExcel();

    // DEPARTAMENTOS
    final deptoSnap = await _departamentos.get();
    final deptoRows = deptoSnap.docs.map((d) => {
      'cod_dane': (d.data()['cod_dane'] ?? d.id).toString(),
      'nombre': (d.data()['nombre'] ?? '').toString(),
    }).toList()
      ..sort((a, b) => a['cod_dane']!.compareTo(b['cod_dane']!));

    final shDeptos = excel['DEPARTAMENTOS'];
    shDeptos.appendRow([_t('cod_dane'), _t('nombre')]);
    for (final r in deptoRows) {
      shDeptos.appendRow([_t(r['cod_dane']), _t(r['nombre'])]);
    }

    // CIUDADES
    final ciudadesSnap = await _ciudades.get();
    final ciudadRows = ciudadesSnap.docs.map((c) => {
      'cod_dane': (c.data()['cod_dane'] ?? c.id).toString(),
      'nombre': (c.data()['nombre'] ?? '').toString(),
      'cod_departamento': (c.data()['cod_departamento'] ?? '').toString(),
    }).toList()
      ..sort((a, b) => a['cod_dane']!.compareTo(b['cod_dane']!));

    final shCiudades = excel['CIUDADES'];
    shCiudades.appendRow([_t('cod_dane'), _t('nombre'), _t('cod_departamento')]);
    for (final r in ciudadRows) {
      shCiudades.appendRow([_t(r['cod_dane']), _t(r['nombre']), _t(r['cod_departamento'])]);
    }

    // TIPO_DOCUMENTO
    final tiposSnap = await _tiposDoc.get();
    final tipoRows = tiposSnap.docs.map((t) => {
      'codigo': (t.data()['codigo'] ?? t.id).toString(),
      'descripcion': (t.data()['descripcion'] ?? '').toString(),
      'tipo_persona': (t.data()['tipo_persona'] ?? '').toString(),
    }).toList()
      ..sort((a, b) => a['codigo']!.compareTo(b['codigo']!));

    final shTipos = excel['TIPO_DOCUMENTO'];
    shTipos.appendRow([_t('codigo'), _t('descripcion'), _t('tipo_persona')]);
    for (final r in tipoRows) {
      shTipos.appendRow([_t(r['codigo']), _t(r['descripcion']), _t(r['tipo_persona'])]);
    }

    excel.setDefaultSheet('DEPARTAMENTOS');

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('No se pudieron generar los bytes del Excel.');
    }
    return Uint8List.fromList(bytes);
  }
}

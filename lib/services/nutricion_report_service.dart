import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';

class NutricionReportService {
  final FirebaseFirestore _db;
  NutricionReportService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Future<Uint8List> exportResumen({
    required String empresaId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final excel = Excel.createExcel();
    final sheetMenus = excel['MENUS'];
    final sheetDerivaciones = excel['DERIVACIONES'];

    sheetMenus.appendRow([
      TextCellValue('menuId'),
      TextCellValue('nombre'),
      TextCellValue('establecimiento'),
      TextCellValue('semana'),
      TextCellValue('periodo'),
      TextCellValue('creadoPor'),
    ]);

    final menusQuery = _db.collection('TBL_MENUS').where('empresaId', isEqualTo: empresaId);
    final menusSnap = await menusQuery.get();
    for (final doc in menusSnap.docs) {
      final data = doc.data();
      sheetMenus.appendRow([
        TextCellValue(doc.id),
        TextCellValue((data['nombre'] ?? '').toString()),
        TextCellValue((data['establecimiento'] ?? '').toString()),
        TextCellValue((data['semana'] ?? '').toString()),
        TextCellValue((data['periodo'] ?? '').toString()),
        TextCellValue((data['creadoPor'] ?? '').toString()),
      ]);
    }

    sheetDerivaciones.appendRow([
      TextCellValue('derivacionId'),
      TextCellValue('pacienteId'),
      TextCellValue('menuId'),
      TextCellValue('dietaId'),
      TextCellValue('kcalFinal'),
      TextCellValue('porcionesFinal'),
      TextCellValue('generadoEn'),
    ]);

    var derivacionesQuery = _db
        .collection('TBL_DERIVACIONES_NUTRICION')
        .where('empresaId', isEqualTo: empresaId);

    if (desde != null) {
      derivacionesQuery = derivacionesQuery.where('generadoEn', isGreaterThanOrEqualTo: desde);
    }
    if (hasta != null) {
      derivacionesQuery = derivacionesQuery.where('generadoEn', isLessThanOrEqualTo: hasta);
    }

    final derivacionesSnap = await derivacionesQuery.get();
    for (final doc in derivacionesSnap.docs) {
      final data = doc.data();
      sheetDerivaciones.appendRow([
        TextCellValue(doc.id),
        TextCellValue((data['pacienteId'] ?? '').toString()),
        TextCellValue((data['menuId'] ?? '').toString()),
        TextCellValue((data['dietaId'] ?? '').toString()),
        TextCellValue((data['kcalFinal'] ?? '').toString()),
        TextCellValue((data['porcionesFinal'] ?? '').toString()),
        TextCellValue((data['generadoEn'] ?? '').toString()),
      ]);
    }

    excel.setDefaultSheet('MENUS');
    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('No se pudieron generar los bytes del Excel.');
    }
    return Uint8List.fromList(bytes);
  }
}
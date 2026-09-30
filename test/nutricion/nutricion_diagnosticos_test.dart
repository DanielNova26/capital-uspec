import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/nutricion/diagnosticos/nutricion_diagnosticos_screen.dart';
import 'package:todo/services/diagnosticos_service.dart';
import '../support/memory_firestore.dart';

void main() {
  test('la plantilla de la app se importa completa (más de 500)', () async {
    final db = MemoryFirestore();
    addTearDown(db.close);
    final bytes = File('assets/diagnosticos_template.xlsx').readAsBytesSync();
    final result = await DiagnosticosService(db: db)
        .importarDiagnosticosDesdeExcel(
          bytes: bytes,
          empresaId: 'A',
          userId: '101',
          sobrescribir: true,
        );
    final medicos = db.documents.entries
        .where((e) => e.key.startsWith('TBL_DIAGNOSTICOS_MEDICOS/'))
        .toList();
    // Antes todo iba en un solo lote y Firestore no acepta más de 500.
    expect(result['diagnosticosMedicos'], greaterThan(500));
    expect(medicos.length, result['diagnosticosMedicos']);
    final uno = medicos.first.value;
    // Catálogo único: sin empresaId, con desde dónde y quién lo actualizó.
    expect(uno.containsKey('empresaId'), isFalse);
    expect(uno['actualizadoDesdeEmpresa'], 'A');
    expect(uno['actualizadoPor'], '101');
  });

  test('consulta: busca por código, nombre o detalle', () {
    const filas = [
      (
        codigo: '5A11',
        nombre: 'Diabetes mellitus tipo 2',
        detalle: 'Endocrino',
      ),
      (
        codigo: 'BA00',
        nombre: 'Hipertensión esencial',
        detalle: 'Circulatorio',
      ),
    ];
    expect(filtrarDiagnosticos(filas, ''), filas);
    expect(filtrarDiagnosticos(filas, '5a1').single.codigo, '5A11');
    expect(filtrarDiagnosticos(filas, 'HIPERTENSIÓN').single.codigo, 'BA00');
    expect(filtrarDiagnosticos(filas, 'endocrino').single.codigo, '5A11');
    expect(filtrarDiagnosticos(filas, 'nada'), isEmpty);
  });
}

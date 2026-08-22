import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/rutas/rutas_models.dart';

void main() {
  group('RutaAsignacionDoc', () {
    test('conserva los dos ayudantes al serializar', () {
      final now = Timestamp.fromDate(DateTime(2026, 8, 13, 8));
      final original = RutaAsignacionDoc(
        empresaId: 'EMPRESA_003',
        rutaId: 'ruta-1',
        rutaCodigo: 'Ruta 1',
        conductorCedula: '1',
        conductorNombre: 'Conductor',
        ayudanteCedula: '2',
        ayudanteNombre: 'Ayudante uno',
        ayudante2Cedula: '3',
        ayudante2Nombre: 'Ayudante dos',
        vigenteDesde: now,
        createdAt: now,
      );

      final restored = RutaAsignacionDoc.fromMap('asig-1', original.toMap());

      expect(restored.ayudanteCedula, '2');
      expect(restored.ayudanteNombre, 'Ayudante uno');
      expect(restored.ayudante2Cedula, '3');
      expect(restored.ayudante2Nombre, 'Ayudante dos');
    });

    test('mantiene compatibilidad con asignaciones antiguas', () {
      final now = Timestamp.fromDate(DateTime(2026, 8, 13, 8));
      final restored = RutaAsignacionDoc.fromMap('legacy', {
        'empresaId': 'EMPRESA_003',
        'rutaId': 'ruta-1',
        'ayudanteCedula': '2',
        'ayudanteNombre': 'Ayudante uno',
        'vigenteDesde': now,
        'createdAt': now,
      });

      expect(restored.ayudante2Cedula, isEmpty);
      expect(restored.ayudante2Nombre, isEmpty);
    });
  });
}

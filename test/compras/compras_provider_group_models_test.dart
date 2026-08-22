import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_models.dart';

void main() {
  group('estado del proveedor', () {
    test('los registros anteriores continúan activos por compatibilidad', () {
      final proveedor = ProveedorDoc.fromMap('p1', {
        'empresaId': 'empresa',
        'nit': '9001',
        'razonSocial': 'Proveedor anterior',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });

      expect(proveedor.activo, isTrue);
    });

    test('lee un proveedor inhabilitado sin perder su motivo', () {
      final proveedor = ProveedorDoc.fromMap('p2', {
        'empresaId': 'empresa',
        'nit': '9002',
        'razonSocial': 'Proveedor inhabilitado',
        'estado': 'inactivo',
        'motivoInactivacion': 'Terminó el contrato',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });

      expect(proveedor.activo, isFalse);
      expect(proveedor.motivoInactivacion, 'Terminó el contrato');
    });
  });

  test('la recepción conserva su grupo de Compras', () {
    final recepcion = RecepcionDoc.fromMap('r1', {
      'empresaId': 'empresa',
      'fecha': Timestamp.fromDate(DateTime(2026, 8, 5)),
      'proveedorId': 'p1',
      'nit': '9001',
      'razonSocial': 'Proveedor',
      'grupoId': 'grupo-6',
      'grupoNombre': 'Grupo 6',
      'productos': <Map<String, dynamic>>[],
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 5)),
    });

    expect(recepcion.grupoId, 'grupo-6');
    expect(recepcion.grupoNombre, 'Grupo 6');
  });
}

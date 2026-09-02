import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/compras/compras_models.dart';

void main() {
  group('normalizeComprasRol', () {
    test('normaliza Director de Calidad como rol calidad', () {
      expect(normalizeComprasRol('Director de Calidad'), kRolCalidad);
      expect(normalizeComprasRol('director_calidad'), kRolCalidad);
      expect(normalizeComprasRol('Control de Calidad'), kRolCalidad);
    });

    test('mantiene roles canonicos del modulo', () {
      expect(normalizeComprasRol('admin_documental'), kRolAdmin);
      expect(normalizeComprasRol('compras'), kRolCompras);
      expect(normalizeComprasRol('bodega'), kRolBodega);
      expect(normalizeComprasRol('solo lectura'), kRolConsultas);
    });
  });

  group('visibilidad por rol y estado', () {
    test('Consultas no ve Abastecimiento', () {
      expect(comprasRolPuedeVerAbastecimiento(kRolConsultas), isFalse);
      expect(comprasRolPuedeVerAbastecimiento('solo lectura'), isFalse);
      expect(comprasRolPuedeVerAbastecimiento(kRolBodega), isTrue);
      expect(comprasRolPuedeVerAbastecimiento(kRolAdmin), isTrue);
    });

    test('la consulta de fichas solo admite documentos aprobados', () {
      FichaTecnicaDoc ficha(String estado) => FichaTecnicaDoc(
        empresaId: 'EMP1',
        proveedorId: 'P1',
        proveedorNombre: 'Proveedor',
        productoId: 'PR1',
        productoNombre: 'Producto',
        documentoActual: DocAdjunto(
          url: 'https://example.test/ficha.pdf',
          estadoCalidad: estado,
        ),
        creadoPor: '1',
        createdAt: Timestamp.fromDate(DateTime(2026, 9, 1)),
      );

      expect(fichaTecnicaVisibleEnConsultas(ficha('aprobado')), isTrue);
      expect(
        fichaTecnicaVisibleEnConsultas(ficha('aprobado_con_requerimientos')),
        isTrue,
      );
      expect(
        fichaTecnicaVisibleEnConsultas(ficha('pendiente_revision_calidad')),
        isFalse,
      );
      expect(fichaTecnicaVisibleEnConsultas(ficha('rechazado')), isFalse);
    });
  });
}

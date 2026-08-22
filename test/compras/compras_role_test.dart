import 'package:flutter_test/flutter_test.dart';
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
}
